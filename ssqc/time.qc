// How old the command being run is, as a ping in milliseconds: from the
// client's own stamp on it (cmd_stamp_clock) where it has one, which is exact
// for this command, and otherwise the engine's ping -- an average over the last
// 64 packets, and a builtin to read.  The stamp's age gets a server frame added,
// the frame a ping is taken to overstate by and remote_time takes back off, so
// the two read alike.
float CmdPing(entity p) {
    if (tf_config.cmd_time && p.classname == "player" && p.cmd_stamp_clock > 0)
        return ((cmd_real_time ? cmd_real_time : time) - p.cmd_stamp_clock) * 1000
               + SERVER_FRAME_MS;
    return infokeyf(p, INFOKEY_P_PING);
}

// Lag corrected `time`: how far back this client's view of the world is.
// Monotonically non-decreasing, which guarantees that for some offset `o`:
//     at t1: remote_time() + o < at t2: remote_time() + o  FOR t2 > t1
// i.e. lag correction can never reorder events that `time` would not.
float remote_time() {
    float adj_ping = max(CmdPing(self) - SERVER_FRAME_MS, 0);
    float offset = min(adj_ping, tf_config.max_rewind_ms);

    float target = (cmd_real_time ? cmd_real_time : time) - offset / 1000.0;
    target = max(target, self.last_remote_time);  // prevent jitter
    self.last_remote_time = target;

    return target;
}

// Runs the pending client-time think, warping `time` to the instant the think
// was scheduled for -- exactly what the engine's SV_RunThink does before
// dispatching .think.  Anything scheduled from inside the think therefore
// lands on an exact time rather than a frame boundary, which is what lets
// CSQC arrive at the same answer when it replays the same animation frame.
void FO_CheckClientThink() {
    if (self.client_nextthink > 0 && time >= self.client_nextthink) {
        float held_time = time;

        time = self.client_nextthink;
        self.client_nextthink = 0;
        self.client_think();

        time = held_time;
    }
}
