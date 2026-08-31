// Ping corrected `time`: how far back this client's view of the world is.
// Monotonically non-decreasing, which guarantees that for some offset `o`:
//     at t1: remote_time() + o < at t2: remote_time() + o  FOR t2 > t1
// i.e. lag correction can never reorder events that `time` would not.
float remote_time() {
    float adj_ping = max(self.client_ping - SERVER_FRAME_MS, 0);
    float offset = min(adj_ping, tf_config.max_rewind_ms);

    float target = time - offset / 1000.0;
    target = max(target, self.last_remote_time);  // prevent jitter
    self.last_remote_time = target;

    return target;
}

float bounded_remote_time(float dt) {
    return max(time - dt, remote_time());
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

void FO_UpdateClientPing() {
    self.client_ping = infokeyf(self, INFOKEY_P_PING);
}
