static string livebot_hook = "https://discord.com/api/webhooks/1221561643801120778/rQvCiclJ4gvi1UXi16EZCZooAZnhE8mfEhEYJvciNYGrQQ8rS8U1-TsV1sAZFX1F-nl5";
static var string announce_endpoint;
static var float announce_ready;

static string GetEndpoint(string type) {
    return strcat(tfl_endpoint, "/api/", type);
}

float AnnounceActive() {
    if (!announce_ready)
        return FALSE;

    return use_announcer;
}

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

static inline string JSON_Name(entity player) {
    return uri_escape(strdecolorize(player.netname));
}

static void AnnounceScoreboard() {
    int count;
    entity* list = find_list(classname, "player", EV_STRING, count);

    string result = "[";

    for (int i = 0; i < count; i++) {
        entity p = list[i];

        if (clienttype(p) != CLIENTTYPE_REAL)
            continue;

        KeyVal kvs[] = {
                        {KV_S, "name", JSON_Name(p)},
                        {KV_I, "team", ftos(p.team_no)},
                        {KV_I, "pc", ftos(p.playerclass)},
                        {KV_I, "kills", ftos(p.kills)},
                        {KV_I, "deaths", ftos(p.deaths)},
                        {KV_I, "dmgg", ftos(p.damagegiven)},
                        {KV_I, "dmgt", ftos(p.damagetaken)},
                        {KV_I, "caps", ftos(p.caps)},
                        {KV_I, "touches", ftos(p.touches)}
                       };

        result = strcat(result, JSON_Wrap(kvs.length, kvs),
                        i + 1 == count ? "" : ",");

    }

    result = strcat(result, "]");

    uri_post(GetEndpoint("scoreboard"), TFL_ANNOUNCE, "application/json", result);
}

void AnnounceEvent(string event, entity player = __NULL__) {
    if (!AnnounceActive())
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


    uri_post(GetEndpoint("event"), TFL_ANNOUNCE, "application/json", data);
}

void AnnounceHeartbeat() {
    if (!AnnounceActive())
        return;

    KeyVal kvs[] = {
                    {KV_S, "map", mapname},
                    {KV_S, "servername", serverkey("hostname")},
                    {KV_I, "time", ftos(time)},
                    {KV_I, "round_start", ftos(round_start_time)},
                    {KV_I, "org_game", ftos(org_game)},
                    {KV_I, "team1score", ftos(team1score)},
                    {KV_I, "team2score", ftos(team2score)},
                   };

    string data = JSON_Wrap(kvs.length, kvs);
    uri_post(GetEndpoint("heartbeat"), TFL_ANNOUNCE, "application/json", data);
}

void AnnounceUpdate() {
    if (!AnnounceActive())
        return;

    static float next_heartbeat;
    if (time > next_heartbeat) {
        next_heartbeat = time + 5;

        AnnounceHeartbeat();
        return;
    }

    static float next_scoreboard;
    if (time > next_scoreboard) {
        next_scoreboard = time + 10;

        AnnounceScoreboard();
        return;
    }
}

void InitAnnounce() {
    /* if (!use_announcer) */
    /*     return; */

    string shard = infokey(world, "shard");
    if (shard == string_null)
        shard = "dev";

    announce_endpoint = strcat("http://localhost:9292/", shard, "/");
    uri_post(strcat(announce_endpoint, "init"), TFL_ANNOUNCE, "application/json", "hello");
}

void InitAnnounceResult(float response) {
    if (!response)
        announce_ready = TRUE;
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
    players[0] = players[1] = comma[0] = comma[1] = string_null;

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
        case TFL_ANNOUNCE:
            InitAnnounceResult(responsecode);
            break;
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
