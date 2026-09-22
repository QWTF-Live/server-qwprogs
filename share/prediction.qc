#define ENT_CONFIG     100
#define ENT_WEAPONPRED 101
#define ENT_PROJECTILE 102

// Below apply to both CSQC & SSQC ents
.float antilag_ms;
.float created_at;
// The command that fired this, on the owner's own sequence.  Carried rather
// than inferred: it is the only handle a predicted copy and the server's copy
// of the same projectile genuinely share, and matching them is what keeps a
// blast from being scheduled twice.
.float fire_seq;

string wp_version = "v1.1";

enumflags {
    FOWP_IMPULSE,
    FOWP_TFSTATE,
    FOWP_LASTPRIME,
    FOWP_CLASSIC_CONC,
    FOWP_CLIP,
    FOWP_GREN,
    FOWP_THINK,
    FOWP_WF,
    FOWP_AF,
    FOWP_CLASS,
    FOWP_MOVETYPE,
    FOWP_RELOAD,
    FOWP_SPECIAL,
    FOWP_RNG0,
    FOWP_RNG1,
    FOWP_RNG2,
    FOWP_PREDICT_FLAGS,
    FOWP_CONCFINISH,
    FOWP_CLOCKFIX,

    // Below this not force-refreshed.  Both are fine without it:
    //   PMOVE is remasked every frame while PF_PMOVE is set, so it self-heals.
    //   FILTER_ENTS carries its own redundancy (kFilterSends) and is an event
    //   rather than a level -- re-sending an empty list would achieve nothing.

    FOWP_PMOVE,
    FOWP_FILTER_ENTS,
    FOWP_LAST,
};
const float FOWP_ALL = FOWP_LAST - 1;
const float FOWP_FIRST_PERIODIC = FOWP_IMPULSE;
// Includes FOWP_CONCFINISH: conc_finished/conc_amp/conc_cap_time are levels,
// not events, and the predict state is sent unreliably -- so without a refresh
// a single dropped update left them stale indefinitely.  conc_finished drives
// when PredictConc() clears TFSTATE_CONC, so the effect would end at the wrong
// time on the client and never correct itself.  Costs 9 bytes once per cycle.
// FOWP_CLOCKFIX is a level too: an announced correction and the command it
// lands on, cleared once applied.  It used to ride inside the PMOVE block, so
// a client with movement prediction off -- the default -- never saw it and
// crossed every correction on command lengths alone, while its weapon replay
// (WP_UpdatePredict) folds the same amount the server does.  Eight bytes,
// only when it changes plus once a cycle.
const float FOWP_LAST_PERIODIC = FOWP_CLOCKFIX;

enumflags {
    FOPP_INIT,
    FOPP_POS,
    FOPP_AUX,
    FOPP_ANGLES,
    FOPP_MOVETYPE,
    FOPP_EXPIRY,
    FOPP_FORWARDKNOCK,
    FOPP_CMDBASE,
    FOPP_KNOCKORG,
    FOPP_BLASTDUE,
    FOPP_SRCPLAYER,
};

// A held or thrown grenade's blast on its holder's own command clock:
// last_prime + GREN_FUSE + 0.1, which both sides derive from the same shared
// number.  The server fires the blast on the first command whose clock reaches
// it; the client anchors its own push on that same command.
// Whether this projectile's owner is a player, which decides the knock
// multiplier: 8 normally, 11 for a player-on-player blast under 60 moment.  The
// client cannot tell from the owner it is sent -- an entity number classifies
// nothing -- and assuming a player over-predicted a sentry gun's rocket by
// three eighths of its push.
.float src_is_player;

// Between a projectile's own clock and the viewer's command chain.  cmd_base is
// that viewer's chain reading at the instant first_phys_time was taken, so the
// two are a pair and everything about the flight is a duration from them.
#define Proj_CmdTime(_e, _phys)  ((_e).fpp.cmd_base + max((_phys) - (_e).first_phys_time, 0))
#define Proj_PhysTime(_e, _cmd)  ((_e).first_phys_time + ((_cmd) - (_e).fpp.cmd_base))

// The projectile's own clock at the instant it was created, sent with the
// INIT so both sides hold the same number.  The flight both sides measure is
// the time from here to the impact.
//
// At creation, not at the first position update.  cmd_base is stamped at
// creation, so pairing it with a clock taken when the entity happened to be
// sent leaves the gap between the two unaccounted -- fifty milliseconds of it
// in the trace, the static forward projection plus the wait for a snapshot.
// Both sides used the same pair, so a blast's due still agreed to five
// decimals and nothing showed; a direct hit does not go through the mapping at
// all on the server -- it pushes from the command the crossing happened in --
// and there the two came out 56 ms and 21 units apart.
.float first_phys_time;

.float blast_cmd_due;

.float forward_knock;
// Where the server's copy of this projectile actually went off.  The client
// simulates the flight itself and its trace does not hit networked entities
// (share/physics.qc), so a projectile the server stopped against a player or a
// brush model carries on in our copy and the blast is measured from the wrong
// place.  Sent with the push time so the copy that supersedes our prediction
// can push from the real point.
.vector knock_org;
// Command clock of the firing command (server: warped `time` at fire; client:
// pstate_pred.server_time at the fire frame -- the same number).  The
// shooter's own push from this projectile is due at fire_cmd_time plus the
// projectile's travel, computed the same way on both sides.
.float fire_cmd_time;
// Physics clock right after the static projection (the clock s_origin was set at).
.float s_time;
.float has_cmd_base;    // this projectile carries a per-viewer explosion clock base

// How many commands ahead a correction lands.  It has to clear everything the
// client has already predicted: it runs about eight commands ahead of what we
// have acknowledged, and the round trip is about the same again, so thirty-two
// leaves ample margin.
const float CMD_CLOCK_LEAD = 32;
// Past this the chain is not wandering, something stopped: snap rather than
// wait out the lead with the chain that far wrong.
const float CMD_CLOCK_SNAP = 0.250;

// How much later than its own moment a blast is scheduled for.
//
// Holding a push for the command it was due on can only ever delay it.  It
// cannot release one on a command that has already run, and that is the case
// we keep losing: the chain sits a few milliseconds ahead of the world clock,
// so the command whose window covers the due time can run before the fuse has
// actually gone off.  The client, which predicts the fuse, schedules it on
// that command regardless, and the server finds the push waiting one command
// too late.
//
// Pushing the due time out past the chain's lead puts it on a command neither
// side has reached yet.  Both apply the same lead, so they still agree, and
// the push lands a little after the blast, which nobody can see.
//
// One server frame, derived rather than guessed.  The commands already run in
// the frame the blast goes off in have chain clocks up to that frame's world
// time plus this player's skew, and the blast is somewhere inside that frame,
// so the worst case is exactly a frame.  Any less and the client can pick a
// command the server has already run and cannot reach: at 0.004 that was six
// grenades in seven agreeing and the seventh -- the one whose due landed 3.90 ms
// into its command, inside the same server frame -- one command apart.
//
// It does not remove ties at a command boundary, and nothing local can: a
// continuous due deciding a discrete command is decided by whatever the two
// sides' arithmetic disagrees by.  Quantising the due only moves the boundaries,
// it does not reduce the odds.  What removes it is both sides evaluating the
// same expression from the same sent number, which the stamped path already
// does -- base plus duration on each side.
const float KNOCK_LEAD = SERVER_FRAME_DT;

// How far the chain may sit from the world clock before we correct it.
//
// Most of that distance is not error.  A command waits for the next server
// frame before it is run, so the difference carries a sawtooth a server frame
// plus a client frame wide -- around thirty milliseconds for a client running
// slower than the server, a couple for one running far faster.  Correcting
// inside that floor would chase frame boundaries and feed their jitter into
// the chain, which is the one thing the chain exists to keep out of the replay.
// So the threshold tracks the floor rather than naming a number.
float CmdClockTol(float cmdlen) {
    return max(0.050, 2 * (SERVER_FRAME_DT + cmdlen));
}

#ifdef SSQC
// A clock for explosion prediction, one reading per player, taken when the
// projectile is created and never taken again.
//
// The command clock serves projectile prediction: it is what the two sides
// use to agree on when a shot was fired and how far it has flown.  It is not
// a world clock, and the projectile's own physics clock is not one either --
// the server runs a projectile on server time while the client runs its own
// on its interpolation time, deliberately, so that collisions line up with
// what the player sees.  Neither is a base an explosion can be scheduled from.
//
// So take a third reading purely for explosions: each player's command clock
// at the moment the projectile appears.  Everything after that is a duration,
// and durations are the one thing both sides measure identically.  A fuse is
// its remaining run; a rocket is its flight.  No offset between our clock and
// theirs is ever applied, on either side, so the two cannot arrive at
// different commands however far their clocks have wandered apart.
const float FO_MAXCLIENTS = 32;
.float proj_cmd_base[FO_MAXCLIENTS];

// Slot of a player edict in the above, or -1.
float PlayerSlot(entity p) {
    float i = num_for_edict(p) - 1;
    return (i >= 0 && i < FO_MAXCLIENTS) ? i : -1;
}

// This viewer's reading, or 0 if the projectile never took one for them.
float Proj_CmdBase(entity proj, entity viewer) {
    float slot = PlayerSlot(viewer);
    return (proj.has_cmd_base && slot >= 0) ? proj.proj_cmd_base[slot] : 0;
}

float RealTime();   // ssqc/antilag.qc: real time even inside the command warp

// Each viewer's own clock at the instant this projectile appeared.
//
// Not that viewer's last command clock, which is what this used to record.  A
// projectile created inside a command warp is created at that command, so the
// two are the same and nothing changes -- but one created from a think, in the
// physics phase between commands, is created after that command has already
// run.  The client then measures its blast from a command boundary in the past
// while the server measures from the creation instant, and the two pick
// different commands for the same push: identical due times, releases one and
// two commands apart, client always early.
//
// So record the instant itself, expressed on that viewer's clock.  This is the
// same conversion the server's own forward_knock makes -- blast_due plus that
// player's skew -- so the two constructions now agree by definition instead of
// by coincidence.  It is still sampled once, here, and sent: the client never
// re-derives it, which is the whole point of carrying a base rather than an
// offset.
void Proj_StampViewers(entity proj) {
    proj.has_cmd_base = TRUE;
    entity p = find(world, classname, "player");
    while (p) {
        float slot = PlayerSlot(p);
        if (slot >= 0)
            proj.proj_cmd_base[slot] = RealTime() + p.cmd_clock_skew;
        p = find(p, classname, "player");
    }
}
#endif


enumflags {
    PF_PMOVE,
    PF_POS,
    // Target's armour absorbs explosion damage.  Needed for knockback
    // prediction and not derivable client-side: no class grants
    // AT_SAVEEXPLOSION (every *_INITARMORCLASS is 0 bar pyro's AT_SAVEFIRE),
    // so it only ever arrives via an armour pickup.
    PF_SAVE_EXPLOSION,
    // Fire armour, for a direct incendiary hit: TF_TD_FIRE, halved by
    // AT_SAVEFIRE.  Pyros spawn with it, so it is not a pickup case.
    PF_SAVE_FIRE,
};

static float MAX_FILTER_ENTS = 4;

// How many consecutive updates each filter entry is repeated in.  The predict
// state goes over an unreliable multicast (MULTICAST_ONE_NOSPECS), and this
// list is the only thing stopping the client double-applying knockback it
// already predicted locally -- so a single dropped packet used to mean one
// explosion counted twice, with no refresh to recover it.
//
// Repeating for a few frames is redundancy rather than reliability: no
// retransmit queue and no head-of-line blocking on every other prediction
// field, and it degrades gracefully under sustained loss instead of stalling.
// The client is naturally idempotent here -- it matches nudges by source and
// clears its own copy, so a repeat it already handled finds nothing to remove.
static float kFilterSends = 3;

struct predict_tf_state {
    int playerclass;
    int predict_flags, effects;
    int impulse;
    Slot current_slot, queue_slot, last_slot;

    ConcState conc_state;

    float tfstate;
    float movetype;
    float last_prime;
    float csqc_maxspeed;

    float conc_amp;
    float conc_finished;
    float conc_cap_time;
    float special_next;

    float server_time;
    float weaponframe;

    float attack_finished;
    float client_nextthink;
    float client_thinkindex;

    float reload_started;
    float reload_finished;
    float clip_fired[4];
    int prng_base[PRNG_NUM_STATES];

    float no_grenades_1, no_grenades_2, primed_gren_type, primed_gren_exp;

    float num_filter_ents;
#ifdef SSQC
    entity filter_ents[MAX_FILTER_ENTS];
    float filter_ttl[MAX_FILTER_ENTS];   // sends remaining, see FOWP_FILTER_ENTS
#else
    float filter_ents[MAX_FILTER_ENTS];
#endif

    // PMove
    struct pmove_t {
        int enabled;
        vector origin;
        vector velocity;
        // The client's wire timestamp of the command that produced this
        // state, as the server saw it (engine field cmd_servertime).  Stamps
        // are chained by msec, so the client rebuilds the server's stamp for
        // any later frame as this plus its own input_timelength per frame:
        // the same number on both sides without either trusting its own
        // clock.  Advanced per replayed frame in pstate_pred.
        float cmd_servertime;

        // How far the command clock runs ahead of the server's own clock for
        // this player.  Anything the server schedules on world time -- a
        // grenade's fuse, a projectile the client did not fire -- has to be
        // moved onto the command clock before the prediction can place it,
        // because the windows it matches against are built from that clock.
        // Sits anywhere up to the clock's re-anchor threshold, so it is worth
        // tens of milliseconds and shows up as a knock landing frames early.
        float cmd_clock_skew;
    float cmd_clock_fix;
    float cmd_clock_fix_seq;
    } pmove;

#ifdef CSQC
    // Used for prediction, not actually communicated.  Reset each frame.
    int seq;
    float ammo_used[AMMO_NUM_TYPES];
    float buttons_down, buttons_up, buttons_held;
#endif
};

string CF_GetSettingRaw(string ps_short, string ps_setting, string ps_default);
float CF_GetSetting(string ps_short, string ps_setting, string ps_default);

enum SoundIndex:float {
    SND_NONE = 0,
    SND_FIRST = 2000,
    SND_AXE = SND_FIRST,
    SND_SG,
    SND_SSG,
    SND_RL,
    SND_GREN,
    SND_THROWGREN,
    SND_NAIL,
    SND_SNAIL,
    SND_FLAMETHROWER,
    SND_RAILGUN,
    SND_TRANQ,
    SND_SNIPER_RIFLE,
    SND_ASSCAN_UP,
    SND_ASSCAN_FIRE,
    SND_ASSCAN_DOWN,
    SND_ASSCAN_SPIN,
};

struct fo_predsnd {
    SoundIndex id;
    string sound;
};

static fo_predsnd snd_types[] = {
    { SND_AXE, "ax1.wav" },
    { SND_SG, "guncock.wav" },
    { SND_SSG, "shotgn2.wav" },
    { SND_RL, "sgun1.wav" },
    { SND_GREN, "grenade.wav" },
    { SND_THROWGREN, "ax1.wav" },
    { SND_NAIL, "rocket1i.wav" },
    { SND_SNAIL, "spike2.wav" },
    { SND_FLAMETHROWER, "flmfire2.wav" },
    { SND_RAILGUN, "railgun.wav" },
    { SND_TRANQ, "dartgun.wav" },
    { SND_SNIPER_RIFLE, "sniper.wav" },
    { SND_ASSCAN_UP, "asscan1.wav" },
    { SND_ASSCAN_FIRE, "asscan2.wav" },
    { SND_ASSCAN_DOWN, "asscan3.wav" },
    { SND_ASSCAN_SPIN, "asscan4.wav" },
};

enum {
    FPP_NONE,
    FPP_FIRST = 50,
    FPP_ROCKET = FPP_FIRST,
    FPP_GRENADE,        // Grenade launcher
    FPP_HANDGRENADE,    // TF Grenade
    FPP_INCENDIARY,
    FPP_NAIL,
    FPP_SUPER_NAIL,
    FPP_FLAMETHROWER,
    FPP_TRANQ,
    FPP_RAILGUN,
    FPP_ASSAULT_CANNON,
};

// Short weapon/projectile name for traces.
string FPP_Name(int fpp_type) {
    switch (fpp_type) {
        case FPP_ROCKET:         return "rocket";
        case FPP_GRENADE:        return "gl";
        case FPP_HANDGRENADE:    return "hgren";
        case FPP_INCENDIARY:     return "ic";
        case FPP_NAIL:           return "nail";
        case FPP_SUPER_NAIL:     return "snail";
        case FPP_FLAMETHROWER:   return "flame";
        case FPP_TRANQ:          return "tranq";
        case FPP_RAILGUN:        return "rail";
        case FPP_ASSAULT_CANNON: return "ac";
        default:                 return ftos(fpp_type);
    }
}

struct fo_projectile {
    int id;
    int movetype;
    float speed;
    string model;
    string trail;
    SoundIndex snd;
    float fixed_project;  // No dynamic proportioning of newmis projection

    // Automatically initialized below this line.
    float modelindex;
    float trailindex;
};

static fo_projectile fpp_types[] = {
    { FPP_ROCKET,       MOVETYPE_FLYMISSILE, PC_SOLDIER_ROCKET_SPEED,
        "missile.mdl", "t_rocket", SND_RL, TRUE },
    { FPP_GRENADE,      MOVETYPE_BOUNCE,     600,
        "grenade2.mdl", "t_grenade", SND_GREN, TRUE},
    { FPP_HANDGRENADE,  MOVETYPE_BOUNCE,     600,
        "hgren2.mdl", "t_grenade", SND_THROWGREN},
    { FPP_INCENDIARY,   MOVETYPE_FLYMISSILE, 800,
        "lavaball.mdl", "t_lavaball", SND_RL, TRUE },
    { FPP_NAIL,         MOVETYPE_FLYMISSILE, 1500,
        "spike.mdl", "tr_spike", SND_NAIL },
    { FPP_SUPER_NAIL,   MOVETYPE_FLYMISSILE, 1500,
        "s_spike.mdl", "tr_spike", SND_SNAIL },
    { FPP_FLAMETHROWER, MOVETYPE_FLYMISSILE, 600,
        "s_explod.spr", "explodesprite", SND_FLAMETHROWER },
    { FPP_TRANQ,        MOVETYPE_FLYMISSILE,  PC_SPY_TRANQSPEED,
        "spike.mdl", "tr_spike", SND_TRANQ },
    { FPP_RAILGUN,      MOVETYPE_FLYMISSILE, PC_ENGINEER_RAILSPEED,
        "e_spike1.mdl", "te_railtrail", SND_RAILGUN },
    { FPP_ASSAULT_CANNON, MOVETYPE_FLYMISSILE, 3000,
        "proj_diam2.mdl", "tr_asscan", SND_NONE /* in anim */ },
};

inline fo_projectile* FPP_Get(int fpp_type) { return &fpp_types[fpp_type - FPP_FIRST]; }
inline fo_predsnd* Snd_Get(int snd_type) { return &snd_types[snd_type - SND_FIRST]; }
inline fo_predsnd* FPP_Sound(int fpp_type) { return Snd_Get(FPP_Get(fpp_type)->snd); }

inline float FPP_IsGrenade(int fpp_type) {
    return fpp_type == FPP_GRENADE || fpp_type == FPP_HANDGRENADE;
}

void InitFppProjectiles() {
    float i;
    static int once;
    ASSERTD_EQ(once, 0);
    once = 1;

    for (i = 0; i < fpp_types.length; i++) {
        fo_projectile* desc = &fpp_types[i];
        ASSERTD_EQ(i + FPP_FIRST, desc->id);
        desc->model = strcat("progs/", desc->model);
        desc->modelindex = getmodelindex(desc->model);
        if (desc->trail != "")
            desc->trailindex = particleeffectnum(strcat("fo-particles.",desc->trail));
    }

    for (i = 0; i < snd_types.length; i++) {
        fo_predsnd* snd = &snd_types[i];

        ASSERTD_EQ(SND_FIRST + i, snd->id);
        snd->sound = strcat("weapons/", snd->sound);
        precache_sound(snd->sound);
    }
}

float max_rewind_credit_ms(int fpp_type) {
    return (FPP_Get(fpp_type)->speed < tf_config.rewind_fast_projectile_thresh) ?
        tf_config.max_rewind_slow_projectile_ms :
        tf_config.max_rewind_fast_projectile_ms;
}


// The original QW implementation always forwards projectiles by 50ms, in a
// similar way to our own antilag projection.  However, this is done in a
// difficult to correct for fashion (especially with more complicated
// projectiles such as grenades) as well as not reflecting the ping times of
// today.  We split this into a ping independent and ping dependent portion, to
// slightly widen the range at which feel and timing is uniform.
//
// NOTE: DO NOT USE NEWMIS FOR FO PROJECTILES.  THE NEWMIS CORRECTION IS NOW
// MADE EXPLICITLY RATHER THAN IMPLICITLY.  [WE AUTOMATICALLY STRIP NEWMIS
// FROM PROJECTILES PASSED TO US.]
static float static_newmis_ms(int fpp_type) {
    if (fpp_type == FPP_FLAMETHROWER || fpp_type == FPP_ASSAULT_CANNON)
        return 0;

    return tf_config.static_newmis_ms - tf_config.dynamic_newmis_ms;
}

inline float dynamic_newmis_ms() {
    return tf_config.dynamic_newmis_ms;
}

inline float fixed_newmis_ms(int fpp_type) {
    return tf_config.static_newmis_ms;
}

// Grenade 1's ping credit: the command's age past the floor, up to the cap.
// No other grenade gets any.  Compiled in, not a knob (2026-09-21).
const float GREN1_CREDIT_FLOOR_MS = 50;
const float GREN1_CREDIT_MAX_MS = 50;

#ifdef SSQC

.predict_tf_state predict_state;
.entity predict_entity;
.float conc_cap_time;

inline float *self_tf_state() { return &self.tfstate; }
float self_class() { return self.playerclass; }
Slot self_current_slot() { return self.current_slot; }
Slot self_queue_slot() { return self.queue_slot; }
float* self_clip_fired(Slot slot) { return &self.clip_fired[SlotIndex(slot)]; }

#else

predict_tf_state pstate_pred, pstate_server;

inline float *self_tf_state() { return &pstate_pred.tfstate; }
float self_class() { return pstate_pred.playerclass; }
Slot self_current_slot() { return pstate_pred.current_slot; }
Slot self_queue_slot() { return pstate_pred.queue_slot; }
float* self_clip_fired(Slot slot) { return &pstate_pred.clip_fired[SlotIndex(slot)]; }

#define MASK_PRED_ENT        256
#define MASK_PRED_PROJECTILE 512
#define MASK_OUTLINE        1024

#endif

#ifdef SSQC
#define OP1(_op, _f1)                       (player.predict_state.##_f1 _op src.##_f1)
#define OP2(_op, _j, _f1, _f2)              OP1(_op, _f2)               _j OP1(_op, _f1)
#define OP3(_op, _j, _f1, _f2, _f3)         OP2(_op, _j, _f2, _f3)      _j OP1(_op, _f1)
#define OP4(_op, _j, _f1, _f2, _f3, _f4)    OP3(_op, _j, _f2, _f3, _f4) _j OP1(_op, _f1)
#define M1(_bit, _f1) if (OP1(!=, _f1)) { mask |= _bit; OP1(=, _f1); }
#define M2(_bit, _f1, _f2) if (OP2(!=, ||, _f1, _f2)) { mask |= _bit; OP2(=, ;, _f1, _f2); }
#define M3(_bit, _f1, _f2, _f3) if (OP3(!=, ||, _f1, _f2, _f3)) { mask |= _bit; OP3(=, ;, _f1, _f2, _f3); }
#define M4(_bit, _f1, _f2, _f3, _f4) if (OP4(!=, ||, _f1, _f2, _f3, _f4)) { mask |= _bit; OP4(=, ;, _f1, _f2, _f3, _f4); }

.float pred_forcebit;
.float predict_flags;

static float Prediction_ChangedMask(entity player, entity src) {
    float mask = 0;

    // Maintained on src, because that is what the delta below transmits.  Each
    // player sets this in their own Predict_Update pass, so a spectator's pass
    // simply recomputes the same value.
    if (src.armorclass & AT_SAVEEXPLOSION)
        src.predict_flags |= PF_SAVE_EXPLOSION;
    else
        src.predict_flags &= ~PF_SAVE_EXPLOSION;
    if (src.armorclass & AT_SAVEFIRE)
        src.predict_flags |= PF_SAVE_FIRE;
    else
        src.predict_flags &= ~PF_SAVE_FIRE;

    player.predict_state.server_time = time;

    if (player.predict_flags & (PF_PMOVE | PF_POS))
        mask |= FOWP_PMOVE;

    if (player == src && player.predict_state.num_filter_ents > 0)
        mask |= FOWP_FILTER_ENTS;

    // The correction is an entity field with no top-level twin in the predict
    // state, so it is compared by hand against the pmove shadow.
    if (player.predict_state.pmove.cmd_clock_fix != src.cmd_clock_fix ||
        player.predict_state.pmove.cmd_clock_fix_seq != src.cmd_clock_fix_seq) {
        mask |= FOWP_CLOCKFIX;
        player.predict_state.pmove.cmd_clock_fix = src.cmd_clock_fix;
        player.predict_state.pmove.cmd_clock_fix_seq = src.cmd_clock_fix_seq;
    }

    M1(FOWP_CLASS, playerclass);
    M4(FOWP_IMPULSE, impulse, current_slot.id, queue_slot.id, last_slot.id);
    M2(FOWP_TFSTATE, tfstate, csqc_maxspeed);
    M1(FOWP_LASTPRIME, last_prime);
    M4(FOWP_CLASSIC_CONC, conc_state.next, conc_state.mag,
                          conc_state.next_push, conc_state.next_flip);
    M3(FOWP_CONCFINISH, conc_finished, conc_amp, conc_cap_time);
    M1(FOWP_MOVETYPE, movetype);
    M1(FOWP_WF, weaponframe);
    M1(FOWP_AF, attack_finished);
    M2(FOWP_THINK, client_nextthink, client_thinkindex);
    M4(FOWP_CLIP, clip_fired[0], clip_fired[1], clip_fired[2], clip_fired[3]);
    M2(FOWP_RELOAD, reload_started, reload_finished);
    M1(FOWP_SPECIAL, special_next);
    M2(FOWP_RNG0, prng_base[PRNG_WEAP], prng_base[PRNG_MOVE]);
    M1(FOWP_RNG1, prng_base[PRNG_HWGUY]);
    M1(FOWP_RNG2, prng_base[PRNG_CONC]);
    M2(FOWP_PREDICT_FLAGS, predict_flags, effects);
    M4(FOWP_GREN, no_grenades_1, no_grenades_2, primed_gren_type, primed_gren_exp)

    // Rotate through forced update fields.
    player.pred_forcebit <<= 1;
    if (player.pred_forcebit < FOWP_FIRST_PERIODIC || player.pred_forcebit > FOWP_LAST_PERIODIC)
        player.pred_forcebit = FOWP_FIRST_PERIODIC;
    mask |= player.pred_forcebit;

    return mask;
}

void Predict_AddFilterEnt(entity p, entity filter) {
    if (p.predict_flags & PF_PMOVE == 0)
        return;

    predict_tf_state* ps = &p.predict_state;

    // Already listed?  Refresh its lifetime rather than consuming a second slot.
    for (float i = 0; i < ps->num_filter_ents; i++) {
        if (ps->filter_ents[i] == filter) {
            ps->filter_ttl[i] = kFilterSends;
            return;
        }
    }

    if (ps->num_filter_ents >= MAX_FILTER_ENTS)
            return;

    ps->filter_ttl[ps->num_filter_ents] = kFilterSends;
    ps->filter_ents[ps->num_filter_ents++] = filter;
}

void Predict_SyncPmove(float is_player);

void TFL_SendPredictState(entity to_player, float mask);

void Predict_Update(float is_player) {
    Predict_SyncPmove(is_player);

    // When spectating, goalentity is our target.
    entity src = self.goalentity;
    if (!src)
        src = self;

    float mask = Prediction_ChangedMask(self, src);
    TFL_SendPredictState(self, mask);
}

#undef OP1
#undef OP2
#undef OP3
#undef OP4
#undef M1
#undef M2
#undef M3
#undef M4

void sprint_pred(entity client, float msglevel, string s) {
    if (ClientPred_Enabled(client, CSQC_WEAP_PRED))
        return;  // Message generated client-side.
    sprint(client, msglevel, s);
}
#endif

#ifdef SSQC
void WriteVector(float to, vector val) {
    WriteCoord(to, val_x);
    WriteCoord(to, val_y);
    WriteCoord(to, val_z);
}
#else /* CSQC */
float() ReadByte = #360;
float() ReadShort = #362;
float() ReadCoord = #364;
float() ReadAngle = #365;
float() ReadFloat = #367;
float() ReadEntity = #368;
int() ReadInt = #0:readint;

vector ReadVector(float to, vector val) {
    return [ReadCoord(), ReadCoord(), ReadCoord()];
}

void InitProjectileEnt(float sendflags);
void WPP_UpdateEnable(float force);

.float owner_entnum;
#endif

#ifdef SSQC
#define SEND_CFG_OP(_ig1, _ctype, _ig2 , _field) \
    Write##_ctype(MSG_MULTICAST, tf_config.##_field);

void TFL_SendConfig(entity target) {
    float msg_t;

    if (target == world) {
        msg_t = MULTICAST_ALL_R;
    } else {
        msg_entity = target;
        msg_t = MULTICAST_ONE_R;
    }

    WriteByte(MSG_MULTICAST, SVC_CGAMEPACKET);
    WriteByte(MSG_MULTICAST, MSG_TFL_CONFIG);
    TMPL_CONFIG_DATA(SEND_CFG_OP)
    multicast('0 0 0', msg_t);
}
#else
#define RECV_CFG_OP(_ig1, _ctype, _ig2 , _field) \
    tf_config.##_field = Read##_ctype();

void TFL_ReceiveConfig() {
    TMPL_CONFIG_DATA(RECV_CFG_OP)
}
#endif

#ifdef SSQC
#define GETF(_field) self.predict_state.##_field
#define COMM(_type, _field) Write##_type(MSG_MULTICAST, GETF(_field))
#define COMM_PM(_type, _field) Write##_type(MSG_MULTICAST, self.##_field)
void TFL_SendPredictState(entity to_player, float mask) {
    WriteByte(MSG_MULTICAST, SVC_CGAMEPACKET);
    WriteByte(MSG_MULTICAST, MSG_PREDICTSTATE);
    WriteFloat(MSG_MULTICAST, mask);
#else
#define GETF(_field) pstate_server.##_field
#define COMM(_type, _field) GETF(_field) = Read##_type()
#define COMM_PM(_type, _field) pstate_server.pmove.##_field = Read##_type()
#define cmd_stamp_clock cmd_servertime   // the echoed stamp clock lands in pmove.cmd_servertime

void WP_ServerUpdate(float mask);

// Careful: This arrives as the server frame increments; but it still reads as
// the previous frame during message receive.  We push processing to
// WP_ClientThink.
void TFL_RecvPredictState() {
    float mask = readfloat();
    pstate_server.pmove.enabled = mask & FOWP_PMOVE;
#endif
    if (mask & FOWP_PREDICT_FLAGS) {
        COMM(Byte, predict_flags);
        COMM(Short, effects);
    }

    // Sent every update, so said plainly rather than behind a mask bit that was
    // always set.  The command clock belongs out here and not in the pmove
    // block: a predicted projectile anchors its start on it and the server
    // anchors its copy on the same number for everybody, so a client with pmove
    // off saw a zero anchor and fell back to a time-based start the server was
    // no longer using.
    COMM(Float, server_time);
    COMM_PM(Float, cmd_stamp_clock);

    // Outside the PMOVE block: the weapon replay folds it whether or not
    // movement is predicted (FOWP_CLOCKFIX, above).
    if (mask & FOWP_CLOCKFIX) {
        COMM_PM(Float, cmd_clock_fix);
        COMM_PM(Float, cmd_clock_fix_seq);
    }

    if (mask & FOWP_PMOVE) {
        COMM_PM(Coord, origin[0]);
        COMM_PM(Coord, origin[1]);
        COMM_PM(Coord, origin[2]);
        COMM_PM(Short, velocity[0]);
        COMM_PM(Short, velocity[1]);
        COMM_PM(Short, velocity[2]);
        // cmd_stamp_clock and the correction are sent above; this one really
        // is movement prediction and stays here.
        COMM_PM(Float, cmd_clock_skew);
    }

    if (mask & FOWP_FILTER_ENTS) {
        COMM(Byte, num_filter_ents);
        for (float i = 0; i < GETF(num_filter_ents); i++)
            COMM(Entity, filter_ents[i]);
#ifdef SSQC
        // Age entries out instead of clearing on first send, so the list
        // survives a lost packet.  Compacts in place, preserving order.
        float keep = 0;
        for (float i = 0; i < GETF(num_filter_ents); i++) {
            if (GETF(filter_ttl[i]) <= 1)
                continue;

            GETF(filter_ents[keep]) = GETF(filter_ents[i]);
            GETF(filter_ttl[keep]) = GETF(filter_ttl[i]) - 1;
            keep++;
        }
        GETF(num_filter_ents) = keep;
#endif
    }

    if (mask & FOWP_CLASS) {
        COMM(Byte, playerclass);
    }

    if (mask & FOWP_MOVETYPE) {
        COMM(Byte, movetype);
    }

    if (mask & FOWP_IMPULSE) {
        COMM(Byte, impulse);
        COMM(Byte, current_slot.id);
        COMM(Byte, queue_slot.id);
        COMM(Byte, last_slot.id);
    }

    if (mask & FOWP_TFSTATE) {
        COMM(Float, tfstate);
        // Not a Short.  TeamFortress_SetSpeed halves for tranq and for a slow
        // goal and scales by leg damage in tenths, so an odd intermediate
        // lands on a half: a tranquilised hwguy with one leg hit is 103.5, a
        // slowed scout 202.5.  Truncating that put the client's movement cap
        // half a unit under the server's, on the one value this whole
        // subsystem exists to keep the two agreeing about.
        COMM(Float, csqc_maxspeed);
    }

    if (mask & FOWP_LASTPRIME) {
        COMM(Float, last_prime);
    }

    if (mask & FOWP_CLASSIC_CONC) {
        COMM(Float, conc_state.next);
        COMM(Byte, conc_state.mag);
        COMM(Float, conc_state.next_push);
        COMM(Byte, conc_state.next_flip);
    }

    if (mask & FOWP_CONCFINISH) {
        // base_amp * the class multiplier: 1.5 for a scout, 0.75 for a hwguy,
        // and base_amp is the foc_amp localinfo.  So it is fractional at the
        // default (110 * 0.75 = 82.5) and leaves a byte entirely once foc_amp
        // is raised past 170.
        COMM(Float, conc_amp);
        COMM(Float, conc_finished);
        COMM(Float, conc_cap_time);
    }

    if (mask & FOWP_THINK) {
        COMM(Float, client_nextthink);
        COMM(Float, client_thinkindex);
    }

    if (mask & FOWP_WF) {
        COMM(Byte, weaponframe);
    }

    if (mask & FOWP_AF) {
        COMM(Float, attack_finished);
    }

    if (mask & FOWP_CLIP) {
        COMM(Byte, clip_fired[0]);
        COMM(Byte, clip_fired[1]);
        COMM(Byte, clip_fired[2]);
        COMM(Byte, clip_fired[3]);
    }

    if (mask & FOWP_RELOAD) {
        COMM(Float, reload_started);
        COMM(Float, reload_finished);
    }

    if (mask & FOWP_SPECIAL) {
        COMM(Float, special_next);
    }

    if (mask & FOWP_RNG0) {
        COMM(Int, prng_base[PRNG_WEAP]);
        COMM(Int, prng_base[PRNG_MOVE]);
    }
    if (mask & FOWP_RNG1)
        COMM(Int, prng_base[PRNG_HWGUY]);
    if (mask & FOWP_RNG2)
        COMM(Int, prng_base[PRNG_CONC]);

    if (mask & FOWP_GREN) {
        COMM(Byte, no_grenades_1);
        COMM(Byte, no_grenades_2);
        COMM(Byte, primed_gren_type);
        COMM(Float, primed_gren_exp);
    }

#ifdef SSQC
    msg_entity = to_player;
    multicast('0 0 0', MULTICAST_ONE_NOSPECS);
#endif
}
#undef COMM
#undef COMM_PM
#undef GETF
#ifndef SSQC
#undef cmd_stamp_clock   // scoped like the rest: 20-odd csqc files follow this one
#endif

#ifdef SSQC
#define COMM(_type, _field) Write##_type(MSG_ENTITY, self.##_field)
#define COMMD(_type, _dest, _field) COMM(_type, _field)
#define COMMO(_type, _dest, _src) Write##_type(MSG_ENTITY, _src)
float PP_SendEntity(entity to_player, float sendmask) {
    float sendflags = sendmask;

    if (sendflags & FOPP_INIT) {
        sendflags = FOPP_INIT | FOPP_POS;  // Note: replaces sendmask
        if (self.fpp.aux)
            sendflags |= FOPP_AUX;
        if (self.fpp.expires_at)
            sendflags |= FOPP_EXPIRY;
        if (FPP_Get(self.fpp.index)->movetype != self.movetype)
            sendflags |= FOPP_MOVETYPE;
        if (self.has_cmd_base)
            sendflags |= FOPP_CMDBASE;
        // A statement about the owner's own command chain, so nobody else is
        // sent it.  Set at the spawn, which is before the first update, so the
        // INIT carries it and no later update has to.
        if (self.blast_cmd_due && to_player == self.owner)
            sendflags |= FOPP_BLASTDUE;
        if (self.owner.classname == "player")
            sendflags |= FOPP_SRCPLAYER;
    }

    // Outside the INIT block on purpose.  forward_knock is only set at impact,
    // and a projectile that lived long enough to be sent once before then takes
    // its last update as a delta, not an INIT -- so the push time only ever
    // reached the client for a projectile whose first update was also its last.
    // Without it the client dates the blast from its own physics clock, which
    // for a shot the server projected 140 ms forward was 90 ms early and 172
    // u/s of push the server had not applied.
    if (self.forward_knock)
        sendflags |= FOPP_FORWARDKNOCK;
    // Its own flag rather than riding the push time: a grenade has a blast
    // point but no push time of its own, its due coming from the fuse both
    // sides already hold.
    if (self.knock_org)
        sendflags |= FOPP_KNOCKORG;

    WriteByte(MSG_ENTITY, ENT_PROJECTILE);
    WriteShort(MSG_ENTITY, sendflags);   // ten flags, long past fitting in a byte
#else
void PM_UpdateNudgeSource(entity ent, vector src);
void PM_ReanchorPredictedNudge(entity sent);
#define COMMD(_type, _dest, _field) self.##_dest = Read##_type()
#define COMMO(_type, _dest, _src) ##_dest = Read##_type()
#define COMM(_type, _field) COMMD(_type, _field, _field)

void EntUpdate_Projectile(float isnew) {
    float sendflags = readshort();
#endif
    if (sendflags & FOPP_INIT) {
        COMM(Byte, fpp.index);
        COMM(Short, antilag_ms);
        COMM(Float, created_at);
        COMM(Float, first_phys_time);
        COMM(Float, fire_seq);
        COMMD(Entity, owner_entnum, owner);
    }

#ifdef CSQC
    if (sendflags & FOPP_INIT)
        self.src_is_player = (sendflags & FOPP_SRCPLAYER) ? TRUE : FALSE;
#endif

    if (sendflags & FOPP_AUX)
        COMM(Short, fpp.aux);
    if (sendflags & FOPP_EXPIRY)
        COMM(Float, fpp.expires_at);

    // Our own command clock at the moment this projectile appeared, read on
    // the server and sent to us alone.  Whatever it goes on to do is timed as
    // a duration from here, by both sides, so neither ever has to convert a
    // world time with an offset the other cannot see.
    if (sendflags & FOPP_CMDBASE) {
        COMMO(Float, self.fpp.cmd_base, Proj_CmdBase(self, to_player));
#ifdef CSQC
        self.has_cmd_base = TRUE;
#endif
    }

    // Which command our own grenade's blast comes off: the first whose clock
    // reaches this.  We work the same value out ourselves when we predict the
    // prime, but the copy that actually pushes us is this one, and it has no
    // way to re-derive it -- the prime it measures from has been cleared by
    // the time the grenade is in the air.
    if (sendflags & FOPP_BLASTDUE)
        COMM(Float, blast_cmd_due);

    if (sendflags & FOPP_POS) {
        COMM(Coord, origin[0]);
        COMM(Coord, origin[1]);
        COMM(Coord, origin[2]);
        COMM(Coord, velocity[0]);
        COMM(Coord, velocity[1]);
        COMM(Coord, velocity[2]);

        COMM(Float, phys_time);
#ifdef CSQC
        self.s_origin = self.origin;
        self.s_time = self.phys_time;
#endif
    }

    if (sendflags & FOPP_ANGLES) {
        COMM(Coord, angles[0]);
        COMM(Coord, angles[1]);
        COMM(Coord, angles[2]);
        COMM(Short, avelocity[0]);
        COMM(Short, avelocity[1]);
        COMM(Short, avelocity[2]);
    }

    if (sendflags & FOPP_MOVETYPE) {
        COMM(Byte, movetype);
        if (self.movetype == MOVETYPE_FOLLOW)
            COMMD(Entity, aiment_num, aiment);
    }

    if (sendflags & FOPP_FORWARDKNOCK)
        COMM(Float, forward_knock);

    if (sendflags & FOPP_KNOCKORG) {
        COMM(Coord, knock_org[0]);
        COMM(Coord, knock_org[1]);
        COMM(Coord, knock_org[2]);
#ifdef CSQC
        // A grenade's blast is scheduled when our own simulation reaches the
        // fuse, from where our copy came to rest; the server's point arrives
        // afterwards.  Nothing else would ever read it, so move the nudge.
        //
        // Never on an INIT: this entity is then a projectile we have not
        // scheduled anything for, and created_seq -- the field that tells it
        // apart from the last projectile in the same recycled slot -- is not
        // refreshed until InitProjectileEnt runs at the end of this function.
        if (!(sendflags & FOPP_INIT))
            PM_UpdateNudgeSource(self, self.knock_org);
#endif
    }

#ifdef CSQC
    // The server's due and blast point for a projectile we predicted, applied
    // to the predicted nudge (PM_ReanchorPredictedNudge).  The copy's own
    // nudge replaces it only when our sim reaches PM_AddSimExplosion for the
    // copy, and on a flight longer than the forward projection that has
    // already happened -- before these fields existed -- and never again.
    if (sendflags & (FOPP_FORWARDKNOCK | FOPP_KNOCKORG))
        PM_ReanchorPredictedNudge(self);
#endif

#ifdef SSQC
    return TRUE;
#else
    if (isnew)
        InitProjectileEnt(sendflags);
#endif
}
#undef COMMD
#undef COMMO
#undef COMM


void Predict_InitDefaultConfig() {
    tf_config.min_ping_ms = 0;
    tf_config.static_newmis_ms = 50;
    tf_config.dynamic_newmis_ms = 0;
    tf_config.rewind_flags = REWIND_DEFAULT_FLAGS;
    tf_config.tfx_flags = TFX_DEFAULT_FLAGS;
    tf_config.max_rewind_ms = 250;
    tf_config.max_rewind_slow_projectile_ms = 150;
    tf_config.max_rewind_fast_projectile_ms = 150;
    tf_config.rewind_fast_projectile_thresh = 1500;
    tf_config.clown_flags = 0;
    tf_config.clown_grav = 400;
    tf_config.fo_concuss = 0;
    tf_config.new_balance_flags = 0;
    tf_config.pipe_cooldown = 0.5;
    tf_config.cmd_time = 1;
}

#ifdef SSQC

#define CONFIG_UPDATE(_flag, _ps_short, _field) \
    do { string _cur = ftos(tf_config.##_field); \
      float _val; \
      if (_flag) \
        _val = ParseFlags(CF_GetSettingRaw(_ps_short, #_field, _cur)); \
      else \
        _val = CF_GetSetting(_ps_short, #_field, _cur); \
      if (_val != tf_config.##_field) { \
          tf_config.##_field = _val; update = TRUE; \
      } \
    } while (0)
#define CLAMP_UPDATE(_field, _clamp_low, _clamp_high) \
    do { if (tf_config.##_field < _clamp_low || tf_config.##_field > _clamp_high) { \
        tf_config.##_field = max(min(tf_config.##_field, _clamp_high), _clamp_low); \
        update = TRUE; \
    } } while (0)

float ForwardDoorsPossible() {
    static float once;
    static float possible;

    if (!once) {
        possible = CF_GetSetting("rfd", "rewind_forward_doors", "off");
        once = TRUE;
    }

    return possible;
}

// Equivalent to stof(str) when not splittable (e.g. single OR'd val).
static float ParseFlags(string str) {
    float n = tokenize(str);
    float result = 0;
    for (int i = 0; i < n; i++)
        result |= stof(argv(i));
    return result;
}

entity config_update;
static void TflCheckConfigUpdate() {
    float update = FALSE;

    // Not dynamically updatable:
    //  old_ng_rof, pipe_cooldown

    float mpm = CF_GetSetting("mpm", "min_ping_ms", 0);
    mpm = max(mpm, min_ping_limit_ms);
    if (mpm != tf_config.min_ping_ms) {
        tf_config.min_ping_ms = mpm;
        update = TRUE;
    }

    // Target is also the long form localinfo name.
    CONFIG_UPDATE(FALSE, "snm", static_newmis_ms);
    CONFIG_UPDATE(FALSE, "dnm", dynamic_newmis_ms);
    CONFIG_UPDATE(FALSE, "mrt", max_rewind_ms);
    CONFIG_UPDATE(FALSE, "mrsp", max_rewind_slow_projectile_ms);
    CONFIG_UPDATE(FALSE, "mrfp", max_rewind_fast_projectile_ms);
    CONFIG_UPDATE(FALSE, "rfpt", rewind_fast_projectile_thresh);
    CONFIG_UPDATE(FALSE, "gbd", gren_beta_disable);

    if (fo_concuss != tf_config.fo_concuss) {
        tf_config.fo_concuss = fo_concuss;
        update = TRUE;
    }



    CONFIG_UPDATE(TRUE,  "rewind", rewind_flags);
    CONFIG_UPDATE(TRUE,  "tfx", tfx_flags);
    CONFIG_UPDATE(TRUE,  "clown", clown_flags);
    CONFIG_UPDATE(FALSE, "clown_grav", clown_grav);
    CONFIG_UPDATE(FALSE, "rj", rj);
    CONFIG_UPDATE(FALSE, "cmdt", cmd_time);

    CLAMP_UPDATE(dynamic_newmis_ms, 0, tf_config.static_newmis_ms);
    CLAMP_UPDATE(max_rewind_ms, 0, 250);
    CLAMP_UPDATE(max_rewind_slow_projectile_ms, 0, tf_config.max_rewind_ms);
    CLAMP_UPDATE(max_rewind_fast_projectile_ms, 0, tf_config.max_rewind_ms);

    if (!ForwardDoorsPossible())
        tf_config.rewind_flags &= ~REWIND_FORWARD_DOORS;

    if (update)
        TFL_SendConfig(world);

    config_update.nextthink = time + 1;
};
#undef CLAMP_UPDATE
#undef CONFIG_UPDATE


void Predict_Init() {
    Predict_InitDefaultConfig();
}

void Config_Final() {
    config_update = spawn();
    config_update.think = TflCheckConfigUpdate;

    TflCheckConfigUpdate();  // Sets nextthink
}

void FO_CustomPhysics() {
    if (!self.voided) {
        self.al_prev_origin = self.origin;
        float physf = 0;
        if (RewindFlagEnabled(REWIND_PROJ_TRAVEL))
            physf = PHYSF_REWIND_PLAYERS;   // each step meets the world as it was at that step's time

        Phys_Advance(self, time + frametime, physf);

        // Moving platforms don't get properly reflected into the entities CSQC
        // sees so just blast the client with updates when on one (in motion).
        // Basically what the stock netcode does anyway.  It's not perfect but,
        // better than nothing.
        entity ground = self.groundentity;
        if ((self.flags & FL_ONGROUND) && (ground.movetype == MOVETYPE_PUSH) &&
            (vlen(ground.velocity) > 0))
            self.SendFlags |= FOPP_POS;
    }

    float held_time, thinktime;
    // Once we lift physics, think execution comes with it.
    do {
        thinktime = self.nextthink;
        if (thinktime <= 0 || thinktime > time + frametime)
            return;

        if (thinktime < time)
            thinktime = time;

        held_time = time;
        self.nextthink = 0;
        time = thinktime;
        self.think();
        time = held_time;

        if (self.is_removed || self.nextthink < thinktime /* no loop on rev */)
            return;
    } while (1);
}

void Pred_Sound(SoundIndex snd, float vol = 1) {
    if (snd == SND_NONE)
        return;

    ASSERTD_GE(snd, SND_FIRST);
    snd -= SND_FIRST;

    entity target = self;
    string wav = snd_types[snd].sound;

    FO_Sound(target, CHAN_WEAPON, wav, vol, ATTN_NORM);
}

void PredProj_Sound(int proj_type, float vol = 1) {
    Pred_Sound(FPP_Get(proj_type)->snd, vol);
}

void Forward_Projectile(int fpp_type, entity projectile);

entity FOProj_Create(int fpp_type) {
    entity prj = spawn();

    prj.fpp.index = fpp_type;
    prj.dimension_seen = DMN_NOFLASH;
#ifdef SSQC
    // World time, not the command clock.  It is paired with expires_at, which
    // is always a world instant, and the blast's delay is the difference: a
    // projectile created inside the command warp took `time` from the chain and
    // the subtraction then cancelled the skew out of the due.  A thrown grenade
    // hit that exactly -- its knock was scheduled on the world clock while its
    // blast fired on the chain, a skew apart.  A held one escaped it only
    // because ExplodePerson runs warped to heat with cmd_real_time cleared, so
    // both sides of the subtraction were world time already.
    prj.created_at = RealTime();
#else
    prj.created_at = time;
#endif
    setmodel(prj, FPP_Get(fpp_type)->model);
    setsize(prj, '0 0 0', '0 0 0');

    return prj;
}

void FOProj_Finalize(entity mis) {
    int fpp_type = mis.fpp.index;
#ifdef SSQC
    // Set here rather than at spawn, where the owner is not attached yet.
    mis.fire_seq = mis.owner.cmd_sequence;

    // Only what can push someone: a nail has no explosion to schedule.
    if (FPP_IsGrenade(fpp_type) || fpp_type == FPP_ROCKET || fpp_type == FPP_INCENDIARY)
        Proj_StampViewers(mis);
#endif
    // We explicitly do not use newmis.  Newmis internally implements a fixed
    // 50m forward of physics handling (equivalent to our projection below)
    // which cannot be nicely unwound or accounted for.ammo_shells
    //
    // For our projectiles we continue to always project by at least 25ms.
    // The remaining 25ms is moved to ping dependent correction.
    if (newmis == mis) {
        PRINT_ONCE("Error: fpp=%d used with newmis\n", (float)fpp_type);
        newmis = __NULL__;
    }
    PredProj_Sound(fpp_type);

    if (FPP_IsGrenade(fpp_type)) {
        FO_GrenInfo* gdesc = FO_GrenDesc(mis.fpp.gren_type);

        setmodel(mis, gdesc->model);
        mis.avelocity = gdesc->avelocity;
        mis.skin = gdesc->skin;
        mis.fpp.gren_type = gdesc->id;
    }

    // After any model updates have occurred
    setsize(mis, '0 0 0', '0 0 0');

    mis.customphysics = FO_CustomPhysics;
    mis.al_proj = 1;
    mis.al_prev_origin = mis.origin;   // after the forward: only real frames count as motion

    Forward_Projectile(mis.fpp.index, mis);
    // Paired with cmd_base, which Proj_StampViewers took at this same instant.
    mis.first_phys_time = mis.phys_time;

    mis.SendEntity = PP_SendEntity;
    mis.SendFlags = FOPP_INIT;
}

// Client-side player movement prediction (pmove): while the client
// advertises it, send the pmove block.  The server's own copy of the player
// is sent to that client non-solid (engine), so there is nothing to hide or
// stage.
void Predict_SyncPmove(float is_player) {
    if (ClientPred_Enabled(self, CSQC_PMOVE) && is_player) {
        self.predict_flags |= PF_POS | PF_PMOVE;
    } else {
        float mask = PF_PMOVE;
        if (!ClientPred_Enabled(self, CSQC_FORCE_POS))
            mask |= PF_POS;
        self.predict_flags &= ~mask;
    }
}
#endif

struct ProjectResult {
    float static_ms;
    float dynamic_ms;
};

ProjectResult Forward_ProjectOffset(int fpp_type, float ping, float gren1 = FALSE) {
    float max_ping_credit = max_rewind_credit_ms(fpp_type);
    float ping_floor = 0;
    float static_credit;

    if (FPP_Get(fpp_type)->fixed_project) {
        static_credit = fixed_newmis_ms(fpp_type);
    } else if (fpp_type == FPP_HANDGRENADE) {
        static_credit = static_newmis_ms(fpp_type);
        // Grenade 1 alone, and only the age past the floor.
        max_ping_credit = gren1 ? GREN1_CREDIT_MAX_MS : 0;
        ping_floor = GREN1_CREDIT_FLOOR_MS;
    } else {
        static_credit = static_newmis_ms(fpp_type);
        max_ping_credit += dynamic_newmis_ms();
    }

    if (IsClownMode(CLOWN_FAST_PROJECTILES) && !FPP_IsGrenade(fpp_type))
        static_credit = 9999;

    // Everything lower than SERVER_FRAME_MS falls into the next frame (and we
    // have no resolution anyway), linearize beyond that.
    float adj_ping = max(ping - SERVER_FRAME_MS - ping_floor, 0);

    ProjectResult result;
    result.static_ms = static_credit;
    result.dynamic_ms = min(adj_ping, max_ping_credit);
    return result;
}

void AugmentGrenadeImpact() {
    if (!FPP_IsGrenade(self.fpp.index) || self.voided ||
        self.fpp.gren_type == GREN_RED)
        return;

    float old_move = self.movetype;

    if (IsClownMode(CLOWN_STICKY_PIPES) && self.fpp.gren_type == GREN_PIPE &&
            other.solid == SOLID_BSP)
        self.movetype = MOVETYPE_NONE;

    if (IsClownMode(CLOWN_STICKY_GRENS) && other.solid == SOLID_SLIDEBOX) {
            self.movetype = MOVETYPE_FOLLOW;
            self.velocity = self.origin - other.origin;
#ifdef SSQC
            self.aiment = other;
            self.SendFlags |= FOPP_POS | FOPP_MOVETYPE;  // Need velocity for
                                                         // offset
#else
            self.aiment_num = other.entnum;
#endif
    }

#ifdef SSQC
    if (other.solid != SOLID_BSP) {
        // Networked (non-csqc) entities don't appear to exist within the
        // client-side CSQC world for our physics simulation.  Until we either
        // (a) migrate them there or (b) find a way to propagate them there, we
        // cheat by sending an update to the client when such a collision
        // occurs.
        self.SendFlags |= FOPP_POS | FOPP_ANGLES;
    }
    if (self.movetype != old_move)
        self.SendFlags |= FOPP_MOVETYPE;
#endif
}

