// Client half of the movement prediction journal.
//
// While predicting, the client records what each input frame did: the inputs
// it ran, where they left it, and what happened along the way.  The server
// records the same for the command with that sequence and sends it back
// (localinfo pm_debug).  When one arrives the two are lined up and anything
// that disagrees is reported with both sides' events, so a mispredict can be
// read off rather than guessed at.
//
// fopmd_debug 1 reports divergences, 2 reports every matched frame.

DEFCVAR_FLOAT(fopmd_debug, 1);
DEFCVAR_FLOAT(fopmd_poserr, 1);    // units of position before a frame counts
DEFCVAR_FLOAT(fopmd_velerr, 8);    // units/sec of velocity before a frame counts
DEFCVAR_FLOAT(fopmd_context, 6);   // frames of run-up printed with a divergence
// A velocity difference in the air is never corrected by anything: once the two
// sides disagree they stay that way, so a steady error says only that something
// went wrong earlier.  These catch the frame it went wrong on, by watching how
// much the difference itself moved rather than how big it is.
DEFCVAR_FLOAT(fopmd_posstep, 0.05);
DEFCVAR_FLOAT(fopmd_velstep, 0.5);

static const float PMD_NJOURNAL = 64;

struct PMD_Entry {
    float used;   // a zeroed entry would otherwise answer for sequence 0
    float seq;
    vector org, vel;
    float onground, waterlevel;
    float buttons, msec;
    vector move;
    float events;
    vector impulse;      // velocity the events added this frame
    float dmg;           // the damage behind it
    float spawn_gen;     // which life this frame belongs to
    // filled in when the server's record for this sequence arrives
    float matched, bad, sv_dpos, sv_dvel, sv_events;
};

static PMD_Entry pmd_journal[PMD_NJOURNAL];
static float pmd_events;        // accumulating for the frame being predicted
static vector pmd_impulse;
static float pmd_dmg;
// The error pass replays the same frames from older states, with nudges that
// have since expired, purely to measure itself.  Those runs must not land in
// the journal or they overwrite the prediction that was actually shown.
float pmd_norecord;

// Totals since the last reset, and the worst frame seen.
static float pmd_matched, pmd_bad, pmd_worstpos, pmd_worstvel, pmd_worstseq;
static const float PMD_NEVENT = 16;   // room for every PMDE_ bit
static float pmd_cause[PMD_NEVENT];      // bad frames carrying each server event bit
static float pmd_saw[PMD_NEVENT];        // every frame carrying it, so a clean run can
                                // still show what it exercised
static float pmd_causeless;     // bad frames the server blamed on nothing
static float pmd_seen;          // said so once, when the first record matched
// The steady state, which is what most frames are: the small differences that
// never trip a threshold but decide things like which frame a landing falls on.
static float pmd_sumpos, pmd_maxpos, pmd_sumvel, pmd_maxvel;
static float pmd_stepdiff, pmd_summsec, pmd_maxmsec;

string PMD_EventNames(float bits) {
    string s = "";
    if (bits & PMDE_JUMP)     s = strcat(s, "jump ");
    if (bits & PMDE_LAND)     s = strcat(s, "land ");
    if (bits & PMDE_WATER)    s = strcat(s, "water ");
    if (bits & PMDE_KNOCK)    s = strcat(s, "knock ");
    if (bits & PMDE_DAMAGE)   s = strcat(s, "damage ");
    if (bits & PMDE_TELEPORT) s = strcat(s, "teleport ");
    if (bits & PMDE_CONC)     s = strcat(s, "conc ");
    if (bits & PMDE_SPEED)    s = strcat(s, "speed ");
    if (bits & PMDE_PUSH)     s = strcat(s, "push ");
    return s == "" ? "-" : s;
}

// From the prediction, as each frame is run.
void PMD_Event(float bit) {
    pmd_events |= bit;
}

// An explosion push, as the prediction applies it.
void PMD_Knock(vector impulse, float dmg) {
    pmd_events |= PMDE_KNOCK;
    pmd_impulse += impulse;
    pmd_dmg = dmg;
}

void PMD_Record(float seq, vector org, vector vel, float onground, float waterlevel) {
    if (pmd_norecord) {
        pmd_events = 0;
        pmd_impulse = '0 0 0';
        pmd_dmg = 0;
        return;
    }
    // The state transitions are read back off the previous frame rather than
    // reported as they happen: they are detected once per client frame, well
    // after the frames they belong to have been replayed.
    PMD_Entry* prev = &pmd_journal[(seq - 1 + PMD_NJOURNAL) % PMD_NJOURNAL];
    if (prev->used && prev->seq == seq - 1) {
        if (prev->onground && !onground)
            pmd_events |= PMDE_JUMP;
        if (!prev->onground && onground)
            pmd_events |= PMDE_LAND;
        if (prev->waterlevel != waterlevel)
            pmd_events |= PMDE_WATER;
    }

    PMD_Entry* e = &pmd_journal[seq % PMD_NJOURNAL];
    e->used = TRUE;
    e->seq = seq;
    e->org = org;
    e->vel = vel;
    e->onground = onground;
    e->waterlevel = waterlevel;
    e->buttons = input_buttons;
    e->msec = input_timelength * 1000;
    e->move = input_movevalues;
    e->events = pmd_events;
    e->impulse = pmd_impulse;
    e->dmg = pmd_dmg;
    e->spawn_gen = game_state.spawn_gen;
    e->matched = e->bad = e->sv_dpos = e->sv_dvel = e->sv_events = 0;
    pmd_events = 0;
    pmd_impulse = '0 0 0';
    pmd_dmg = 0;
}

// One line of run-up: what we predicted for that frame and how it compared.
static void PMD_Context(float seq) {
    if (seq < 0)
        return;   // asked for run-up from before the first frame of the session
    PMD_Entry* e = &pmd_journal[seq % PMD_NJOURNAL];
    if (!e->used || e->seq != seq)
        return;
    printf("    %i %s d=%.2f/%.1f og=%i wl=%i",
           (int)seq, e->matched ? (e->bad ? "MISS" : "ok  ") : "....",
           e->sv_dpos, e->sv_dvel, (int)e->onground, (int)e->waterlevel);
    printf(" in=%i %v %.0fms cl=%s sv=%s\n",
           (int)e->buttons, e->move, e->msec,
           PMD_EventNames(e->events), PMD_EventNames(e->sv_events));
}

void PMD_Reset() {
    pmd_matched = pmd_bad = 0;
    pmd_worstpos = pmd_worstvel = pmd_worstseq = 0;
    pmd_causeless = 0;
    pmd_sumpos = pmd_maxpos = pmd_sumvel = pmd_maxvel = 0;
    pmd_stepdiff = pmd_summsec = pmd_maxmsec = 0;
    for (float i = 0; i < PMD_NEVENT; i++)
        pmd_cause[i] = pmd_saw[i] = 0;
}

// One of the server's records has arrived.
void PMD_ServerRecord(float seq, vector org, vector vel, float onground,
                      float waterlevel, float events, vector impulse, float dmg,
                      float spawn_gen, float msec) {
    PMD_Entry* e = &pmd_journal[seq % PMD_NJOURNAL];
    if (!e->used || e->seq != seq)
        return;   // predicted too long ago, or never predicted
    if (e->spawn_gen != spawn_gen)
        return;   // the two records are of different lives, not a mispredict

    vector dp = e->org - org;
    vector dv = e->vel - vel;
    float pos = vlen(dp), vel_d = vlen(dv);
    float bad = pos > CVARF(fopmd_poserr) || vel_d > CVARF(fopmd_velerr) ||
                e->onground != onground || e->waterlevel != waterlevel;

    // Integrating the same inputs over different steps is the one difference
    // that makes and unmakes itself every frame without ever accumulating.
    float dmsec = e->msec - msec;
    if (fabs(dmsec) > 0.01)
        bad = TRUE;

    // How much of this frame's difference is new.  A frame that introduces one
    // is where the fault is; the frames after it are carrying it.
    PMD_Entry* before = &pmd_journal[(seq - 1 + PMD_NJOURNAL) % PMD_NJOURNAL];
    float onset = FALSE;
    if (before->used && before->seq == seq - 1 && before->matched) {
        if (fabs(pos - before->sv_dpos) > CVARF(fopmd_posstep) ||
            fabs(vel_d - before->sv_dvel) > CVARF(fopmd_velstep))
            onset = TRUE;
    }
    bad = bad || onset;

    e->matched = TRUE;
    e->bad = bad;
    e->sv_dpos = pos;
    e->sv_dvel = vel_d;
    e->sv_events = events;

    pmd_matched++;
    if (!pmd_seen) {
        pmd_seen = TRUE;
        printf("pmd: matching server records, from seq %i\n", (int)seq);
    }
    pmd_sumpos += pos;
    pmd_sumvel += vel_d;
    if (pos > pmd_maxpos) pmd_maxpos = pos;
    if (vel_d > pmd_maxvel) pmd_maxvel = vel_d;
    pmd_summsec += fabs(dmsec);
    if (fabs(dmsec) > pmd_maxmsec) pmd_maxmsec = fabs(dmsec);
    if (fabs(dmsec) > 0.01) pmd_stepdiff++;
    for (float i = 0; i < PMD_NEVENT; i++)
        if (events & (1 << i))
            pmd_saw[i]++;

    if (bad) {
        pmd_bad++;
        if (pos > pmd_worstpos) {
            pmd_worstpos = pos;
            pmd_worstvel = vel_d;
            pmd_worstseq = seq;
        }
        if (!events)
            pmd_causeless++;
        else
            for (float i = 0; i < PMD_NEVENT; i++)
                if (events & (1 << i))
                    pmd_cause[i]++;
    }

    if (!CVARF(fopmd_debug))
        return;
    if (!bad && CVARF(fopmd_debug) < 2)
        return;

    printf("pmd %i %s dpos=%.3f %v dvel=%.2f %v\n", (int)seq,
           !bad ? "ok" : (onset ? "ONSET" : "MISS"), pos, dp, vel_d, dv);
    printf("    cl org=%v vel=%v og=%i wl=%i ev=%s\n",
           e->org, e->vel, (int)e->onground, (int)e->waterlevel, PMD_EventNames(e->events));
    printf("    sv org=%v vel=%v og=%i wl=%i ev=%s\n",
           org, vel, (int)onground, (int)waterlevel, PMD_EventNames(events));
    if (fabs(dmsec) > 0.001)
        printf("    step cl=%.4fms sv=%.4fms d=%.4f\n", e->msec, msec, dmsec);
    if (e->impulse != '0 0 0' || impulse != '0 0 0')
        printf("    push cl=%v dmg=%.1f | sv=%v dmg=%.1f\n",
               e->impulse, e->dmg, impulse, dmg);

    // The run-up, but only at the start of a run of bad frames: once it has
    // gone wrong the following frames are usually the same divergence being
    // carried forward, and their context is the frames already printed.
    PMD_Entry* prev = &pmd_journal[(seq - 1 + PMD_NJOURNAL) % PMD_NJOURNAL];
    if (bad && !(prev->used && prev->seq == seq - 1 && prev->matched && prev->bad)) {
        float n = CVARF(fopmd_context);
        if (n > PMD_NJOURNAL - 2)
            n = PMD_NJOURNAL - 2;
        for (float i = n; i >= 1; i--)
            PMD_Context(seq - i);
        PMD_Context(seq);
    }
}

void PMD_Dump() {
    if (!pmd_matched) {
        printf("pmd: nothing matched yet (localinfo pm_debug 1 on the server)\n");
        return;
    }
    printf("pmd: %i frames, %i missed (%.1f%%), worst %.2fu at seq %i (vel %.1f)\n",
           (int)pmd_matched, (int)pmd_bad, 100 * pmd_bad / pmd_matched,
           pmd_worstpos, (int)pmd_worstseq, pmd_worstvel);
    printf("  steady state: pos mean %.3fu max %.3fu | vel mean %.2f max %.2f\n",
           pmd_sumpos / pmd_matched, pmd_maxpos, pmd_sumvel / pmd_matched, pmd_maxvel);
    printf("  step: mean %.4fms max %.4fms, %i frames over 0.01ms\n",
           pmd_summsec / pmd_matched, pmd_maxmsec, (int)pmd_stepdiff);
    string seen = "";
    for (float i = 0; i < PMD_NEVENT; i++)
        if (pmd_saw[i])
            seen = strcat(seen, PMD_EventNames(1 << i), ftos(pmd_saw[i]), "  ");
    printf("  events seen: %s\n", seen == "" ? "none" : seen);

    if (!pmd_bad)
        return;
    printf("  missed frames by what the server did that frame:\n");
    for (float i = 0; i < PMD_NEVENT; i++)
        if (pmd_cause[i])
            printf("    %-10s %i\n", PMD_EventNames(1 << i), (int)pmd_cause[i]);
    if (pmd_causeless)
        printf("    %-10s %i\n", "(nothing)", (int)pmd_causeless);
}
