static string livebot_hook = "https://discord.com/api/webhooks/1221561643801120778/rQvCiclJ4gvi1UXi16EZCZooAZnhE8mfEhEYJvciNYGrQQ8rS8U1-TsV1sAZFX1F-nl5";
static var string announce_endpoint;
static var float announce_ready;

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

static string JSON_Wrap(int n, KeyVal* key_vals, string embeds = "") {
    float has_embeds = embeds != "" ? 1 : 0;
    int last = n - !has_embeds;
    string result = "{\n";
    for (int i = 0; i < n; i++) {
        result = strcat(result, " \"", key_vals[i].key,"\":");
        if (key_vals[i].type == KV_S)
            result = strcat(result, "\"", key_vals[i].val, "\"");
        else
            result = strcat(result, key_vals[i].val);

        result = strcat(result, i < last ? ",\n" : "\n");
    }
    if (has_embeds) {
        result = strcat(result, "  \"embeds\": [ {\n", embeds, "\n} ]\n");
    }
    result = strcat(result, "}\n");
    return result;
}

static inline string JSON_Name(entity player) {
    return strdecolorize(player.netname);
}

static void AnnounceScoreboard() {
    int count;
    entity* list = find_list(classname, "player", EV_STRING, count);

    string result = "[";

    for (int i = 0; i < count; i++) {
        entity p = list[i];
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

    uri_post(strcat(announce_endpoint, "scoreboard"), FO_ANNOUNCE,
            "application/json", result);
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


    uri_post(strcat(announce_endpoint, "event"), FO_ANNOUNCE,
             "application/json", data);
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
    uri_post(strcat(announce_endpoint, "heartbeat"), FO_ANNOUNCE, "application/json", data);
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
    uri_post(strcat(announce_endpoint, "init"), FO_ANNOUNCE, "application/json", "hello");
}

void InitAnnounceResult(float response) {
    if (!response)
        announce_ready = TRUE;
}

#if 0
static string blank_icon = "<:blank:1221574759720943708>";

static string flag_icon(float team_no) {
    string icons[] = {
        "<:flag_1:1221574798514192434>",
        "<:flag_2:1221574954831839283>",
        "<:flag_3:1221574795280384110>",
        "<:flag_4:1221574953975943200>",
    };

    return icons[team_no - 1];
}

static string to_icon(float team_no, float class_no) {
    TeamString icons[] = {
        {{"<:scout_blue:1221574792264548403>", "<:scout_red:1221575126982721626>"}},
        {{"<:sniper_blue:1221574788460576899>", "<:sniper_red:1221575128132092032>"}},
        {{"<:soldier_blue:1221574785314717777>", "<:soldier_red:1221575129436389487>"}},
        {{"<:demoman_blue:1221574782227710002>", "<:demoman_red:1221575454377508904>"}},
        {{"<:medic_blue:1221574771616124929>", "<:medic_red:1221574769661444188>"}},
        {{"<:hwguy_blue:1221574778096189501>", "<:hwguy_red:1221575455778541649>"}},
        {{"<:pyro_blue:1221574774375841805>", "<:pyro_red:1221575457795739731>"}},
        {{"<:spy_blue:1221574768856273057>", "<:spy_red:1221574765697957918>"}},
        {{"<:engineer_blue:1221574764422893588>", "<:engineer_red:1221574763198021683>"}},
    };
    if ((class_no < 1 || class_no > icons.length) ||
        (team_no < 1 || team_no > 2))
        return blank_icon;
    else
        return icons[class_no - 1].code[team_no - 1];
}
#endif
