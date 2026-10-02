// Door prediction: the server's door motion, sent to the client as a schedule.
//
// Player physics on the client collides every command it replays with the one
// copy of a door in the newest snapshot (CL_SetSolidEntities reads only
// cl.validsequence), so no single position the server picks is right for more
// than one of them, and a door is a round trip late to start opening on top of
// that.  A client that predicts doors itself is sent no engine copy of the door
// at all (DoorNet_Customize, ssqc/doorpred.qc) and this instead: where the door
// is, the leg it is on, and when it will close, enough to place it at any
// command's time.  The client collides each command with the door at that
// command's time, starts the door itself on the command its own touch fires it,
// and draws the door where the newest command meets it (csqc/doorpred.qc).
//
// One companion entity per door, not the door itself: an entity with a
// SendEntity reaches every CSQC client only through it, which would take the
// engine copy away from the clients still predicting with the engine.

enumflags {
    DN_STATIC,  // model, bounds, travel, the trigger field
    DN_MOTION,  // where it is and the leg it is on, at a server time
    DN_FIRES,   // whether this client's touch opens it (Activated, per viewer)
};
const float DN_ALL = DN_STATIC | DN_MOTION | DN_FIRES;

.float dn_modelindex;
.float dn_doornum;              // the door's own entity number
.vector dn_pos1, dn_pos2;       // closed and open
.float dn_speed, dn_wait;
.vector dn_bmin, dn_bmax;       // the door's bounds about its origin
.vector dn_fmin, dn_fmax;       // the trigger field, absolute and as linked (grown a unit)

.float dn_tref;                 // server time the motion state holds at
.float dn_state;                // STATE_*
.vector dn_org;                 // where the door is at dn_tref
.vector dn_from, dn_dest;       // the leg it is on: start and end
.float dn_elapsed, dn_rem;      // seconds of the leg run and left at dn_tref
.float dn_close;                // a door at the top: server time it starts down, 0 if never
.float dn_fieldready;           // server time the field will fire again (its debounce)

.float dn_fires;                // this client's touch opens it

// A pusher's think runs at the end of the frame its own clock reaches it in,
// and the move that think starts begins with the next frame: a scheduled start
// lands on the first whole frame at or after it, counted from a time that is
// itself a frame.  Measured: a close predicted on the schedule itself ran a
// frame ahead of the server's, 2.6 units on a 200 u/s door.
float DoorNet_OnFrame(float from, float dt) {
    return from + ceil(dt / SERVER_FRAME_DT - 0.001) * SERVER_FRAME_DT;
}

// The close from the top that the state implies: scheduled, or the wait that
// door_hit_top will set when a leg up arrives.
float DoorNet_CloseAt(entity d) {
    if (d.dn_state == STATE_TOP)
        return d.dn_close ? DoorNet_OnFrame(d.dn_tref, d.dn_close - d.dn_tref) : 0;
    if (d.dn_state == STATE_UP && d.dn_wait >= 0)
        return DoorNet_OnFrame(d.dn_tref, d.dn_rem + d.dn_wait);
    return 0;
}

// dt seconds into a close from the top.  SUB_CalcMove's speed, and its floor.
vector DoorNet_Closing(entity d, float dt) {
    float travel = max(vlen(d.dn_pos1 - d.dn_pos2) / d.dn_speed, 0.03);
    return d.dn_pos2 + (d.dn_pos1 - d.dn_pos2) * bound(0, dt / travel, 1);
}

// Where the server's own motion has the door at server time t, given the close
// from the top at close_at (0: none).  The leg is run forward or back from the
// reference and stops at its ends.
vector DoorNet_ServerPos(entity d, float t, float close_at) {
    if (close_at && t > close_at)
        return DoorNet_Closing(d, t - close_at);
    float leg = d.dn_elapsed + d.dn_rem;
    if (leg <= 0)
        return d.dn_org;
    float f = bound(0, (d.dn_elapsed + t - d.dn_tref) / leg, 1);
    return d.dn_from + (d.dn_dest - d.dn_from) * f;
}

// What door_go_up would find at server time t, from the same state.  Before
// the leg in hand began, the door was where that leg started from.
float DoorNet_ServerPhase(entity d, float t, float close_at) {
    if (close_at && t > close_at) {
        float travel = max(vlen(d.dn_pos1 - d.dn_pos2) / d.dn_speed, 0.03);
        return t < close_at + travel ? STATE_DOWN : STATE_BOTTOM;
    }
    float start = d.dn_tref - d.dn_elapsed, end = d.dn_tref + d.dn_rem;
    if (d.dn_state == STATE_UP) {
        if (t < start)
            return STATE_BOTTOM;
        return t < end ? STATE_UP : STATE_TOP;
    }
    if (d.dn_state == STATE_DOWN) {
        if (t < start)
            return STATE_TOP;
        return t < end ? STATE_DOWN : STATE_BOTTOM;
    }
    return d.dn_state;
}

// One body for both directions, as the predict state and projectiles are.
#ifdef SSQC
#define DCOMM(_type, _field) Write##_type(MSG_ENTITY, self.##_field)
#define DCOMMV(_field) WriteVector(MSG_ENTITY, self.##_field)
float DoorNet_Write(float sf) {
    sf &= DN_ALL;
    WriteByte(MSG_ENTITY, ENT_DOOR);
    WriteByte(MSG_ENTITY, sf);
#else
#define DCOMM(_type, _field) self.##_field = Read##_type()
#define DCOMMV(_field) self.##_field = ReadVector(0, '0 0 0')
void DoorPred_Updated(entity d, float isnew, float sf);
void EntUpdate_Door(float isnew) {
    float sf = ReadByte();
#endif
    if (sf & DN_STATIC) {
        DCOMM(Short, dn_modelindex);
        DCOMM(Short, dn_doornum);
        DCOMMV(dn_pos1);
        DCOMMV(dn_pos2);
        DCOMM(Float, dn_speed);
        DCOMM(Float, dn_wait);
        DCOMMV(dn_bmin);
        DCOMMV(dn_bmax);
        DCOMMV(dn_fmin);
        DCOMMV(dn_fmax);
    }
    if (sf & DN_MOTION) {
        DCOMM(Float, dn_tref);
        DCOMM(Byte, dn_state);
        DCOMMV(dn_org);
        DCOMMV(dn_from);
        DCOMMV(dn_dest);
        DCOMM(Float, dn_elapsed);
        DCOMM(Float, dn_rem);
        DCOMM(Float, dn_close);
        DCOMM(Float, dn_fieldready);
    }
    if (sf & DN_FIRES)
        DCOMM(Byte, dn_fires);
#ifdef SSQC
    return TRUE;
}
#else
    DoorPred_Updated(self, isnew, sf);
}
#endif
#undef DCOMM
#undef DCOMMV
