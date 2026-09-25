// Admin rights, and the console gate they open.
//
// The gate is SV_RconCommand, the engine's hook for an rcon sent by a player
// without the real password: the engine splits the line on ";" and newlines and
// expands "$" first, then asks about each command that falls out, alias bodies
// and exec'd files included.  So a level that allows one command cannot be
// talked into running another after a separator, and there is nothing to
// sanitise here -- only a name to look up.  The correct rcon_password still
// runs as it always has and is never asked about; that is the tooling path, the
// pug bot rconning in from qwtf-logs.
//
// The cache is the source of truth.  A level in it is trusted until something
// replaces it, and what asks the site for a replacement is a player reaching
// for the gate, not a timer.  The resync runs alongside the command rather than
// in front of it, so the command is answered from what we already knew: that
// deliberately admits one command against a level that has just changed, and
// the next one is right.  Not every command resyncs, only one whose cached
// level has gone a few days unconfirmed or came up short of what was asked --
// the second of which is how rights granted in Discord mid-game arrive, the
// refusal being the lookup that makes the next attempt work.
//
// A player with nothing cached is a different case: there is no level to be
// slightly out of date, so nothing is guessed on their behalf.  Login covers
// it, looking up anyone the cache has never heard of as they arrive, early
// enough that their first command is answered from the cache like everyone
// else's.  With the site down they stay unknown and do not get in, which is the
// safe way round: the people that would otherwise lock out are the regular
// admins, and they are exactly the ones the cache has.
//
// What the site is asked for is how many games it has the player in and an
// override an admin can set from the bot (-1 when unset).  Turning those into a
// level happens here rather than on the site so the thresholds can be retuned
// by rebuilding the mod, which is the side that gets deployed often.

const float kAdminUnknown = -1;     // logged in, but never looked up

enum {
    kAdminNone,   // not logged in, or too new to be trusted with anything
    kAdminMap,    // map
    kAdminQuit,   // + quit
    kAdminAll,    // anything the console will take
};

const float kAdminGamesMap  = 10;   // fewer games than this: kAdminNone
const float kAdminGamesQuit = 50;   // fewer games than this: kAdminMap

const float kAdminResyncDays = 3;   // a cached level older than this is rechecked
const float kAdminResyncWait = 10;  // seconds between a player's requests

static float Admin_LevelFrom(float games, float override_level) {
    if (override_level >= 0)
        return bound(kAdminNone, override_level, kAdminAll);

    if (games < kAdminGamesMap)
        return kAdminNone;
    if (games < kAdminGamesQuit)
        return kAdminMap;

    return kAdminQuit;
}

// --- the cache -------------------------------------------------------------
//
// One line per player, "<tfl_id> <level> <day>".  The engine sandboxes QC
// writes, so this lands in <gamedir>/data/ even though reads find it in either
// place -- look there, not beside the .dat, when it seems to be missing.
//
// What is cached is the level rather than the two numbers it came from, because
// the level is what has to still be answerable with the site down; retuning the
// thresholds above therefore takes one resync per player to show up.  The day a
// row was last confirmed is kept only to choose which row to lose when the
// table is full: rows do not expire, they are replaced.

#define kAdminCacheFile "admin_levels.txt"

const float kAdminCacheMax = 128;

typedef struct {
    string id;
    float level;
    float day;
} AdminCacheRow;

static AdminCacheRow admin_cache[kAdminCacheMax];
static float admin_cache_n;

// Days rather than seconds: a float holds a unix timestamp only to the nearest
// couple of minutes, which is ample for the day it is divided down to and
// nothing like enough for the seconds it started as.
static float Admin_Today() {
    return floor(stof(strftime(FALSE, "%s")) / 86400);
}

static float Admin_CacheFind(string id) {
    for (float i = 0; i < admin_cache_n; i++)
        if (admin_cache[i].id == id)
            return i;

    return -1;
}

static void Admin_CacheSave() {
    float fh = fopen(kAdminCacheFile, FILE_WRITE);

    if (fh < 0) {
        dprint("admin: cannot write ", kAdminCacheFile, "\n");
        return;
    }

    for (float i = 0; i < admin_cache_n; i++)
        fputs(fh, sprintf("%s %d %d\n", admin_cache[i].id,
                          admin_cache[i].level, admin_cache[i].day));

    fclose(fh);
}

static void Admin_CachePut(string id, float level) {
    float today = Admin_Today();
    float i = Admin_CacheFind(id);

    if (i >= 0 && admin_cache[i].level == level && admin_cache[i].day == today)
        return;   // nothing a later read would see differently

    if (i < 0) {
        if (admin_cache_n < kAdminCacheMax)
            i = admin_cache_n++;
        else {
            // Full: lose the row that has gone longest without confirmation.
            i = 0;
            for (float j = 1; j < admin_cache_n; j++)
                if (admin_cache[j].day < admin_cache[i].day)
                    i = j;
        }
    }

    admin_cache[i].id = id;
    admin_cache[i].level = level;
    admin_cache[i].day = today;

    Admin_CacheSave();
}

// Called from WorldSpawnPost.  Progs globals are reset on a map change, so this
// file is the only thing that carries a level across one.
void Admin_LoadCache() {
    admin_cache_n = 0;

    float fh = fopen(kAdminCacheFile, FILE_READ);
    if (fh < 0)
        return;   // nothing cached yet, which is not an error

    for (string ln = fgets(fh); ln; ln = fgets(fh)) {
        if (admin_cache_n >= kAdminCacheMax)
            break;

        // Three fields or it is not a row: a short line read as one would cache
        // a level of zero against whatever the first word happened to be.
        tokenizebyseparator(strtrim(ln), " ");
        if (argv(0) == "" || argv(1) == "" || argv(2) == "")
            continue;

        admin_cache[admin_cache_n].id = argv(0);
        admin_cache[admin_cache_n].level = stof(argv(1));
        admin_cache[admin_cache_n].day = stof(argv(2));
        admin_cache_n++;
    }

    fclose(fh);

    dprint(sprintf("admin: %d cached level(s)\n", admin_cache_n));
}

// --- what a player is worth ------------------------------------------------

// What a command is tested against, or kAdminUnknown when the player is logged
// in and nobody has ever asked the site about them.  Guessing on their behalf
// would be a command run at a level nobody has established.
float Admin_Level(entity player) {
    if (player.tfl_id == "")
        return kAdminNone;

    float i = Admin_CacheFind(player.tfl_id);

    return i < 0 ? kAdminUnknown : admin_cache[i].level;
}

// --- what a command is worth -----------------------------------------------

float Pug_Active();   // ssqc/pug.qc

// A game people are in the middle of.  A pug knows its own phases, so any of
// them but off and finished counts.  Quad has no such state to read: a round is
// live while it is not in prematch, and round_over is what distinguishes the
// gap between two rounds -- both of which are still a game -- from the prematch
// before the first one.  That leans on prematch being entered at map start,
// which is InitPrematch's job and needs "localinfo clan on" -- as every quad
// config sets.  Without it an idle quad server would read as mid-game.
static float Admin_GameInProgress() {
    if (pugmode)
        return Pug_Active();

    return quadmode && (!cb_prematch || round_over);
}

typedef struct {
    string name;
    float level;    // what it takes on an idle server
    float ingame;   // what it takes while a pug or quad is on
} AdminCmd;

// Anything not named here needs kAdminAll.  quit costs more mid-game than it
// does idle: ending the server then ends the game for everyone in it, so it
// stops being the thing the level below the top exists to do.
static const AdminCmd admin_cmds[] = {
//   name      idle         in a game
    {"map",    kAdminMap,   kAdminMap},
    {"quit",   kAdminQuit,  kAdminAll},
};

static float Admin_CmdRow(string cmd) {
    for (float i = 0; i < admin_cmds.length; i++)
        if (admin_cmds[i].name == cmd)
            return i;

    return -1;
}

static float Admin_NeedFor(float row, float ingame) {
    if (row < 0)
        return kAdminAll;

    return ingame ? admin_cmds[row].ingame : admin_cmds[row].level;
}

// For the announce, which happens when they arrive rather than mid-game, so it
// is the idle column that describes what they have.
static string Admin_CmdList(float have) {
    if (have >= kAdminAll)
        return "anything";

    string list = "", sep = "";

    for (float i = 0; i < admin_cmds.length; i++)
        if (admin_cmds[i].level <= have) {
            list = strcat(list, sep, admin_cmds[i].name);
            sep = ", ";
        }

    return list;
}

// --- telling them, and keeping them current --------------------------------

// Everything that follows from knowing what a player is worth: the in-game
// admin flag the menus, votes and kick commands read, and -- when the level has
// gone up -- a line telling them so.
//
// is_admin is level 1 or better, the same bar as being able to change the map.
// It is deliberately not read back when ruling on rcon: rights come from the
// level, and letting them round-trip through is_admin would quietly promote the
// bottom tier to the top one.
//
// rcon_password is set for them rather than asked for.  The engine will not
// send an rcon at all while it is empty, and the value does not matter -- it is
// wrong either way, which is exactly what routes the command through
// SV_RconCommand instead of running it unchecked.
void Admin_ApplyLevel(entity player) {
    float have = Admin_Level(player);

    if (have == kAdminUnknown)
        return;   // nothing established yet, so nothing to revise

    player.is_admin = have >= kAdminMap;

    if (have <= kAdminNone || have == player.admin_announced)
        return;

    player.admin_announced = have;

    sprint(player, PRINT_HIGH, sprintf("[You have access to rcon {%s}]\n",
                                       Admin_CmdList(have)));
    stuffcmd(player, "rcon_password live\n");
}

// Fire and forget.  The reply is filed against the id asked about rather than
// whoever holds the slot when it lands, so a disconnect in between updates the
// right row instead of the wrong one.
void Admin_Resync(entity player) {
    if (player.tfl_id == "" || time < player.admin_resync_at)
        return;

    player.admin_resync_at = time + kAdminResyncWait;
    player.admin_level_for = player.tfl_id;

    // uri_post files the callback against whatever self is now, and
    // SV_RconCommand runs with self as world.  Say who this is for rather than
    // depending on the caller to have it set.
    entity oself = self;
    self = player;
    WEB_AdminLevelRequest(player);
    self = oself;
}

// Login is the other place a lookup starts, and only for someone the cache has
// never heard of: the gate should not be the first thing that goes and finds
// out.  A level already good enough to act on is good enough to log in with, so
// anyone cached is left for a command to recheck.
void Admin_PrimeLevel(entity player) {
    if (player.tfl_id == "")
        return;

    if (Admin_CacheFind(player.tfl_id) >= 0) {
        Admin_ApplyLevel(player);
        return;
    }

    Admin_Resync(player);
}

// Refusals always, since being short of the level asked for is what someone
// just granted rights looks like.  Otherwise only once the cached level has
// gone a few days unconfirmed -- an admin using the gate all evening should not
// be asking the site every time.
static float Admin_WorthResync(entity player, float refused) {
    if (refused)
        return TRUE;

    float i = Admin_CacheFind(player.tfl_id);

    return i < 0 || Admin_Today() - admin_cache[i].day > kAdminResyncDays;
}

// The site replies "<games> <level>" as plain text, the way /api/login replies
// with a bare token: there is no JSON reader in here and two numbers do not
// warrant one.  A failure needs no handling: the cache already answered.
void Admin_LevelResponse(entity player, float responsecode, string body) {
    if (responsecode || player.admin_level_for == "")
        return;

    tokenizebyseparator(body, " ");
    Admin_CachePut(player.admin_level_for,
                   Admin_LevelFrom(stof(argv(0)), stof(argv(1))));

    // Only tell them if the slot is still the player we asked about.  The row
    // itself is filed either way, under the id asked about: for that to be the
    // wrong row, the player would have to disconnect, the slot be taken, and
    // the new one log in, all inside one round trip -- and their next command
    // resyncs it anyway.
    if (player.tfl_id == player.admin_level_for)
        Admin_ApplyLevel(player);
}

// --- the gate --------------------------------------------------------------

// The engine hook: one command of a player's rcon, already split out of the
// line and expanded, asked about before it runs.  TRUE runs it.
float SV_RconCommand(string ip, string command, entity requester) {
    // Only reachable with a requester -- an rcon carrying the real password
    // never asks -- but there would be nothing to judge without one.
    if (requester == world)
        return TRUE;

    tokenizebyseparator(command, " ");

    // Lowercased only to pick the level: the console does not care about the
    // case of a command name, so neither should the table that gates it.
    string cmd = strtolower(argv(0));

    float ingame = Admin_GameInProgress();
    float row = Admin_CmdRow(cmd);
    float need = Admin_NeedFor(row, ingame);
    float have = Admin_Level(requester);
    float refused = have < need;   // kAdminUnknown is short of every command

    if (Admin_WorthResync(requester, refused))
        Admin_Resync(requester);

    if (have == kAdminUnknown) {
        sprint(requester, PRINT_HIGH,
               "rcon: looking up your admin level, try that again in a moment\n");
        return FALSE;
    }

    if (refused) {
        // Say which of the two it is.  "Needs a level you do not have" and "is
        // not something anyone does mid-game" are different problems, and only
        // one of them is worth waiting out.
        if (row >= 0 && ingame && need > admin_cmds[row].level)
            sprint(requester, PRINT_HIGH,
                   sprintf("rcon: \"%s\" is not allowed while a game is on\n",
                           cmd));
        else
            sprint(requester, PRINT_HIGH,
                   sprintf("rcon: \"%s\" needs level %d, you are %d\n",
                           cmd, need, have));
        return FALSE;
    }

    // The gated commands are worth announcing in full -- everyone wants to know
    // who changed the map.  A kAdminAll command is not: "everything" includes
    // setting a password, and the server console is where that belongs.  Prints
    // from in here go to that console, not back down the rcon.
    bprint(PRINT_HIGH, requester.netname, " (rcon): ",
           need < kAdminAll ? command : cmd, "\n");
    print(requester.netname, " (rcon): ", command, "\n");

    return TRUE;
}
