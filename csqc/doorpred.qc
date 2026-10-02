// Door prediction, client side (share/doorpred.qc has the why).
//
// A door the server streams to us is ours to collide with, start and draw: the
// engine copy is not sent, so neither player physics nor the renderer has it.
//
//  - Each replayed command meets the door where the door is at that command's
//    time (DoorPred_Clip), which is what the server's command does.
//  - A command whose sweep touches the door's field starts it opening at that
//    command's time (DoorPred_Touch), as the server will when the command
//    arrives -- so the door starts where it does at no ping, not a round trip
//    later.  The server's motion replaces ours when it arrives.
//  - The door is drawn where the view's command meets it (DoorPred_AddToScene),
//    so what is seen is what is collided with.
//  - Everything else that traces -- predicted rockets and grenades, the build
//    preview, the sniper's sight -- meets it there too, as a solid brush, the
//    way it met the engine copy (World_ClipToNetwork).  Except the clip's own
//    slide, which has already put the door at its command's time.

// -1 follows pmove: on whenever the movement replay runs.  0 off.
DEFCVAR_FLOAT(pm_doors, -1);
// 1: the clip and touch events, and per acknowledged command near a door the
// prediction's error.  2 adds every moving door's drawn position each frame.
DEFCVAR_FLOAT(pm_doorsdebug, 0);

float PM_DoorPred() { return CVARF(pm_doors) != 0; }

const float DP_MAX = 128;
static entity dp_door[DP_MAX];
float dp_count;
.float dp_slot;     // 1 + its index in dp_door

// What this replay's own touches have done to each door.  The running copy;
// pmove.qc keeps one per saved state (PMS_Data), as it does a nudge's fired
// flag: a replay resumed from a cached state continues that state's lineage,
// and one from the snapshot starts clean because the server's motion already
// holds everything before it.
float dp_pred_t[DP_MAX];        // server time our touch started it up, 0 none
float dp_pred_close[DP_MAX];    // server time our touch at the top put its close back to
float dp_pred_ready[DP_MAX];    // server time the field fires again after our touch

float dp_view_cmd;              // command clock the view is drawn at (pmove.qc)

static const float DP_EPS = 0.03125;    // DIST_EPSILON: how far short of a plane a player trace stops

// The dimension the doors are solid in.  Every entity hits all of them by
// default (255); the clip's slide takes this one out of what it hits.  1 is
// what the engine's networked entities count as, so not that.
static const float DP_DIM = 2;

void DoorPred_Removed() {
    if (self.dp_slot) {
        dp_door[self.dp_slot - 1] = world;
        dp_count--;
    }
}

void DoorPred_Updated(entity d, float isnew, float sf) {
    if (!d.dp_slot) {
        float i;
        for (i = 0; i < DP_MAX; i++)
            if (!dp_door[i])
                break;
        if (i == DP_MAX) {
            // The engine copy is not coming either, so this door would be
            // missing outright.  Say so loudly; the cap is far above any map.
            PRINT_ONCE("doorpred: more than %d doors, some are missing\n", DP_MAX);
            return;
        }
        dp_door[i] = d;
        d.dp_slot = i + 1;
        dp_count++;
        dp_pred_t[i] = dp_pred_close[i] = dp_pred_ready[i] = 0;
        d.classname = "door_pred";
        d.solid = SOLID_BSP;
        d.movetype = MOVETYPE_NONE;    // moved by us, not by physics_mode 2
        d.dimension_solid = DP_DIM;
        d.drawmask = 0;     // drawn by DoorPred_AddToScene, after the replay
        d.removefunc = DoorPred_Removed;
        if (CVARF(pm_doorsdebug))
            printf("doorpred: door %.0f predicted (slot %.0f)\n", d.dn_doornum, i);
    }
    if (sf & DN_STATIC)
        setmodelindex(d, d.dn_modelindex);
    if (isnew)
        setorigin(d, d.dn_org);     // solid where the server has it until first drawn
}

void DoorPred_ResetPredicted() {
    for (float i = 0; i < DP_MAX; i++)
        dp_pred_t[i] = dp_pred_close[i] = dp_pred_ready[i] = 0;
}

static float DoorPred_CloseAt(float i, entity d) {
    float c = DoorNet_CloseAt(d);
    if (c && dp_pred_close[i] > c)
        c = dp_pred_close[i];
    return c;
}

// The leg our own touch started: where from, how long it takes, and when the
// door it opened will start back down.
static void DoorPred_Leg(float i, entity d, __out vector start, __out float travel, __out float close) {
    float pt = dp_pred_t[i];
    start = DoorNet_ServerPos(d, pt, DoorPred_CloseAt(i, d));
    travel = max(vlen(d.dn_pos2 - start) / d.dn_speed, 0.03);
    close = d.dn_wait >= 0 ? DoorNet_OnFrame(pt, travel + d.dn_wait) : 0;
    if (close && dp_pred_close[i] > close)
        close = dp_pred_close[i];
}

// Where the door is at server time t, our own touches included.
vector DoorPred_Pos(float i, entity d, float t) {
    float pt = dp_pred_t[i];
    if (!pt || t < pt)
        return DoorNet_ServerPos(d, t, DoorPred_CloseAt(i, d));

    vector start;
    float travel, close;
    DoorPred_Leg(i, d, start, travel, close);
    if (t < pt + travel)
        return start + (d.dn_pos2 - start) * ((t - pt) / travel);
    if (close && t > close)
        return DoorNet_Closing(d, t - close);
    return d.dn_pos2;
}

static float DoorPred_Phase(float i, entity d, float t) {
    float pt = dp_pred_t[i];
    if (!pt || t < pt)
        return DoorNet_ServerPhase(d, t, DoorPred_CloseAt(i, d));

    vector start;
    float travel, close;
    DoorPred_Leg(i, d, start, travel, close);
    if (t < pt + travel)
        return STATE_UP;
    if (close && t > close) {
        float down = max(vlen(d.dn_pos1 - d.dn_pos2) / d.dn_speed, 0.03);
        return t < close + down ? STATE_DOWN : STATE_BOTTOM;
    }
    return STATE_TOP;
}

// A field is touched the way a pad is: entering, crossing or staying in it.
float PM_SegHitsBox(vector a, vector b, vector lo, vector hi);   // pmove.qc

// The segment a -> b against the box [lo, hi] (the door grown by the player's
// box and by DP_EPS): the fraction it enters at and that face's outward normal.
// Resting on the face -- where the last command's clip left us -- enters at 0.
// FALSE if it misses, or starts inside: the door moved into us, and the server
// pushes us or is blocked by us, which is left to it.
static float DP_Sweep(vector a, vector b, vector lo, vector hi, __out float frac, __out vector norm) {
    vector d = b - a;
    float tmin = -1000000, tmax = 1000000, best = -1, sgn = 0;

    for (float axis = 0; axis < 3; axis++) {
        float da = axis == 0 ? d_x : (axis == 1 ? d_y : d_z);
        float aa = axis == 0 ? a_x : (axis == 1 ? a_y : a_z);
        float la = axis == 0 ? lo_x : (axis == 1 ? lo_y : lo_z);
        float ha = axis == 0 ? hi_x : (axis == 1 ? hi_y : hi_z);

        if (fabs(da) < 0.000001) {
            if (aa < la || aa > ha)
                return FALSE;
            continue;
        }
        float t1 = (la - aa) / da, t2 = (ha - aa) / da, s = -1;
        if (t1 > t2) { float t = t1; t1 = t2; t2 = t; s = 1; }
        if (t1 > tmin) { tmin = t1; best = axis; sgn = s; }
        if (t2 < tmax) tmax = t2;
        if (tmin > tmax)
            return FALSE;
    }
    if (best < 0 || tmin >= 1 || tmax <= 0)
        return FALSE;
    if (tmin < 0) {
        // Behind the entry face: by float noise when resting on it, or really
        // inside.
        float da = best == 0 ? d_x : (best == 1 ? d_y : d_z);
        if (-tmin * fabs(da) > DP_EPS)
            return FALSE;
        tmin = 0;
    }
    frac = tmin;
    norm = best == 0 ? '1 0 0' : (best == 1 ? '0 1 0' : '0 0 1');
    norm *= sgn;
    return TRUE;
}

float dp_debug_seq;     // the command the debug lines are about, 0 for none
float dp_debug_last;    // newest command they have been about

// A command's move, from `from` to where player physics left it, against every
// door at server time t.  Player physics never had the doors, so this is the
// whole of the collision: stop on the face, slide the rest of the move along
// it as the engine's slide move would, and take the speed into it away.
void DoorPred_Clip(entity ent, vector from, float t) {
    vector to = ent.origin;
    if (to == from)
        return;
    vector grow = '1 1 1' * DP_EPS;
    for (float i = 0; i < DP_MAX; i++) {
        entity d = dp_door[i];
        if (!d)
            continue;
        vector o = DoorPred_Pos(i, d, t);
        vector lo = o + d.dn_bmin - ent.maxs - grow;
        vector hi = o + d.dn_bmax - ent.mins + grow;
        float frac;
        vector n;
        if (!DP_Sweep(from, to, lo, hi, frac, n))
            continue;
        vector hit = from + (to - from) * frac;
        vector rest = to - hit;
        rest -= n * (rest * n);
        // Not against the doors: they are solid where they are drawn, and this
        // command meets them where they are at its own time, here.
        float dh = ent.dimension_hit;
        ent.dimension_hit = dh - (dh & DP_DIM);
        tracebox(hit, ent.mins, ent.maxs, hit + rest, MOVE_NOMONSTERS, ent);
        ent.dimension_hit = dh;
        to = trace_endpos;
        float into = ent.velocity * n;
        if (into < 0)
            ent.velocity -= n * into;
        if (CVARF(pm_doorsdebug) && dp_debug_seq)
            printf("DPC seq=%.0f t=%.4f door=%.0f doorz=%.2f frac=%.3f n=%v to=%v\n",
                   dp_debug_seq, t, d.dn_doornum, o_z, frac, n, to);
    }
    ent.origin = to;
}

// The command swept from `from` to where it ended, at server time t: does it
// fire a door's field, and what does that do to the door?  door_trigger_touch
// and door_go_up, with the field's one-second debounce.
void DoorPred_Touch(entity ent, vector from, float t) {
    const vector margin = '1 1 1';  // the engine grows both boxes a unit when linking
    for (float i = 0; i < DP_MAX; i++) {
        entity d = dp_door[i];
        if (!d || !d.dn_fires)
            continue;
        vector lo = d.dn_fmin - ent.maxs - margin;
        vector hi = d.dn_fmax - ent.mins + margin;
        if (!PM_SegHitsBox(from, ent.origin, lo, hi))
            continue;
        if (t < max(d.dn_fieldready, dp_pred_ready[i]))
            continue;
        dp_pred_ready[i] = t + 1;
        float ph = DoorPred_Phase(i, d, t);
        if (ph == STATE_BOTTOM || ph == STATE_DOWN) {
            if (!dp_pred_t[i]) {
                dp_pred_t[i] = t;
                if (CVARF(pm_doorsdebug) && dp_debug_seq)
                    printf("DPT seq=%.0f t=%.4f door=%.0f opens from %v\n",
                           dp_debug_seq, t, d.dn_doornum, DoorPred_Pos(i, d, t));
            }
        } else if (ph == STATE_TOP && d.dn_wait >= 0) {
            float later = DoorNet_OnFrame(t, d.dn_wait);
            if (later > dp_pred_close[i])
                dp_pred_close[i] = later;
        }
    }
}

float DoorPred_Active() {
    return dp_count > 0;
}

// Debug: what was shown for each command, to hold against the server's copy
// when it is acknowledged.  The first prediction of it, made as it was the
// newest: that is the one on screen, a round trip ahead of the server.  A later
// replay starts nearer to it and has less to get wrong.
static vector dp_shown[64];
static float dp_shown_seq[64];

void DoorPred_DebugShown(float seq, vector org) {
    if (dp_shown_seq[seq & 63] == seq)
        return;
    dp_shown[seq & 63] = org;
    dp_shown_seq[seq & 63] = seq;
}

static float DoorPred_Near(vector p, float r) {
    for (float i = 0; i < DP_MAX; i++) {
        entity d = dp_door[i];
        if (!d)
            continue;
        vector lo = d.dn_org + d.dn_bmin, hi = d.dn_org + d.dn_bmax;
        if (p_x > lo_x - r && p_x < hi_x + r && p_y > lo_y - r && p_y < hi_y + r &&
            p_z > lo_z - r && p_z < hi_z + r)
            return TRUE;
    }
    return FALSE;
}

void DoorPred_DebugAck(float seq, vector server_org, float server_t) {
    if (!CVARF(pm_doorsdebug) || !dp_count || dp_shown_seq[seq & 63] != seq)
        return;
    if (!DoorPred_Near(server_org, 160))
        return;
    vector e = dp_shown[seq & 63] - server_org;
    printf("DPE seq=%.0f st=%.4f err=%.2f %v sv=%v\n", seq, server_t, vlen(e), e, server_org);
}

void DoorPred_AddToScene() {
    if (!dp_count)
        return;
    float t = time;
    if (PM_Enabled() && game_state.is_alive)
        t = dp_view_cmd - pstate_server.pmove.cmd_clock_skew;
    float dbg = CVARF(pm_doorsdebug) > 1;
    for (float i = 0; i < DP_MAX; i++) {
        entity d = dp_door[i];
        if (!d)
            continue;
        vector o = DoorPred_Pos(i, d, t);
        setorigin(d, o);
        addentity(d);
        if (dbg && (o != d.dn_pos1 || dp_pred_t[i]))
            printf("DPV t=%.4f door=%.0f z=%.2f pred=%.4f\n", t, d.dn_doornum, o_z, dp_pred_t[i]);
    }
}
