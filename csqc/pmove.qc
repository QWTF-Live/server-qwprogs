DEFCVAR_FLOAT(fo_jumpvolume, 1);

// Quake's V_CalcRefdef step-smoothing constants.
#define STEP_RAMP    80   // units/sec the view catches up
#define STEP_MAX_LAG 12   // units the view may trail the true z

// `seq` is the start of the first frame after which all input_*s are handled.
// Running to `seq` will result in being on frame `seq + 1` in the resultant
// state.  In the case that `seq == commandclientframe` this could only be
// partially true since the input_*s (in particular, timelength) are not
// constant for this frame.
const static float PM_NUDGES = 8;

static struct PMS_Data {
    vector org, vel;
    float seq, server_seq;
    float interp_t;
    // Per nudge slot, the command its push landed on in the lineage that
    // produced this state -- so a replay resumed from it does not land the
    // push again.  Part of the state rather than a global: a replay that
    // resumes the cache (or the error pass's prior state) is a continuation
    // whose starting velocity already carries the push, while a fresh replay
    // from the snapshot is not and must land it.  A backward clock correction
    // is what makes the window reopen; with the clock folded into one command
    // the next command's window can contain a due the lineage already fired
    // on, and the server consumes its queued push once.
    float nudge_fired[PM_NUDGES];
} pm_s, pm_so, pm_c;

static struct {
    entity ent;
    float last_vel_z;
    PMS_Data* active_pmsd;

    float seq, server_seq;
    float interp_t;
    float last_nudge;
    float nudge_fired[PM_NUDGES];   // the running copy of the state's

    vector error;
    float errortime;
    float errorspan;   // how long this particular error is being glided over

    float step, steptime, step_oldz;

    vector vieworg;
} pm;

// Where we were at the end of each command, kept so a projectile simulated on
// its own clock can be collided against where we actually were rather than
// where we have since got to.  The replay walks every command anyway, and a
// command of our travel is five to ten units against a bbox thirty-two wide.
//
// Power of two, indexed by sequence: a replay rewrites the same entries with
// the same values, so there is nothing to invalidate.
// The chain clock at the end of the last command we have predicted.  What a
// projectile of somebody else's should be advanced to: our own copy of the
// world has reached exactly here and no further.
float PM_CmdClock() { return pm.interp_t; }

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
DEFCVAR_FLOAT(fopm_errortime, 0);
// The client half of the trace switch.  Declared with the other pm cvars in
// pmdebug.qc, which compiles first and needs it too.
float RJ_On() { return CVARF(fopm_debug); }

// The three the player actually has a reason to touch.  -1 on all of them means
// "not chosen", and everything is on unless somebody turns it off -- so the
// default is the same whether or not the cvar exists in their config.
//
// pmove defers to fo_pmove while that name is still in circulation; setting
// pmove at all wins.  The two knock switches are independent because the cases
// are: your own explosions move you the instant you fire, somebody else's move
// you when their blast reaches you, and only the first is worth losing if the
// prediction is wrong.
//
// pm_knock_other is off by default for now.  Your own explosion is yours to
// predict -- you fired it and you know when; somebody else's arrives on their
// clock and the prediction is only as good as the copy of their projectile we
// were sent.  On by default is a decision to make once it has run switched on
// for a while, not before.
DEFCVAR_FLOAT(pmove, -1);
DEFCVAR_FLOAT(pm_knock_self, -1);
DEFCVAR_FLOAT(pm_knock_other, -1);

static float TriState(float v, float dflt) { return v < 0 ? dflt : (v ? 1 : 0); }

float PM_WantPmove()  { return TriState(CVARF(pmove), CVARF(fo_pmove) ? 1 : 0); }

// pmove 2: score a rocket that hits us through the radius falloff, the way it
// was scored before KNOCK_DIRECT, for players timing against the old arc.
//
// Only the scoring.  The crossing still runs, so the blast keeps the position
// and the instant we fixed -- what changes is 92 through the falloff instead of
// a flat 102, about ten per cent short of what the server applies, corrected
// upward mid-flight.
//
// Not the whole of the old behaviour: that also had the source wrong, because
// our copy of the rocket flew past us to whatever was behind and the blast was
// measured from there, which is where the thirty per cent came from.  knock_org
// repairs the source from the server now and nothing here undoes that.  So this
// is the old formula at the right place, not the old push.
float PM_LegacySelfHit() { return CVARF(pmove) == 2; }
float PM_KnockSelf()  { return TriState(CVARF(pm_knock_self), 1); }
float PM_KnockOther() { return TriState(CVARF(pm_knock_other), 0); }

// Whose explosion this is, and whether they asked to be moved by it.
//
// The null check matters: somebody else's projectile carries no owner at all
// on our side, and before prediction is up player_ent is null too, which would
// make every one of them ours.
float PM_KnockAllowed(entity ent) {
    float mine = pengine.player_ent && ent.owner == pengine.player_ent;
    return mine ? PM_KnockSelf() : PM_KnockOther();
}

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
    float verbose = CVARF(fopm_debug) > 1;
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
    for (float i = 0; i < PM_NUDGES; i++)
        pmsd->nudge_fired[i] = pm.nudge_fired[i];
}

static void PM_ActivatePMS(PMS_Data *pmsd) {
    entity ent = pm.ent;
    ent.origin = pmsd->org;
    ent.velocity = pmsd->vel;
    ent.pmove_flags = 0;  // Not clear there's anything to save/restore here.

    pm.seq = pmsd->seq;
    pm.server_seq = pmsd->server_seq;
    pm.interp_t = pmsd->interp_t;
    for (float i = 0; i < PM_NUDGES; i++)
        pm.nudge_fired[i] = pmsd->nudge_fired[i];
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
    NT_BLAST,   // what went off is in the nudge's KnockBlast
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

    vector dash_vel;    // NT_DASH: the velocity it assigns
    KnockBlast blast;   // NT_BLAST: what went off, as the server holds it too
    // created_seq of the projectile this came from.  The two copies are meant
    // to agree: a predicted one takes it from the fire sequence, a networked
    // one from servercommandframe when its first update is parsed, and that
    // update normally rides the snapshot acknowledging the fire command.  It
    // only holds while that is true, so an update that arrives a frame late --
    // out of PVS, a lost packet -- leaves the predicted nudge unmatched and
    // the push lands twice.
    float src_cseq;
    float src_fseq;    // fire_seq of that projectile: the handle both copies share
    // Its type, because owner plus fire_seq is not yet one projectile: a held
    // grenade materialising and a rocket firing on the same command both carry
    // that command's number, and the first server copy to arrive retired both
    // pushes.
    float src_fpp;
    // The blast command anchor for our own grenade: the push is due a
    // KNOCK_LEAD past the clock of the first command to reach it, which is what
    // the server anchors on too.  Resolved during the replay, because that is
    // the only place the command clocks are.
    float cmd_due;
    float cmd_resolved;
    float was_live;   // RJ_TRACE: to catch the frame a nudge stops being live

    // Command clock of the shot we predicted, for a push we predicted
    // ourselves.  Once the server has run that command its cooldown witnesses
    // whether it fired, without us needing to see the projectile at all.
    float fire_clk;
    // The command this nudge pushed on, once it has.  While the server has not
    // acknowledged that command the push exists only here, so the nudge has to
    // outlive its own timer until it does.
    float fired_seq;
    float trace_seq;   // RJ_TRACE: last replay seq this nudge was reported at
};

const static float NUDGE_SEQ = 3;
const static float NUDGE_EPS = NUDGE_SEQ * SERVER_FRAME_DT;
static PM_Nudge nudges[PM_NUDGES];
static float num_nudges, have_active_nudges;
static float nudges_added;   // since the last error pass; its saved prior state predates them
// A command is replayed several times a frame -- rendering, the error pass,
// the graphs -- and only the last one reaching clientcommandframe is what the
// player is shown.  A trace line from any other pass describes a push that was
// recomputed and thrown away, which has read as a doubled push three times now.
// Only the surviving pass talks.
static float pm_final_pass;
// Which pushes a replay actually applied, as seq/slot pairs folded together.
// The error pass compares two replays; if they did not carry the same pushes
// the difference between them is not a correction the player ever saw.
static float nudge_sig;
static float nudge_sig_from;   // only commands past this one are in the signature
static float rj_trace_until_seq;   // RJ_TRACE: report server updates/errors until this seq
// RJ_TRACE: a frame's correction is only worth a line if it is big enough to
// read; the quiet ones are carried as a count so the denominator survives.
const static float RJ_ERR_NOTABLE = 0.25;
const static float RJ_ERR_EVERY = 256;
static float rj_err_n, rj_err_filt, rj_err_max, rj_err_max_scf;
static float rj_unfired_seq;   // RJ_TRACE: last shot reported as never fired
// RJ_TRACE: per-frame result of the most recent replay, i.e. what was shown for that frame.
struct RJ_Shown { float seq; vector org, vel; };
static const float RJ_NSHOWN = 64;
static RJ_Shown rj_shown[RJ_NSHOWN];

static float nudge_expired(PM_Nudge* n);

// The two replays the error pass compares judge nudge expiry against different
// moments -- the prior against the update it was shown for, the new one against
// this update -- so a nudge can be live for one and expired for the other.  The
// one that has it carries a whole push the other does not, and integrated over
// the commands since that was 76 units of a grenade jump in the last trace.
//
// The signature cannot see this: it only compares the overlap of the two
// command ranges, and the push sits below that.  Ask the nudges directly.
static float PM_NudgeLivenessDiffers(float alt_seq, float alt_time) {
    float held_seq = pstate_server.seq, held_time = pstate_server.server_time;
    float differs = FALSE;

    for (float i = 0; i < nudges.length; i++) {
        PM_Nudge* n = &nudges[i];
        if (n->nat == NA_NONE)
            continue;

        float now_live = !nudge_expired(n);
        pstate_server.seq = alt_seq;
        pstate_server.server_time = alt_time;
        float then_live = !nudge_expired(n);
        pstate_server.seq = held_seq;
        pstate_server.server_time = held_time;

        if (now_live != then_live)
            differs = TRUE;
    }

    return differs;
}

static float nudge_expired(PM_Nudge* n) {
    if (n->expire_frame && n->expire_frame <= pstate_server.seq)
        return TRUE;

    if (n->expire_spawnseq && n->expire_spawnseq != game_state.spawn_gen)
        return TRUE;

    // A nudge that has already pushed outlives its own timer until the server
    // acknowledges the command it pushed on.  Until then the push exists only
    // here: retiring on a time margin left a frame where the nudge had let go
    // and the snapshot had not yet arrived, so the view lost the push and got
    // it back -- 78 units one frame and 93 the next on a grenade jump.  The
    // margin that was supposed to cover this was two server frames of guessed
    // time; this is the condition it was guessing at.
    //
    // No double push: a replay starts at the command after the last one
    // acknowledged, so once the server has that command this test stops
    // holding and the command is no longer replayed anyway.
    if (n->fired_seq && n->fired_seq > pstate_server.seq)
        return FALSE;

    if (n->expire_time && n->expire_time <= pstate_server.server_time)
        return TRUE;

    // A shot of ours the server has since run.  Firing puts the weapon on
    // cooldown past the command that fired it, so if the server's cooldown has
    // not moved, the attack never happened and neither did the push.  The
    // projectile itself is no witness here: it can be out of our view, or gone
    // before it was ever sent.
    // Only where a cooldown is a witness at all.  A hand grenade does not set
    // one, so a bare "the server's attack_finished is behind this shot" retired
    // every predicted grenade blast in the trace.  Ask instead whether our own
    // prediction put the weapon on cooldown for this shot and the server's did
    // not: silence from a weapon that was never going to speak proves nothing.
    if (n->fire_clk && !n->src_no && n->src_fseq &&
        pstate_server.seq >= n->src_fseq &&
        pstate_pred.attack_finished > n->fire_clk &&
        pstate_server.attack_finished <= n->fire_clk) {
        if (pm_final_pass && rj_unfired_seq != n->src_fseq) {
            rj_unfired_seq = n->src_fseq;
            rj_trace("C: unfired fseq=%.0f fire=%.4f af=%.4f\n",
                     n->src_fseq, n->fire_clk, pstate_server.attack_finished);
        }
        return TRUE;
    }

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
        float slot = (num_nudges++) % nudges.length;
        PM_Nudge* n = &nudges[slot];

        if (!nudge_expired(n))
            continue;

        cache_invalidated = TRUE;
        nudges_added = TRUE;
        n->nat = NA_NONE;
        n->src_no = 0;
        n->src = 0;
        n->fire_clk = 0;
        n->fired_seq = 0;
        n->cmd_due = 0;
        n->cmd_resolved = 0;
        n->was_live = 0;
        n->expire_frame = 0;
        n->expire_time = 0;
        n->expire_spawnseq = 0;
        // Identity too: a recycled slot kept the previous blast's handles, and
        // a constructor that did not write them then matched the wrong copy.
        n->src_cseq = 0;
        n->src_fseq = 0;
        n->src_fpp = 0;
        n->fire_clk = 0;
        // A new push is in no state yet.  The cache is invalidated above; this
        // is the running copy, for a replay already in progress.  The ring
        // slot's marker, not the search counter's: clearing by the counter
        // took another live nudge's marker off and left this slot's stale one
        // on, so that one pushed twice and this one not at all.
        pm.nudge_fired[slot] = 0;
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

    // Already retired, by the supersede when the server's copy of this
    // projectile exploded.  Its replacement is what fired; reporting the empty
    // slot as push@0 says a push was lost when none was, and under packet loss
    // it said so thirteen times in one trace.
    if (n->nat == NA_NONE)
        return;

    // An explicit window retires itself, so nothing here needs to retire it.
    //
    // This used to make an exception of our own predicted copies, on the
    // grounds that their removal means the server's equivalent has replaced
    // them.  It has not, not yet: a predicted rocket reaches its impact before
    // the server's copy reaches ours, so the nudge exists while the copy that
    // arrives and cleans it up is still in flight and carries no push time at
    // all.  The replacement only appears when the impact does, a round trip
    // later, by which time the command it was due on has been acknowledged and
    // is no longer replayed.  Measured: itime 15.700 against the server's due
    // of 15.700 -- the timing was exactly right -- removed push@0, and 107 u/s
    // of knock lost with the two positions agreeing to a hundredth of a unit.
    //
    // Retiring the predicted nudge is PM_SupersedePredictedNudge's job.  It is
    // keyed on the fire_seq both copies share and runs from the server copy's
    // own explosion, which is the moment the replacement exists.
    if (n->nat == NA_ITIME_EXPLICIT_EXPIRE)
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
    ent.velocity = nudge->dash_vel;
}

void PM_AddNudgeDash(float cseq) {
    PM_Nudge* n = find_nudge_slot();
    if (!n)
        return;
    n->type = NT_DASH;
    n->nat = NA_SEQ;
    n->seq = cseq;

    n->dash_vel = v_forward * 540;
    n->dash_vel.z = 181;
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

static void PM_NudgeExplosion(PM_Nudge* nudge, entity ent, float back) {
    // Copied field by field: assigning a struct through a pointer is not
    // something to take on trust here.
    KnockBlast b;
    b.type = nudge->blast.type;
    b.src = nudge->blast.src;
    b.base = nudge->blast.base;
    b.flags = nudge->blast.flags;
    b.slack = NudgeExplosionEps();
    b.back = back;   // measure at the due instant, not the command end

    float points = Knock_Points(&b, ent);
    if (!points)
        return;

    // A hit needs no line of sight to itself, and at contact range the trace is
    // as likely to find the surface behind us as open air.
    if (b.type != KNOCK_DIRECT && !PM_ExplosionReaches(b.src, ent.origin))
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
    if (b.type == KNOCK_DIRECT) {
        // A direct hit is dealt as the projectile's own damage type, not as
        // an explosion.  A rocket's is TF_TD_OTHER, which no armour halves.
        // An incendiary's is TF_TD_FIRE: halved by fire armour, and dealt
        // after SetOnFire has lit the target, so the burn amp is already on
        // when it lands even if we were not burning a moment ago -- unless
        // SetOnFire declined, which it does for fire armour with value left
        // in it, and in prematch.
        if (nudge->src_fpp == FPP_INCENDIARY) {
            float fire_armour = pstate_server.predict_flags & PF_SAVE_FIRE;
            if (!(fire_armour && getstatf(STAT_ARMOR) > 0) && !prematch)
                dsf |= DSF_BURNING;
            if (fire_armour)
                dsf |= DSF_SAVE_FIRE;
        }
    } else if (pstate_server.predict_flags & PF_SAVE_EXPLOSION)
        dsf |= DSF_SAVE_EXPLOSION;

    float moment = Class_ScaleMoment(WP_PlayerClass(), Damage_Scale(points, b.flags, dsf));
    vector knock = Knock_Velocity(&b, ent, moment);

    // Once per seq, and not from the error pass's replays: those are thrown
    // away, so a line from one describes a push nobody saw.
    if (nudge->trace_seq != pm.seq && pm_final_pass) {
        nudge->trace_seq = pm.seq;
        Knock_Trace(&b, ent, pm.seq, pm.interp_t + input_timelength, nudge->itime, moment, knock, nudge->src_no, clientcommandframe);
        rj_trace_until_seq = pm.seq + 30;
    }

    pm.ent.velocity += knock;
    PMD_Knock(knock, moment);
}

// Can be either by {seq + itime} for predicted projectiles, or by {itime} for
// server projectiles.
static PM_Nudge* PM_AddNudgeExplosion(float nat, float seq, float itime, entity ent, float dmg,
                                      vector src = '0 0 0', float ktype = KNOCK_RADIUS) {
    if (!PM_KnockAllowed(ent))
        return 0;
    if (src == '0 0 0')
        src = ent.origin;
    if (vlen(PM_Org() - src) > dmg * 3)  // Fine tune this..
        return 0;

    PM_Nudge* n = find_nudge_slot();
    if (!n)
        return 0;

    n->type = NT_BLAST;
    n->blast.type = ktype;
    n->blast.src = src;   // the ent's own position unless the server told us better
    n->blast.base = dmg;
    // Who fired it decides the multiplier, and an entity number classifies
    // nothing -- the server tells us.  Assuming a player was right for every
    // case anyone had looked at and wrong for a sentry gun, whose rocket we
    // predicted at eleven eighths of the push it actually lands.
    n->blast.flags = KF_TARG_PLAYER;
    if (ent.src_is_player)
        n->blast.flags |= KF_SRC_PLAYER;
    if (ent.owner == pengine.player_ent)
        n->blast.flags |= KF_SELF;
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

    n->src = ent;
    n->src_no = ent.entnum;
    n->src_cseq = ent.created_seq;
    n->src_fseq = ent.fire_seq;
    n->src_fpp = ent.fpp.index;
    if (!ent.entnum && ent.owner == pengine.player_ent)
        n->fire_clk = ent.fire_cmd_time;

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
    // Only our own copy can claim a nudge we predicted: fire_seq is the
    // owner's command counter, so somebody else's projectile can carry the
    // same number, and both call sites run before the knock-eligibility
    // check, so this happened with pm_knock_other off too.  The null guard is
    // the one PM_KnockAllowed explains -- before prediction is up player_ent
    // is null, and a copy with no owner would match it.
    if (!pengine.player_ent || sent.owner != pengine.player_ent)
        return;

    for (float i = 0; i < nudges.length; i++) {
        PM_Nudge* n = &nudges[i];
        if (n->nat == NA_NONE)
            continue;   // empty slot: nothing to say about it

        // Any blast of ours, not only a radius one.  The handle below -- our own
        // copy, carrying the fire_seq this one also carries -- is what
        // identifies it; which shape the push takes says nothing about whether
        // the two are the same shot.
        float ok_type = (n->type == NT_BLAST);
        float ok_pred = (n->src_no == 0);
        float ok_live = !nudge_expired(n);
        float ok_seq  = (n->src_fseq && n->src_fseq == sent.fire_seq &&
                         n->src_fpp == sent.fpp.index);

        if (ok_type && ok_pred && ok_live && ok_seq) {
            n->nat = NA_NONE;
            continue;
        }

        // Only the near miss speaks.  Every condition used to print for every
        // slot, which answered the question it was added for -- the four are
        // not redundant and none is dead -- and then went on costing a line per
        // slot per supersede.  A predicted blast of ours that this copy did not
        // claim is the case worth seeing: it means one of us has the wrong
        // handle, and both pushes stay live.
        if (ok_type && ok_pred && ok_live)
            rj_trace("C: supersede-miss i=%.0f ours=%.0f theirs=%.0f ent=%.0f\n",
                     i, n->src_fseq, sent.fire_seq, sent.entnum);
    }
}

static void PM_AddNudgeBounce(float itime, entity ent, float dmg) {
    if (!PM_KnockAllowed(ent))
        return;
    if (vlen(PM_Org() - ent.origin) > dmg * 3)  // Fine tune this..
        return;

    PM_Nudge* n = find_nudge_slot();
    if (!n)
        return;

    n->type = NT_BLAST;
    n->blast.type = KNOCK_BOUNCE;
    n->blast.src = ent.origin;
    n->blast.base = dmg;
    n->blast.flags = 0;
    n->nat = NA_ITIME_EXPLICIT_EXPIRE;
    n->expire_time = itime;
    n->itime = itime;

    // The same identity block PM_AddNudgeExplosion writes.  Without it a conc
    // carried whatever handles the slot last held: supersession by its own
    // server copy missed, and PM_UpdateNudgeSource refused the authoritative
    // blast position because src_cseq was not the projectile's.
    n->src = ent;
    n->src_no = ent.entnum;
    n->src_cseq = ent.created_seq;
    n->src_fseq = ent.fire_seq;
    n->src_fpp = ent.fpp.index;
    if (!ent.entnum && ent.owner == pengine.player_ent)
        n->fire_clk = ent.fire_cmd_time;

    ent.nudge = n;
    ent.removefunc = PM_RemoveSelfNudges;
}

static void PM_NudgeBounce(PM_Nudge* nudge, entity ent, float back) {
    KnockBlast b;
    b.type = nudge->blast.type;
    b.src = nudge->blast.src;
    b.base = nudge->blast.base;
    b.flags = nudge->blast.flags;
    b.slack = NudgeExplosionEps();
    b.back = back;   // measure at the due instant, not the command end

    float points = Knock_Points(&b, ent);
    if (!points)
        return;

    vector before = ent.velocity;
    ent.velocity = Knock_Velocity(&b, ent, points);
    PMD_Knock(ent.velocity - before, points);

    if (nudge->trace_seq != pm.seq && pm_final_pass) {
        nudge->trace_seq = pm.seq;
        Knock_Trace(&b, ent, pm.seq, pm.interp_t + input_timelength, nudge->itime,
                    points, ent.velocity - before, nudge->src_no, clientcommandframe);
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

// The server's copy of where a blast we have already scheduled actually went
// off.  Our grenade came to rest wherever our own bounces put it, which in the
// last trace was 1.4 units from the server's and 25 u/s of push.
// Entity numbers are recycled, so "the nudge whose source is this entity" named
// a nudge from a previous grenade that happened to land in the same slot, and
// every new grenade dragged that stale source across the map -- two thousand
// units in the last trace, and sixty-unit corrections into the view.  Name the
// projectile, not the slot: live, ours, and the same creation.
const static float KNOCK_SRC_MAX = 64;   // past this it is not the same blast

void PM_UpdateNudgeSource(entity ent, vector src) {
    for (float i = 0; i < nudges.length; i++) {
        PM_Nudge* n = &nudges[i];
        if (n->nat == NA_NONE || n->type != NT_BLAST)
            continue;
        if (n->src != ent || n->src_no != ent.entnum || n->src_cseq != ent.created_seq)
            continue;
        if (nudge_expired(n))
            continue;
        if (n->blast.src == src)
            continue;

        // Our copy settles a unit or two from theirs.  Anything further is not
        // the blast we scheduled, whatever the bookkeeping says, and moving a
        // push we are already showing is the expensive way to be wrong.
        float moved = vlen(src - n->blast.src);
        if (moved > KNOCK_SRC_MAX) {
            rj_trace("C: knock-src ent=%.0f rejected by=%.2f\n", (float)ent.entnum, moved);
            continue;
        }

        rj_trace("C: knock-src ent=%.0f by=%.2f %v -> %v\n", (float)ent.entnum,
                 moved, n->blast.src, src);
        n->blast.src = src;
        cache_invalidated = TRUE;
    }
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
    //
    // Our own grenade is better than that again.  Its blast comes off a
    // command on the server -- the first whose clock reaches last_prime +
    // GREN_FUSE, an anchor we hold too -- and the push is a lead past that
    // command, not a lead past the fuse.  Anchoring on the same command makes
    // the two numbers identical rather than merely close, so there is no
    // boundary left for a tie to sit on and no skew drift between the prime
    // and the creation to carry.  Which command that is can only be answered
    // during the replay, so the due is carried on the nudge and resolved there.
    float cmd_due = 0;
    if (ent.blast_cmd_due && ent.owner == pengine.player_ent)
        cmd_due = ent.blast_cmd_due;
    else if (ent.has_cmd_base)
        itime = ent.fpp.cmd_base + max(ent.fpp.expires_at - ent.created_at, 0);
    else
        itime = PM_WorldToCmdTime(itime);
    if (cmd_due)
        itime = cmd_due;
    itime += KNOCK_LEAD;   // the same lead the server schedules it with

    // The server's copy of a grenade we predicted: retire our own nudge here,
    // where the replacement is being created, rather than when the copy merely
    // arrived.  PM_AddSimExplosion has always done this and this path never
    // did, so with nothing else retiring the predicted one both fired -- the
    // same held grenade pushing twice, exactly 2x the server's velocity on
    // every axis with the damage matching to a tenth.
    if (ent.entnum)
        PM_SupersedePredictedNudge(ent);

    FO_GrenExp exp;
    if (!FO_GrenGetExp(ent.fpp.gren_type, exp))
        return;

    float dmg = exp.dmg;

    PM_Nudge* n;
    if (exp.type == KNOCK_RADIUS)
        PM_AddNudgeExplosion(NA_ITIME_EXPLICIT_EXPIRE, 0, itime, ent, dmg,
                             ent.knock_org);
    else
        PM_AddNudgeBounce(itime, ent, dmg);

    // No margin on top of the expiry.  It used to hold a couple of server
    // frames because the state had not caught up with the push yet, and named
    // the server's filter entry as what really retired it -- both untrue now.
    // A deferred push sends no filter entry, and a nudge that has fired
    // outlives its timer until the server acknowledges the command it fired on,
    // which is the exact condition the margin was approximating.
    if (ent.nudge) {
        ent.nudge->expire_time = itime;
        ent.nudge->cmd_due = cmd_due;
    }
}

void PM_AddSimExplosion(float itime, entity ent) {
    if (!PM_Enabled())
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

    // A rocket that stopped on us is not a blast we are standing near.  The
    // server excludes a directly hit player from the radius pass entirely --
    // they are ignore1 to T_RadiusDamage -- and the whole push comes off the
    // direct damage instead, at a fixed 102.  Predicting the radius falloff
    // against that was thirty per cent short: mom 75 against 103, 77 against
    // 96, 76 against 112, with the source and the distance already agreeing.
    float ktype = KNOCK_RADIUS;
    if (ent.hit_self && !PM_LegacySelfHit()) {
        ktype = KNOCK_DIRECT;
        // By type: the incendiary's direct hit is about half a rocket's.
        dmg = (ent.fpp.index == FPP_INCENDIARY) ? KNOCK_DIRECT_IC_DMG
                                                : KNOCK_DIRECT_DMG;
    }

    float seq = 0, nat = NA_ITIME;
    if (ent.owner == pengine.player_ent)
    {
        rj_trace("C: sim t=%.3f type=%i itime=%.3f fk=%.3f stime=%.3f cseq=%.0f",
                 time, ent.fpp.index, itime, ent.forward_knock, ent.s_time, ent.created_seq);
        rj_trace(" svt=%.3f ccf=%.0f org=%v\n", pstate_server.server_time, clientcommandframe, ent.origin);
    }
    // Our own projectile whose copy has reached us with no push time on it.
    // Our prediction dates the blast the way the server does, from the fire
    // command plus the travel; the fallback below dates it from this copy's
    // physics clock, which is our clock and not the server's.  Trading the
    // first for the second is how we pushed 90 ms early.  Keep what we have.
    if (ent.entnum && ent.owner == pengine.player_ent && !ent.forward_knock)
        return;

    // -1 is AntilagKnock declining: it built no forward push for this shot, so
    // the server pushes us through the ordinary radius path instead and this
    // copy has nothing to schedule.  Taken before the supersede below, because
    // retiring our prediction and then returning leaves the push to nobody --
    // the client applies nothing and the server's arrives as a correction.
    // Measured: dvel 145.5 with the positions agreeing to eight thousandths,
    // and the whole of it the push we never made.
    if (ent.forward_knock == -1 && ent.owner == pengine.player_ent)
        return;

    // The server's copy of a projectile we predicted ourselves: retire the
    // predicted nudge whatever route this copy then takes.  This used to sit
    // inside the forward_knock branch below, so a copy that arrived before
    // that field was set left both nudges live and both pushing.
    if (ent.entnum)
        PM_SupersedePredictedNudge(ent);

    if (ent.forward_knock && ent.owner == pengine.player_ent) {
        nat = NA_ITIME_EXPLICIT_EXPIRE;  // Knock forwards are synchronized
        itime = ent.forward_knock;
    } else if (ent.entnum && ent.has_cmd_base && ent.s_time &&
               ent.owner_entnum != pengine.player_entnum) {
        // Someone else's rocket: our clock when it appeared plus its flight,
        // which both sides measure from the projectile's own start.  Its
        // physics clock cannot be compared across the wire -- the server runs
        // it on server time and we run ours on interpolation time, on purpose,
        // so that collisions line up with what we are shown -- but the time it
        // has been in the air is the same quantity on both sides.
        //
        // Plus the lead, which this branch never carried.  Knock_Defer puts one
        // on every push it schedules for somebody else's projectile, grenade
        // and rocket alike, and the grenade path here has always matched it --
        // so a third-party rocket was a whole server frame early, on top of
        // whatever the flight measurement below costs.
        //
        // RJ_TRACE: the two halves of that flight, because they are not read
        // off the same clock.  s_time arrives as the server's phys_time and
        // itime is on ours, so the subtraction is only a duration to the
        // extent the two clocks agree; measured against the server's own
        // blast_delay it ran 10-20 ms short.
        //
        // And an explicit window, the same one the grenade path uses.  Left on
        // the open-ended NA_ITIME it was removed unused every single time: the
        // server's rocket entity goes away at the instant it explodes, which is
        // before the replay has reached the command the push is due on, and
        // PM_RemoveSelfNudges only spares a nudge with an explicit window.  Now
        // that this due is built the same way the grenade's is, it earns the
        // same treatment -- six rockets, six push@0, against three grenades
        // that pushed on the right command in the same trace.
        nat = NA_ITIME_EXPLICIT_EXPIRE;
        //
        // No lead on a hit that landed on us.  The lead exists so a blast
        // discovered in physics can still reach a command; a crossing is found
        // inside the victim's own command and the server pushes from there,
        // with no defer and no schedule -- due and clk equal, edge zero.  So
        // the crossing instant lands in the command that owns it by itself.
        itime = Proj_CmdTime(ent, itime) + (ent.hit_self ? 0 : KNOCK_LEAD);
        rj_trace("C: sim-other t=%.3f itime=%.4f base=%.4f flight=%.1fms stime=%.4f pt=%.4f ccf=%.0f\n",
                 time, itime, ent.fpp.cmd_base, (itime - KNOCK_LEAD - ent.fpp.cmd_base) * 1000,
                 ent.first_phys_time, ent.phys_time, (float)clientcommandframe);
    } else if (ent.entnum) {
        // Same lead, same reason: a push the server scheduled for us.
        itime = PM_WorldToCmdTime(itime) + KNOCK_LEAD;
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

    // Our simulation of the flight cannot hit networked entities, so a rocket
    // the server stopped against a player or a brush model flew on in our copy
    // and our blast is measured from further down the path.  Point-blank that
    // is most of the push: the last trace had the two sources eleven units
    // apart and the velocities ninety-five apart.  When the server's copy
    // reaches us it brings the point it actually went off at; take it.
    vector src = '0 0 0';
    if (ent.entnum && ent.knock_org)
        src = ent.knock_org;

    PM_AddNudgeExplosion(nat, seq, itime, ent, dmg, src, ktype);
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

// A rocket of somebody else's, stopping on us the way the server's copy does.
//
// Our simulation cannot hit networked entities, so a direct hit on us used to
// fly straight through: our copy went off somewhere behind us, at a different
// time, and at the range that leaves, the push direction is not slightly wrong
// but arbitrary.  knock_org repairs the source after the fact and can do
// nothing for the flight.
//
// Our own position is the one quantity we know better than anything else here:
// it agrees with the server to eight hundredths of a unit.  So this is the
// collision worth having, and the only one -- another player's position on our
// side is advanced by a frame count and is tens of units from theirs.
//
// Driven by the command chain, not by the projectile's simulation.  Hung off
// the projectile's own steps it asked where we would be up to a hundred
// milliseconds from now -- that advance is for drawing the rocket ahead of the
// last snapshot -- and the only honest answer was our newest position, so the
// sweep degenerated to a static box and reported frac=0.000 with the segment
// already inside it.  A command is an interval we have actually predicted, at
// both ends, and the rocket's position at either end follows from its own
// straight path.
static void PM_CheckMissileHits(entity ent, vector from_org, float sitime, float eitime) {
    if (!PM_Enabled() || !pengine.player_ent || !pm_final_pass)
        return;
    if (eitime <= sitime)
        return;

    entity e = findradius(ent.origin, 512);
    while (e) {
        entity next = e.chain;
        if (e.entnum && !e.voided && e.movetype == MOVETYPE_FLYMISSILE &&
            e.owner != pengine.player_ent && e.has_cmd_base && e.first_phys_time &&
            e.velocity != '0 0 0') {
            // Where the rocket is at this command's two ends, on its own clock.
            float p0 = Proj_PhysTime(e, sitime), p1 = Proj_PhysTime(e, eitime);
            vector a = Proj_OrgAt(e, p0), b = Proj_OrgAt(e, p1);

            float frac;
            if (p1 > e.first_phys_time &&
                Proj_Crosses(a, b, from_org, ent.origin, ent.mins, ent.maxs, &frac)) {
                vector hit = a + (b - a) * frac;
                rj_trace("C: self-hit seq=%.0f frac=%.3f span=%.4f->%.4f",
                         (float)pm.seq, frac, sitime, eitime);
                rj_trace(" rocket=%v->%v us=%v->%v hit=%v pt=%.4f\n",
                         a, b, from_org, ent.origin, hit, p0 + (p1 - p0) * frac);
                rj_trace_until_seq = pm.seq + 30;

                e.voided = TRUE;
                e.hit_self = TRUE;
                setorigin(e, hit);
                PM_AddSimExplosion(p0 + (p1 - p0) * frac, e);
            }
        }
        e = next;
    }
}

// TODO: This obviously wants to be smarter
static void PM_ApplyNudges(entity ent, float seq, float sitime, float eitime, float slack = 0) {
    if (!have_active_nudges)
        return;

    for (float i = 0; i < nudges.length; i++) {
        PM_Nudge* n = &nudges[i];

        // Anchor on the command the server's blast fires from: the first whose
        // clock reaches the shared due.  Both sides then hold the same number
        // to the bit, so reach is exactly KNOCK_LEAD and there is no boundary
        // for a tie to sit on.  Stable across replays because a command's own
        // clock is.
        if (n->cmd_due && !n->cmd_resolved && eitime >= n->cmd_due) {
            n->itime = eitime + KNOCK_LEAD;
            n->expire_time = n->itime;
            n->cmd_resolved = TRUE;
        }

        if (pm.nudge_fired[i])
            continue;   // already in the state this replay is running from
        if (!MatchNudge(n, seq, sitime, eitime, slack))
            continue;

        pm.last_nudge = seq;
        n->fired_seq = seq;
        pm.nudge_fired[i] = seq;
        if (seq > nudge_sig_from)
            nudge_sig += seq * nudges.length + i + 1;
        switch (n->type) {
            case NT_DASH:
                PM_NudgeDash(n, ent);
                break;
            case NT_BLAST: {
                // How much of this command had already elapsed when the blast
                // was due.  Both sides step back by their own copy of it, so a
                // tie that puts them a command apart costs the timing of the
                // push and not its direction.
                float back = max(eitime - n->itime, 0);
                if (n->blast.type == KNOCK_BOUNCE)
                    PM_NudgeBounce(n, ent, back);
                else
                    PM_NudgeExplosion(n, ent, back);
                break;
            }
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
    pm_final_pass = (endframe == clientcommandframe) && !pmd_norecord;
    nudge_sig = 0;

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

        PM_CheckMissileHits(ent, pm_moved_from, pm.interp_t, pm.interp_t + step);

        if (pm.seq != clientcommandframe) {
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
            PMD_Record(pm.seq, pm_moved_from, ent.origin, ent.velocity,
                       (ent.flags & FL_ONGROUND) ? 1 : 0,
                       PM_GetWaterLevel(ent.origin, &wtype), nudge_sig);
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

    pm.errortime = pm.steptime = pm.errorspan = 0;
    pm.step_oldz = pm.ent.origin_z;
    PM_LerpReset();
}

// How long to glide a correction out over, by how big it is.
//
// A flat span trades a rare yank for a constant lag: the errors that actually
// happen are a tenth of a unit and ought to snap, and stretching those leaves
// the view permanently behind where the player is.  What wants a glide is the
// rare large one -- a push landing a command apart from the server's because
// the two anchors were sampled three and a half seconds apart and the skew
// drifted a few milliseconds in between.  That residual is not further
// reducible without re-anchoring the per-viewer path, so it is a thing to
// absorb rather than chase, and one command of a 770 u/s push integrated over
// the replay is seventy units however near the miss was.
//
// So scale it: small errors keep the old snap, and the span only grows for
// something worth hiding.  The view trails the true position while it glides
// and shots come from the eye, so this is paid for in aim -- which is why it
// buys nothing for the errors that do not need it.
static float ErrorSpan(vector err) {
    static float kDefault = 25 * MSEC;
    static float kMax = 150 * MSEC;
    static float kPerUnit = 2 * MSEC;

    if (CVARF(fopm_errortime))
        return min(CVARF(fopm_errortime), kMax);

    return bound(kDefault, vlen(err) * kPerUnit, kMax);
}

static void PM_UpdateError() {
    entity ent = pm.ent;
    pmd_norecord++;

    // A life boundary, not just a dead player.  Death runs its own physics on
    // the body -- an upward kick, or a gib velocity outright -- and the frame
    // that reports it still reads as alive here, so the kick went into the
    // lerp as a nine-unit correction before the flag caught up.  Nothing
    // across a boundary is a correction to anything we showed.
    static float err_spawn_gen;
    float life_changed = (err_spawn_gen != game_state.spawn_gen);
    err_spawn_gen = game_state.spawn_gen;

    ent.owner = edict_num(player_localentnum);
    if (CVARF(fopm_noerror) || !game_state.is_alive || life_changed ||
        (clientcommandframe == servercommandframe + 1)) {
        pm.error = '0 0 0';
        pm.errortime = 0;
        pm.errorspan = 0;
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
    // Commands before the prior's own start are already integrated into it, so
    // the new prediction replaying them is not a difference between the two.
    // That start is the command the prior state was saved at, not the server
    // frame it descends from; the two are several commands apart and using the
    // latter counted every push the server had not acknowledged yet.
    nudge_sig_from = last.seq - 1;
    PM_RunMovement(&last, clientcommandframe);
    float prior_sig = nudge_sig;
    pstate_server.seq = held_seq;
    pstate_server.server_time = held_time;
    have_active_nudges = held_active;
    vector err = ent.origin;

    // Repeat with updated state.
    PM_RunMovement(SimPMSD(), clientcommandframe - 2);
    float new_sig = nudge_sig;
    PM_SavePMS(&last);  // Save at -2 to replay nudges going into -1
    PM_RunMovement(SimPMSD(), clientcommandframe);
    new_sig += nudge_sig;
    nudge_sig_from = 0;

    // New nudges can result in small errors on replay due to timeshift, we
    // could backdate all the nudges and recompute the world but as a first
    // simpler pass let's just filter them out.
    //
    // The frame test only catches a push that landed on the command just gone.
    // It misses the handover, where the server's copy of a projectile arrives
    // several commands after we predicted its blast and replaces the nudge in
    // place: the two replays then straddle the swap and disagree by a whole
    // command of knock velocity, four units at a typical rocket.  Nothing moved
    // on screen, so feeding that into the lerp is pure judder.  Comparing which
    // pushes each replay applied catches it whatever the reason: if they did
    // not carry the same set, the difference between them is not a correction.
    float liveness_moved = pm_prev_update_seq &&
                           PM_NudgeLivenessDiffers(pm_prev_update_seq, pm_prev_update_time);
    // 1 a push landed on the command just gone, 2 the two replays applied
    // different pushes, 4 a nudge was live for one of them and expired for the
    // other.  Reported as a set so a trace says which rule earned its keep.
    float filtered = (pm.last_nudge == clientcommandframe - 1) |
                     ((prior_sig != new_sig) * 2) |
                     (liveness_moved * 4);
    err -= ent.origin;
    vector raw = err;
    if (filtered)
        err = '0 0 0';

    // The frames where the two replays agree are the overwhelming majority and
    // they all say the same thing, so a line each buries the handful that do
    // not.  Report a frame only when the difference is large enough to be worth
    // reading, and carry the rest as a count so the denominator is not lost.
    if (servercommandframe < rj_trace_until_seq) {
        rj_err_n++;
        rj_err_filt += !!filtered;
        if (vlen(raw) > RJ_ERR_NOTABLE) {
            rj_trace("C: err scf=%.0f ccf=%.0f err=%.2f %v filtered=%.0f/%.2f",
                     servercommandframe, clientcommandframe, vlen(err), err, filtered, vlen(raw));
            rj_trace(" sig=%.0f/%.0f lastnudge=%.0f acc=%.2f\n",
                     prior_sig, new_sig, pm.last_nudge, vlen(pm.error));
        } else if (vlen(raw) > rj_err_max) {
            rj_err_max = vlen(raw);      // the largest we did not report
            rj_err_max_scf = servercommandframe;
        }

        if (rj_err_n >= RJ_ERR_EVERY) {
            rj_trace("C: err-quiet n=%.0f filtered=%.0f max=%.2f@scf=%.0f\n",
                     rj_err_n, rj_err_filt, rj_err_max, rj_err_max_scf);
            rj_err_n = rj_err_filt = rj_err_max = rj_err_max_scf = 0;
        }
    }


    float nerr = vlen(err);
    if (nerr > 64) {  // teleport
        pm.error = '0 0 0';
        pm.errortime = 0;
        pm.errorspan = 0;
    } else { // figure out the error amount, and add it to accumulated lerp
        if (pm.errorspan > 0)
            pm.error *= max(pm.errortime - time, 0) / pm.errorspan;
        pm.error += err;

        if (vlen(pm.error) > 1) {
            pm.errorspan = ErrorSpan(pm.error);
            pm.errortime = time + pm.errorspan;
        } else {
            pm.error = '0 0 0';
            pm.errortime = 0;
            pm.errorspan = 0;
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

    // Correct view position over the span chosen for this error's size.
    if (pm.errortime - time > 0 && pm.errorspan > 0)
        pm.vieworg += (pm.errortime - time) * (1 / pm.errorspan) * pm.error;

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

// The server's way of saying it has taken an entity's effect over: stop nudging
// for it as of the command this update acknowledges.
//
// Only an immediate push sends one now.  A deferred push used to, and retired
// the nudge as of the command the blast was *found* on rather than the one the
// push lands on -- a command or two early, which showed as the client dropping
// a push and picking it up again a frame later.  A deferred nudge needs no
// telling: it carries an explicit expiry and outlives it until the server
// acknowledges the command it fired on, which is the moment this message was
// trying to name.
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

// RJ_TRACE: which rule retired a nudge that had already pushed.
//
// A nudge that fires on a command still being replayed must outlive its own
// timer, or the next replay rebuilds that command without the push and the
// whole of it comes back as a correction -- 345 u/s and 25 units in the last
// trace, with the pass stamp showing the entry written in a replay whose
// signature had gone from 9252 to nothing.
//
// Reported here rather than from nudge_expired, which the error pass calls with
// pstate_server mutated to a previous update: a trace from inside would
// describe a moment that never happened.  Expiry depends only on pstate_server,
// so a server update is the only thing that can change the answer.
static void PM_ReportNudgeDeaths() {
    for (float i = 0; i < nudges.length; i++) {
        PM_Nudge* n = &nudges[i];
        float live = (n->nat != NA_NONE) && !nudge_expired(n);

        if (n->was_live && !live && n->fired_seq) {
            rj_trace("C: nudge-died i=%.0f nat=%s fired=%.0f svseq=%.0f",
                     i, NAT_tos(n->nat), n->fired_seq, (float)pstate_server.seq);
            rj_trace(" itime=%.4f exp_t=%.4f svt=%.4f exp_f=%.0f gen=%.0f/%.0f ccf=%.0f\n",
                     n->itime, n->expire_time, pstate_server.server_time,
                     n->expire_frame, n->expire_spawnseq,
                     (float)game_state.spawn_gen, (float)clientcommandframe);
        }

        n->was_live = live;
    }
}

void PM_ServerUpdate() {
    PM_ReportNudgeDeaths();
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
    // The server's state carries none of our predicted pushes; every replay
    // from here lands them afresh.
    for (float i = 0; i < PM_NUDGES; i++)
        pm.nudge_fired[i] = 0;
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

// The eye actually being rendered from: ours when pmove owns the view, the
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
