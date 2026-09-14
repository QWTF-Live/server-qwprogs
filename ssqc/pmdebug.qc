// Server half of the movement prediction journal.  For each command it runs,
// the server records where the command left the player and what happened to
// them along the way, and sends it to that player, who holds the same record
// from its own prediction and compares.  See csqc/pmdebug.qc.
//
// Off unless a client asks.  It is a per-command message, and the client is the
// only side that knows whether anybody is reading it.

float pm_debug;   // a client has advertised CSQC_PMDEBUG; refreshed per second

// The server half of the trace switch, and the same question the journal's send
// asks: is anybody reading this right now.
float RJ_On() { return pm_debug; }

// Set from wherever the event happens, cleared at the top of each command.
//
// Gated on the same question the send is: whether anybody is reading.  Testing
// only the localinfo meant a journal a client had asked for arrived with its
// event bits and its impulse empty -- a dump reporting no push on a command
// that had one, which reads as a prediction bug rather than a gating slip.
void PMD_Event(entity p, float bit) {
    if (pm_debug)
        p.pmd_events |= bit;
}

// An explosion push, as the server applies it.
void PMD_Knock(entity p, vector impulse, float dmg) {
    if (!pm_debug)
        return;
    p.pmd_events |= PMDE_KNOCK;
    p.pmd_impulse += impulse;
    p.pmd_dmg = dmg;
}

void PMD_BeginCommand(entity p) {
    p.pmd_msec = input_timelength * 1000;   // the step this command is run over
    p.pmd_pre_org = p.origin;   // where the move starts, so a divergence can be
                                // placed before it or inside it
}

// From PlayerPostThink, after everything that command does.
void PMD_EndCommand(entity p) {
    // Sent to whoever asked for it.  This is a message per command per player,
    // so it goes to the clients reading it and to nobody else.
    if (p.classname != "player" || !ClientPred_Enabled(p, CSQC_PMDEBUG))
        return;

    float onground = (p.flags & FL_ONGROUND) ? 1 : 0;
    if (p.pmd_last_onground && !onground)
        p.pmd_events |= PMDE_JUMP;
    if (!p.pmd_last_onground && onground)
        p.pmd_events |= PMDE_LAND;
    if (p.pmd_last_waterlevel != p.waterlevel)
        p.pmd_events |= PMDE_WATER;
    p.pmd_last_onground = onground;
    p.pmd_last_waterlevel = p.waterlevel;

    // Built in the multicast buffer and flushed to the one player, as every
    // other client-game packet here is: the engine frames the packet when the
    // buffer is sent, so writing to MSG_ONE and then flushing the multicast
    // buffer sends an empty packet and desynchronises the client's parse.
    msg_entity = p;
    WriteByte(MSG_MULTICAST, SVC_CGAMEPACKET);
    WriteByte(MSG_MULTICAST, MSG_PMDEBUG);
    WriteFloat(MSG_MULTICAST, p.cmd_sequence);
    WriteCoord(MSG_MULTICAST, p.pmd_pre_org_x);
    WriteCoord(MSG_MULTICAST, p.pmd_pre_org_y);
    WriteCoord(MSG_MULTICAST, p.pmd_pre_org_z);
    WriteCoord(MSG_MULTICAST, p.origin_x);
    WriteCoord(MSG_MULTICAST, p.origin_y);
    WriteCoord(MSG_MULTICAST, p.origin_z);
    WriteCoord(MSG_MULTICAST, p.velocity_x);
    WriteCoord(MSG_MULTICAST, p.velocity_y);
    WriteCoord(MSG_MULTICAST, p.velocity_z);
    WriteByte(MSG_MULTICAST, onground);
    WriteByte(MSG_MULTICAST, p.waterlevel);
    WriteFloat(MSG_MULTICAST, p.pmd_events);
    WriteCoord(MSG_MULTICAST, p.pmd_impulse_x);
    WriteCoord(MSG_MULTICAST, p.pmd_impulse_y);
    WriteCoord(MSG_MULTICAST, p.pmd_impulse_z);
    WriteFloat(MSG_MULTICAST, p.pmd_dmg);
    WriteFloat(MSG_MULTICAST, p.spawn_gen);
    WriteFloat(MSG_MULTICAST, p.pmd_msec);
    multicast('0 0 0', MULTICAST_ONE);

    // Cleared here rather than at the start of the next command: a fuse fires
    // in the physics phase, between the two, and clearing on the way in threw
    // away the one event whose cause we most wanted to read.  Whatever lands
    // between commands is reported with the command whose state first shows
    // it, which is where its velocity turns up anyway.
    p.pmd_events = 0;
    p.pmd_impulse = '0 0 0';
    p.pmd_dmg = 0;
}
