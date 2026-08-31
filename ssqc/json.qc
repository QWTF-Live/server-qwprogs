static string GetEndpoint(string type) {
    return strcat(tfl_endpoint, "/api/", type);
}

// Latched by the first scoreboard query.  Until something is actually polling
// us there is no consumer for events, so there is no point building or
// retaining them.  This replaces the old config-plus-init-handshake gate, which
// could leave the endpoint silently empty on a server whose announcer had never
// been configured.
static float scoreboard_active;

inline float ScoreboardActive() { return scoreboard_active; }

enum {
    KV_S,
    KV_I,
};

struct KeyVal {
    int type;
    string key;
    string val;
};

string JSON_Wrap(int n, KeyVal* key_vals) {
    string result = "{ ";
    int last = n - 1;
    for (int i = 0; i < n; i++) {
        result = strcat(result, " \"", key_vals[i].key,"\":");
        if (key_vals[i].type == KV_S)
            result = strcat(result, "\"", key_vals[i].val, "\"");
        else
            result = strcat(result, key_vals[i].val);

        if (i < last)
            result = strcat(result, ", ");
    }
    result = strcat(result, " }");
    return result;
}

static string JSON_Array(int n, string* arr) {
    string result = "[", comma = "";
    for (int i = 0; i < n; i++)
        if (arr[i] != string_null) {
            result = strcat(result, comma, arr[i]);
            comma = ", ";
        }

    return strcat(result, "]");
}

// Escapes a string for embedding in a JSON string literal.
//
// Player names are attacker-controlled, so a lone `"` or `\\` is not cosmetic --
// it breaks the document and lets a player inject arbitrary JSON structure.
// This escapes rather than deletes: clearString() strips these characters
// outright, but that is a filename sanitiser (see its use for MVD names in
// clan.qc) and mangles legitimate names.
//
// Output is pure printable ASCII, so it is always valid UTF-8 and therefore
// always a valid JSON string; anything else becomes a \uXXXX escape.
static string JSON_Escape(string s) {
    float n = strlen(s);

    // Fast path: most names need nothing, and the loop below costs a tempstring
    // per character.
    float needs = FALSE;
    for (float i = 0; i < n; i++) {
        float c = str2chr(s, i);
        if (c == '"' || c == '\\' || c < 0x20 || c > 0x7E) {
            needs = TRUE;
            break;
        }
    }
    if (!needs)
        return s;

    string result = "";
    for (float i = 0; i < n; i++) {
        float c = str2chr(s, i);

        if (c == '"')
            result = strcat(result, "\\\"");
        else if (c == '\\')
            result = strcat(result, "\\\\");
        else if (c >= 0x20 && c <= 0x7E)
            result = strcat(result, chr2str(c));
        else if (c > 0 && c <= 0xFFFF)
            result = strcat(result, sprintf("\\u%04x", c));
        // else: unpaired surrogate or out of BMP -- drop it.
    }

    return result;
}

static inline string JSON_Name(entity player) {
    // strdecolorize flattens markup; strconv maps the Quake red/brown charset
    // back to plain characters (0 = leave case alone, unlike clearString).
    return JSON_Escape(strconv(0, 1, 1, strdecolorize(player.netname)));
}

// Builds the scoreboard as a JSON array of the real (non-bot) players.  Pure --
// no transport, no side effects -- so it can be called straight from the HTTP
// handler below on whatever frame the request lands in.
//
// Note the separator is a *leading* comma tracked across the loop rather than
// `i + 1 == count`: entries are skipped for non-real clients, so keying the
// comma off the loop index emits a trailing one whenever the last entity in
// the list is a bot, producing malformed JSON.
static string JSON_Scoreboard() {
    int count;
    entity* list = find_list(classname, "player", EV_STRING, count);

    string result = "[", comma = "";

    for (int i = 0; i < count; i++) {
        entity p = list[i];

        if (clienttype(p) != CLIENTTYPE_REAL)
            continue;

        KeyVal kvs[] = {
                        {KV_S, "name", JSON_Name(p)},
                        // Empty when not logged in (tfl_username is string_null
                        // then, and strcat flattens that to "").  Escaped like
                        // the name: it originates outside the server.
                        {KV_S, "login", JSON_Escape(p.tfl_username)},
                        {KV_I, "team", ftos(p.team_no)},
                        {KV_I, "pc", ftos(p.playerclass)},
                        {KV_I, "kills", ftos(p.kills)},
                        {KV_I, "deaths", ftos(p.deaths)},
                        {KV_I, "dmgg", ftos(p.damagegiven)},
                        {KV_I, "dmgt", ftos(p.damagetaken)},
                        {KV_I, "caps", ftos(p.caps)},
                        {KV_I, "touches", ftos(p.touches)}
                       };

        result = strcat(result, comma, JSON_Wrap(kvs.length, kvs));
        comma = ",";
    }

    return strcat(result, "]");
}

// Events are produced at arbitrary points in a frame and drained by the HTTP
// handler, potentially many frames later.  No strzone() needed: FTE keeps
// tempstrings alive while they are still referenced
// (FTE_QC_PERSISTENTTEMPSTRINGS), so holding one in a global array is enough.
#define ANNOUNCE_EVENT_MAX 16

static string announce_events[ANNOUNCE_EVENT_MAX];
static int announce_event_next;   // slot to write next
static int announce_event_count;  // live entries, saturating at the ring size

static void AnnounceEventPush(string json) {
    // An empty entry would consume a slot -- and, on a full ring, evict a real
    // event -- while contributing nothing to the drained array.  Nothing in
    // AnnounceEvent() can construct one (the payload is anchored by literal
    // text), so this guards against a caller added later, and against the
    // string having been emptied before it reaches us.
    if (json == string_null || json == "")
        return;

    announce_events[announce_event_next] = json;
    announce_event_next = (announce_event_next + 1) % ANNOUNCE_EVENT_MAX;

    // Saturates rather than growing: once full, the assignment above has
    // already overwritten the oldest entry.
    if (announce_event_count < ANNOUNCE_EVENT_MAX)
        announce_event_count++;
}

// Drains the ring into a JSON array, oldest first, and empties it.  Events are
// delivered exactly once, so a second reader sees only what arrived since the
// first one drained.
static string AnnounceEventDrain() {
    string result = "[", comma = "";

    int start = (announce_event_next - announce_event_count + ANNOUNCE_EVENT_MAX)
                % ANNOUNCE_EVENT_MAX;

    for (int i = 0; i < announce_event_count; i++) {
        int idx = (start + i) % ANNOUNCE_EVENT_MAX;

        string ev = announce_events[idx];
        announce_events[idx] = string_null;  // release for GC

        // The separator is advanced only when something is actually appended.
        // Keying it off the loop index instead would emit a comma for an empty
        // slot, closing the array as ",]" -- malformed.  A slot should never be
        // empty here, so this is belt and braces, but the failure mode is a
        // broken document for every consumer rather than one missing event.
        if (ev == string_null || ev == "")
            continue;

        result = strcat(result, comma, ev);
        comma = ",";
    }

    announce_event_count = 0;
    announce_event_next = 0;

    return strcat(result, "]");
}

// Scoreboard is pulled, not pushed: the engine calls this for requests on its
// HTTP listener (operator needs sv_port_tcp set and net_enable_http on).
//
// Contract per fteextensions.qc: return __NULL__ to let the engine handle the
// request normally, "" for a 404, any other string for a 200.  Anything that
// isn't a GET for our path is passed through untouched so we don't shadow
// whatever else the listener is serving.
const string kScoreboardURI = "scoreboard";

// The engine is inconsistent about the leading slash (its own file-server
// fallback reports the path with it stripped), and may append a query string.
// Normalise both away before matching.
static string HTTP_Path(string uri) {
    if (substring(uri, 0, 1) == "/")
        uri = substring(uri, 1, -1);

    float q = strstrofs(uri, "?");
    if (q >= 0)
        uri = substring(uri, 0, q);

    return uri;
}

string (string uri, string method, string postdata,
        __in string requestheaders,
        __inout string responseheaders) HTTP_GeneratePage = {
    if (method != "GET" || HTTP_Path(uri) != kScoreboardURI)
        return __NULL__;

    scoreboard_active = TRUE;
    responseheaders = strcat(responseheaders, "Content-Type: application/json\n");

    // Built into locals rather than nested in the strcat() argument list so the
    // order of evaluation is explicit and neither half is a pending argument
    // while the other one allocates.
    //
    // Note the drain empties the event ring, so this response is not idempotent
    // -- each event is handed to exactly one reader.
    string players = JSON_Scoreboard();
    string events  = AnnounceEventDrain();

    return strcat("{ \"players\": ", players, ", \"events\": ", events, " }");
};

// Buffered for the scoreboard endpoint rather than posted, and only once
// something has read that endpoint -- see ScoreboardActive().
void AnnounceEvent(string event, entity player = __NULL__) {
    if (!ScoreboardActive())
        return;

    KeyVal kvs[] = {
        {KV_S, "type", event},
        {KV_I, "time", ftos(time)},
        {KV_I, "round_start", ftos(round_start_time)},
        {KV_S, "team1score", ftos(team1score)},
        {KV_S, "team2score", ftos(team2score)},
     };

    string data = strcat("{ \"event\": ", JSON_Wrap(kvs.length, kvs));

    if (player) {
        KeyVal pkvs[] = {
            {KV_S, "name", JSON_Name(player)},
            {KV_I, "team", ftos(player.team_no)},
            {KV_I, "pc", ftos(player.playerclass)},
        };
        data = strcat(data, ", \"player\": ", JSON_Wrap(pkvs.length, pkvs));
    }

    data = strcat(data, "}");

    AnnounceEventPush(data);
}

void InitAnnounce() {
    localcmd("net_enable_http 1\n");
    localcmd("serverinfo has_announce 1\n");
}

string FO_GetUserSettingString(entity ent, string ps_short, string ps_setting,
                               string ps_default);
float TeamFortress_TeamGetScore(float tno);

enum {
    kReportStart,
    kReportHalftime,
    kReportEnd,
};

string MvdName(float include_ext);
float (float tno) TeamFortress_TeamGetNoPlayersExcludingAllTime;

void ReportMatchResult(int report_type) {
    static float last_state = -1;

    // Conditions on reporting the start so we don't need to externally filter.
    if (report_type > kReportStart && last_state == -1)
        return;
    last_state = report_type;

    if (report_type == kReportStart)
        is_small_game = TeamFortress_TeamGetNoPlayersExcludingAllTime(1) == 2;

    int count;
    entity* list = find_list(classname, "player", EV_STRING, count);

    string players[2], comma[2];
    int tsize[2];
    players[0] = players[1] = comma[0] = comma[1] = string_null;
    tsize[0] = tsize[1] = 0;

    for (int i = 0; i < count; i++) {
        entity p = list[i];
        if (p.all_time != ALL_TIME_COLOUR || p.team_no < 1 || p.team_no > 2)
            continue;

        KeyVal pvs[] = {
            {KV_S, "username", p.tfl_username},
            {KV_S, "fo_token", infokey(p, "_fo_token")},
            {KV_I, "pc", ftos(p.playerclass)},
        };

        int idx = p.team_no - 1;
        players[idx] = strcat(players[idx], comma[idx], JSON_Wrap(pvs.length, pvs));
        comma[idx] = ", ";
        tsize[idx]++;
    }

    static string last_players[2];
    static int last_tsize[2];

    for (int i = 0; i < 2; i++) {
        if (report_type == kReportEnd)
            if (tsize[i] < last_tsize[i])
                players[i] = last_players[i];
        last_players[i] = players[i];
        last_tsize[i] = tsize[i];
    }

    string teams[2];
    for (int i = 0; i < 2; i++) {
        KeyVal tvs[] = {
            {KV_I, "score", ftos(TeamFortress_TeamGetScore(i+1))},
            {KV_I, "players", strcat("[", players[i], "]")},
        };

        teams[i] = JSON_Wrap(tvs.length, tvs);
    }

    string rtype_string = "unknown";
    switch(report_type) {
        case kReportStart: rtype_string = "start"; break;
        case kReportHalftime: rtype_string = "round"; break;
        case kReportEnd: rtype_string = "end"; break;
    }

    KeyVal fvs[] = {
        {KV_S, "server_name", infokey(world, "hostname")},
        {KV_S, "server_address", cvar_string("sv_serverip")},
        {KV_S, "region", infokey(world, "tfl_region")},
        {KV_S, "shard", infokey(world, "shard")},
        {KV_S, "game_token", game_token},
        {KV_S, "report_type", rtype_string},
        {KV_S, "map", mapname},
        {KV_I, "teams", JSON_Array(2, teams)},
        {KV_S, "mvd", MvdName(TRUE)},
        {KV_I, "round_start", ftos(round_start_time)},
        {KV_I, "round_end", ftos(time)},
    };

    string req = JSON_Wrap(fvs.length, fvs);
    dprint("Reporting to qwtf-live: ", req, "\n");

    string req = JSON_Wrap(fvs.length, fvs);
    uri_post(GetEndpoint("report"), TFL_RESULT, "application/json", req);
}

void WEB_MigrateLoginRequest(entity player) {
    KeyVal fvs[] = {
        {KV_S, "type", "migrate"},
        {KV_S, "fo_login", player.old_fo_login},
        {KV_S, "fo_token", player.old_fo_token},
    };

    string req = JSON_Wrap(fvs.length, fvs);
    uri_post(GetEndpoint("login"), LOGIN_REQUEST, "application/json", req);
}

void WEB_CheckLoginRequest(entity player, string token) {
    KeyVal fvs[] = {
        {KV_S, "type", "check"},
        {KV_S, "token", token},
    };

    string req = JSON_Wrap(fvs.length, fvs);
    uri_post(GetEndpoint("login"), LOGIN_REQUEST, "application/json", req);
}

enumflags {
    kCheckLoginFromWeb,
    kCheckLoginDbg,
};

float TFL_CheckLogin(string token, float flags = 0);
void UpdateClient_SetLoginToken(entity player, string token);

void(float reqid, float responsecode, string resourcebody, int resourcebytes) URI_Get_Callback = {
    local float success = !responsecode;

    switch(reqid) {
        case TFL_RESULT:
            break;

        case LOGIN_REQUEST:
            self.tfl_need_login = FALSE;
            if (responsecode)
                return;

            string token = resourcebody;
            // Note: In the case of a migration, we have no original raw token.
            if ((token != self.tfl_raw_token) && TFL_CheckLogin(token, kCheckLoginFromWeb))
                UpdateClient_SetLoginToken(self, resourcebody);
            break;
    }
}
