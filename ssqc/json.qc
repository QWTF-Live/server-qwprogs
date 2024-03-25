static string livebot_hook = "https://discord.com/api/webhooks/1221561643801120778/rQvCiclJ4gvi1UXi16EZCZooAZnhE8mfEhEYJvciNYGrQQ8rS8U1-TsV1sAZFX1F-nl5";

struct KeyVal {
    string key;
    string val;
};

static string JSON_Wrap(int n, KeyVal* key_vals, string embeds = "") {
    float has_embeds = embeds != "" ? 1 : 0;
    int last = n - !has_embeds;
    string result = "{\n";
    for (int i = 0; i < n; i++) {
        result = strcat(result, " \"", key_vals[i].key,"\": \"",
                                        key_vals[i].val, "\"",
                                        i < last ? ",\n" : "\n");
    }
    if (has_embeds) {
        result = strcat(result, "  \"embeds\": [ {\n", embeds, "\n} ]\n");
    }
    result = strcat(result, "}\n");
    return result;
}

static string to_mins(float t) {
    float m = t / 60;
    float s = t % 60;

    return sprintf("%02d:%02d", m, s);
}

struct TeamString { string code[2]; };

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

void LiveBotPostAnnounce(string message) {
    KeyVal kvs[] = {{"content", message}};
    string data = JSON_Wrap(kvs.length, kvs);
    uri_post(livebot_hook, FO_ANNOUNCE_REQUEST, "application/json", data);
}

struct FieldCol {
    string name;
    int inl;
    string values;
};

static void InitFieldCol(FieldCol* col, string name, int inl) {
    col->name = name;
    col->inl = inl;
    col->values = "";
}

static void AddRow(FieldCol* col, string row) {
    if (col->values == "")
        col->values = row;
    else
        col->values = strcat(col->values, "\\n",row);
}

static string RenderFieldCol(FieldCol* col, float last = FALSE) {
    string result = strcat("{\"name\": \"", col->name, "\",");
    if (col->inl)
        result = strcat(result, "\"inline\":true,");
    result = strcat(result, "\"value\": \"", col->values, "\"}",
                    last ? "" : ",\n");
    return result;
}

string RenderScoreBoardField() {
    FieldCol rnd1, red[4], blue[4];

    InitFieldCol(&rnd1, "Round 1", TRUE);
    InitFieldCol(&blue[0], "Blue", FALSE);
    InitFieldCol(&blue[1], "K/D", TRUE);
    InitFieldCol(&blue[2], "DMG", TRUE);

    int count;
    entity* list = find_list(classname, "player", EV_STRING, count);
    for (int i = 0; i < count; i++) {
        entity p = list[i];
        FieldCol* t = p.team_no == 1 ? blue : red;
        AddRow(&t[0], strcat(to_icon(p.team_no, p.playerclass), p.netname));
        AddRow(&t[1], sprintf("%d/%d", p.kills, p.deaths));
        AddRow(&t[2], ftos(p.damagegiven));
    }

    string result = strcat(RenderFieldCol(&rnd1),
                           RenderFieldCol(&blue[0]),
                           RenderFieldCol(&blue[1]),
                           RenderFieldCol(&blue[2], TRUE));

    return result;
}

string EmbedFields(string embed) {
    return strcat("\"fields\": [\n", embed, "\n]");
}


void AnnounceScoreboard() {
    static float next;
    if (time < next)
        return;
    next = time + 5;

    string msg = sprintf("Scoreboard: %s", mapname);
    KeyVal kvs[] = {{"content", msg}};
    string data = JSON_Wrap(kvs.length, kvs, EmbedFields(RenderScoreBoardField()));
    uri_post(strcat(livebot_hook,"?wait=true"), 6, "application/json", data);
}

static var float announce_active;
float AnnounceActive() {
    if (!use_announcer)
        return FALSE;

    if (!org_game || time < round_start_time)
        return FALSE;

    return announce_active;
}

enum {
    AN_GAME_START,
    AN_ROUND_END,
    AN_GAME_END,
};

void AnnounceEvent(float ev) {
    string msg = "";
    switch (ev) {
        case AN_GAME_START:
            msg = sprintf("### %s: game started on %s", serverkey("hostname"), mapname);
            announce_active = TRUE;
            break;
        case AN_ROUND_END:
            msg = sprintf("### Round 1: %s %s %d - %s %d", msg,
                    flag_icon(1), team1score, flag_icon(2), team2score);
            break;
        case AN_GAME_END:
            if (team1score == team2score)
                msg = "Draw!";
            else
                msg = (team1score > team2score) ? "Blue wins!" : "Red wins!";

            msg = sprintf("### %s: %s %s %d - %s %d", serverkey("hostname"), msg,
                    flag_icon(1), team1score, flag_icon(2), team2score);
            break;
    }

    if (msg != "" && AnnounceActive())
        LiveBotPostAnnounce(msg);
}

void AnnounceCapture(entity player) {
    if (!AnnounceActive())
        return;

    float captured = player.team_no == 1 ? 1 : 0;
    string suffix[] = {
        strcat(" captured the ", flag_icon(1), " flag!"),
        strcat(" captured the ", flag_icon(2), " flag!"),
    };

    string p_s = strcat(to_icon(player.team_no, player.playerclass), " ",
                        player.netname);
    p_s = strcat(p_s, suffix[captured]);

    string msg = sprintf("[%s] %s (Score: %d - %d)",
            to_mins(time - round_start_time), p_s, team1score, team2score);

    LiveBotPostAnnounce(msg);
}
