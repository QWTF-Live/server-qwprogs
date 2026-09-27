// Pusher lag compensation (doors).
//
// The engine (fteqw fork) sends each client every MOVETYPE_PUSH entity advanced
// along its velocity by that client's .pusher_advance, unless the pusher holds
// itself with .pusher_noadvance.  One snapshot position serves every command
// the client re-predicts, and the server has already run the older of those,
// so a pusher may only ever be shown where it is at least as obstructive as it
// will be for any of them: a closing door is advanced to the far end of the
// window (an edge the server lets the player through), an opening door is held
// where it is (doors.qc) and reaches the client a snapshot late, which costs a
// bump on an edge and never a stick.
//
// No predicted start.  There was one: a player whose path would trigger a door
// was sent it already opening, extrapolated to the far end of their window --
// which is the one position that is wrong for every command but the last, and
// walked them into a gap the server had not opened.  It came back in the field
// as doors that looked open and were not.  Its timing was right and its
// position was not, and the position can only be right per command, which is
// a client-side job the snapshot cannot do.
//
// localinfo:
//   pusher_buffer (pb)  ms added to ping, default 25.  Only pushers whose
//                       motion makes them more obstructive are advanced, so
//                       the margin for ping jitter belongs on that side.
//   pusher_max (pm)     ping cap in ms, default 200.
//
// A player standing on a pusher is carried by it on the server; the client's
// replay does the same from PP_SendRides and the ride in the predict state.

// Engine fields (fteqw server/progdefs.h).
.float  pusher_advance;         // players: seconds to report pushers ahead by
.vector pp_vel_pre;             // players: velocity before this command's move
.float  pusher_noadvance;       // pushers: hold the real motion where it is (an opening door)

float pp_buffer, pp_max;
float pp_next_refresh;


static void PP_RefreshSettings() {
    if (time < pp_next_refresh)
        return;
    pp_next_refresh = time + 1;
    pp_buffer = CF_GetSetting("pb", "pusher_buffer", "25");
    pp_max = CF_GetSetting("pm", "pusher_max", "200");
}

// Distance to a brush model has to be measured against its box, not its centre.
// findradius measures to the centre, so a door wide enough to stand at the edge
// of is further away than its own size -- two stops into a fast-opening door
// came back reported as ordinary geometry because of it.
static float PP_BoxNear(entity e, vector p, float r) {
    if (p_x < e.absmin_x - r || p_x > e.absmax_x + r) return FALSE;
    if (p_y < e.absmin_y - r || p_y > e.absmax_y + r) return FALSE;
    if (p_z < e.absmin_z - r || p_z > e.absmax_z + r) return FALSE;
    return TRUE;
}

// Being stopped by a door is hard to catch on purpose, so catch it on its own.
//
// A player brought to a hard stop next to a pusher is the signature: the server
// clips a velocity component the client's copy of that pusher did not, and the
// client runs on past it.  The suspicion is that the advance is symmetric --
// a closing door shown early is harmless because the client stops short, but an
// opening one shown early lets the client through a gap the server has not
// opened yet, which is what "more open feels like a wall" in antilag.md warns
// about.  This reports the numbers that decide it: where the pusher actually
// was, where this player was shown it, and how much speed the stop took.
static void PP_ReportPusherStop() {
    // Two bars.  Near a pusher, anything that stops a player hard is worth a
    // line, because a pusher being within reach of a hard stop is itself rare.
    // Away from one it is not: walking into a wall at 240 costs the whole of
    // it, twice in a two-minute run, correctly predicted both times.  So the
    // no-pusher case only speaks for a loss no ordinary movement reaches --
    // the event worth catching took 1048.
    float lost = vlen(self.pp_vel_pre) - vlen(self.velocity);
    if (lost < 200 || self.pp_vel_pre == '0 0 0')
        return;
    // Any pusher, not only a moving one.  A door that has finished moving is
    // still a problem if the client's copy of it is a snapshot behind: both
    // copies are stationary, in different places, and no amount of advance
    // reasoning applies.  A run with a stop above the threshold and no line at
    // all said this needed widening -- vel on the report says which case it is.
    entity e = nextent(world);
    while (e) {
        if (e.movetype == MOVETYPE_PUSH && PP_BoxNear(e, self.origin, 64)) {
            rj_trace("S: pusher-stop seq=%.0f lost=%.0f org=%v vel=%v -> %v\n",
                     self.cmd_sequence, lost, self.origin, self.pp_vel_pre, self.velocity);
            // shown is what the engine sent this client: advanced unless held.
            rj_trace(" pusher=%s at=%v vel=%v shown=%v held=%.0f adv=%.0fms\n",
                     e.classname, e.origin, e.velocity,
                     e.pusher_noadvance ? e.origin : e.origin + e.velocity * self.pusher_advance,
                     e.pusher_noadvance, self.pusher_advance * 1000);
            self.rj_trace_until = time + 0.4;
            return;
        }
        e = nextent(e);
    }

    // Nothing pusher-shaped nearby: say so, so a stop that is simply world
    // geometry is not mistaken for a missing report.
    if (lost < 600)
        return;

    rj_trace("S: hard-stop seq=%.0f lost=%.0f org=%v vel=%v -> %v og=%.0f\n",
             self.cmd_sequence, lost, self.origin, self.pp_vel_pre, self.velocity,
             (float)!!(self.flags & FL_ONGROUND));
}

// Where the pusher each rider stands on sits in the snapshot about to go out
// to them, for their movement replay to place them on it (PM_Ride*, pmove.qc).
//
// Player physics on the client collides with the snapshot's copy of the
// pusher, one position for every command it replays, so the replay moves the
// rider into the frame where the pusher sits there instead of moving the
// pusher.  That needs the position exactly: short of it the rider stands in
// the pusher, past it they float.  So this is the engine's own arithmetic
// (SV_Snapshot_AdvancePusher), on the same fields at the same moment: EndFrame
// runs after the frame's pusher physics and before the snapshots are built,
// and `time` here is the physicstime they are built at.  Tagged with the
// command the snapshot acknowledges, so the client can tell it belongs.
void PP_SendRides() {
    for (entity p = find(world, classname, "player"); p; p = find(p, classname, "player")) {
        if (!p.ride_ent || !(p.predict_flags & PF_PMOVE))
            continue;
        entity e = edict_num(p.ride_ent);
        if (e.movetype != MOVETYPE_PUSH)
            continue;

        vector at = e.origin;
        float adv = max(0, p.pusher_advance);
        float moving = (e.velocity != '0 0 0' || e.avelocity != '0 0 0') && e.nextthink > e.ltime;
        if (adv > 0 && moving && !e.pusher_noadvance) {
            float end = time + adv;
            float dt = min(end - time, e.nextthink - e.ltime);
            if (dt > 0)
                at = at + e.velocity * dt;
        }

        msg_entity = p;
        WriteByte(MSG_MULTICAST, SVC_CGAMEPACKET);
        WriteByte(MSG_MULTICAST, MSG_PM_RIDE);
        WriteLong(MSG_MULTICAST, p.cmd_sequence);
        WriteShort(MSG_MULTICAST, p.ride_ent);
        WriteCoord(MSG_MULTICAST, at_x);
        WriteCoord(MSG_MULTICAST, at_y);
        WriteCoord(MSG_MULTICAST, at_z);
        multicast('0 0 0', MULTICAST_ONE_NOSPECS);
    }
}

void PP_PlayerPostThink() {
    PP_ReportPusherStop();

    PP_RefreshSettings();

    if (self.playerclass == 0) {
        self.pusher_advance = 0;    // spectators have no commands to compensate
        return;
    }

    // Plus the buffer, not minus.  Only pushers whose motion makes them more
    // obstructive are advanced (doors.qc holds an opening one), so the margin
    // for ping jitter belongs on the obstructive side: a closing door shown a
    // little further along is a phantom edge the server lets the player
    // through, shown a little short it is a gap the server closes.
    self.pusher_advance = max(0, (min(self.client_ping, pp_max) + pp_buffer) / 1000);
}
