DEFCVAR_FLOAT(fo_jumpvolume, 1);

// Quake's V_CalcRefdef step-smoothing constants.
#define STEP_RAMP    80   // units/sec the view catches up
#define STEP_MAX_LAG 12   // units the view may trail the true z

// `seq` is the start of the first frame after which all input_*s are handled.
// Running to `seq` will result in being on frame `seq + 1` in the resultant
// state.  In the case that `seq == commandclientframe` this could only be
// partially true since the input_*s (in particular, timelength) are not
// constant for this frame.
static struct PMS_Data {
    vector org, vel;
    float seq, server_seq;
    float interp_t;
} pm_s, pm_so, pm_c;

static struct {
    entity ent;
    float last_vel_z;
    PMS_Data* active_pmsd;

    float seq, server_seq;
    float interp_t;
    float last_nudge;

    vector error;
    float errortime;

    float step, steptime, step_oldz;

    vector vieworg;
} pm;

vector PM_Org() { return PM_Enabled() ? pm.ent.origin : pmove_org; }
vector PM_Vel() { return PM_Enabled() ? pm.ent.velocity : pmove_vel; }
float PM_onground() { return PM_Enabled() ? pm.ent.flags & FL_ONGROUND : pmove_onground; }
inline entity PM_Ent() { return pm.ent; }

float CSQC_JumpSounds_Active() {
    if (PM_Enabled())
            return TRUE;  // PM sounds are accurate.
    return CVARF(fo_csjumpsounds);
}

// Sets *type to whatever is at the feet of `point`.
static float PM_GetWaterLevel(vector point, float* type) {
    float waterlevel = 0;
    float offsets[] = { PLAYER_MINS.z + 1, (PLAYER_MINS.z + PLAYER_MAXS.z) / 2,
                        DEFAULT_VIEWHEIGHT };
    for (int i = 0; i < 3; i++) {
        float cont = pointcontents(point + offsets[i] * '0 0 1');
        if (i == 0)
            *type = cont;
        if (cont == CONTENT_WATER || cont == CONTENT_SLIME || cont == CONTENT_LAVA)
            waterlevel++;
        else
            break;
    }
    return waterlevel;
}

static void PM_Sounds(float is_jumping, float is_jumpframe,
                      float is_landing,
                      float last_vel_z) {
    float fluidtype;
    static float last_waterlevel;  // Hacky ...
    float waterlevel = PM_GetWaterLevel(PM_Org(), &fluidtype);

    if (is_landing && last_vel_z < -300) {  // Hard or water land.
        if (fluidtype == CONTENT_WATER)
            Predicted_Sound("player/h2ojump.wav", CHAN_BODY, 1);
        else if (last_vel_z < -650)  // Will take damage.
            Predicted_Sound("player/land2.wav", CHAN_BODY, 1);
        else
            Predicted_Sound("player/land.wav", CHAN_BODY, 1);
    }

    // TODO: Model health above and not play jump when landing into death.
    if (is_jumping) {
        static float swimsound_next;
        if (waterlevel >= 2) {
           if (time > swimsound_next) {
               swimsound_next = time + 1;
               float rand = shared_prng(PRNG_MOVE);
               Predicted_Sound(rand < 0.5 ? "misc/water1.wav" : "misc/water2.wav",
                               CHAN_BODY, 1);
           }
        } else if (is_jumpframe) {
            // The default pmove implementation and server behave slightly
            // differently here in two important ways here:
            // 1) Jump calculations run _prior_ to movement rather than post,
            //    meaning you can test for jumping and onground directly.  We
            //    get around this by just using prior frame's onground.
            // 2) Something (probably airstep) masks on-grounds that get
            //    skipped, which otherwise results in false jumps moving up
            //    stairs when combined with (1).  We can test for this by
            //    watching to see whether we actually got a sufficiently large
            //    velocity increase.
            Predicted_Sound("player/plyrjmp8.wav", CHAN_AUTO, CVARF(fo_jumpvolume));
        }
    }

    if (waterlevel > 0 && last_waterlevel == 0) {  // Water entry.
        string sound = "";
        switch(fluidtype) {
            case CONTENT_LAVA: sound = "player/inlava.wav"; break;
            case CONTENT_WATER: sound = "player/inh2o.wav"; break;
            case CONTENT_SLIME: sound = "player/slimbrn2.wav"; break;
        }
        Predicted_Sound(sound, CHAN_BODY, 1);
    } else if (waterlevel == 0 && last_waterlevel > 0) {  // Water exit.
        Predicted_Sound("misc/outwater.wav", CHAN_BODY, 1);
    }

    last_waterlevel = waterlevel;
}

// Some versions of FTE do not correctly update pmove_vel (although other state,
// e.g. PM_Org() is).  Until we're directly tied to pmove, we snoop on recent
// values when we think this is happening.
float recent_pmove_vel_z;

void PM_PredictJump_Engine() {
    if (!CSQC_JumpSounds_Active() || getstatf(STAT_PAUSED))
        return;

    if (PM_Enabled())  // Handled by PredictJump_Pmove
        return;

    static float last_onground, last_vel_z;

    float jumping = input_buttons & BUTTON_JUMP;
    float onground = pmove_onground;
    float landing = (onground && !last_onground);
    float vel_z = pmove_vel_z ?: recent_pmove_vel_z;

    if (!game_state.is_alive) {
        last_onground = 1;
        last_vel_z = 0;
        return;
    }

    float is_jump = last_onground && !onground && vel_z > last_vel_z + 200;

    PM_Sounds(jumping, is_jump, landing, last_vel_z);

    last_vel_z = vel_z;
    last_onground = onground;
};

////////////////////////////////////////////////////////////////////////////////
// Pmove
////////////////////////////////////////////////////////////////////////////////

enum {
    SERVER,
    PMOVE,
    ERROR_POS,
    ERROR_VEL,
    ERROR_VIEW,
    NUM_DBG_GRAPH_TYPES,
};

DEFCVAR_FLOAT(fo_smartjump, 1);

DEFCVAR_FLOAT(fopm_noerror, 0);
DEFCVAR_FLOAT(fopm_nocache, 0);
DEFCVAR_FLOAT(fopm_nostep, 0);
DEFCVAR_FLOAT(fopm_nonudge, 0);
DEFCVAR_FLOAT(fopm_errortime, 0);
DEFCVAR_FLOAT(fopm_debug, 0);

DEFCVAR_FLOAT(fopm_explosion_eps, -1);
static float NudgeExplosionEps() {
    float val = CVARF(fopm_explosion_eps);
    if (val == -1)
        return 5;
    return val;
}

DEFCVAR_FLOAT(fopmd_graph_x, -10);
DEFCVAR_FLOAT(fopmd_graph_y, 100);
DEFCVAR_FLOAT(fopmd_graph_w, 200);
DEFCVAR_FLOAT(fopmd_graph_h, 100);

DEFCVAR_FLOAT(v_viewheight, 0);

enumflags {
    PMDG_ON,              //  1 for laziness..
    PMDG_NO_ALIGN_INTERP, //  2
    PMDG_ERROR_VEL,       //  4
    PMDG_ERROR_POS,       //  8
    PMDG_ERROR_VIEW,      // 16
};
DEFCVAR_FLOAT(fopmd_graph, 0);

static const float NHIST = 21;
struct PM_History {
    vector org, vel;
    float seq;
};
static PM_History hist[NHIST];

void PMH_Log(float seq) {
    PM_History* pmh = &hist[seq % NHIST];
    pmh->org = PM_Org();
    pmh->vel = PM_Vel();
    pmh->seq = seq;
}

PM_History* PMH_Get(float seq) {
    PM_History* pmh = &hist[seq % NHIST];
    return pmh->seq == seq ? pmh : 0;
}

void PM_Init() {
    pm.ent = spawn();
    pm.ent.solid = SOLID_NOT;
    setsize(pm.ent, '-16 -16 -24', '16 16 32');
}

// Should be invoked immediately after RunMovement() to ensure correctness of
// `seq` versus state.  On server packets we manually set `seq` to sf + 1.
static void PM_SavePMS(PMS_Data *pmsd) {
    entity ent = pm.ent;
    pmsd->org = ent.origin;
    pmsd->vel = ent.velocity;

    pmsd->seq = pm.seq;
    pmsd->server_seq = pm.server_seq;
    pmsd->interp_t = pm.interp_t;
}

static void PM_ActivatePMS(PMS_Data *pmsd) {
    entity ent = pm.ent;
    ent.origin = pmsd->org;
    ent.velocity = pmsd->vel;
    ent.pmove_flags = 0;  // Not clear there's anything to save/restore here.

    pm.seq = pmsd->seq;
    pm.server_seq = pmsd->server_seq;
    pm.interp_t = pmsd->interp_t;
    pm.active_pmsd = pmsd;
};

static float cache_invalidated;
static PMS_Data* SimPMSD() {
    return (cache_invalidated || CVARF(fopm_nocache)) ? &pm_s : &pm_c;
}

void PM_InputFrame();

enum {
    NT_EMPTY,
    NT_DASH,
    NT_EXPLOSION,
    NT_BOUNCE,
};

enum {
    NA_NONE,
    NA_SEQ,
    NA_SEQTIME,
    NA_ITIME,
    NA_ITIME_EXPLICIT_EXPIRE,
};

static string NAT_tos(int nat) {
    switch (nat) {
        case NA_SEQ: return "SEQ";
        case NA_SEQTIME: return "SEQTIME";
        case NA_ITIME: return "ITIME";
        case NA_ITIME_EXPLICIT_EXPIRE: return "ITIME_EXPLICIT";
    }
    return sprintf("[NAT:%i]", nat);
}

struct PM_Nudge {
    float type;

    entity src;
    float src_no;

    float nat, seq, itime;
    float expire_frame, expire_time, expire_spawnseq;

    vector org;
    float aux;
};

const static float NUDGE_SEQ = 3;
const static float NUDGE_EPS = NUDGE_SEQ * SERVER_FRAME_DT;
static PM_Nudge nudges[8];
static float num_nudges, have_active_nudges;

static float nudge_expired(PM_Nudge* n) {
    if (n->expire_frame && n->expire_frame <= pstate_server.seq)
        return TRUE;

    if (n->expire_time && n->expire_time <= pstate_server.server_time)
        return TRUE;

    if (n->expire_spawnseq && n->expire_spawnseq != game_state.spawn_gen)
        return TRUE;

    switch (n->nat) {
        case NA_NONE: return TRUE;
        case NA_SEQ: return n->seq + NUDGE_SEQ <= pstate_server.seq;
        case NA_SEQTIME:
            return n->seq + ceil(n->itime / SERVER_FRAME_DT) + NUDGE_SEQ <= pstate_server.seq;
        case NA_ITIME:
            return n->itime >= pstate_server.server_time + NUDGE_EPS;  // Slack
        case NA_ITIME_EXPLICIT_EXPIRE: return FALSE;  // TRUE handled above
    }

    return TRUE;
}

static PM_Nudge* find_nudge_slot() {
    have_active_nudges = TRUE;

    for (float i = 0; i < nudges.length; i++) {
        PM_Nudge* n = &nudges[(num_nudges++) % nudges.length];

        if (!nudge_expired(n))
            continue;

        cache_invalidated = TRUE;
        n->nat = NA_NONE;
        n->src_no = 0;
        n->src = 0;
        n->expire_frame = 0;
        n->expire_time = 0;
        n->expire_spawnseq = 0;
        return n;
    }

    if (CVARF(fopm_debug))
        printf("ERROR: no nudge slots!\n");
    return 0;
}

.PM_Nudge* nudge;

static void PM_RemoveSelfNudges() {
    if (!self.nudge)
        return;

    PM_Nudge* n = self.nudge;

    // We skip the removal of explicit expiry server ents, which have known
    // cause and effect.  We do not do this for client ents as their removal
    // means they've been replaced by an equivalent server ent.
    if (n->nat == NA_ITIME_EXPLICIT_EXPIRE && self.entnum)
        return;

    // The removal arrives before the frame with the affect included.  Normally
    // this coincides with the arrival of something else which replaces the
    // nudge.
    n->expire_frame = servercommandframe;
}

static void PM_NudgeDash(PM_Nudge* nudge, entity ent) {
    ent.velocity = nudge->org;
}

void PM_AddNudgeDash(float cseq) {
    PM_Nudge* n = find_nudge_slot();
    if (!n)
        return;
    n->type = NT_DASH;
    n->nat = NA_SEQ;
    n->seq = cseq;

    n->org = v_forward * 540;
    n->org.z = 181;
}

float nudge_i(PM_Nudge* n) {
    for (float i = 0; i < nudges.length; i++)
        if (&nudges[i] == n)
            return i;
    return -1;
}

static void PM_NudgeExplosion(PM_Nudge* nudge, entity ent) {
    float dmg = nudge->aux;
    if (vlen(ent.origin - nudge->org) > dmg + 40 - NudgeExplosionEps())
        return;

    const float MOVE_WORLDONLY = 3;
    traceline(ent.origin, nudge->org, MOVE_WORLDONLY, pm.ent);
    if (trace_fraction < 1)  // No knock from occluded explosions
        return;

    float flg = KF_BOTH_PLAYER;  // Assumes everything is from a player for now
    if (nudge->src.owner == pengine.player_ent)
       flg |= KF_SELF;

    dmg = CalcRadiusDamage(nudge->org, ent, flg, dmg);

    // Same scaling chain the server runs in TF_T_Damage(), via shared code so
    // the two can't drift.  Both inputs are our own state: TFSTATE_BURNING is
    // predicted, and explosion armour arrives as a predict flag because it
    // comes from pickups rather than playerclass.
    //
    // Still unmodelled: KF_QUAD.  That depends on the *attacker's*
    // super_damage_finished, which we don't have for someone else's grenade --
    // a quadded thrower still mispredicts by 4x.
    float dsf = 0;
    if (pstate_pred.tfstate & TFSTATE_BURNING)
        dsf |= DSF_BURNING;
    if (pstate_server.predict_flags & PF_SAVE_EXPLOSION)
        dsf |= DSF_SAVE_EXPLOSION;

    dmg = Damage_Scale(dmg, flg, dsf);
    dmg = Class_ScaleMoment(WP_PlayerClass(), dmg);
    vector knock = CalcKnock(nudge->org, ent, flg, dmg);

    pm.ent.velocity += knock;
}

// Can be either by {seq + itime} for predicted projectiles, or by {itime} for
// server projectiles.
static PM_Nudge* PM_AddNudgeExplosion(float nat, float seq, float itime, entity ent, float dmg) {
    if (vlen(PM_Org() - ent.origin) > dmg * 3)  // Fine tune this..
        return 0;

    PM_Nudge* n = find_nudge_slot();
    if (!n)
        return 0;

    n->type = NT_EXPLOSION;
    n->nat = nat;
    n->seq = seq;
    n->itime = itime;
    if (nat == NA_ITIME_EXPLICIT_EXPIRE)
        n->expire_time = itime;

    // This is slightly imprecise, since you could throw a grenade then spawn
    // and jump on it, but it's more right than wrong; and the wrong cases lead
    // to false lerps.
    if (ent.owner == pengine.player_ent)
        n->expire_spawnseq = game_state.spawn_gen;

    n->org = ent.origin;  // We end up mostly using the ent here
    n->aux = dmg;

    n->src = ent;
    n->src_no = ent.entnum;

    ent.nudge = n;
    ent.removefunc = PM_RemoveSelfNudges;

    return n;
}

static void PM_AddNudgeBounce(float itime, entity ent, float dmg) {
    if (vlen(PM_Org() - ent.origin) > dmg * 3)  // Fine tune this..
        return;

    PM_Nudge* n = find_nudge_slot();
    if (!n)
        return;

    n->type = NT_BOUNCE;
    n->nat = NA_ITIME_EXPLICIT_EXPIRE;
    n->expire_time = itime;
    n->itime = itime;

    n->org = ent.origin;
    n->aux = dmg;

    n->src = ent;
    n->src_no = ent.entnum;

    ent.nudge = n;
    ent.removefunc = PM_RemoveSelfNudges;
}

static void PM_NudgeBounce(PM_Nudge* nudge, entity ent) {
    float dmg = nudge->aux;

    if (vlen(ent.origin - nudge->org) > dmg + 40 - NudgeExplosionEps())
        return;

    vector targ_org = ent.origin + (ent.mins + ent.maxs) * 0.5;
    float points = dmg - vlen(targ_org - nudge->org) / 2;

    ent.velocity = (targ_org - nudge->org) * points/20;

    NB_ConcCapAction(ent, pstate_pred.playerclass, &pstate_pred.tfstate,
                     pm.interp_t, &pstate_pred.conc_cap_time, kLaunch);
}


void PM_AddGrenadeExplosion(float itime, entity ent) {
    if (!PM_Enabled())
        return;

    FO_GrenExp exp;
    if (!FO_GrenGetExp(ent.fpp.gren_type, exp))
        return;

    float dmg = exp.dmg;

    PM_Nudge* n;
    if (exp.type == kRadiusDamage)
        PM_AddNudgeExplosion(NA_ITIME_EXPLICIT_EXPIRE, 0, itime, ent, dmg);
    else
        PM_AddNudgeBounce(itime, ent, dmg);
}

void PM_AddSimExplosion(float itime, entity ent) {
    if (!PM_Enabled())
        return;

    if ((CVARF(fo_beta_nudge_explosion) & 2 == 0) &&
            ent.owner != pengine.player_ent)
        return;

    float dmg = 0;
    switch (ent.fpp.index) {
        case FPP_ROCKET:
        case FPP_INCENDIARY:
            dmg = 92;
            break;
        default:
            return;  // Not recognized
    }

    float seq = 0, nat = NA_ITIME;
    if (ent.forward_knock && ent.owner == pengine.player_ent) {
        if (ent.forward_knock == -1)
            return;
        nat = NA_ITIME_EXPLICIT_EXPIRE;  // Knock forwards are synchronized
        itime = ent.forward_knock;
    } else if (ent.created_seq && ent.entnum == 0) {
        float dtime = 0;
        if (ent.s_time)
            dtime = max(itime - ent.s_time, 0);
        seq = ent.created_seq;
        itime = dtime;
        nat = NA_SEQTIME;  // Same as NA_SEQ when itime == 0
    }

    PM_AddNudgeExplosion(nat, seq, itime, ent, dmg);
}

float MatchNudge(PM_Nudge* n, float seq, float sitime, float eitime, float slack = 0) {
    if (nudge_expired(n))
        return FALSE;

    switch (n->nat) {
        case NA_SEQ: return seq == n->seq;
        case NA_SEQTIME: return seq == n->seq + floor(n->itime / SERVER_FRAME_DT);
        case NA_ITIME_EXPLICIT_EXPIRE: return n->itime > sitime && n->itime <= eitime;
        case NA_ITIME: return (n->itime > sitime - slack) && (n->itime <= eitime);
        default:
            return FALSE;
    }
}

// TODO: This obviously wants to be smarter
static void PM_ApplyNudges(entity ent, float seq, float sitime, float eitime, float slack = 0) {
    if (!have_active_nudges)
        return;

    for (float i = 0; i < nudges.length; i++) {
        PM_Nudge* n = &nudges[i];

        if (!MatchNudge(n, seq, sitime, eitime, slack))
            continue;

        pm.last_nudge = seq;
        switch (n->type) {
            case NT_DASH:
                PM_NudgeDash(n, ent);
                break;
            case NT_EXPLOSION:
                PM_NudgeExplosion(n, ent);
                break;
            case NT_BOUNCE:
                PM_NudgeBounce(n, ent);
                break;
        }
    }
}

static void RunPlayerPhysics() {
    entity ent = pm.ent;

    pm.last_vel_z = ent.velocity_z;
    runstandardplayerphysics(ent);
}

static void RunDeadMovement(float endframe) {
    entity ent = pm.ent;
    float held_movetype = ent.movetype;
    float held_solid = ent.solid;
    float held_buttons = input_buttons;
    vector held_movevalues = input_movevalues;

    ent.movetype = MOVETYPE_TOSS;
    ent.solid = SOLID_NOT;
    input_buttons = 0;
    input_movevalues = '0 0 0';
    while (pm.seq <= endframe) {
        runstandardplayerphysics(ent);
        pm.seq++;
    }

    ent.movetype = held_movetype;
    ent.solid = held_solid;
    input_buttons = held_buttons;
    input_movevalues = held_movevalues;
}

// End state:
//   pmsd.seq --> endframe + 1
static void PM_RunMovement(PMS_Data* pmsd, float endframe) {
    entity ent = pm.ent;

    // This runs several times per frame (rendering, error measurement, debug
    // graphs), so it must be idempotent.  The conc paths below now advance
    // bookkeeping -- the stumble schedule, its PRNG stream, and the conc
    // tfstate bits -- so snapshot all of it and put it back.  The velocity a
    // stumble imparts is the output and deliberately survives.
    //
    // Prediction still works because pstate_pred is reset wholesale from
    // pstate_server each cycle, so every replay re-derives forward from the
    // last authoritative state instead of accumulating on top of itself.
    ConcState saved_conc      = pstate_pred.conc_state;
    float saved_prng_conc     = pstate_pred.prng_base[PRNG_CONC];
    float saved_tfstate       = pstate_pred.tfstate;
    float saved_conc_cap_time = pstate_pred.conc_cap_time;

    if (pm.active_pmsd != pmsd || pm.seq > endframe) {
        ASSERTF_GT(endframe, pm.server_seq);
        PM_ActivatePMS(pmsd);
    }

    if (!game_state.is_spectator && !game_state.is_alive) {
        RunDeadMovement(endframe);
        return;
    }

    ASSERTF_GT(pm.seq, 0);

    while (pm.seq <= endframe) {
        if (!getinputstate(pm.seq))
            break;

        pm.ent.pmove_flags &= ~PMF_JUMP_HELD;  // Auto-bunny.
        // We have to apply this on the leading edge since INPUT_FRAME
        // modifications do not occur until the frame is finalized.
        if (pm.seq == clientcommandframe)
            PM_InputFrame();

        RunPlayerPhysics();

        if (!CVARF(fopm_nonudge) && pm.seq != clientcommandframe) {
            float slack = 0;
            PM_ApplyNudges(ent, pm.seq, pm.interp_t, pm.interp_t + input_timelength, slack);

            if (pstate_pred.tfstate & TFSTATE_CONC) {
                if (pointcontents(ent.origin) == CONTENT_WATER)
                    ent.flags |= FL_INWATER;  // pmove doesn't usually maintain this.
                                              //
                if (!Conc_Update(&pstate_pred.conc_state, pm.ent,
                        pm.interp_t + input_timelength, pm.interp_t)) {
                    if ((ent.pmove_flags & PMF_JUMP_HELD))
                        Conc_Jump(&pstate_pred.conc_state, ent);
                }

            }

            if ((ent.pmove_flags & PMF_JUMP_HELD) && (pstate_pred.tfstate & TFSTATE_CONC_CAP)) {
                NB_ConcCapAction(ent, pstate_pred.playerclass, &pstate_pred.tfstate,
                                 pm.interp_t, &pstate_pred.conc_cap_time,
                                 kLand);
            }
        }

        pm.seq++;
        pm.interp_t += input_timelength;
    }

    // Add in anything that was applied after (for low packet rate protocols)
    input_angles = view_angles;

    pstate_pred.conc_state            = saved_conc;
    pstate_pred.prng_base[PRNG_CONC]  = saved_prng_conc;
    pstate_pred.tfstate               = saved_tfstate;
    pstate_pred.conc_cap_time         = saved_conc_cap_time;

}

static void PM_LerpReset();

static void PM_SetEnabled(float enabled) {
    pengine.pm_enabled = enabled;

    PM_Refresh();

    if (!enabled)
        return;

    pm.errortime = pm.steptime  = 0;
    pm.step_oldz = pm.ent.origin_z;
    PM_LerpReset();
}

static float ErrorTime() {
    static float kDefault = 25 * MSEC;
    static float kMax = 50 * MSEC;

    if (!CVARF(fopm_errortime))
        return kDefault;

    return min(CVARF(fopm_errortime), kMax);
}

static void PM_UpdateError() {
    entity ent = pm.ent;

    ent.owner = edict_num(player_localentnum);
    if (CVARF(fopm_noerror) || !game_state.is_alive ||
        (clientcommandframe == servercommandframe + 1)) {
        pm.error = '0 0 0';
        pm.errortime = 0;
        return;
    }

    static PMS_Data last;
    if (last.server_seq != pm_s.server_seq - 1)
        last = pm_so;

    // Run prior prediction to present.
    PM_RunMovement(&last, clientcommandframe);
    vector err = ent.origin;

    // Repeat with updated state.
    PM_RunMovement(SimPMSD(), clientcommandframe - 2);
    PM_SavePMS(&last);  // Save at -2 to replay nudges going into -1
    PM_RunMovement(SimPMSD(), clientcommandframe);

    // New nudges can result in small errors on replay due to timeshift, we
    // could backdate all the nudges and recompute the world but as a first
    // simpler pass let's just filter them out.
    if (pm.last_nudge == clientcommandframe - 1)
        err = '0 0 0';
    else
        err -= ent.origin;


    float nerr = vlen(err);
    if (nerr > 64) {  // teleport
        pm.error = '0 0 0';
        pm.errortime = 0;
    } else { // figure out the error amount, and add it to accumulated lerp
        pm.error *= max(pm.errortime - time, 0) / ErrorTime();
        pm.error += err;

        if (vlen(pm.error) > 1) {
            pm.errortime = time + ErrorTime();
        } else {
            pm.error = '0 0 0';
            pm.errortime = 0;
        }
    }
}

DEFCVAR_FLOAT(v_deathtilt, 1);

// ezQuake-style adaptive lerp of the eye (cl_pred.c:CL_LerpMove).
//
// Keeps three (time, origin) samples taken at *complete* input frames and
// interpolates between them using a self-tuning latency offset.  The offset is
// servoed every frame -- clamped up if we run past the newest sample, clamped
// down if we fall behind the oldest, otherwise allowed to drift down slowly --
// so the lerp fraction essentially never saturates and the camera translates at
// a constant rate regardless of how input frames land relative to video frames.
//
// Samples come from the last COMPLETE frame, never the pending one: the engine
// recomputes the pending frame's msec from realtime on every getinputstate(),
// so a sample taken through it would be timestamped against a value that keeps
// moving.
//
// View only.  pm.ent.origin stays replayed through the pending frame so weapon
// prediction, tracelines and spawn positions are unaffected.
// On by default: measured ~10x lower roughness (0.1 -> 0.01) with catch-up
// falling from 3-5 to 1.0, i.e. the stall-and-spike pairs disappear entirely.
// Costs the eye a few ms of latency -- see "lerp lat" in fopm_smooth_status.
// Set 0 for the old direct-replay view.
DEFCVAR_FLOAT(fopm_lerpmove, 1);



// The servo settles around one input-frame interval (~12.5ms at 77Hz), which
// is the minimum that guarantees two samples bracketing simtime.  Two attempts
// to get below it were measured and both failed the same way -- by trading a
// steady offset for occasional large ones:
//
//   Bleeding latency off faster (x50+): bought ~1ms, took roughness 10x worse
//   and climbed catch-up.  The servo just clamps more, and a clamp is a stall.
//
//   Extrapolating past the newest sample along its velocity (5ms): bought 5.5ms
//   and held mean roughness at 0.05, but catch-up went 1.0 -> 3-8.  Overshoot
//   corrects when the real sample lands, and that correction is a large
//   single-frame displacement.
//
// catch-up is the constraint to protect: perception is dominated by the worst
// frame, not the average one, so a rare 8x spike reads worse than a uniform
// 12.5ms of latency.  The floor is honest -- lower it by raising cl_netfps
// (which shrinks the sample interval itself), not by predicting past it.
static const float kLerpMaxLat = 0.05;
static const float kLerpTeleport = 100;  // inter-sample jump treated as discontinuity

static struct {
    float t[3];
    vector o[3];
    float last_seq, lat, newframe, valid;
} lm;

static void PM_LerpReset() {
    lm.valid = lm.lat = lm.newframe = 0;
    lm.last_seq = -1;
}

static void PM_LerpSample() {
    float seq = clientcommandframe - 1;
    if (seq == lm.last_seq || seq <= servercommandframe)
        return;

    PM_RunMovement(SimPMSD(), seq);
    vector o = pm.ent.origin;

    // Teleport/respawn: lerping across it would slide the camera through the
    // world, so drop the history and restart.
    if (lm.valid && vlen(o - lm.o[0]) > kLerpTeleport)
        PM_LerpReset();

    lm.t[2] = lm.t[1]; lm.t[1] = lm.t[0]; lm.t[0] = cltime;
    lm.o[2] = lm.o[1]; lm.o[1] = lm.o[0]; lm.o[0] = o;

    lm.last_seq = seq;
    lm.newframe = TRUE;
    if (lm.valid < 3)
        lm.valid++;
}

// Spectating gets the same ezQuake servo, fed from a different source.
// PM_LerpEye only needs a timestamped position buffer, and pmove is disabled
// while spectating, so lm is free to reuse -- only the sampler differs:
// tracked position on each new server frame, rather than a replayed prediction.
DEFCVAR_FLOAT(fopm_spec_lerp, 0);

static float slm_seq;

static void PM_SpecSample() {
    if (servercommandframe == slm_seq)
        return;
    slm_seq = servercommandframe;

    vector o = pmove_org;
    if (lm.valid && vlen(o - lm.o[0]) > kLerpTeleport)
        PM_LerpReset();

    lm.t[2] = lm.t[1]; lm.t[1] = lm.t[0]; lm.t[0] = cltime;
    lm.o[2] = lm.o[1]; lm.o[1] = lm.o[0]; lm.o[0] = o;

    lm.newframe = TRUE;
    if (lm.valid < 3)
        lm.valid++;
}

static vector PM_LerpEye(vector fallback);

// TRUE if it took over the view.
float PM_SpecView() {
    // player_localentnum <= 32 means we are viewing from a real player, the
    // same test TrackingPlayer() makes in main.qc (which compiles later).
    if (!CVARF(fopm_spec_lerp) || PM_Enabled() || player_localentnum > 32) {
        PM_LerpReset();
        slm_seq = 0;
        return FALSE;
    }

    PM_SpecSample();

    vector eye = PM_LerpEye(pmove_org);
    eye.z += getstatf(STAT_VIEWHEIGHT);

    setviewprop(VF_ORIGIN, eye);
    makevectors(view_angles);
    SetListener(eye, v_forward, v_right, v_up);
    return TRUE;
}

static vector PM_LerpEye(vector fallback) {
    if (lm.valid < 3)
        return fallback;

    float simtime = cltime - lm.lat;

    if (simtime > lm.t[0])
        lm.lat = cltime - lm.t[0];              // ran past newest: hold back more
    else if (simtime < lm.t[2])
        lm.lat = cltime - lm.t[2];              // fell behind oldest: catch up
    else if (lm.newframe)
        lm.lat -= min(frametime * 0.005, 0.001);  // healthy: bleed latency off

    lm.newframe = FALSE;
    lm.lat = min(max(lm.lat, 0), kLerpMaxLat);

    simtime = cltime - lm.lat;

    float from = 2, to = 1;
    if (simtime > lm.t[1]) { from = 1; to = 0; }

    if (lm.t[to] == lm.t[from])
        return lm.o[to];

    float frac = min(max((simtime - lm.t[from]) / (lm.t[to] - lm.t[from]), 0), 1);
    return lm.o[from] + (lm.o[to] - lm.o[from]) * frac;
}

static void PM_UpdateLocalMovement() {
    entity ent = pm.ent;

    if (CVARF(fopm_lerpmove))
        PM_LerpSample();

    if (game_state.is_ceasefire || clientcommandframe > servercommandframe + 63) {
        PM_ActivatePMS(&pm_s);
    } else {
        PM_RunMovement(SimPMSD(), clientcommandframe);
    }

    vector org = pm.ent.origin;
    if (CVARF(fopm_lerpmove))
        org = PM_LerpEye(org);

    // Smooth stair stepping.  Modelled on Quake's V_CalcRefdef: step_oldz lags
    // the true z, ramping up at STEP_RAMP units/sec and never trailing by more
    // than STEP_MAX_LAG, for *any* upward movement while on ground.
    //
    // The previous form only fired for a discrete 8..24 unit jump with
    // velocity_z exactly zero, and did nothing at all outside that window --
    // so an 8-unit stair (the bound was strict, and 8 is a common map step),
    // two steps taken between render frames, or any residual vertical velocity
    // failing the exact compare all stepped hard.  pm.steptime is now simply
    // the last frame's time.
    float step_dt = min(max(time - pm.steptime, 0), 0.25);
    pm.steptime = time;

    if (PM_onground() && org_z > pm.step_oldz) {
        pm.step_oldz += step_dt * STEP_RAMP;

        if (pm.step_oldz > org_z)
            pm.step_oldz = org_z;
        if (org_z - pm.step_oldz > STEP_MAX_LAG)
            pm.step_oldz = org_z - STEP_MAX_LAG;

        pm.step = pm.step_oldz - org_z;  // <= 0: pulls the view down
    } else {
        pm.step_oldz = org_z;
        pm.step = 0;
    }

    float viewheight = CVARF(v_viewheight);
    if (viewheight < -7)
        viewheight = -7;
    else if (viewheight > 7)
        viewheight = 7;

    pm.vieworg = org;
    pm.vieworg.z += getstatf(STAT_VIEWHEIGHT) + viewheight;

    if (!game_state.is_alive && WP_PlayerClass())
        view_angles.z = CVARF(v_deathtilt) * 80;

    // Correct view position over ErrorTime()
    if (pm.errortime - time > 0)
        pm.vieworg += (pm.errortime - time) * (1 / ErrorTime()) * pm.error;

    if (!CVARF(fopm_nostep))
        pm.vieworg.z += pm.step;
}

void PMD_UpdateImpulse(int seq);

void PM_SyncTo(float seq) {
    if (!PM_Enabled())
        return;

    if (!game_state.is_alive)
        return;

    // Skip using the cache; bit of a hack to improve prediction quality.. some
    // issues with jumps sounds that it fixes to look into...  This isn't
    // supposed to matter.
    PM_RunMovement(&pm_s, seq);

    entity ent = pm.ent;
    // Note: ~FL_ONGROUND and jump occur in same frame, produces JUMP_HELD
    float jumping = input_buttons & BUTTON_JUMP;
    float landing = pm.last_vel_z < 0 && (ent.flags & FL_ONGROUND);
    float jump_frame = ent.pmove_flags & PMF_JUMP_HELD;

    PM_Sounds(jumping, jump_frame, landing, pm.last_vel_z);
}

static void PM_HandleRemovedNudges() {
    if (!pstate_server.num_filter_ents)
        return;

    for (float i = 0; i < nudges.length; i++) {
        PM_Nudge* n = &nudges[i];
        if (nudge_expired(n))
            continue;

        for (float j = 0; j < pstate_server.num_filter_ents; j++) {
            if (n->nat != NA_SEQ && n->src_no == pstate_server.filter_ents[j]) {
                n->nat = NA_SEQ;
                n->seq = n->expire_frame = pstate_server.seq;
            }
        }
    }
    pstate_server.num_filter_ents = 0;
}

void PM_ServerUpdate() {
    float was_enabled = PM_Enabled();
    float enabled = (pstate_server.predict_flags & PF_PMOVE) &&
                    game_state.is_player;

    if (isdemo())
        enabled = 0;

    if (enabled != was_enabled ||
        game_state.is_player != prev_game_state.is_player)
        PM_SetEnabled(enabled);

    if (!pstate_server.pmove.enabled)
        return;

    PM_HandleRemovedNudges();
    if (have_active_nudges) {
        have_active_nudges = FALSE;
        for (int i = 0; i < nudges.length; i++) {
            if (!nudge_expired(&nudges[i])) {
                have_active_nudges = TRUE;
                break;
            }
        }
    }

    pm_so = pm_s;
    pm.server_seq = servercommandframe;
    pm.seq = pm.server_seq + 1;  // server state includes move
    pm.interp_t = pstate_server.server_time;
    pm.ent.origin = pstate_server.pmove.origin;
    pm.ent.velocity = pstate_server.pmove.velocity;
    PM_SavePMS(&pm_s);

    if (!CVARF(fopm_nocache)) {
        // clientcommandframe) so that we can accelerate the common case of
        // computation at clientcommandframe (which does require constant
        // re-evaluation).  In the case there's no separation (e.g. lan pings)
        // then the server frame is directly used as the cache frame.
        if (clientcommandframe > servercommandframe + 1)
            PM_RunMovement(&pm_s, clientcommandframe - 1);
        PM_SavePMS(&pm_c);
        cache_invalidated = FALSE;
    }

    if (enabled && was_enabled)
        PM_UpdateError();
    PMD_UpdateImpulse(servercommandframe);
}

void PM_Refresh() {
    if (!PM_Enabled())
        return;

    entity ent = pm.ent;
    if (game_state.is_player) {
        ent.owner = edict_num(player_localentnum);
        ent.movetype = MOVETYPE_WALK;
        ent.solid = SOLID_SLIDEBOX;
    } else {
        ent.owner = world;  // Needs more than this for spec..
        ent.movetype = MOVETYPE_NOCLIP;
        ent.solid = SOLID_NOT;
    }
}

DEFCVAR_FLOAT(cl_upspeed, 400);
void PM_InputFrame() {
    float max_speed = isdemo() ? SPEC_MAXSPEED : pstate_pred.csqc_maxspeed;

    // cl_smartjump replacement
    float type;
    if (input_buttons & BUTTON_JUMP) {
        if (game_state.is_spectator ||
            (game_state.is_player && CVARF(fo_smartjump) && game_state.is_alive &&
            PM_GetWaterLevel(PM_Org(), &type) >= 2 && vlen(input_movevalues) == 0)) {
            input_buttons &= ~BUTTON_JUMP;
            input_movevalues.z = CVARF(cl_upspeed);
        }
    }

    if (game_state.is_player) {
        // Make sure that inconsistent CVAR>max doesnt contribute to clamp.
        float class_speed = Class_MaxSpeed(WP_PlayerClass());
        input_movevalues.x = min(input_movevalues.x, class_speed);
        input_movevalues.y = min(input_movevalues.y, class_speed);
        input_movevalues.z = min(input_movevalues.z, class_speed);
    }

    // Technically the sync with pstate_pred being on the right frame is loose..
    if (pstate_pred.tfstate & TFSTATE_AIMING)
        max_speed = min(max_speed, 80);

    if (vlen(input_movevalues) > max_speed)
        input_movevalues = normalize(input_movevalues) * max_speed;
}

////////////////////////////////////////////////////////////////////////////////
// View/Render
////////////////////////////////////////////////////////////////////////////////

// The eye actually being rendered from: ours when fo_pmove owns the view, the
// engine's otherwise.  Lets the smoothness metric measure either path.
vector PM_ViewOrigin() {
    return PM_Enabled() ? pm.vieworg : pmove_org;
}

void PM_UpdateView() {
    PM_UpdateLocalMovement();
    setviewprop(VF_ORIGIN, pm.vieworg);
    setviewprop(VF_ANGLES, view_angles);

    makevectors(view_angles);
    SetListener(pm.vieworg, v_forward, v_right, v_up);

    EffectToDynamicLight(pm.vieworg, pstate_server.effects);
}

////////////////////////////////////////////////////////////////////////////////
// Smoothness metric
////////////////////////////////////////////////////////////////////////////////
//
// Quantifies how evenly the eye actually translates, to replace "feels
// smoother" with a number when comparing configs or engines.
//
// Sampled from the camera trajectory rather than pixels: CSQC has no
// framebuffer readback, and pixels would fold in GPU queueing, animation lerp
// and texture detail -- none of which is the thing being chased.
//
// CRITICAL: dt comes from cltime, never frametime.  frametime is the limiter's
// *output* and is pinned to exactly 1/cl_maxfps while jitter stays under
// cl_maxfps_slop, so dividing by it would normalise away the very irregularity
// we are trying to detect and every config would score identically.  cltime is
// built from raw realtime and is honest.  Their difference is a free bonus
// metric: the pacing error the limiter is concealing.

DEFCVAR_FLOAT(fopm_smooth, 0);

// Sampling window: long enough to average out mouse input, short enough to
// read as a rolling series while you move.
static const float kSmoothPeriod = 3;

void PM_SmoothStatus();

static struct {
    float have_prev, last_t, start_t;
    vector last_eye, last_vel;

    float n;                  // frames contributing to roughness
    float sum_v, sum_dv;      // apparent speed, and its frame-to-frame change
    float peak_v;

    // Horizontal *speed* roughness.  The vector form above counts direction
    // change as roughness, so a figure-8 scores badly however smooth it is;
    // and Z is dominated by jumping.  Bunnyhopping holds horizontal speed
    // roughly constant, so variation in |v_xy| is mostly artifact.
    float sum_hv, sum_dhv;

    float moving, stalls;     // stall = camera held still while genuinely moving
    float sum_pace, peak_pace;      // frametime - dt
    float sum_lat, peak_lat;        // servo latency, i.e. what smoothness costs
} sm;

static void PM_SmoothReset() {
    sm.have_prev = sm.start_t = 0;
    sm.n = sm.sum_v = sm.sum_dv = sm.peak_v = 0;
    sm.sum_hv = sm.sum_dhv = 0;
    sm.moving = sm.stalls = 0;
    sm.sum_pace = sm.peak_pace = 0;
    sm.sum_lat = sm.peak_lat = 0;
}

// Call once per rendered frame with whatever eye position is authoritative.
void PM_SmoothProbe(vector eye) {
    if (!CVARF(fopm_smooth)) {
        if (sm.have_prev)
            PM_SmoothReset();
        return;
    }

    float t = cltime;
    if (!sm.have_prev) {
        sm.have_prev = TRUE;
        sm.start_t = t;
        sm.last_t = t;
        sm.last_eye = eye;
        return;
    }

    float dt = t - sm.last_t;
    if (dt <= 0)
        return;

    // Raw |dp| would just track how fast you are running; per-frame apparent
    // velocity is the primitive.  A correctly smoothed camera holds this
    // near-constant even while dt jitters -- that is the property being tested.
    vector v = (eye - sm.last_eye) * (1 / dt);
    float speed = vlen(v);

    vector hv = v;  hv_z = 0;
    float hspeed = vlen(hv);
    vector last_hv = sm.last_vel;  last_hv_z = 0;

    // Only meaningful while the servo is actually running -- lm.lat is not
    // cleared when the cvar is turned off, so reading it unconditionally
    // reports a stale value from the last time lerpmove was enabled.
    float lat = CVARF(fopm_lerpmove) ? lm.lat : 0;
    sm.sum_lat += lat;
    sm.peak_lat = max(sm.peak_lat, lat);

    float pace = fabs(frametime - dt);
    sm.sum_pace += pace;
    sm.peak_pace = max(sm.peak_pace, pace);

    if (sm.n > 0 || sm.last_vel != '0 0 0') {
        sm.sum_dv += vlen(v - sm.last_vel);
        sm.sum_v += speed;

        sm.sum_dhv += fabs(hspeed - vlen(last_hv));
        sm.sum_hv += hspeed;
        sm.peak_v = max(sm.peak_v, speed);
        sm.n++;

        // Targets the clamp signature specifically: the camera holding still
        // for a frame despite real elapsed time and real velocity.  A generic
        // roughness number moves for many reasons; this moves for ~one.
        if (speed > 50) {
            sm.moving++;
            if (vlen(eye - sm.last_eye) < 0.1 * speed * dt)
                sm.stalls++;
        }
    }

    sm.last_t = t;
    sm.last_eye = eye;
    sm.last_vel = v;

    if (t - sm.start_t >= kSmoothPeriod)
        PM_SmoothStatus();
}

void PM_SmoothStatus() {
    if (sm.n < 2)
        return;

    float mean_v = sm.sum_v / sm.n;

    printf("smooth over %d frames / %0.1fs\n", sm.n, sm.last_t - sm.start_t);
    // Dimensionless, so comparable across runs and movement speeds.  Lower is
    // smoother; this is the headline figure.
    printf("  roughness   %0.4f   (mean |dv| / mean |v|)\n",
           mean_v > 0 ? sm.sum_dv / sm.sum_v : 0);
    // The figure to trust while bunnyhopping: direction change and jump Z are
    // excluded, so this is much closer to pure artifact.
    printf("  h-roughness %0.4f   (mean |d|v_xy|| / mean |v_xy|)\n",
           sm.sum_hv > 0 ? sm.sum_dhv / sm.sum_hv : 0);
    printf("  stalls      %0.2f%%  (%d of %d moving frames)\n",
           sm.moving > 0 ? sm.stalls * 100 / sm.moving : 0,
           sm.stalls, sm.moving);
    // Stalls should pair with spikes: a held frame is followed by a
    // double-length step.  Stalls without a raised peak means something other
    // than a clamp is at work.
    printf("  catch-up    %0.2f    (peak |v| / mean |v|)\n",
           mean_v > 0 ? sm.peak_v / mean_v : 0);
    printf("  pacing err  %0.2fms avg, %0.2fms peak  (|frametime - dt|)\n",
           sm.sum_pace / sm.n * 1000, sm.peak_pace * 1000);
    // What the servo costs: the eye is held this far behind the newest sample.
    // Should settle just above the worst inter-frame gap and stay there; if it
    // pumps, the servo is hunting rather than converging.
    printf("  lerp lat    %0.2fms avg, %0.2fms peak  (fopm_lerpmove)\n",
           sm.sum_lat / sm.n * 1000, sm.peak_lat * 1000);

    PM_SmoothReset();
}

////////////////////////////////////////////////////////////////////////////////
// Debug
////////////////////////////////////////////////////////////////////////////////

static const float NIMP = 300;
struct PmoveDebug {
    float points[NIMP];
    int nimp;
};

static PmoveDebug pmd[NUM_DBG_GRAPH_TYPES];

static void PMD_AddPoint(int ptype, float val) {
    PmoveDebug* pd = &pmd[ptype];

    pd->points[pd->nimp++ % NIMP] = val;
}

static void PMD_UpdateImpulse(int seq) {
    if (!CVARF(fopmd_graph))
        return;

    static int old_seq;
    if (old_seq == seq)
        return;
    old_seq = seq;

    float cseq = clientcommandframe;
    if (PM_Enabled())
        PM_RunMovement(SimPMSD(), cseq);

    PMH_Log(cseq);

    vector sv = pm_s.vel;
    vector pv = PM_Vel();

    if (!vlen(pv) && !vlen(sv))
        return;

    PMD_AddPoint(SERVER, vlen(sv));
    PMD_AddPoint(PMOVE,  vlen(pv));

    PMD_AddPoint(ERROR_VIEW, vlen(pm.error) / 128 * 1200);

    PM_History* hist = PMH_Get(servercommandframe);
    if (!hist)
        return;

    PMD_AddPoint(ERROR_POS, hist ? vlen(pm_s.org - hist.org) : 0);
    PMD_AddPoint(ERROR_VEL, hist ? vlen(pm_s.vel - hist.vel) : 0);
}

static void PMD_Graph(int type, int offset, vector c1, vector c2, vector rgb) {
    PmoveDebug* pd = &pmd[type];
    float wx = c2.x - c1.x, wy = c2.y - c1.y;

    float maxv = pd->points[0], minv = pd->points[0];
    for (int i = 1; i < NIMP; i++) {
        maxv = max(maxv, pd->points[i]);
        minv = min(minv, pd->points[i]);
    }

    float h = max(maxv - minv, 1200);

    float px = wx / NIMP, py = (wy - 2) / h;
    vector lend = c1 + [0, wy, 0];

    vector m1 = [0, wy - maxv * py, 0];
    drawline(1, c1 + m1, c1 + m1 + [wx, 0, 0], '50 150 150', 1);

    for (int i = offset; i < NIMP; i++) {
        int idx = (pd->nimp + i) % NIMP;
        vector sx =
            [c1.x + (i - offset) * px, c2.y - (pd->points[idx]) * py + 1, 0];
        vector sy = [sx.x + px, sx.y, 0];

        drawline(1, sx, sy, rgb, 1);
        drawline(1, lend, sx, rgb, 1);
        lend = sy;
    }
}

void PMD_DrawGraphs(float width) {
    float pmove_on = pstate_server.predict_flags & PF_PMOVE;
    if (pmove_on)
        drawstring([width - 100, 20, 0], sprintf("PM err: %0.1f", vlen(pm.error)),
                   '8 8 0', '1 1 1', 1, 0);

    if (!CVARF(fopmd_graph))
        return;

    vector c1 = [CVARF(fopmd_graph_x), CVARF(fopmd_graph_y), 0];
    if (c1.x < 0)
        c1.x += width - CVARF(fopmd_graph_w);
    vector w =  [CVARF(fopmd_graph_w), CVARF(fopmd_graph_h), 0];
    vector c2 = c1 + w;

    drawfill(c1, w, '0.2 0.2 0.2', 1);
    drawfill(c2, '5 5 5', '1 0 0', 1);

    float offset = (CVARF(fopmd_graph) & PMDG_NO_ALIGN_INTERP) ? 0 :
        clientcommandframe - servercommandframe - 1;

    offset = max(0, offset);
    PMD_Graph(PMOVE, 0, c1, c2, '0 0 1');
    PMD_Graph(SERVER, offset, c1, c2, '0 1 0');

    if ((CVARF(fopmd_graph) & PMDG_ERROR_VIEW) &&
            (pstate_server.predict_flags & PF_PMOVE))
        PMD_Graph(ERROR_VIEW, 0, c1, c2, '1 0 1');
    if ((CVARF(fopmd_graph) & PMDG_ERROR_VEL))
        PMD_Graph(ERROR_VEL, 0, c1, c2, '1 1 0');
    if ((CVARF(fopmd_graph) & PMDG_ERROR_POS))
        PMD_Graph(ERROR_POS, 0, c1, c2, '1 0 0');

}
