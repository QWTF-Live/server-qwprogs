// Lag compensation on the engine's own history (fteqw fork).  The server
// logs every player's position after each of their commands, at the
// command's time; a trace with
// MOVE_LAGGEDTIME resolves players at the time last set with setlaggedtime,
// and rewindworld/restoreworld move them there physically for the one thing a
// trace can't cover, radius damage.  Both refuse to place a player across a
// spawn, teleport or disconnect, so there is nothing to mark here.  Only
// origins move; velocity and everything else stay live, so a push applied to
// a rewound player lands on their current flight.  A time after a player's
// newest sample is live.
#define LAGHIST_MAX_DT 0.6   // the engine keeps at least this much history per player

float (string ps_short, string ps_setting, string ps_default) CF_GetSetting;

// A player and a projectile crossing paths within one frame.  The projectile's
// sweep for the frame is tested against where the player stood at its start,
// and the player's next command sweeps against where the projectile ended up:
// both static, and a crossing in between passes both.  From PlayerPostThink,
// after this command's move: pair the player's move with each projectile's
// motion over its last frame and sweep the two against each other, which in
// the projectile's frame of reference is the player's box swept from its
// previous origin shifted by the projectile's motion, to where it is now,
// against the projectile where it is now.  A hit puts the projectile at the
// point along its motion where they met and runs its touch; the player is
// not moved.
void Antilag_CrossCheck(entity p) {
    vector dP = p.origin - p.al_cmd_prev;
    if (dP == '0 0 0' || p.solid != SOLID_SLIDEBOX || p.health <= 0)
        return;

    // The span this command covered, which is what the projectile's motion has
    // to be measured over for the two to be paired at all.
    float t1 = RealTime(), t0 = t1 - input_timelength;

    int count;
    entity* projs = find_list(al_proj, 1, EV_FLOAT, count);
    for (int i = 0; i < count; i++) {
        entity e = projs[i];
        if (e.voided || !e.touch || e.owner == p || e.solid == SOLID_NOT)
            continue;
        // The projectile's motion over *this command's* span, not over its last
        // physics frame.  Those are two different intervals and pairing them
        // was the whole of the granularity: the player's thirteen milliseconds
        // against whatever the projectile happened to cover since it last ran.
        // A missile flies straight, so its position at either end of the
        // command follows from its own clock.
        vector qa, qb;
        if (e.movetype == MOVETYPE_FLYMISSILE && e.velocity != '0 0 0') {
            qa = Proj_OrgAt(e, t0);
            qb = Proj_OrgAt(e, t1);
        } else {
            qa = e.al_prev_origin;
            qb = e.origin;
        }

        if (qa == qb)
            continue;   // did not move: the command's own sweep covered it

        // The same predicate the client runs, on the same interval, out of the
        // same function.  A projectile is a point, so this is exactly what the
        // box trace computed and it needs neither the trace nor moving the
        // projectile to the end of the span and back to satisfy MOVE_OTHERONLY.
        float f;
        if (!Proj_Crosses(qa, qb, p.al_cmd_prev, p.origin, p.mins, p.maxs, &f))
            continue;

        trace_fraction = f;
        vector at = qa + f * (qb - qa);
        rj_trace("S: cross t=%.3f %s f=%.2f proj=%v->%v", time, FPP_Name(e.fpp.index), trace_fraction, e.al_prev_origin, e.origin);
        // The projectile's own clock, so the client's copy of this rocket can be
        // put beside ours at the same instant.  The two came out ten units
        // apart at what should be the same phys time, and from the trace alone
        // there is no telling a position drift from a mapping error.
        rj_trace(" player=%v->%v at=%v pt=%.4f first=%.4f st=%.4f",
                 p.al_cmd_prev, p.origin, at, e.phys_time, e.first_phys_time, e.s_time);
        // Why the step sweep did not get here first.  It runs only for a
        // missile whose flight is rewinding players, and this line firing at
        // all means it did not.
        rj_trace(" mt=%.0f travel=%.0f\n", e.movetype,
                 (float)!!RewindFlagEnabled(REWIND_PROJ_TRAVEL));
        setorigin(e, at);

        entity held_self = self;
        self = e;
        other = p;
        self.touch();
        self = held_self;
    }
}

// `time` may be warped to the command clock inside PlayerPostThink; the
// rewind log and projectile forwarding are on real time.
float RealTime() {
    return cmd_real_time ? cmd_real_time : time;
}

float RewindPlayersExcept(entity except, float farthest_rewind_point) {
    float rewind_max_offset = LAGHIST_MAX_DT;
    farthest_rewind_point = max(farthest_rewind_point,
                                RealTime() - rewind_max_offset);

    // Det was pushed at remote_time(), let's see if we can get there.
    float rewind_to = max(farthest_rewind_point, remote_time());

    // Ignore for LAN pings.
    if (RealTime() - rewind_to < SERVER_FRAME_DT)
        return FALSE;

    rewindworld(rewind_to, except);   // until the caller's restoreworld()
    return TRUE;
}

// tf_config.cmd_time (localinfo cmd_time / cmdt, live, sent to clients): forward
// projectiles fired by a command from the client's own clock stamp on that
// command (engine field cmd_servertime) instead of a ping estimate; the client
// starts its predicted projectile at the same stamp.  Every fire is on the
// command path, including those from before a death the client had not yet
// seen (the ghost replay in client.qc).
void Forward_Projectile(int fpp_type, entity proj) {
    float ping = proj.owner.client_ping;
    if (tf_config.cmd_time && proj.owner.classname == "player" && proj.owner.cmd_stamp_clock > 0) {
        ping = min((RealTime() - proj.owner.cmd_stamp_clock) * 1000,
                   tf_config.max_rewind_ms - 25);
        // Forward_ProjectOffset takes a server frame off whatever it is given,
        // on the basis that a ping is an estimate.  The stamp is exact, and the
        // client anchors its copy on it exactly, so give the frame back: the
        // projectile then starts at the stamp, not a frame after it.
        ping += SERVER_FRAME_MS;
    }

    ProjectResult offset = Forward_ProjectOffset(fpp_type, ping);
    float static_dt = offset.static_ms / 1000.0;
    float dynamic_dt = offset.dynamic_ms / 1000.0;


    float rewind_hit = RewindFlagEnabled(REWIND_PROJ_FIRE) &&
                       !(proj.fpp.flags & FPF_NO_REWIND) &&
                       dynamic_dt > 0;

    float phys_flags = PHYSF_CONSUME_ALL;
    float stime = RealTime();

    // Rewound flight resolves players at each step's time from the engine's
    // history; the shooter stays live, the projectile leaves from where they
    // are now.
    if (rewind_hit) {
        stime -= dynamic_dt;
        phys_flags |= PHYSF_REWIND_PLAYERS | PHYSF_REWIND_EXCLUDE_OWNER;
    }

    // Static projection happens instantly.  If rewind is active, we'll do it at
    // a prior point in time, but we don't advance time while stepping.
    // Before the projection: an impact inside it is deferred to the fire
    // command like any other, with the real damage sent to the client,
    // rather than applied inline with damage the client could only guess.
    proj.s_time = stime;            // the clock after the static projection, as the client sets it
    proj.fire_cmd_time = time;      // command clock inside the warp
    float ft = Phys_Init(proj, stime, static_dt, phys_flags);
    proj.s_origin = proj.origin;

    if (!proj.voided)
        ft += Phys_Advance(proj, RealTime(), phys_flags);

    proj.antilag_ms = ft * 1000;

    {
        rj_trace("S: fire %s t=%.3f own=%s ping=%.0f static=%.0f dyn=%.0f fwd=%.0fms",
                 FPP_Name(fpp_type), RealTime(), proj.owner.classname, ping, offset.static_ms, offset.dynamic_ms, proj.antilag_ms);
        proj.owner.rj_cmd_trace_until = RealTime() + 0.16;
        rj_trace(" cmdt=%.0f ctime=%.3f age=%.0fms seq=%.0f clk=%.4f",
                 tf_config.cmd_time, proj.owner.cmd_servertime, (RealTime() - proj.owner.cmd_servertime) * 1000, proj.owner.cmd_sequence, proj.owner.cmd_clock);
        rj_trace(" cnt=%.4f af=%.4f\n", proj.owner.client_nextthink, proj.owner.attack_finished);
        rj_trace(" sorg=%v porg=%v pvel=%v\n", proj.s_origin, proj.owner.origin, proj.owner.velocity);
    }
}

void Forward_OpenDoors(entity player) {
    if (!RewindFlagEnabled(REWIND_FORWARD_DOORS))
        return;

    vector offset = min(550, vlen(player.velocity)) * normalize(player.velocity);
    offset *= max(player.client_ping, 150) / 1000.0;
    traceline(player.origin, player.origin + offset, MOVE_TRIGGERS, player);

    if (trace_fraction < 1 && trace_ent.solid == SOLID_TRIGGER) {
        entity held_self = self;
        other = player;
        self = trace_ent;
        trace_ent.touch();
        self = held_self;
    }
}

