// Pusher lag compensation (doors).
//
// The engine (fteqw fork) sends each client every MOVETYPE_PUSH entity advanced
// along its velocity by that client's .pusher_advance, so what the client
// predicts against and shoots at is the door where it will be when the client's
// commands are processed.  That only covers a door that is already moving.  The
// round trip on the trigger itself is hidden here: each frame every player is
// extrapolated along their velocity by their advance, and if that path touches
// a door's trigger field we offer the engine a predicted start
// (.pusher_predict_*).  Clients whose advance window reaches past the predicted
// time are sent the door as if it had already begun to move, so the phantom
// motion joins the real motion seamlessly when the real command lands.
//
// Why the horizon equals the advance: the trace hits at fraction f of a path of
// length advance*speed, so the player reaches the field advance*f after the
// server's view of them.  Their command for that moment lands one-way latency
// later, but the origin the trace started from is itself one-way latency old,
// and the two cancel.  The real door starts at exactly time + f*advance, and a
// client whose window reaches that time is exactly one the engine should be
// sending the phantom to.
//
// Nothing here changes game state.  The engine zeroes pusher_predict_time
// after every frame's snapshots go out, so a prediction is a per-frame offer:
// a player who veers off simply stops offering.
//
// localinfo:
//   pusher_buffer (pb)  ms subtracted from ping, default 25.  Late-biased on
//                       purpose: a door shown slightly less open than reality
//                       is harmless, one shown more open feels like a wall.
//                       Everyone above 25ms feels like 25ms.
//   pusher_max (pm)     ping cap in ms, default 200.
//   pusher_share (ps)   1 (default): every client sees the predicted start
//                       through their own advance.  0: only the player whose
//                       path produced it.
//
// Not predicted: a closing door being re-triggered (the engine reports real
// motion while a pusher moves, so the reversal shows up one RTT late), plats
// (the player stands on them; advancing a plat into a predicted player would
// need a carry step the client's pmove doesn't have), and shootable, keyed or
// button-driven doors, which have no trigger field.

// Engine fields (fteqw server/progdefs.h).
.float  pusher_advance;         // players: seconds to report pushers ahead by
.float  pusher_predict_time;    // pushers: predicted start, per-frame offer
.vector pusher_predict_velocity;
.float  pusher_predict_endtime;
.entity pusher_predict_client;  // world = every client

void () door_trigger_touch;
void () door_use;
void () multi_touch;
float (entity Goal, entity AP) Activated;

float pp_buffer, pp_max, pp_share;
float pp_next_refresh;


static void PP_RefreshSettings() {
    if (time < pp_next_refresh)
        return;
    pp_next_refresh = time + 1;
    pp_buffer = CF_GetSetting("pb", "pusher_buffer", "25");
    pp_max = CF_GetSetting("pm", "pusher_max", "200");
    pp_share = CF_GetSetting("ps", "pusher_share", "1");
}

// Earliest offer of the frame wins.  The earliest real trigger is the one that
// will actually happen, so a later prediction must not overwrite it.
static void PP_Offer(entity door, float start, vector vel, float end, entity who) {
    if (door.pusher_predict_time && start >= door.pusher_predict_time)
        return;
    door.pusher_predict_time = start;
    door.pusher_predict_velocity = vel;
    door.pusher_predict_endtime = end;
    door.pusher_predict_client = who;
}

// door_fire only moves a door that is closed and at rest.  A door at the top
// just has its wait extended, and a moving door is reported by the engine from
// real motion, so neither gets a prediction.
static float PP_DoorClosed(entity master) {
    return master.state == STATE_BOTTOM && master.velocity == '0 0 0';
}

// Mirrors door_trigger_touch, with no side effects.
static float PP_FieldWouldFire(entity trigger, entity pl) {
    if (pl.health <= 0 || pl.playerclass == 0)
        return FALSE;
    if (!Activated(trigger, pl))
        return FALSE;
    return PP_DoorClosed(trigger.owner);
}

// Mirrors multi_touch, with no side effects.  Doors with a targetname have no
// field of their own and are opened by trigger_multiple volumes targeting them.
static float PP_MultiWouldFire(entity trigger, entity pl) {
    if (pl.classname != "player")
        return FALSE;
    if (!Activated(trigger, pl))
        return FALSE;
    if (trigger.movedir != '0 0 0') {
        makevectors(pl.angles);
        if ((v_forward * trigger.movedir) < 0)
            return FALSE;
    }
    return TRUE;
}

// door_fire moves the whole linked set, so offer the plan to each door in the
// master's chain, with the velocity SUB_CalcMove will give it.
static void PP_OfferChain(entity master, float start, entity who) {
    entity e = master;
    vector delta;
    float len, traveltime;
    do {
        delta = e.pos2 - e.origin;
        len = vlen(delta);
        if (len > 0 && e.speed > 0) {
            traveltime = max(len / e.speed, 0.03);
            PP_Offer(e, start, delta * (1 / traveltime), start + traveltime, who);
        }
        e = e.enemy;
    } while (e != master && e != world);
}

// The first closed door a trigger_multiple would open, or world.
static entity PP_MultiFirstDoor(entity trigger) {
    entity t;
    for (t = find(world, targetname, trigger.target); t; t = find(t, targetname, trigger.target))
        if (t.use == door_use && PP_DoorClosed(t.owner))
            return t.owner;
    return world;
}

void PP_PlayerPostThink() {
    float adv, start;
    entity trigger, e, who;

    PP_RefreshSettings();

    if (self.playerclass == 0) {
        self.pusher_advance = 0;    // spectators have no commands to compensate
        return;
    }

    adv = (min(self.client_ping, pp_max) - pp_buffer) / 1000;
    if (adv < 0)
        adv = 0;
    self.pusher_advance = adv;

    if (!adv || self.health <= 0 || self.velocity == '0 0 0')
        return;

    // Where will my commands have taken me by the time they land?
    tracebox(self.origin, self.mins, self.maxs, self.origin + self.velocity * adv, MOVE_TRIGGERS, self);
    trigger = world;
    if (trace_ent.touch == door_trigger_touch || (trace_ent.touch == multi_touch && trace_ent.target != ""))
        trigger = trace_ent;

    if (!trigger)
        return;

    start = time + trace_fraction * adv;
    if (trace_startsolid && trace_ent == trigger)
        start = time;   // already inside the volume: the real touch is happening now
    who = pp_share ? world : self;

    if (trigger.touch == door_trigger_touch) {
        if (!PP_FieldWouldFire(trigger, self))
            return;
        if (start < trigger.attack_finished)
            start = trigger.attack_finished;    // door_trigger_touch's debounce
        PP_OfferChain(trigger.owner, start, who);
    } else {
        if (!PP_MultiWouldFire(trigger, self))
            return;
        if (trigger.nextthink > time && start < trigger.nextthink)
            start = trigger.nextthink;          // still in its wait; fires when it re-arms
        start += trigger.delay;                 // SUB_UseTargets' DelayedUse
        for (e = find(world, targetname, trigger.target); e; e = find(e, targetname, trigger.target))
            if (e.use == door_use && PP_DoorClosed(e.owner))
                PP_OfferChain(e.owner, start, who);
    }
}
