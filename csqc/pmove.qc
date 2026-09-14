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

// ---- jump pad prediction (experiment) ----
//
// Push volumes are static and their effect is a constant, so the prediction
// can run them itself instead of being launched a round trip late.  The server
// sends the plain ones when we join (SendPushVolumes); anything aimed or gated
// is left to arrive as state, as all of them used to.
DEFCVAR_FLOAT(fopm_pushpred, 1);

static const float PUSHPRED_MAX = 32;
struct PM_Push { vector mins, maxs, vel; };
static PM_Push pm_push[PUSHPRED_MAX];
static float pm_npush;

void PM_SetPushVolumes(float n) {
    pm_npush = n > PUSHPRED_MAX ? PUSHPRED_MAX : n;
    printf("pmd: %i push volumes for prediction\n", (int)pm_npush);
    float verbose = CVARF(fopmd_debug) > 1;
    for (float i = 0; i < n; i++) {
        vector mins, maxs, vel;
        mins_x = readcoord(); mins_y = readcoord(); mins_z = readcoord();
        maxs_x = readcoord(); maxs_y = readcoord(); maxs_z = readcoord();
        vel_x  = readcoord(); vel_y  = readcoord(); vel_z  = readcoord();
        if (i >= PUSHPRED_MAX)
            continue;
        pm_push[i].mins = mins;
        pm_push[i].maxs = maxs;
        pm_push[i].vel = vel;
        if (verbose)
            printf("pmd:   pad %v .. %v vel=%v\n", mins, maxs, vel);
    }
}

// Does the segment from a to b touch the box the way the server would?  One
// axis at a time, narrowing the range of the segment that could still be
// inside all of them.
//
// Leaving does not count.  The server picks triggers up from the move's own
// traces and from where the move ended, so entering one, crossing it, or
// staying in it all touch, but a frame that starts inside and ends outside
// does not -- and on a pad that frame is a second launch the server never
// gave.
static float PM_SegHitsBox(vector a, vector b, vector lo, vector hi) {
    vector d = b - a;
    float tmin = 0, tmax = 1, t1, t2, t;

    for (float axis = 0; axis < 3; axis++) {
        float da = axis == 0 ? d_x : (axis == 1 ? d_y : d_z);
        float aa = axis == 0 ? a_x : (axis == 1 ? a_y : a_z);
        float la = axis == 0 ? lo_x : (axis == 1 ? lo_y : lo_z);
        float ha = axis == 0 ? hi_x : (axis == 1 ? hi_y : hi_z);

        if (fabs(da) < 0.000001) {
            if (aa < la || aa > ha)
                return FALSE;   // parallel to this slab and outside it
            continue;
        }
        t1 = (la - aa) / da;
        t2 = (ha - aa) / da;
        if (t1 > t2) { t = t1; t1 = t2; t2 = t; }
        if (t1 > tmin) tmin = t1;
        if (t2 < tmax) tmax = t2;
        if (tmin > tmax)
            return FALSE;
    }
    if (tmin <= 0 && tmax < 1)
        return FALSE;   // started inside and left: the server does not re-touch
    return TRUE;
}

// The engine collects the triggers a player sweeps through during the move and
// touches them after it, so a volume entered and left inside one frame still
// fires.  Testing only where the frame ended misses the fast ones by a frame,
// which on a pad is the difference between being launched now and next frame.
// Sweep the player's box along the move instead, which is the same as sweeping
// its origin through the volume grown by the box.
static void PM_PushVolumes(entity ent, vector from) {
    if (!CVARF(fopm_pushpred) || !pm_npush)
        return;
    // The volume arrives as the absolute bounds the server keeps, which the
    // engine already grew by a unit when it linked the trigger, and the box it
    // tests against them is grown by a unit as well.  Match both.
    const vector margin = '1 1 1';
    for (float i = 0; i < pm_npush; i++) {
        vector lo = pm_push[i].mins - ent.maxs - margin;
        vector hi = pm_push[i].maxs - ent.mins + margin;
        if (!PM_SegHitsBox(from, ent.origin, lo, hi))
            continue;
        ent.velocity = pm_push[i].vel;
        PMD_Event(PMDE_PUSH);
    }
}

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
// Frame and time of the previous server update, for judging nudge expiry in
// the error pass's prior replay as it stood when that prediction was shown.
static int pm_prev_update_seq;
static float pm_prev_update_time;
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
    float src_cseq;    // created_seq of the projectile this came from (predicted and server copies share it)
    float trace_seq;   // RJ_TRACE: last replay seq this nudge was reported at
};

const static float NUDGE_SEQ = 3;
const static float NUDGE_EPS = NUDGE_SEQ * SERVER_FRAME_DT;
static PM_Nudge nudges[8];
static float num_nudges, have_active_nudges;
static float nudges_added;   // since the last error pass; its saved prior state predates them
static float rj_trace_until_seq;   // RJ_TRACE: report server updates/errors until this seq
// RJ_TRACE: per-frame result of the most recent replay, i.e. what was shown for that frame.
struct RJ_Shown { float seq; vector org, vel; };
static const float RJ_NSHOWN = 64;
static RJ_Shown rj_shown[RJ_NSHOWN];

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
        nudges_added = TRUE;
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
    float push_frame = n->seq;
    if (n->nat == NA_SEQTIME)
        push_frame += floor(n->itime / SERVER_FRAME_DT);
    rj_trace("C: nudge-removed src=%.0f ent=%.0f nat=%s seq=%.0f itime=%.3f", n->src_no, self.entnum, NAT_tos(n->nat), n->seq, n->itime);
    rj_trace(" push@%.0f expire@scf=%.0f ccf=%.0f\n", push_frame, servercommandframe, clientcommandframe);
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

// Does the explosion reach us?  The server casts five rays, to our origin and
// to four corners of our box, and takes any one of them as reached; a single
// ray refuses knock the server grants around a pillar or a doorframe, so cast
// the same five.
//
// One difference is left and cannot be closed from here: the server clips
// against solid brush entities as well as the world, and doors and platforms
// are not in the client's trace world at all, so an explosion behind one is
// blocked for the server and clear for us.
static float PM_ExplosionReaches(vector src, vector targ) {
    const float MOVE_WORLDONLY = 3;
    vector corners[5] = { '0 0 0', '15 15 0', '-15 -15 0', '-15 15 0', '15 -15 0' };
    for (float i = 0; i < 5; i++) {
        traceline(src, targ + corners[i], MOVE_WORLDONLY, pm.ent);
        if (trace_fraction == 1)
            return TRUE;
    }
    return FALSE;
}

static void PM_NudgeExplosion(PM_Nudge* nudge, entity ent) {
    KnockBlast b;
    b.type = KNOCK_RADIUS;
    b.src = nudge->org;
    b.base = nudge->aux;
    b.flags = KF_BOTH_PLAYER;   // assumes everything is from a player for now
    if (nudge->src.owner == pengine.player_ent)
        b.flags |= KF_SELF;
    b.slack = NudgeExplosionEps();

    float points = Knock_Points(&b, ent);
    if (!points)
        return;

    if (!PM_ExplosionReaches(b.src, ent.origin))
        return;

    // The scaling chain the server runs in TF_T_Damage().  Both inputs are our
    // own state: TFSTATE_BURNING is predicted, and explosion armour arrives as
    // a predict flag because it comes from pickups rather than playerclass.
    //
    // Still unmodelled: KF_QUAD.  That depends on the *attacker's*
    // super_damage_finished, which we do not have for someone else's grenade,
    // so a quadded thrower still mispredicts by 4x.
    float dsf = 0;
    if (pstate_pred.tfstate & TFSTATE_BURNING)
        dsf |= DSF_BURNING;
    if (pstate_server.predict_flags & PF_SAVE_EXPLOSION)
        dsf |= DSF_SAVE_EXPLOSION;

    float moment = Class_ScaleMoment(WP_PlayerClass(), Damage_Scale(points, b.flags, dsf));
    vector knock = Knock_Velocity(&b, ent, moment);

    if (nudge->trace_seq != pm.seq) {   // replays re-apply at the same seq; report once per seq
        nudge->trace_seq = pm.seq;
        Knock_Trace(&b, ent, pm.seq, pm.interp_t + input_timelength, nudge->itime, moment, knock);
        rj_trace_until_seq = pm.seq + 30;
    }

    pm.ent.velocity += knock;
    PMD_Knock(knock, moment);
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
    n->src_cseq = ent.created_seq;

    ent.nudge = n;
    ent.removefunc = PM_RemoveSelfNudges;

    return n;
}

// The server's copy of a predicted projectile has arrived with an explicit
// push time: it supersedes whatever the predicted copy scheduled.  Kill that
// outright rather than letting removal expire it at the current frame, so
// the error pass's prior replay (which judges expiry as of the previous
// update) doesn't apply both.
static void PM_SupersedePredictedNudge(entity sent) {
    for (float i = 0; i < nudges.length; i++) {
        PM_Nudge* n = &nudges[i];
        if (n->type != NT_EXPLOSION || n->src_no != 0 || nudge_expired(n))
            continue;
        if (n->src_cseq != sent.created_seq)
            continue;
        rj_trace("C: nudge-superseded cseq=%.0f nat=%s seq=%.0f itime=%.3f by fk=%.3f\n",
                 n->src_cseq, NAT_tos(n->nat), n->seq, n->itime, sent.forward_knock);
        n->nat = NA_NONE;
    }
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
    KnockBlast b;
    b.type = KNOCK_BOUNCE;
    b.src = nudge->org;
    b.base = nudge->aux;
    b.flags = 0;
    b.slack = NudgeExplosionEps();

    float points = Knock_Points(&b, ent);
    if (!points)
        return;

    vector before = ent.velocity;
    ent.velocity = Knock_Velocity(&b, ent, points);
    PMD_Knock(ent.velocity - before, points);

    if (nudge->trace_seq != pm.seq) {
        nudge->trace_seq = pm.seq;
        Knock_Trace(&b, ent, pm.seq, pm.interp_t + input_timelength, nudge->itime,
                    points, ent.velocity - before);
    }

    NB_ConcCapAction(ent, pstate_pred.playerclass, &pstate_pred.tfstate,
                     pm.interp_t, &pstate_pred.conc_cap_time, kLaunch);
}


// A time the server chose on its own clock, moved onto the command clock the
// replay windows are built from.  Without this the push lands however far the
// two clocks have drifted apart, which is tens of milliseconds and reads as a
// blast going off a couple of frames early.
float PM_WorldToCmdTime(float t) {
    return t + pstate_server.pmove.cmd_clock_skew;
}

void PM_AddGrenadeExplosion(float itime, entity ent) {
    if (!PM_Enabled())
        return;

    // Our own command clock when the grenade appeared, read on the server and
    // sent to us alone, plus what was left of the fuse.  A base we both hold
    // identically and a duration we both measure the same way, so neither
    // side converts a world time with an offset the other cannot see.  Which
    // command a fuse lands on is a discrete choice, and two samples of that
    // offset taken a round trip apart differ by a few milliseconds, which near
    // a frame edge is a whole frame of push.
    if (ent.has_cmd_base)
        itime = ent.fpp.cmd_base + max(ent.fpp.expires_at - ent.created_at, 0);
    else
        itime = PM_WorldToCmdTime(itime);
    itime += KNOCK_LEAD;   // the same lead the server schedules it with

    // A nudge normally stops once the server's state has reached its time, on
    // the basis that the state then carries the push itself.  The server runs
    // a fuse in its physics phase, after the command whose clock covers it, so
    // for a stretch the state has not caught up and the nudge is already gone
    // -- and the prediction drops a push it had been showing.  Hold it a
    // couple of server frames longer; the filter the server sends for the
    // exploding entity is what really retires it.
    float hold = 2 * SERVER_FRAME_DT;

    FO_GrenExp exp;
    if (!FO_GrenGetExp(ent.fpp.gren_type, exp))
        return;

    float dmg = exp.dmg;

    PM_Nudge* n;
    if (exp.type == kRadiusDamage)
        PM_AddNudgeExplosion(NA_ITIME_EXPLICIT_EXPIRE, 0, itime, ent, dmg);
    else
        PM_AddNudgeBounce(itime, ent, dmg);

    if (ent.nudge)
        ent.nudge->expire_time = itime + hold;
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
    if (ent.owner == pengine.player_ent)
    {
        rj_trace("C: sim t=%.3f type=%i itime=%.3f fk=%.3f stime=%.3f cseq=%.0f",
                 time, ent.fpp.index, itime, ent.forward_knock, ent.s_time, ent.created_seq);
        rj_trace(" svt=%.3f ccf=%.0f org=%v\n", pstate_server.server_time, clientcommandframe, ent.origin);
    }
    if (ent.forward_knock && ent.owner == pengine.player_ent) {
        if (ent.forward_knock == -1)
            return;
        nat = NA_ITIME_EXPLICIT_EXPIRE;  // Knock forwards are synchronized
        itime = ent.forward_knock;
        PM_SupersedePredictedNudge(ent);
    } else if (ent.entnum && ent.has_cmd_base && ent.s_time) {
        // Someone else's rocket: our clock when it appeared plus its flight,
        // which both sides measure from the projectile's own start.  Its
        // physics clock cannot be compared across the wire -- the server runs
        // it on server time and we run ours on interpolation time, on purpose,
        // so that collisions line up with what we are shown -- but the time it
        // has been in the air is the same quantity on both sides.
        itime = ent.fpp.cmd_base + max(itime - ent.s_time, 0);
    } else if (ent.entnum) {
        itime = PM_WorldToCmdTime(itime);   // the server's clock, not ours
    } else if (ent.created_seq && ent.entnum == 0) {
        float dtime = 0;
        if (ent.s_time)
            dtime = max(itime - ent.s_time, 0);
        if (tf_config.cmd_time && ent.fire_cmd_time > 0) {
            // Same due time the server computes for its copy: the fire
            // command's clock plus the projectile's travel, on the fire
            // command itself when within a server frame.  Matched by window
            // like the server's explicit push, so the two land on the same
            // frame rather than one counted in frames and one in time.
            nat = NA_ITIME_EXPLICIT_EXPIRE;
            itime = ent.fire_cmd_time + (dtime > SERVER_FRAME_DT ? dtime : 0);
        } else {
            seq = ent.created_seq;
            itime = dtime;
            nat = NA_SEQTIME;  // Same as NA_SEQ when itime == 0
        }
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

// Server has us at MOVETYPE_NONE -- between pug rounds, and anywhere else it
// takes a player out of the simulation.  Consume the input frames so the
// sequence still advances (reconciliation expects pm.seq to reach endframe)
// but run no physics, so the predicted origin stays put instead of walking off
// and being yanked back by error correction.
static void RunFrozenMovement(float endframe) {
    entity ent = pm.ent;

    ent.velocity = '0 0 0';
    while (pm.seq <= endframe)
        pm.seq++;
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

    if (!game_state.is_spectator &&
        pstate_server.movetype == MOVETYPE_NONE) {
        RunFrozenMovement(endframe);
        return;
    }

    if (!game_state.is_spectator && !game_state.is_alive) {
        RunDeadMovement(endframe);
        return;
    }

    ASSERTF_GT(pm.seq, 0);

    while (pm.seq <= endframe) {
        if (!getinputstate(pm.seq))
            break;

        // The chain is an estimate of the world clock, and the server corrects
        // it as it wanders.  A correction is announced before the command it
        // applies to, so we fold the same amount into the same place and our
        // chain stays identical to theirs.
        float step = input_timelength;
        if (pstate_server.pmove.cmd_clock_fix_seq &&
            pm.seq == pstate_server.pmove.cmd_clock_fix_seq)
            step += pstate_server.pmove.cmd_clock_fix;

        pm.ent.pmove_flags &= ~PMF_JUMP_HELD;  // Auto-bunny.
        // We have to apply this on the leading edge since INPUT_FRAME
        // modifications do not occur until the frame is finalized.
        if (pm.seq == clientcommandframe)
            PM_InputFrame();

        vector pm_moved_from = ent.origin;
        RunPlayerPhysics();
        PM_PushVolumes(ent, pm_moved_from);

        if (!CVARF(fopm_nonudge) && pm.seq != clientcommandframe) {
            float slack = 0;
            PM_ApplyNudges(ent, pm.seq, pm.interp_t, pm.interp_t + step, slack);

            if (pstate_pred.tfstate & TFSTATE_CONC) {
                if (pointcontents(ent.origin) == CONTENT_WATER)
                    ent.flags |= FL_INWATER;  // pmove doesn't usually maintain this.
                                              //
                if (!Conc_Update(&pstate_pred.conc_state, pm.ent,
                        pm.interp_t + step, pm.interp_t)) {
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

#if RJ_TRACE
        {
            RJ_Shown* sh = &rj_shown[pm.seq % RJ_NSHOWN];
            sh->seq = pm.seq;
            sh->org = ent.origin;
            sh->vel = ent.velocity;
        }
#endif
        // Not the newest frame: its nudges are deliberately deferred a frame,
        // and the cache means this pass can be the last one that touches it,
        // so recording it would journal a frame with its pushes left out.
        // The engine's player physics leaves .waterlevel alone, so take it
        // from the world rather than the entity.
        if (pm.seq != clientcommandframe) {
            float wtype;
            PMD_Record(pm.seq, ent.origin, ent.velocity,
                       (ent.flags & FL_ONGROUND) ? 1 : 0,
                       PM_GetWaterLevel(ent.origin, &wtype));
        }
        pm.seq++;
        pm.interp_t += step;
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
    pmd_norecord++;

    ent.owner = edict_num(player_localentnum);
    if (CVARF(fopm_noerror) || !game_state.is_alive ||
        (clientcommandframe == servercommandframe + 1)) {
        pm.error = '0 0 0';
        pm.errortime = 0;
        pmd_norecord--;
        return;
    }

    // The saved prior is a mid-prediction state from the previous update.  A
    // nudge added since then may land before it, so it can't be replayed in;
    // start from the raw previous state instead so the prior and the new
    // prediction contain the same pushes and only real mismatch remains.
    static PMS_Data last;
    if (nudges_added || last.server_seq != pm_s.server_seq - 1)
        last = pm_so;
    nudges_added = FALSE;

    // Run prior prediction to present.  Nudge expiry is judged against the
    // previous update's frame and time, as it was when this prediction was
    // shown.  This update may already have expired a nudge whose push it is
    // the first to carry -- an immediate self-knock, or the update after a
    // lost one -- and replaying without it reports the whole knock as a
    // correction that never happened on screen.
    // have_active_nudges was recomputed against this update above and may
    // already be false for the same reason, which would skip nudges entirely.
    float held_seq = pstate_server.seq, held_time = pstate_server.server_time;
    float held_active = have_active_nudges;
    if (pm_prev_update_seq) {
        pstate_server.seq = pm_prev_update_seq;
        pstate_server.server_time = pm_prev_update_time;
        have_active_nudges = TRUE;
    }
    PM_RunMovement(&last, clientcommandframe);
    pstate_server.seq = held_seq;
    pstate_server.server_time = held_time;
    have_active_nudges = held_active;
    vector err = ent.origin;

    // Repeat with updated state.
    PM_RunMovement(SimPMSD(), clientcommandframe - 2);
    PM_SavePMS(&last);  // Save at -2 to replay nudges going into -1
    PM_RunMovement(SimPMSD(), clientcommandframe);

    // New nudges can result in small errors on replay due to timeshift, we
    // could backdate all the nudges and recompute the world but as a first
    // simpler pass let's just filter them out.
    float filtered = (pm.last_nudge == clientcommandframe - 1);
    if (filtered)
        err = '0 0 0';
    else
        err -= ent.origin;

    if (servercommandframe < rj_trace_until_seq)
        rj_trace("C: err scf=%.0f ccf=%.0f err=%.2f %v filtered=%.0f lastnudge=%.0f acc=%.2f\n",
                 servercommandframe, clientcommandframe, vlen(err), err, filtered, pm.last_nudge, vlen(pm.error));


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
    pmd_norecord--;
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
    float maxlat;   // latency ceiling
} lm;

static void PM_LerpReset() {
    lm.valid = lm.lat = lm.newframe = 0;
    lm.last_seq = -1;
    lm.maxlat = kLerpMaxLat;
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
    lm.maxlat = kLerpMaxLat;
    lm.newframe = TRUE;
    if (lm.valid < 3)
        lm.valid++;
}

// Spectating needs a different tool than the pmove path.  That servo is a
// jitter buffer: it reconstructs motion from a *stepped* signal by holding
// back and interpolating between discrete updates.  The spectator position is
// already dense -- the engine interpolates it -- but noisy, so there are no
// steps to bridge and delaying it just adds lag without removing the shake.
// Widening the buffer measurably did not help.
//
// A noisy continuous signal wants a low-pass instead: follow the target with
// a fixed time constant, so high-frequency shake is attenuated while real
// motion still comes through a beat later.
// Shortest way round, so yaw crossing 180 does not spin the camera.  Loops
// rather than a single test: one subtraction only normalises a delta already
// inside +-540, and spec_ang can be arbitrarily stale after a switch.
static float AngleDelta(float cur, float target) {
    float d = target - cur;
    while (d > 180)  d -= 360;
    while (d < -180) d += 360;
    return d;
}

// Beyond this in a single frame it is a spectate switch or a teleport, not
// someone turning -- interpolating across it swings the camera the long way.
const float kSpecAngSnap = 60;

float spec_have;
vector spec_eye;
vector spec_ang;
float spec_outlier;   // consecutive frames the incoming sample looked wrong

// The spectator view, smoothed.
//
// The engine's own camera is already interpolated per frame, so there is
// nothing to reconstruct: delaying it cannot reduce roughness (shifting a
// sequence leaves every frame-to-frame delta unchanged) and interpolating it
// only recovers detail a stepped source would have lost.  A low-pass is the
// one mechanism that actually smooths, and it pays for it in lag.
//
// Earlier versions here inferred timing they did not need -- an adaptive
// jitter buffer, a time-based delay, a whole-frame ring -- and each measured
// identical to doing nothing, because none of them filtered.
DEFCVAR_FLOAT(fopm_spec_lerp, 1);     // master switch
DEFCVAR_FLOAT(fopm_spec_filter, 0.05);  // low-pass time constant, seconds

// Turn rate, deg/sec, at which the filter runs twice as fast.
//
// A flick is a deliberate fast turn, not a discontinuity, so it never trips
// the teleport snap -- the filter simply rounds it off and the camera
// undershoots where the player actually looked.  Rather than lower tau
// globally and lose the smoothing everywhere, scale it by how fast the aim is
// moving:
//
//     tau_eff = tau / (1 + (turn/flick)^2)
//
// Continuous and monotonic, with no threshold to cross -- an earlier version
// ramped between two cutoffs and the knees at each end made the response step,
// which is the chop.  Here the filter simply gets progressively quicker the
// faster the player turns, and never fully stops filtering.
DEFCVAR_FLOAT(fopm_spec_flick, 1500);

vector spec_raw_eye, spec_raw_ang;    // last accepted sample, for outlier tests
float spec_last_t;

// Flick detection runs at server rate, not render rate.  A render frame is a
// few ms with jittery timing, so dividing a small angular delta by it
// amplifies that jitter -- which is how a steady 700 deg/sec turn read as
// 5000.  Server frames are ~13ms and regularly spaced, so the same absolute
// timing error matters far less and the larger delta carries more signal.
vector spec_sv_ang;
float spec_sv_t, spec_sv_seq, spec_turn;

// TRUE if it took over the view.
float PM_SpecView() {
    // Must actually be spectating.  !PM_Enabled() alone is not enough: it is
    // also true for a live player with pmove off, and for a dead one -- and
    // taking their view over freezes it in place.
    //
    // player_localentnum <= 32 means we are viewing from a real player, the
    // same test TrackingPlayer() makes in main.qc (which compiles later).
    if (!CVARF(fopm_spec_lerp) || !game_state.is_spectator || PM_Enabled() ||
        player_localentnum > 32) {
        spec_have = FALSE;
        return FALSE;
    }

    // Read before we write: the engine establishes the view each frame before
    // calling CSQC_UpdateView, so this is its value and not our last one.  It
    // is the eye already, so no STAT_VIEWHEIGHT is wanted.
    vector target = getviewprop(VF_ORIGIN);
    vector aim = getviewprop(VF_ANGLES);

    float first = !spec_have;

    if (servercommandframe != spec_sv_seq) {
        float sdt = cltime - spec_sv_t;
        if (spec_sv_seq && sdt > 0)
            spec_turn = (fabs(AngleDelta(spec_sv_ang.y, aim.y)) +
                         fabs(AngleDelta(spec_sv_ang.x, aim.x))) / sdt;

        spec_sv_seq = servercommandframe;
        spec_sv_ang = aim;
        spec_sv_t = cltime;
    }

    // cltime, not frametime.  frametime is the limiter's idealised output and
    // can arrive as ~0, which the old max(frametime, 0.0001) floor turned into
    // a 5000 deg/sec reading from a half-degree step -- a phantom flick that
    // opened the filter and juddered.
    float dt = cltime - spec_last_t;
    spec_last_t = cltime;
    if (dt <= 0)
        dt = frametime;
    dt = bound(0.001, dt, 0.25);

    // Against the last raw sample, not the rendered one: the rendered one
    // legitimately trails, and calling that a discontinuity would snap
    // constantly.
    float big = !first &&
                (vlen(target - spec_raw_eye) > kLerpTeleport ||
                 fabs(AngleDelta(spec_raw_ang.y, aim.y)) > kSpecAngSnap ||
                 fabs(AngleDelta(spec_raw_ang.x, aim.x)) > kSpecAngSnap);

    spec_outlier = big ? spec_outlier + 1 : 0;

    // A spectate switch persists; a single bad sample does not.  Believing the
    // first one flashed to the garbage and back, so hold instead and only
    // accept the jump once it repeats.
    if (first || spec_outlier >= 2) {
        spec_raw_eye = spec_eye = target;
        spec_raw_ang = spec_ang = aim;
        spec_have = TRUE;
        spec_outlier = 0;
    } else if (!big) {
        spec_raw_eye = target;
        spec_raw_ang = aim;

        float tau = CVARF(fopm_spec_filter);
        if (tau > 0) {
            float lo = CVARF(fopm_spec_flick);
            if (lo > 0) {
                float r = spec_turn / lo;
                tau = tau / (1 + r * r);
            }

            float k = bound(0, dt / tau, 1);

            spec_eye += (target - spec_eye) * k;
            spec_ang.x += AngleDelta(spec_ang.x, aim.x) * k;
            spec_ang.y += AngleDelta(spec_ang.y, aim.y) * k;
            spec_ang.z += AngleDelta(spec_ang.z, aim.z) * k;
        } else {
            spec_eye = target;
            spec_ang = aim;
        }
    }
    // else: outlier, hold the previous eye and aim for this frame

    setviewprop(VF_ORIGIN, spec_eye);
    setviewprop(VF_ANGLES, spec_ang);
    makevectors(spec_ang);
    SetListener(spec_eye, v_forward, v_right, v_up);
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
    lm.lat = min(max(lm.lat, 0), lm.maxlat > 0 ? lm.maxlat : kLerpMaxLat);

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
                rj_trace("C: nudge-replaced src=%.0f was=%s seq=%.0f itime=%.3f -> SEQ at scf=%i (expires there)\n",
                         n->src_no, NAT_tos(n->nat), n->seq, n->itime, pstate_server.seq);
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

    if (servercommandframe < rj_trace_until_seq)
        rj_trace("C: sv scf=%.0f svt=%.3f org=%v vel=%v\n",
                 servercommandframe, pstate_server.server_time, pstate_server.pmove.origin, pstate_server.pmove.velocity);
#if RJ_TRACE
    // Same-frame alignment: the last replay's result for the frame this
    // update makes authoritative (i.e. what was shown for it), against what
    // the server says it was.
    {
        RJ_Shown* sh = &rj_shown[servercommandframe % RJ_NSHOWN];
        if (sh->seq == servercommandframe && was_enabled && game_state.is_alive) {
            vector dp = sh->org - pstate_server.pmove.origin;
            vector dv = sh->vel - pstate_server.pmove.velocity;
            if (servercommandframe < rj_trace_until_seq || vlen(dp) > 0.5 || vlen(dv) > 5)
                rj_trace("C: pm scf=%.0f svt=%.3f dpos=%.2f %v dvel=%.1f %v\n",
                         servercommandframe, pstate_server.server_time, vlen(dp), dp, vlen(dv), dv);
        }
    }
#endif
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

    pm_prev_update_seq = pstate_server.seq;
    pm_prev_update_time = pstate_server.server_time;
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
// The eye actually being rendered from.
//
// Not pmove_org when spectating: that is a raw stat stepping at server rate,
// while the engine's camera is interpolated per frame.  Measuring pmove_org
// reported roughness ~1.9 for a camera that is in fact smooth, which is what
// sent the spectator smoothing work chasing a problem that was not there.
vector PM_ViewOrigin() {
    if (PM_Enabled())
        return pm.vieworg;
    if (spec_have)
        return spec_eye;
    if (!game_state.is_spectator)
        return pmove_org;

    vector v = getviewprop(VF_ORIGIN);
    return v;
}

void PM_UpdateView() {
    PM_UpdateLocalMovement();
    setviewprop(VF_ORIGIN, pm.vieworg);
    setviewprop(VF_ANGLES, view_angles);

    makevectors(view_angles);
    SetListener(pm.vieworg, v_forward, v_right, v_up);

    // Always the local player, so mode 2 suppresses it here.
    if (PowerupGlowVisible(TRUE))
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
    vector last_ang;
    float last_turn, sum_dturn, sum_turn, peak_turn;
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
    sm.sum_dturn = sm.sum_turn = sm.last_turn = sm.peak_turn = 0;
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

    // Angular roughness, measured the same way: frame-to-frame turn rate, and
    // how much that rate changes.  A positional probe cannot see angle judder
    // at all, yet angle noise rotates every pixel -- which is why the eye has
    // measured smooth while spectating still looked wrong.
    vector a = getviewprop(VF_ANGLES);
    float turn = (fabs(AngleDelta(sm.last_ang.x, a.x)) +
                  fabs(AngleDelta(sm.last_ang.y, a.y))) / dt;
    if (sm.n > 0) {
        sm.sum_dturn += fabs(turn - sm.last_turn);
        sm.sum_turn += turn;
        sm.peak_turn = max(sm.peak_turn, turn);
    }
    sm.last_ang = a;
    sm.last_turn = turn;

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
    printf("  a-roughness %0.4f   (mean |d turnrate| / mean turnrate)\n",
           sm.sum_turn > 0 ? sm.sum_dturn / sm.sum_turn : 0);
    printf("  turnrate    %0.0f / %0.0f deg/s  (mean / peak)\n",
           sm.n > 0 ? sm.sum_turn / sm.n : 0, sm.peak_turn);
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
