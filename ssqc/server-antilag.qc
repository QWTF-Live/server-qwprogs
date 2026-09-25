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
// Not covered: plats (the player stands on them; advancing a plat into a
// predicted player would need a carry step the client's pmove doesn't have).

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
