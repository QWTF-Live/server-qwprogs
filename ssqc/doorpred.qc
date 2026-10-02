// Door prediction, server side (share/doorpred.qc has the why).
//
// A door the client can run itself gets a companion that streams its motion to
// clients predicting doors (CSQC_DOOR_PRED), and stops being sent to them as an
// engine entity.  Everyone else -- engine prediction, demos -- gets the door as
// before.
//
// Which doors: ones a touch opens.  A door with a trigger field of its own, not
// toggled, keyed, shot or targeted, so the field and the state are the whole
// story.  And one nobody stands on: the client's own player physics no longer
// has the door in it, and the door is only collided with from the side
// (DoorPred_Clip), so a door that is also a floor stays an engine entity.

.entity dn_net;         // a door: its companion
.entity dn_door;        // a companion: its door
.vector dn_legfrom;     // a door: where the leg it is on started

// Could a player stand on the door's top face with the door at `at`?
static float DoorNet_Standable(entity d, vector at) {
    vector p = at + (d.mins + d.maxs) * 0.5;
    p_z = at_z + d.maxs_z + 25;     // feet (hull mins_z -24) a unit above the top
    tracebox(p, VEC_HULL_MIN, VEC_HULL_MAX, p, MOVE_NOMONSTERS, d);
    return !trace_startsolid && !trace_allsolid;
}

static float DoorNet_Eligible(entity d) {
    entity m = d.owner;
    if (!m || !m.trigger_field)
        return FALSE;   // a button, a key, damage, or a target opens it
    if ((m.spawnflags & 32) || d.health || d.items || m.items || d.speed <= 0)
        return FALSE;
    if (DoorNet_Standable(d, d.pos1) || DoorNet_Standable(d, d.pos2))
        return FALSE;
    return TRUE;
}

// Asked for, and the movement replay that does the colliding is running: it
// is switched on from the same userinfo, and only for a player.
float DoorNet_Wanted(entity pl) {
    return pl.classname == "player" && ClientPred_Enabled(pl, CSQC_DOOR_PRED) &&
           (pl.predict_flags & PF_PMOVE);
}

// The engine copy, for everyone but a client drawing and colliding with its own.
// A demo is built with other == world, and keeps it.
float DoorNet_Customize() {
    return !DoorNet_Wanted(other);
}

// The motion as of now: SendEntity runs as the snapshot is built, after the
// frame's pusher physics, so `time` is the frame the door's origin belongs to.
static void DoorNet_Capture(entity n, entity d, entity viewer) {
    entity f = d.owner.trigger_field;

    n.dn_modelindex = d.modelindex;
    n.dn_doornum = num_for_edict(d);
    n.dn_pos1 = d.pos1;
    n.dn_pos2 = d.pos2;
    n.dn_speed = d.speed;
    n.dn_wait = d.wait;
    n.dn_bmin = d.mins;
    n.dn_bmax = d.maxs;
    n.dn_fmin = f.absmin;
    n.dn_fmax = f.absmax;

    n.dn_tref = time;
    n.dn_state = d.state;
    n.dn_org = d.origin;
    float speed = vlen(d.velocity);
    if (speed > 0 && d.think == SUB_CalcMoveDone && d.nextthink > d.ltime) {
        n.dn_from = d.dn_legfrom;
        n.dn_dest = d.finaldest;
        n.dn_rem = d.nextthink - d.ltime;
        n.dn_elapsed = vlen(d.origin - d.dn_legfrom) / speed;
    } else {
        n.dn_from = n.dn_dest = d.origin;
        n.dn_rem = n.dn_elapsed = 0;
    }
    n.dn_close = 0;
    if (d.state == STATE_TOP && d.think == door_go_down && d.nextthink > d.ltime)
        n.dn_close = time + d.nextthink - d.ltime;
    n.dn_fieldready = f.attack_finished;

    n.dn_fires = viewer.playerclass && Activated(f, viewer);
}

float DoorNet_Send(entity viewer, float sf) {
    if (!DoorNet_Wanted(viewer))
        return FALSE;   // and removed from a client that stopped asking
    DoorNet_Capture(self, self.dn_door, viewer);
    return DoorNet_Write(sf);
}

// doors.qc, on every change of leg or schedule, with self the door.
void DoorNet_Changed() {
    if (self.dn_net)
        self.dn_net.SendFlags |= DN_MOTION;
}

// doors.qc, as a leg starts: what DoorNet_Capture measures the leg from.
void DoorNet_LegStart() {
    self.dn_legfrom = self.origin;
    DoorNet_Changed();
}

void DoorNet_Frame() {
    static float inited, next_refresh;

    if (!inited) {
        if (time < 2)
            return;     // LinkDoors runs off each door's first think
        inited = TRUE;
        float n = 0, all = 0;
        for (entity d = find(world, classname, "door"); d; d = find(d, classname, "door")) {
            all++;
            if (!DoorNet_Eligible(d))
                continue;
            entity c = spawn();
            c.classname = "door_net";
            c.dn_door = d;
            c.SendEntity = DoorNet_Send;
            c.SendFlags = DN_ALL;
            c.pvsflags = PVSF_IGNOREPVS;    // few, small, and needed before they are in view
            // Seen in every dimension.  A flash takes DMN_NOFLASH out of what a
            // player sees, and a companion that went with it would take the door
            // out of their collision too, the engine copy being withheld.
            c.dimension_seen = 16777215;
            d.dn_net = c;
            // Deprecated for drawing per client, which CSQC does better; this
            // is what keeps the engine copy from a client that has the CSQC one.
#pragma warning disable F326
            d.customizeentityforclient = DoorNet_Customize;
#pragma warning enable F326
            n++;
        }
        dprint(sprintf("doorpred: %d of %d doors predicted\n", n, all));
    }

    // Whether a touch fires a field depends on the viewer's team, class and
    // items, and the motion on anything that moved a door without a leg change
    // (a block): refresh both rather than chase every cause.
    if (time >= next_refresh) {
        next_refresh = time + 1;
        for (entity c = find(world, classname, "door_net"); c; c = find(c, classname, "door_net"))
            c.SendFlags |= DN_MOTION | DN_FIRES;
    }
}
