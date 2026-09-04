// Simplified PUG mode.
//
// A pug is what quadmode is actually used for: a prematch, two timed rounds
// with the sides swapping in between, and a result reported at the end.
// quadmode.qc grew a lot of machinery around that -- a think that counts one
// second at a time carrying minutes in .cnt and seconds in .cnt2, a `rounds`
// counter that runs downwards and doubles as the phase, and a single
// StartQuadRound that is at once "round is over", "match is over" and "set up
// the next round" depending on where that counter happens to be.
//
// This is a separate implementation of just the pug case.  It is deliberately
// self-contained so that turning it on cannot change how quadmode behaves,
// and so quadmode.qc can be deleted whole once this replaces it.  Nothing here
// calls into quadmode.qc and quadmode.qc does not know it exists.
//
// The differences that matter:
//
//   - Phases are an explicit state, not an arithmetic property of a counter.
//   - Timing is an absolute deadline compared against `time`, so the think
//     rate is a display concern rather than the thing that defines the clock.
//     A dropped or late think cannot make a round longer.
//   - One function per transition, each of which says what it does.
//
// Enable with `localinfo pug on`.  Leave quadmode and clan off: this runs its
// own prematch and takes over the round entity itself.

// ---------------------------------------------------------------------------
// Balance
// ---------------------------------------------------------------------------
//
// Codified here rather than left to localinfo and fo_quadmode.cfg: a pug
// should play the same on every server, and a table in the progs is one thing
// to update instead of a config file per host.
//
// fteqcc has no designated initialisers -- "{PC_HVYWEAP, .gren2 = 1}" fails
// with `"." - not a name` -- so the rows are positional against the column
// header below.  -1 means "leave whatever the default was".

typedef struct {
    float pc;           // PC_* class
    float gren1;        // primary grenade count
    float gren2;        // secondary grenade count
    float class_limit;  // players of this class per team, 0 = unlimited
    float armor;        // max armour; the class default armour type is kept
    float rockets;      // max rockets
} PugClassBalance;

// The baseline, applied to every role.
static const PugClassBalance pug_balance[] = {
//   class          gren1  gren2  limit  armor  rockets
    {PC_SCOUT,        2,     2,     0,     -1,     -1},
    {PC_SNIPER,       3,     0,     0,     -1,     -1},
    {PC_SOLDIER,      4,     1,     0,     -1,     -1},
    {PC_DEMOMAN,      3,     1,     0,     -1,     -1},
    {PC_MEDIC,        3,     2,     0,     -1,     -1},
    {PC_HVYWEAP,      3,     1,     0,     -1,     -1},
    {PC_PYRO,         3,     1,     0,     -1,     40},
    {PC_SPY,          3,     1,     0,     -1,     -1},
    {PC_ENGINEER,     4,     1,     0,     -1,     -1},
};

// Per-side adjustments on top of the baseline, for the rounds where one side
// attacks and the other defends.  A row here only has to name the fields it
// changes; -1 leaves the baseline value alone.  Both start empty.
static const PugClassBalance pug_balance_o_override[] = {
//   class          gren1  gren2  limit  armor
    {PC_ENGINEER,     4,     2,     0,     60},
};

static const PugClassBalance pug_balance_d_override[] = {
//   class          gren1  gren2  limit  armor  rockets
};


void () info_player_teamspawn;
void () func_wall;
void (entity flag) Quad_HideFlag;
void (entity flag) Quad_UnHideFlag;
void (entity pl) ResetAndRespawnPlayer;
void () door_go_down_silent;
void () LinkDoors;
void () ReturnItem;
void (entity item, entity player, float flag) tfgoalitem_RemoveFromPlayer;
void () TeamFortress_ThrowGrenade;
void () TeamFortress_RemoveTimers;
void (entity eng) Engineer_RemoveBuildings;
void () DumpClanScores;
void () Admin_UpdateServer;
void UpdateClientPrematch(entity pl, float countdownstarted);
void UpdateClientQuadRoundBegin(entity pl, float round_time);
void UpdateClient_SetNextEndTime(float next);
void Stats_CaptureRoundBase();
void AnnounceEvent(string event, entity player);
void LogEventRoundStart();
void ReportMatchResult(int report_type);
void TFL_ClearAutoTeam();
void () UpdateAllClientsTeamScores;
void (entity pl, float from, float to, float held) LogEventChangeClass;
void () LogEventTeamScores;
void () LogEventGameEnd;
void () LogEventGameStart;
void GenerateMvdName();
string MvdName(float include_ext);
float (entity pe, float tno, float skipclasscheck) TeamFortress_TeamSet_Options;
float (float tno) TeamFortress_TeamGetNoPlayersExcludingAllTime;
void UpdateClientMenu_Close(entity pl);
void (entity pl, string...count) Status_Print;
void () ActivateOrgGame;
string CF_GetSettingRaw(string s, string l, string d);

#define kPugRosterMax 10
#define kPugNumClasses 12

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

// All of pug's mutable state, so it is one thing to find and obviously
// separate from the const balance tables above.
static struct {
    float state;
    float round;            // 1 or 2 while PUG_ROUND
    float deadline;         // absolute time the current phase ends
    float last_think;       // for holding the clock across a pause
    float last_sec;         // last whole second announced, -1 = none yet
    float last_min;         // last minute pushed to serverinfo status
    float forced;           // admin forcestart, skip waiting
    entity ent;             // the "round" entity driving the phase think
    float ready;            // how many players have readied up
    float msg_secs;         // seconds in prematch, for the periodic nag

    // Read once at map start.
    float round_time;       // minutes per round
    float countdown_secs;

    // The intended line-up, from localinfo; used only to place people on
    // connect.  See the comment on Pug_LoadAutoTeam.
    string autoteam[2 * kPugRosterMax];
    float autoteam_n[2];
    float autoteam_loaded;

    // Who actually held a team place when round 1 began.
    string roster[2 * kPugRosterMax];
    float roster_n[2];

    // All-time players at that moment, indexed by role rather than team.
    string alltime[2 * kPugRosterMax];
    float alltime_n[2];

    float teams_locked;

    // Per-role overrides for things that are compile-time #defines per class,
    // so unlike the role tables they cannot be written up front.  Indexed
    // role * kPugNumClasses + playerclass; -1 leaves the class default.
    float armor[3 * kPugNumClasses];
    float rockets[3 * kPugNumClasses];
} pug;

// Armour is a compile-time #define per class (PC_SCOUT_MAXARMOR and friends),
// so unlike the grenade limits it cannot be written into a role table up
// front.  It is kept here and applied to the player in Pug_ApplyArmor when
// their equipment is set.
// Flat because fteqcc has no 2D arrays: index is role * kPugNumClasses + pc,
// with role 0 none, 1 attack, 2 defence.

static void PugApplyRow(Team_Role* role, float armor_slot,
                        PugClassBalance row) {
    if (row.gren1 >= 0)
        role->gren1_limits[row.pc] = row.gren1;
    if (row.gren2 >= 0)
        role->gren2_limits[row.pc] = row.gren2;
    if (row.class_limit >= 0)
        role->class_limits[row.pc] = row.class_limit;

    pug.armor[armor_slot * kPugNumClasses + row.pc] = row.armor;
    pug.rockets[armor_slot * kPugNumClasses + row.pc] = row.rockets;
}

void Pug_SetupBalance() {
    if (!pugmode)
        return;

    // A pug is attack/defence by definition, so the per-side role tables are
    // always in play -- Pug_ApplyRoles assigns them regardless.  Set the flag
    // too so anything else keying off it (roles.qc's report, the class limit
    // path) agrees rather than believing roles are off.
    quad_roles = TRUE;

    // 2, not 3: no gren2 pickups, gren1 still picked up.  Matches
    // ActivateOrgGame; 3 is quadmode's 2v2 ruleset, which is not this.
    disable_resup_gren = 2;
    drop_gren1 = 0;

    int i;

    // Baseline into every role, so a class plays the same whichever side it
    // is on unless an override below says otherwise.
    for (i = 0; i < pug_balance.length; i++) {
        PugApplyRow(&Role_None,    0, pug_balance[i]);
        PugApplyRow(&Role_Attack,  1, pug_balance[i]);
        PugApplyRow(&Role_Defence, 2, pug_balance[i]);
    }

    for (i = 0; i < pug_balance_o_override.length; i++)
        PugApplyRow(&Role_Attack, 1, pug_balance_o_override[i]);

    for (i = 0; i < pug_balance_d_override.length; i++)
        PugApplyRow(&Role_Defence, 2, pug_balance_d_override[i]);

    PC_PYRO_AIRBLAST_COOLDOWN = 10;
    PC_ENGINEER_GRENADE_TYPE_2_RANGE = 200;

    // Goes with the scout's 2 flash / 2 conc above: both come from
    // ActivateOrgGame's tfx_exp branch, taken here unconditionally because a
    // pug should not depend on whether the host set tfx_exp.
    cussgrentime = 5;

    // Still left out: NBF_CONC_NEW_CAP and NBF_NO_CAP, which ActivateOrgGame
    // takes from the nbcc/nbnc settings rather than from tfx_exp.  Add them
    // here if a pug should always run the new conc caps.
}

// Called at the end of TeamFortress_SetEquipment, which has just written the
// class defaults.  Only overrides what the table asks for.
void Pug_ApplyClassOverrides(entity p) {
    if (!pugmode || p.playerclass < 1 || p.playerclass >= kPugNumClasses)
        return;

    float slot = 0;
    if (p.team_no && p.team_no == team_no_attack)
        slot = 1;
    else if (p.team_no)
        slot = 2;

    float idx = slot * kPugNumClasses + p.playerclass;

    float armor = pug.armor[idx];
    if (armor >= 0) {
        p.maxarmor = armor;
        if (p.armorvalue > armor)
            p.armorvalue = armor;
    }

    // Clamp what they are carrying too: SetEquipment has just filled them to
    // the class default, which is above the new cap.
    float rockets = pug.rockets[idx];
    if (rockets >= 0) {
        p.maxammo_rockets = rockets;
        if (p.ammo_rockets > rockets)
            p.ammo_rockets = rockets;
    }
}


enum {
    PUG_OFF,
    PUG_PREMATCH,
    PUG_COUNTDOWN,
    PUG_ROUND,
    PUG_INTERMISSION,
    PUG_ENDED,
};

// pugmode itself lives in qw.qc with quadmode and clanbattle.

// Tunables, read once at map start.

const float kPugRounds = 2;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// Between rounds and after the match the players are frozen -- takedamage
// off, SOLID_NOT, MOVETYPE_NONE, no model.  Callers use this to refuse the
// things that freeze alone does not stop: suicide, throwing grenades, and
// client-side movement prediction, which otherwise happily keeps walking
// because CSQC never learns the server changed movetype.
float Pug_Frozen() {
    return pugmode &&
           (pug.state == PUG_INTERMISSION || pug.state == PUG_ENDED);
}

// ---------------------------------------------------------------------------
// Teams
// ---------------------------------------------------------------------------
//
// Two separate lists, which are easy to confuse:
//
//   pug.autoteam  the intended line-up, from localinfo auto_team1/auto_team2.
//                 Only used to put someone on the right side when they first
//                 connect.  It does not restrict anything -- switching sides
//                 afterwards is allowed.
//
//   pug.roster    who was actually on each team when round 1 began, whether or
//                 not that matched the autoteam.  This is what decides who may
//                 rejoin mid-match.
//
// Both are flat arrays indexed team * kPugRosterMax + i, fteqcc having no 2D
// arrays.

float Pug_MatchStarted();


// All-time players are recorded apart from the team rosters, indexed by role
// rather than by team, because that is what they actually belong to -- they
// change team at the swap and follow attack or defence instead.  Keeping them
// out of pug.roster is also what makes the capacity test below correct:
// TeamFortress_TeamGetNoPlayersExcludingAllTime does not count them, so a
// roster that did would leave every side looking permanently one short.


// Read once per map.  No strzone on the argv() results: it is a nop on FTE,
// which keeps QC strings alive by reference rather than in a fixed temp pool.
static void Pug_LoadAutoTeam() {
    if (pug.autoteam_loaded)
        return;
    pug.autoteam_loaded = TRUE;

    for (float t = 0; t < 2; t++) {
        string li = infokey(world, sprintf("auto_team%d", t + 1));
        if (li == string_null)
            continue;

        float n = min(tokenizebyseparator(li, ","), kPugRosterMax);
        pug.autoteam_n[t] = n;
        for (float i = 0; i < n; i++)
            pug.autoteam[t * kPugRosterMax + i] = argv(i);
    }
}

// 1, 2, or 0 for "not on the intended line-up".
static float Pug_AutoTeamOf(string login) {
    if (login == string_null || login == "")
        return 0;

    Pug_LoadAutoTeam();

    for (float t = 0; t < 2; t++)
        for (float i = 0; i < pug.autoteam_n[t]; i++)
            if (pug.autoteam[t * kPugRosterMax + i] == login)
                return t + 1;

    return 0;
}

// Whoever is playing as round 1 starts, autoteam or not: all-time players
// into their role's list, everyone else into their team's.
void Pug_CaptureRoster() {
    int count;
    entity* players = find_list(classname, "player", EV_STRING, count);

    pug.roster_n[0] = pug.roster_n[1] = 0;
    pug.alltime_n[0] = pug.alltime_n[1] = 0;

    for (int i = 0; i < count; i++) {
        entity p = players[i];

        if (p.tfl_username == string_null)
            continue;

        if (p.all_time == ALL_TIME_ATTACK || p.all_time == ALL_TIME_DEFENCE) {
            float r = p.all_time - 1;   // ATTACK 1 -> 0, DEFENCE 2 -> 1
            float an = pug.alltime_n[r];
            if (an >= kPugRosterMax)
                continue;

            pug.alltime[r * kPugRosterMax + an] = p.tfl_username;
            pug.alltime_n[r] = an + 1;
            continue;
        }

        float t = p.team_no;
        if (t < 1 || t > 2)
            continue;

        float n = pug.roster_n[t - 1];
        if (n >= kPugRosterMax)
            continue;

        pug.roster[(t - 1) * kPugRosterMax + n] = p.tfl_username;
        pug.roster_n[t - 1] = n + 1;
    }

    printf("Pug: roster locked, blue %g red %g, all-time att %g def %g\n",
           pug.roster_n[0], pug.roster_n[1],
           pug.alltime_n[0], pug.alltime_n[1]);
}

// Was this login all-time in that role when the pug started?
static float Pug_OnAllTime(string login, float role) {
    if (login == string_null || role < ALL_TIME_ATTACK ||
        role > ALL_TIME_DEFENCE)
        return FALSE;

    float r = role - 1;
    for (float i = 0; i < pug.alltime_n[r]; i++)
        if (pug.alltime[r * kPugRosterMax + i] == login)
            return TRUE;

    return FALSE;
}

static float Pug_OnRoster(string login, float tno) {
    if (login == string_null || tno < 1 || tno > 2)
        return FALSE;

    for (float i = 0; i < pug.roster_n[tno - 1]; i++)
        if (pug.roster[(tno - 1) * kPugRosterMax + i] == login)
            return TRUE;

    return FALSE;
}

// All-time attack/defence is a prematch commitment.  It decides which side you
// follow across the round swap, and all-time players are excluded from the
// roster counts in Pug_TeamJoinAllowed -- so becoming one mid-match would
// silently open a place on the team being left, which is the hole the team
// lock exists to close.
float Pug_AllTimeAllowed(entity pe, float want) {
    if (!Pug_MatchStarted() || !pug.teams_locked)
        return TRUE;
    if (pe.all_time == want)
        return TRUE;   // already committed to this before the match began

    // Someone who was all-time at the start and dropped can resume the role
    // they had; this is a reconnect, not a mid-match switch.
    if (Pug_OnAllTime(pe.tfl_username, want))
        return TRUE;

    sprint(pe, PRINT_HIGH, "All-time attack/defence can only be chosen "
                           "during prematch.\n");
    return FALSE;
}

void Pug_UnlockTeams() {
    pug.teams_locked = FALSE;
}

// Called from TeamFortress_TeamSet_Options.  Prematch is unrestricted beyond
// the login requirement that gate already applies.
float Pug_TeamJoinAllowed(entity pe, float tno) {
    if (!Pug_MatchStarted() || !pug.teams_locked)
        return TRUE;
    if (tno < 1 || tno > 2 || pe.team_no == tno)
        return TRUE;

    // Their own place is always theirs to take back.
    if (Pug_OnRoster(pe.tfl_username, tno))
        return TRUE;

    // Otherwise only to fill a gap left by someone who has dropped.  All-time
    // players sit outside the count so they neither fill nor open a place.
    if (TeamFortress_TeamGetNoPlayersExcludingAllTime(tno) <
        pug.roster_n[tno - 1])
        return TRUE;

    sprint(pe, PRINT_HIGH,
           "That team is full -- teams are locked once the pug starts.\n");
    return FALSE;
}

// On connect, put someone where the line-up says they belong.  Nothing here
// holds them there; changing sides afterwards goes through the check above.
void Pug_AutoTeam(entity p) {
    float t = Pug_AutoTeamOf(p.tfl_username);
    if (!t)
        return;

    entity oldself = self;
    self = p;

    if (TeamFortress_TeamSet_Options(p, t, TRUE) == 1) {
        p.playerclass = p.nextpc = PC_SOLDIER;
        ResetAndRespawnPlayer(p);
        UpdateClientMenu_Close(p);

        string side = "^1RED";
        if (t == 1)
            side = "^4BLUE";

        string msg = strcat(p.tfl_username, ": You're on the ", side,
                            "^7 team.\n");
        sprint(p, PRINT_HIGH, msg);
        Status_Print(p, msg);
        p.clear_status_message = time + 15;  // Hack, mirrors TFL_AutoTeam
    }

    self = oldself;
}

// Past the warmup: the roster is fixed and the team lock applies, including
// across the intermission between rounds.
float Pug_MatchStarted() {
    return pugmode && (pug.state == PUG_ROUND ||
                       pug.state == PUG_INTERMISSION ||
                       pug.state == PUG_ENDED);
}

float Pug_Active() {
    return pugmode && pug.state != PUG_OFF && pug.state != PUG_ENDED;
}

// Seconds left in the current phase, never negative.
static float Pug_Remaining() {
    return max(0, pug.deadline - time);
}

// The round entity is the one quadmode uses and, more importantly, the one
// UpdateClientPrematch reads the client-side timer out of -- as
// cnt * 60 + cnt2.  Keep those two fields meaning what that code expects
// rather than inventing a second representation the HUD cannot see.
//
// Held rather than looked up: the clock republishes on every think, and this
// is a singleton, so there is nothing to search for after the first time.
static void Pug_EnsureController() {
    if (pug.ent)
        return;

    int count;
    entity* found = find_list(classname, "round", EV_STRING, count);
    pug.ent = count ? found[0] : spawn();
    pug.ent.owner = world;
    pug.ent.classname = "round";
}

static void Pug_PublishClock() {
    float remaining = Pug_Remaining();

    pug.ent.cnt = floor(remaining / 60);
    pug.ent.cnt2 = remaining - pug.ent.cnt * 60;
}

static void Pug_SetStatus(string s) {
    localcmd("serverinfo status \"", s, "\"\n");
}

// Freeze takes a player out of the simulation entirely for prematch and
// intermission: quadmode did this inline in three places with the same five
// assignments each time.
static void Pug_FreezePlayer(entity pl) {
    if (pl.netname == "" || !pl.team_no || !pl.playerclass)
        return;
    pl.takedamage = DAMAGE_NO;
    pl.solid = SOLID_NOT;
    pl.movetype = MOVETYPE_NONE;
    pl.modelindex = 0;
    pl.model = string_null;
}

static void Pug_ThawPlayer(entity pl) {
    if (pl.netname == "" || !pl.team_no || !pl.playerclass)
        return;
    pl.takedamage = DAMAGE_AIM;
    pl.solid = SOLID_SLIDEBOX;
    pl.movetype = MOVETYPE_WALK;
}

static void Pug_FreezeAll(float freeze) {
    int count;
    entity* players = find_list(classname, "player", EV_STRING, count);

    for (int i = 0; i < count; i++) {
        if (freeze)
            Pug_FreezePlayer(players[i]);
        else
            Pug_ThawPlayer(players[i]);
    }
}

// Tell every CSQC client which phase we are in.  Both players and observers,
// because the prematch overlay is drawn by spectators too.
static void Pug_PushPrematchState(float countdown_started) {
    int count, i;

    entity* players = find_list(classname, "player", EV_STRING, count);
    for (i = 0; i < count; i++)
        UpdateClientPrematch(players[i], countdown_started);

    entity* observers = find_list(classname, "observer", EV_STRING, count);
    for (i = 0; i < count; i++)
        UpdateClientPrematch(observers[i], countdown_started);
}

static void Pug_CenterPrintAll(string a, string b, string c) {
    int count;
    entity* players = find_list(classname, "player", EV_STRING, count);

    for (int i = 0; i < count; i++)
        if (players[i].netname != "")
            CenterPrint3(players[i], a, b, c);
}

// ---------------------------------------------------------------------------
// World reset between phases
// ---------------------------------------------------------------------------
//
// Everything a round can leave lying around.  Run on entering each round so a
// round always starts from the same world, whichever phase preceded it.

// Schedules an entity for removal on the next frame.  Several of the sweeps
// below want exactly this and nothing else.
static void Pug_RemoveSoon(entity e) {
    e.think = SUB_Remove;
    e.nextthink = time + 0.1;
}

static void Pug_ResetWorld() {
    entity oldself, returner;
    int count, i;

    // Breakables come back.
    entity* breakables = find_list(classname, "func_breakable", EV_STRING,
                                   count);
    for (i = 0; i < count; i++) {
        setmodel(breakables[i], breakables[i].mdl);
        breakables[i].solid = SOLID_BSP;
    }

    // Doors shut, silently -- a round start should not sound like a fight.
    entity* doors = find_list(classname, "door", EV_STRING, count);
    for (i = 0; i < count; i++) {
        oldself = self;
        self = doors[i];
        door_go_down_silent();
        self.think = LinkDoors;
        self = oldself;
    }

    // Dropped or carried goals go home.
    entity* goals = find_list(classname, "item_tfgoal", EV_STRING, count);
    for (i = 0; i < count; i++) {
        if (goals[i].origin == goals[i].oldorigin)
            continue;
        if (goals[i].owner != world)
            tfgoalitem_RemoveFromPlayer(goals[i], goals[i].owner, 1);
        goals[i].solid = SOLID_NOT;

        returner = spawn();
        returner.enemy = goals[i];
        returner.weapon = 3;
        returner.nextthink = time + 0.2;
        returner.think = ReturnItem;
    }

    // Anything a player is holding or has built.
    entity* players = find_list(classname, "player", EV_STRING, count);
    for (i = 0; i < count; i++) {
        oldself = self;
        self = players[i];
        self.menu_count = 30;
        TeamFortress_ThrowGrenade();
        TeamFortress_RemoveTimers();
        if (self.playerclass == PC_ENGINEER)
            Engineer_RemoveBuildings(self);
        self = oldself;
    }

    // Live ordnance and pickups.  find_list hands back a snapshot, so the
    // detpack sweep can dremove as it goes -- walking a find() chain while
    // removing links out of it is how that loop used to have to be written.
    entity* grenades = find_list(classname, "grenade", EV_STRING, count);
    for (i = 0; i < count; i++)
        Pug_RemoveSoon(grenades[i]);

    entity* detpacks = find_list(classname, "detpack", EV_STRING, count);
    for (i = 0; i < count; i++) {
        if (detpacks[i].is_disarming == 1) {
            TeamFortress_SetSpeed(detpacks[i].enemy);
            dremove(detpacks[i].oldenemy);
            dremove(detpacks[i].observer_list);
        }
        dremove(detpacks[i].linked_list);
        dremove(detpacks[i]);
    }

    entity* packs = find_list(classname, "backpack", EV_STRING, count);
    for (i = 0; i < count; i++)
        Pug_RemoveSoon(packs[i]);

    entity* ammo = find_list(classname, "ammobox", EV_STRING, count);
    for (i = 0; i < count; i++)
        Pug_RemoveSoon(ammo[i]);
}

// Map-driven round changes: fo_roundchange entities swap walls, spawns and
// goals over for the second round.  On round 1 the restore group is hidden
// instead, so the map starts in its first-round configuration.
// Quad_UnHideFlag restores a goal's model and touch but not its solidity, and
// a goal can reach here SOLID_NOT: Pug_ResetWorld clears that on anything
// being carried and schedules a ReturnItem, which then refuses to run because
// it will not restore a goal that has since been hidden.  Nothing else ever
// puts solid back, so the flag stays untouchable for the rest of the map.
static void Pug_ShowGoal(entity g) {
    Quad_UnHideFlag(g);

    if (g.solid != SOLID_NOT)
        return;

    // Same choice ReturnItem makes.
    if ((g.goal_activation & 8192) && g.classname == "item_tfgoal")
        g.solid = SOLID_BBOX;
    else
        g.solid = SOLID_TRIGGER;
}

// Show or hide every goal in a map group in one call.  The three group fields
// below differ only in that and in which way round the flag goes.
static void Pug_SetGroupGoalsHidden(float group, float hidden) {
    if (!group)
        return;

    int count;
    entity* members = find_list(group_no, group, EV_FLOAT, count);

    for (int i = 0; i < count; i++) {
        if (members[i].classname != "item_tfgoal")
            continue;
        if (hidden)
            Quad_HideFlag(members[i]);
        else
            Pug_ShowGoal(members[i]);
    }
}

// Flip a group's team ownership over for the second round, and re-run the
// spawn/wall setup that depends on it.
static void Pug_SwitchGroupTeams(float group) {
    if (!group)
        return;

    entity oldself = self;
    int count;
    entity* members = find_list(group_no, group, EV_FLOAT, count);

    for (int i = 0; i < count; i++) {
        entity c = members[i];

        switch (c.team_no) {
            case TEAM_BLUE: c.team_no = TEAM_RED;  break;
            case TEAM_RED:  c.team_no = TEAM_BLUE; break;
            case TEAM_YELL: c.team_no = TEAM_GREN; break;
            case TEAM_GREN: c.team_no = TEAM_YELL; break;
        }

        switch (c.classname) {
            case "func_wall":
                self = c;
                func_wall();
                break;
            case "info_player_teamspawn":
                self = c;
                info_player_teamspawn();
                break;
            case "plat":
                if (c.enemy)
                    c.enemy.team_no = c.team_no;
                break;
        }
    }

    self = oldself;
}

static void Pug_ApplyRoundChange(float round_no) {
    entity oldself = self;
    int count;
    entity* changers = find_list(targetname, "fo_roundchange", EV_STRING,
                                 count);

    for (int i = 0; i < count; i++) {
        entity e = changers[i];
        self = e;

        if (round_no == 1) {
            // First round: the map stays as built, with whatever the restore
            // group holds kept out of play until the swap.
            Pug_SetGroupGoalsHidden(e.restore_group_no, TRUE);
            continue;
        }

        self.use();
        Pug_SetGroupGoalsHidden(e.remove_group_no, TRUE);
        Pug_SetGroupGoalsHidden(e.restore_group_no, FALSE);
        Pug_SwitchGroupTeams(e.switch_team_group_no);
    }

    self = oldself;
    LogEventRoundStart();
}

// Which side attacks, and the goal visibility that goes with it.  Round 1 has
// team 1 attacking, round 2 team 2.
static void Pug_ApplyRoles(float round_no) {
    // `rounds` is not the phase here, but json.qc reports the round number as
    // (rounds == 1) ? 2 : 1 and other code reads team_no_attack, so both are
    // kept at the values quadmode would have had.  Round 1 -> 2, round 2 -> 1.
    rounds = kPugRounds + 1 - round_no;
    team_no_attack = 1 + (rounds % 2);

    // Not behind the "qr" setting the way quadmode has it: a pug is
    // attack/defence by definition, and with both teams left on Role_None
    // nothing ever reads Role_Attack or Role_Defence, so the per-side
    // overrides in pug_balance_o_override / _d_override would do nothing.
    if (round_no == 1) {
        Team1_Role = &Role_Attack;
        Team2_Role = &Role_Defence;
    } else {
        Team1_Role = &Role_Defence;
        Team2_Role = &Role_Attack;
    }

    // Only the attacking side's target should exist -- with both flags out,
    // defenders can cap and the round makes no sense.
    int count;
    entity* goals = find_list(classname, "item_tfgoal", EV_STRING, count);

    for (int i = 0; i < count; i++) {
        entity te = goals[i];

        // Only one side's goal is in play per round: the attackers'.
        if (te.team_no == 2 && te.owned_by == 1) {
            if (round_no == 1)
                Quad_HideFlag(te);
            else
                Pug_ShowGoal(te);
        } else if (te.team_no == 1 && te.owned_by == 2) {
            if (round_no == 1)
                Pug_ShowGoal(te);
            else
                Quad_HideFlag(te);
        }
    }
}

// What MapEndSequence does, minus the restart timer it spawns: a finished pug
// stays on the map so people can look at the scoreboard and call the next one.
// Changing map is an explicit "cmd map".
static void Pug_LogMatchEnd() {
    int count;
    entity* players = find_list(classname, "player", EV_STRING, count);

    for (int i = 0; i < count; i++) {
        entity p = players[i];
        if (p.playerclass != 0 && p.has_disconnected != 1) {
            LogEventChangeClass(p, p.playerclass, 0, gametime - p.classtime);
            p.classtime = gametime;
        }
    }

    LogEventTeamScores();
    LogEventGameEnd();

    // localinfo survives a map restart, so a re-run of the same map would
    // otherwise come back with the old teams still locked in.
    TFL_ClearAutoTeam();

    if (logfilehandle > 0)
        fclose(logfilehandle);
    canlog = 0;
}

// ---------------------------------------------------------------------------
// Phase transitions
// ---------------------------------------------------------------------------

static void Pug_EnterPhase(float state, float duration) {
    pug.state = state;
    pug.deadline = time + duration;
    pug.last_think = time;
    pug.last_sec = -1;
    pug.last_min = -1;
    Pug_PublishClock();
}

void Pug_BeginRound(float round_no) {
    pug.round = round_no;

    cb_prematch = 0;
    round_active = 1;
    round_over = 0;
    cease_fire = 0;
    cs_paused = 0;

    Pug_ResetWorld();
    Pug_ApplyRoles(round_no);
    Pug_ApplyRoundChange(round_no);

    // Respawn everyone into the round's own spawn points, which the round
    // change above may just have moved.
    int count;
    entity* players = find_list(classname, "player", EV_STRING, count);
    entity oldself;

    for (int i = 0; i < count; i++) {
        oldself = self;
        self = players[i];
        ResetAndRespawnPlayer(self);
        self = oldself;
    }
    Pug_FreezeAll(FALSE);

    localcmd("timelimit ", ftos(pug.round_time), "\n");
    lightstyle(0, "m");

    Pug_EnterPhase(PUG_ROUND, pug.round_time * 60);
    round_start_time = time;

    Stats_CaptureRoundBase();
    UpdateClientQuadRoundBegin(world, pug.round_time);
    UpdateClient_SetNextEndTime(pug.deadline);
    Pug_PushPrematchState(FALSE);

    bprint(2, "ROUND ", ftos(round_no), " OF ", ftos(kPugRounds),
           " BEGINS NOW\n");

    // The match proper starts with round 1; round 2 is reported as halftime,
    // matching what the bot already expects to receive.
    if (round_no == 1) {
        // Whoever holds a team place now is the pug.  From here
        // Pug_TeamJoinAllowed only lets these logins back in, or anyone into
        // a side that is short.
        Pug_CaptureRoster();
        AnnounceEvent("game_start", __NULL__);
        ReportMatchResult(kReportStart);
    } else {
        AnnounceEvent("round_end", __NULL__);
        ReportMatchResult(kReportHalftime);
    }
}

// Players who always want the same role change team so the role follows them.
// Everyone else keeps their team and picks up the other role, which
// Pug_ApplyRoles has already swapped.
static void Pug_SwapSides() {
    int count;
    entity* players = find_list(classname, "player", EV_STRING, count);

    for (int i = 0; i < count; i++) {
        entity te = players[i];
        string cmd = "";

        switch (te.all_time) {
            case ALL_TIME_ATTACK:  cmd = "cmd changeteam attack\n";  break;
            case ALL_TIME_DEFENCE: cmd = "cmd changeteam defence\n"; break;
        }
        if (cmd == "")
            continue;

        sprint(te, PRINT_HIGH, "Swapping teams.\n");
        stuffcmd(te, cmd);
    }
}

void Pug_EnterIntermission() {
    round_active = 0;
    round_over = 2;
    cb_prematch = 1;

    Pug_FreezeAll(TRUE);
    Pug_ResetWorld();
    Pug_SwapSides();

    // Shared with quadmode: localinfo rdt.  Read here rather than cached in
    // Pug_Init, which DecodeLevelParms calls before it assigns this.
    float delay = max(5, round_delay_time);

    Pug_EnterPhase(PUG_INTERMISSION, delay);
    Pug_SetStatus("Standby");
    Pug_PushPrematchState(TRUE);

    bprint(2, "ROUND TIME OVER\nNext round begins in ",
           ftos(delay), " seconds\n");
    UpdateClient_SetNextEndTime(pug.deadline);
}

static string Pug_WinnerName(float team_no) {
    switch (team_no) {
        case 1: return "Blue Team Wins!\n";
        case 2: return "Red Team Wins!\n";
        case 3: return "Yellow Team Wins!\n";
        case 4: return "Green Team Wins!\n";
    }
    return "Round Drawn!\n";
}

// Highest score wins; a tie at the top is a draw.
static float Pug_Winner() {
    float best = 0, winner = 0;
    float scores[4] = {team1score, team2score, team3score, team4score};

    for (float i = 0; i < scores.length; i++) {
        if (scores[i] > best) {
            best = scores[i];
            winner = i + 1;
        } else if (scores[i] == best) {
            winner = 0;
        }
    }
    return winner;
}

void Pug_EndMatch() {
    pug.state = PUG_ENDED;
    round_active = 0;
    round_over = 1;
    cb_prematch = 1;

    Pug_FreezeAll(TRUE);
    Pug_PushPrematchState(TRUE);

    // Same as prematch: the match is over, so nothing is counting down.
    UpdateClient_SetNextEndTime(0);
    localcmd("timelimit 0\n");

    bprint(2, Pug_WinnerName(Pug_Winner()));

    AnnounceEvent("game_end", __NULL__);
    ReportMatchResult(kReportEnd);
    TFL_ClearAutoTeam();
    Pug_SetStatus("Finished");

    bprint(2, "Match over! Use \"cmd map <mapname>\" to go to the next map.\n");

    if (!clan_scores_dumped) {
        DumpClanScores();
        Pug_LogMatchEnd();
        clan_scores_dumped = 1;
    }

    localcmd("stop\n");
    Admin_UpdateServer();
}

// ---------------------------------------------------------------------------
// Prematch and ready-up
// ---------------------------------------------------------------------------
//
// Implemented here rather than borrowing clan.qc's, which is gated on
// clanbattle throughout -- StartTimer refuses outright when it is unset -- so
// using it would have meant pug pretending to be a clan match.  The stat flags
// are the shared part and stay as they are: PLAYER_READY, ENEMY_TEAM_READY and
// LAST_NOT_READY are what CSQC draws the ready UI from.

// Players who could actually take part: on a team, with a class, still here.
static float Pug_ActivePlayers() {
    int count, active = 0;
    entity* players = find_list(classname, "player", EV_STRING, count);

    for (int i = 0; i < count; i++)
        if (players[i].netname != "" && players[i].team_no &&
            players[i].playerclass && !players[i].has_disconnected)
            active++;

    return active;
}

// ENEMY_TEAM_READY and LAST_NOT_READY drive the client's prematch display:
// "the other team is waiting on you", and "you are the only one left".
static void Pug_UpdateReadyStatus() {
    float team_size[5], team_ready[5];
    int count, i;
    entity* players = find_list(classname, "player", EV_STRING, count);

    for (i = 0; i < count; i++) {
        float t = players[i].team_no;
        if (t < 1 || t > 4)
            continue;
        team_size[t]++;
        if (players[i].stat_flags & PLAYER_READY)
            team_ready[t]++;
    }

    float teams_ready = 0;
    for (i = 1; i <= 4; i++)
        if (team_size[i] && team_size[i] == team_ready[i])
            teams_ready++;

    float total = Pug_ActivePlayers();
    float one_left = total > 1 && (total - pug.ready) == 1;

    for (i = 0; i < count; i++) {
        entity p = players[i];
        float t = p.team_no;
        float own_ready = (t >= 1 && t <= 4 && team_size[t] &&
                           team_size[t] == team_ready[t]);

        if (teams_ready - own_ready > 0)
            p.stat_flags |= ENEMY_TEAM_READY;
        else
            p.stat_flags &= ~ENEMY_TEAM_READY;

        if (!(p.stat_flags & PLAYER_READY) && one_left)
            p.stat_flags |= LAST_NOT_READY;
        else
            p.stat_flags &= ~LAST_NOT_READY;
    }
}

static void Pug_ShowNotReady() {
    string list = "Not ready: ";
    int count, shown = 0;
    entity* players = find_list(classname, "player", EV_STRING, count);

    for (int i = 0; i < count; i++) {
        entity p = players[i];
        if ((p.stat_flags & PLAYER_READY) || p.has_disconnected)
            continue;

        shown++;
        if (shown == 1)
            list = strcat(list, p.netname);
        else if (shown < 5)
            list = strcat(list, ", ", p.netname);
        else {
            list = strcat(list, " and others...");
            break;
        }
    }

    if (!shown)
        return;

    for (int i = 0; i < count; i++)
        if (players[i].netname != "")
            CenterPrint(players[i], list);
}

// Start the MVD and open the JSON event log for it.  This lives in clan's
// PreMatch_Think, which pug does not run -- so without it a pug recorded no
// demo and every logevent wrote to an unopened handle.  Same setting gates
// it, so a server with recording off is unaffected.
static void Pug_StartRecording() {
    // Cancel first, in case a demo is already running: recording twice writes
    // the second over the first.
    localcmd("cancel\n");

    if (infokey(world, "serverdemo") != "on")
        return;

    GenerateMvdName();
    localcmd(sprintf("record %s\n", MvdName(FALSE)));

    if (logfilehandle > 0)
        fclose(logfilehandle);
    logfilehandle = fopen(strcat(mvd_name, ".json"), FILE_WRITE);
}

void Pug_StartCountdown() {
    is_countdown = 1;
    lightstyle(0, "e");
    Pug_StartRecording();
    Pug_EnterPhase(PUG_COUNTDOWN, pug.countdown_secs);
    UpdateClient_SetNextEndTime(pug.deadline);

    int count;
    entity* players = find_list(classname, "player", EV_STRING, count);
    for (int i = 0; i < count; i++)
        if (players[i].netname != "")
            stuffcmd(players[i], "play items/protect2.wav\n");

    // Tell the clients the countdown is running: the ready panel is drawn
    // while prematch is set and SBAR.CountdownStarted is not, so without this
    // it keeps saying "press j to ready up" through the whole countdown.
    Pug_PushPrematchState(TRUE);

    bprint(2, "All players ready, starting match\n");
    localcmd("localinfo clown 0\n");   // Disable any clown settings.
}

// Returns TRUE when everyone is ready and the countdown has been started.
static float Pug_CheckAllReady() {
    if (pug.state != PUG_PREMATCH || intermission_running)
        return FALSE;

    float active = Pug_ActivePlayers();
    bprint(PRINT_HIGH, "Total players ready - ", ftos(pug.ready), "/",
           ftos(active), ".\n");

    if (pug.ready != active || pug.ready < 1)
        return FALSE;

    if (TeamFortress_TeamGetNoPlayersExcludingAllTime(1) !=
        TeamFortress_TeamGetNoPlayersExcludingAllTime(2)) {
        bprint(2, "Teams have uneven number of players, is someone supposed "
                  "to be all-time attack?\n");
        return FALSE;
    }
    if (cease_fire) {
        bprint(2, "All players ready, match will start after ceasefire "
                  "ends.\n");
        return FALSE;
    }

    Pug_StartCountdown();
    return TRUE;
}

void Pug_PlayerNotReady() {
    if (!(self.stat_flags & PLAYER_READY))
        return;

    self.stat_flags &= ~PLAYER_READY;
    pug.ready = max(0, pug.ready - 1);
    Pug_UpdateReadyStatus();
    bprint(2, self.netname, " is NOT ready anymore\n");
    Pug_ShowNotReady();
}

void Pug_PlayerReady() {
    // Spectators and observers have nothing to ready: readying is counted
    // against Pug_ActivePlayers, which only counts "player" entities, so
    // letting anyone else in would push pug.ready past the total and the
    // match would never start.
    //
    // No login test either.  TeamFortress_TeamSet refuses an unlogged team
    // join outright in pug, so having a team is proof of a login.
    if (self.classname != "player" || intermission_running)
        return;

    if (pug.state != PUG_PREMATCH) {
        sprint(self, 2, "You cannot do this after countdown has started.\n");
        return;
    }
    if (self.team_no == 0) {
        sprint(self, 2, "You must join a team first.\n");
        return;
    }
    if (self.playerclass == 0) {
        sprint(self, 2, "You must choose a class first.\n");
        return;
    }

    if (self.stat_flags & PLAYER_READY) {
        Pug_PlayerNotReady();
        return;
    }

    self.stat_flags |= PLAYER_READY;
    pug.ready++;
    Pug_UpdateReadyStatus();
    bprint(3, self.netname, " is ready to start the match\n");

    if (!Pug_CheckAllReady())
        Pug_ShowNotReady();
}

// Once every 30s, so joining late still tells you what to do.
static void Pug_PrematchTick() {
    pug.msg_secs++;

    if (pug.msg_secs % 30 == 0) {
        int count;
        entity* players = find_list(classname, "player", EV_STRING, count);

        for (int i = 0; i < count; i++) {
            entity p = players[i];
            if (p.netname == "")
                continue;

            sprint(p, PRINT_HIGH, "Currently in \sprematch\s time\n");
            if (p.stat_flags & PLAYER_READY)
                sprint(p, PRINT_HIGH, "You are \sready\s to start the match.\n"
                                      " Type \s/notready\s in the console if "
                                      "you are not ready\n");
            else
                sprint(p, PRINT_HIGH, "Type \s/ready\s in the console if you "
                                      "are ready to start the match\n");
            stuffcmd(p, "play buttons/switch04.wav\n");
            UpdateClientPrematch(p, FALSE);
        }
    }

    Pug_ShowNotReady();
}

void Pug_EnterPrematch() {
    cb_prematch = 1;
    round_active = 0;
    // 0, not 1.  round_over ships to CSQC in MSG_PREMATCH, and the ready panel
    // reads prematch && round_over as "the match is finished" -- it draws
    // "Change map to continue playing" instead of the ready prompt
    // (csqc/status.qc:551).  1 belongs to Pug_EndMatch, which is that state.
    round_over = 0;
    rounds = kPugRounds;
    pug.ready = 0;
    pug.msg_secs = 0;
    pug.teams_locked = TRUE;

    // Struct members cannot carry an initialiser the way the old
    // "var float pug_last_sec = -1" did, so set the "nothing announced yet"
    // value here.  Every phase that uses the clock also goes through
    // Pug_EnterPhase, which resets it, but this keeps the invariant true from
    // the start rather than only after the first transition.
    pug.last_sec = -1;
    pug.last_min = -1;
    is_countdown = 0;
    clan_scores_dumped = 0;

    pug.state = PUG_PREMATCH;
    pug.deadline = 0;

    // Nothing counts down in prematch -- it ends on /ready, so a clock would
    // be counting to nothing.  Three separate things can put one on screen and
    // all of them have to be cleared:
    //
    //   the round entity's cnt/cnt2, which client.qc spawns holding round_time
    //   and UpdateClientPrematch ships as "time remaining";
    //   round_end_time (STAT_ROUND_END), left over from a previous round;
    //   the engine timelimit, which gameClockString falls back to when the
    //   other two are zero -- this is the one that was still showing.
    Pug_PublishClock();
    UpdateClient_SetNextEndTime(0);
    localcmd("timelimit 0\n");

    Pug_SetStatus("Standby");
    Pug_PushPrematchState(FALSE);

    bprint(2, "Pug mode: ", ftos(kPugRounds), " rounds of ",
           ftos(pug.round_time), " minutes.\n");
    bprint(2, "Type \s/ready\s when you have picked a team and class.\n");
}

// ---------------------------------------------------------------------------
// Clock
// ---------------------------------------------------------------------------

// Called once per whole second of a round, so the announcements below read as
// a plain list instead of being tangled up with the countdown arithmetic.
static void Pug_RoundSecond(float secs_left) {
    float mins_left = floor(secs_left / 60);

    if (secs_left == 300 || secs_left == 60) {
        bprint(2, "\s[\s", ftos(mins_left), "\s]\s minute");
        if (mins_left != 1)
            bprint(2, "s");
        bprint(2, " remaining\n");
    }

    if (secs_left == 30 || secs_left == 15 ||
        (secs_left <= 10 && secs_left >= 1)) {
        bprint(2, "\s[\s", ftos(secs_left), "\s]\s second");
        if (secs_left != 1)
            bprint(2, "s");
        bprint(2, " remaining\n");
    }

    gametime++;
    gametime_string = ftos(gametime);
}

static void Pug_TickClock() {
    float remaining = Pug_Remaining();
    float secs = ceil(remaining);

    Pug_PublishClock();

    if (secs == pug.last_sec)
        return;
    pug.last_sec = secs;

    if (pug.state == PUG_ROUND) {
        Pug_RoundSecond(secs);

        float mins = ceil(remaining / 60);
        if (mins != pug.last_min) {
            pug.last_min = mins;
            Pug_SetStatus(strcat(ftos(mins), " min left"));
        }
    } else if (pug.state == PUG_COUNTDOWN || pug.state == PUG_INTERMISSION) {
        if (secs <= 10 || secs == 30 || secs == 60) {
            Pug_CenterPrintAll("Round begins in: ", ftos(secs),
                               " second(s).\nEnsure correct class is chosen!\n");
        }
        if (secs == 5)
            Pug_PushPrematchState(TRUE);
    }
}

// Wake for the next thing that actually needs doing: the next whole second of
// the countdown, since announcements are per-second, or the end of the phase.
// The deadline is absolute, so that moment is known rather than something to
// poll for -- the old implementation ticked at a fixed rate and re-derived
// where it was each time.
static void Pug_ScheduleThink() {
    float remaining = Pug_Remaining();
    float delay = remaining - floor(remaining);

    // Sitting exactly on a boundary means that second is already handled, so
    // aim at the next one.  The epsilon keeps floating point from leaving us a
    // hair short and burning a wakeup re-deciding the same second.
    if (delay < 0.01)
        delay += 1;

    // Never overshoot the deadline, and always make progress.
    self.nextthink = time + max(0.05, min(delay, remaining));
}

void Pug_Think() {
    // No deadline in prematch: it ends when everybody readies, not on a clock.
    if (pug.state == PUG_PREMATCH) {
        self.nextthink = time + 1;
        Pug_PrematchTick();
        return;
    }


    Pug_ScheduleThink();

    // Hold the deadline still while paused rather than letting real time eat
    // into the round.
    if (cease_fire || cs_paused) {
        pug.deadline += time - pug.last_think;
        pug.last_think = time;
        Pug_PublishClock();
        return;
    }
    pug.last_think = time;

    Pug_TickClock();

    if (Pug_Remaining() > 0)
        return;

    switch (pug.state) {
        case PUG_COUNTDOWN:
            is_countdown = 0;
            gametime = 0;
            gametime_string = "0";
            canlog = 1;
            LogEventGameStart();
            Pug_BeginRound(1);
            break;
        case PUG_ROUND:
            if (pug.round < kPugRounds)
                Pug_EnterIntermission();
            else
                Pug_EndMatch();
            break;
        case PUG_INTERMISSION:
            Pug_BeginRound(pug.round + 1);
            break;
    }
}

// Admin "cmd forcestart": skip waiting on /ready, or skip the break between
// rounds.  Returns TRUE when pug has handled it, so ForceStartMatch falls
// through to its clanbattle path otherwise.
float Pug_ForceStart() {
    if (!pugmode)
        return FALSE;

    if (pug.state == PUG_PREMATCH) {
        Pug_StartCountdown();
        return TRUE;
    }
    if (pug.state == PUG_INTERMISSION) {
        pug.forced = TRUE;
        pug.deadline = time;   // the next think rolls the phase over
        return TRUE;
    }

    // Claim it anyway: falling through to the clanbattle path would do nothing
    // in pug mode, and silence is what makes this hard to diagnose.
    sprint(self, PRINT_HIGH, "Pug: nothing to force start right now.\n");
    return TRUE;
}

// Admin "cmd pug_nextround": end the round now.  Collapsing the deadline
// rather than calling the transition directly means this goes wherever the
// clock running out would have -- intermission after round 1, and the end of
// the match after the last one.
float Pug_NextRound() {
    if (!pugmode)
        return FALSE;

    if (pug.state != PUG_ROUND) {
        sprint(self, PRINT_HIGH, "Pug: no round in progress.\n");
        return TRUE;
    }

    pug.deadline = time;
    bprint(2, self.netname, " ended the round early.\n");
    return TRUE;
}

// Admin "cmd pug_settime mm:ss": jump to that point in the round, so
// "pug_settime 7:00" in a 10 minute round leaves 3 minutes.  A bare number is
// read as minutes.  Returns FALSE only when pug is not running, so the caller
// can say so; anything else is reported here.
float Pug_SetTime(string spec) {
    if (!pugmode)
        return FALSE;

    if (pug.state != PUG_ROUND) {
        sprint(self, PRINT_HIGH, "Pug: no round in progress.\n");
        return TRUE;
    }

    float colon = strstrofs(spec, ":");
    float mins, secs;

    if (colon < 0) {
        mins = stof(spec);
        secs = 0;
    } else {
        mins = stof(substring(spec, 0, colon));
        secs = stof(substring(spec, colon + 1, strlen(spec) - colon - 1));
    }

    float elapsed = mins * 60 + secs;
    float total = pug.round_time * 60;

    if (elapsed < 0 || elapsed >= total) {
        sprint(self, PRINT_HIGH, "Pug: time must be between 0:00 and ",
               ftos(pug.round_time), ":00.\n");
        return TRUE;
    }

    pug.deadline = time + (total - elapsed);

    // Move the round's start with it, or anything derived from elapsed time --
    // the round_start field on reported events, and the per-round stats base --
    // would still describe the old clock.
    round_start_time = time - elapsed;

    // The announcement bookkeeping is keyed on the second last seen, so clear
    // it or a jump backwards replays nothing until it passes that mark again.
    pug.last_sec = -1;
    pug.last_min = -1;

    UpdateClient_SetNextEndTime(pug.deadline);
    Pug_PublishClock();
    pug.ent.nextthink = time + 0.05;

    // if/else rather than a ternary: fteqcc has produced "__variant" for a
    // ternary with string branches, which only shows up as a bad argument
    // later on.
    string pad = "";
    if (secs < 10)
        pad = "0";

    bprint(2, self.netname, " set the round clock to ", ftos(mins), ":",
           pad, ftos(secs), "\n");
    return TRUE;
}

// Admin "cmd pug_status": dump what the phase machine and the goals actually
// look like right now.  "not touchable" has several possible causes that look
// identical in game -- still in prematch, the goal hidden by the round change,
// or the goal left SOLID_NOT -- and this separates them.
float Pug_Status() {
    if (!pugmode)
        return FALSE;

    // Split across calls: sprintf takes at most 8 varargs.
    sprint(self, PRINT_HIGH, sprintf("pug: state %g round %g remaining %g\n",
        pug.state, pug.round, Pug_Remaining()));
    sprint(self, PRINT_HIGH, sprintf(
        "     cb_prematch %g round_active %g round_over %g countdown %g\n",
        cb_prematch, round_active, round_over, is_countdown));
    sprint(self, PRINT_HIGH, sprintf(
        "     attack_team %g rounds %g locked %g\n",
        team_no_attack, rounds, pug.teams_locked));

    int count;
    entity* goals = find_list(classname, "item_tfgoal", EV_STRING, count);

    for (int i = 0; i < count; i++) {
        entity g = goals[i];
        string hid = "shown";
        if (g.touch == item_tfgoal_hidden_touch)
            hid = "HIDDEN";
        if (g.origin != g.oldorigin)
            hid = strcat(hid, " MOVED");

        sprint(self, PRINT_HIGH, sprintf(
            "  goal team %g owned_by %g group %g solid %g %s\n",
            g.team_no, g.owned_by, g.group_no, g.solid, hid));
    }

    return TRUE;
}

// Admin "cmd pug_setscore <blue> <red>".
float Pug_SetScore(float blue, float red) {
    if (!pugmode)
        return FALSE;

    team1score = blue;
    team2score = red;
    UpdateAllClientsTeamScores();

    bprint(2, self.netname, " set the score to Blue ", ftos(blue),
           " - Red ", ftos(red), "\n");
    return TRUE;
}

// ---------------------------------------------------------------------------
// Entry
// ---------------------------------------------------------------------------

// Called from worldspawn init.  Does nothing at all unless `localinfo pug` is
// set, so quadmode and clan mode are untouched by its presence.
void Pug_Init() {
    string raw = CF_GetSettingRaw("pug", "pug", "off");
    pugmode = CF_GetSetting("pug", "pug", "off");

    // Says what it read and what it decided, once per map: "nothing happened"
    // is otherwise indistinguishable between the setting not being seen, the
    // init not running, and another mode having taken the round entity.
    printf("Pug: localinfo pug = \"%s\" -> %g\n", raw, pugmode);

    if (!pugmode)
        return;

    // DecodeLevelParms runs its "first entry" block more than once per map.
    // Pug_BeginRound respawns everyone, ResetAndRespawnPlayer calls
    // PutClientInServer, and that calls DecodeLevelParms again -- which lands
    // back here mid-round.  Re-entering prematch from there put cb_prematch
    // back to 1 while Pug_BeginRound went on to set the phase to PUG_ROUND, so
    // the state looked right and nothing was touchable: the goal and item
    // touch handlers all return early on cb_prematch.
    if (pug.state != PUG_OFF)
        return;

    // Not mutually exclusive in code: clan spawns its own prematch entity, and
    // quadmode seizes the same round entity this drives.  Refuse rather than
    // let two state machines fight over one entity.
    if (quadmode || clanbattle) {
        bprint(PRINT_HIGH, "Pug mode NOT started: turn off "
                           "localinfo quadmode and localinfo c first.\n");
        printf("Pug: refused, quadmode=%g clanbattle=%g\n",
               quadmode, clanbattle);
        pugmode = FALSE;
        return;
    }

    pug.round_time = CF_GetSetting("pug_round_time", "pug_round_time", "10");
    if (pug.round_time <= 0)
        pug.round_time = 10;

    pug.countdown_secs = CF_GetSetting("pug_countdown", "pug_countdown", "10");
    if (pug.countdown_secs < 1)
        pug.countdown_secs = 10;

    // Pugs are organised games: no map voting, and the scoreboard treats them
    // the way it treats clan and quad matches.
    disable_voting = TRUE;
    org_game = TRUE;

    Pug_SetupBalance();

    Pug_EnsureController();
    pug.ent.think = Pug_Think;
    pug.ent.nextthink = time + 0.1;

    Pug_EnterPrematch();
}
