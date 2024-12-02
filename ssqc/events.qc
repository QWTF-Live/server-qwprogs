string (string text) clearString;
string (float tno) GetTeamName;

float (entity player) isPlayerValid = {
    if (player.has_disconnected == 1 
            || !infokey(player, INFOKEY_P_USERID)
            || infokey(player, INFOKEY_P_USERID) == ""
            || !infokey(player, INFOKEY_P_NAME) 
            || infokey(player, INFOKEY_P_NAME) == "") {
        return 0;
    }
    return 1;
}

string () ISOTimemillis = {
    string padding = string_null;
    string timeuse = strftime(0,"%Y-%m-%dT%H:%M:%S.");
    float randmillis = rint((random()*1000*random()));
    if (randmillis < 10)
        padding = "00";
    else if (randmillis < 100)
        padding = "0";
    string padded = strcat(padding, ftos(randmillis));
    timeuse = strcat(timeuse, padded);
    timeuse = strcat(timeuse, "Z");
    return timeuse;
}

string (entity pl) getEntityNameOrLogin = {
    if (login_required)
        return pl.tfl_username;
    else
        return clearString(pl.netname);
}

void (string evt) logevent = {
    string st = infokey (world, "event_debug");
    if (stof(st) > 0)
        bprint(PRINT_HIGH, evt, "\n");
    fputs(logfilehandle, evt);
}


.float logged_start;
void LogEventPlayerStart(entity player) {
    if (canlog == 0)
        return;
    if (isPlayerValid(player) == FALSE)
        return;
    if (player.logged_start)
        return;
    player.logged_start = TRUE;

    KeyVal kvs[] = {
        {KV_I, "time", gametime_string},
        {KV_S, "type", "playerStart"},
        {KV_S, "player", getEntityNameOrLogin(player)},
        {KV_I, "playerClass", ftos(player.playerclass)},
    };

    string event = strcat(JSON_Wrap(kvs.length, kvs), ",\n");
    logevent(event);
}

void () LogEventGameStart = {
    if (canlog == 0)
        return;
    entity player;
    float numplayers = 0;
    player = find (world, classname, "player");

    while (player) {
        if (isPlayerValid(player) == TRUE)
            numplayers++;
        player = find (player, classname, "player");
    }

    KeyVal kvs[] = {
        {KV_I, "time", gametime_string},
        {KV_S, "type", "gameStart"},
        {KV_S, "wall_time", ISOTimemillis()},
        {KV_S, "map", mapname},
        {KV_I, "numPlayers", ftos(numplayers)},
        {KV_I, "numTeams", ftos(number_of_teams)},
        {KV_S, "demo", cvar_string("server_demo")},
        {KV_I, "time", gametime_string},
        {KV_S, "gameToken", game_token},
        {KV_S, "server_name", infokey(world, "hostname")},
        {KV_S, "server_address", cvar_string("sv_serverip")},
        {KV_S, "region", infokey(world, "tfl_region")},
        {KV_S, "shard", infokey(world, "shard")},
        {KV_S, "mvd", MvdName(TRUE)},
    };

    string event = strcat("[\n", JSON_Wrap(kvs.length, kvs), ",\n");
    logevent(event);
}

void LogEventRoundStart() {
    if (canlog == 0)
        return;

    KeyVal kvs[] = {
        {KV_I, "time", gametime_string},
        {KV_S, "type", "roundStart"},
    };

    string event = strcat(JSON_Wrap(kvs.length, kvs), ",\n");
    logevent(event);
}

void (entity player, float previous, float next, float timeplayed) LogEventChangeClass = {
    if (canlog == 0)
        return;
    if (isPlayerValid(player) == FALSE)
        return;
    if (previous == 0)
        return;

    KeyVal kvs[] = {
        {KV_I, "time", gametime_string},
        {KV_S, "type", "changeClass"},
        {KV_S, "player", getEntityNameOrLogin(player)},
        {KV_I, "playerClass", ftos(previous)},
        {KV_I, "nextClass", ftos(next)},
        {KV_I, "team", ftos(player.team_no)},
        {KV_I, "timePlayed", ftos(timeplayed)},
    };

    string event = strcat(JSON_Wrap(kvs.length, kvs), ",\n");
    logevent(event);
}

string (float weapon) GetWeaponName = {
    if (weapon >= 1 && weapon <= WEAP_LAST) {
        string name = FO_GetWeapName(weapon);
        name = strtolower(name);
        name = strreplace(" ", "", name);
        return name;
    }

    return "undefined";
}

void (entity attacker, entity target, string afflictionType) LogAffliction = {
    if (attacker.classname == "player" && target.classname == "player") {
        if (attacker.team_no == target.team_no)
            attacker.afflicted = attacker.afflicted + 1;
        else
            attacker.teamafflicted = attacker.teamafflicted + 1;
    }
}

void (entity attacker, entity target, entity inflictor, float damage, float truedam) LogEventDamage = {
    if (!cb_prematch) {
        entity realattacker = attacker;
        if (attacker.classname == "building_sentrygun" || attacker.classname == "building_dispenser")
            realattacker = attacker.real_owner;

        if (realattacker.team_no != target.team_no) {
            if (realattacker != target && realattacker != target.real_owner) {
                if (realattacker.classname == "player" && (target.classname == "player" || target.classname == "building_sentrygun"))
                    realattacker.damagegiven = realattacker.damagegiven + truedam;

                if (target.classname == "player")
                    target.damagetaken = target.damagetaken + truedam;
            }
        }
    }

    if (canlog == 0)
        return;

    string damageKind;
    string attackername;
    string targetname;
    string inflictorId;

    attackername = getEntityNameOrLogin(attacker);
    targetname = getEntityNameOrLogin(target);
    if (attacker == target)
        damageKind = "self";
    else if (attacker.team_no == target.team_no)
        damageKind = "team";
    else
        damageKind = "enemy";


    if (inflictor.classname == "player") {
        inflictorId = GetWeaponName(FO_PlayerCurrentWeapon(attacker));
    } else {
        inflictorId = inflictor.classname;
        if ((inflictor.classname == "spike") && (attacker.playerclass == 3))
            inflictorId = "nailgrenspike";
        else if ((inflictor.classname == "spike") && (attacker.playerclass == 5))
            inflictorId = "superspike";

        if (inflictorId == "worldspawn") {
            attackername = "world";
        } else if (inflictorId == "building_sentrygun") {
            attackername = getEntityNameOrLogin(attacker.real_owner);
            if (damageKind == "damageTeam")
                return;
        }
        else if (inflictorId == "grenade" && inflictor.fpp.gren_type >= GREN_FIRST)
            inflictorId = FO_GrenDesc(inflictor.fpp.gren_type)->logname;
    }

    KeyVal kvs[] = {
        {KV_I, "time", gametime_string},
        {KV_S, "type", "damageDone"},
        {KV_S, "kind", damageKind},
        {KV_S, "player", attackername},
        {KV_I, "playerClass", ftos(attacker.playerclass)},
        {KV_I, "playerTeam", ftos(attacker.team_no)},
        {KV_S, "target", getEntityNameOrLogin(target)},
        {KV_I, "targetClass", ftos(target.playerclass)},
        {KV_I, "targetTeam", ftos(target.team_no)},
        {KV_S, "inflictor", inflictorId},
        {KV_I, "damage", ftos(truedam)},
    };

    string event = strcat(JSON_Wrap(kvs.length, kvs), ",\n");
    logevent(event);
}

void (entity attacker, entity target, entity inflictor) LogEventKill = {
    if (!cb_prematch) {
        entity realattacker = attacker;
        if (attacker.classname == "building_sentrygun" || attacker.classname == "building_dispenser")
            realattacker = attacker.real_owner;

        if (realattacker.classname == "player" && (target.classname == "player" || target.classname == "building_sentrygun")) {
            if (realattacker != target && realattacker != target.real_owner)
            {
                if (realattacker.team_no == target.team_no)
                    realattacker.sbteamkills = realattacker.sbteamkills + 1;
                else
                    realattacker.kills = realattacker.kills + 1;
            }

            target.deaths = target.deaths + 1;
        }
    }

    if (canlog == 0)
        return;

    if ((target.classname != "player") && (target.classname != "building_sentrygun"))
        return;

    string killKind;
    string attackername;
    string targetname;
    string inflictorId;

    attackername = getEntityNameOrLogin(attacker);
    targetname = getEntityNameOrLogin(target);
    if (attacker == target)
        killKind = "self";
    else if (attacker.team_no == target.team_no)
        killKind = "team";
    else
        killKind = "enemy";

    if (inflictor.classname == "player") {
        inflictorId = GetWeaponName(FO_PlayerCurrentWeapon(attacker));
    } else {
        inflictorId = inflictor.classname;
        if ((inflictor.classname == "spike") && (attacker.playerclass == 3)) {
            inflictorId = "nailgrenspike";
        }
        else if ((inflictor.classname == "spike") && (attacker.playerclass == 5)) {
            inflictorId = "superspike";
        }

        if (inflictorId == "worldspawn")
            attackername = "world";
        else if (inflictorId == "building_sentrygun")
            attackername = getEntityNameOrLogin(attacker.real_owner);
        else if (inflictorId == "grenade" && inflictor.fpp.gren_type >= GREN_FIRST)
            inflictorId = FO_GrenDesc(inflictor.fpp.gren_type)->logname;
    }

    KeyVal kvs[] = {
        {KV_I, "time", gametime_string},
        {KV_S, "type", "kill"},
        {KV_S, "kind", killKind},
        {KV_S, "player", attackername},
        {KV_I, "playerClass", ftos(attacker.playerclass)},
        {KV_I, "playerTeam", ftos(attacker.team_no)},
        {KV_S, "target", targetname},
        {KV_I, "targetClass", ftos(target.playerclass)},
        {KV_I, "targetTeam", ftos(target.team_no)},
        {KV_S, "inflictor", inflictorId},
    };

    string event = strcat(JSON_Wrap(kvs.length, kvs), ",\n");
    logevent(event);
}

void (entity attacker, entity target, float tfstate) LogEventAffliction = {
    if (attacker != target) {
        if (attacker.team_no == target.team_no)
            attacker.teamafflicted = attacker.teamafflicted + 1;
        else
            attacker.afflicted = attacker.afflicted + 1;
    }
};

void (entity player) LogEventGoal = {
    flag_update = 1;
    if(player == world)
        return;

    player.caps = player.caps + 1;
    AnnounceEvent("capture", player);

    if (canlog == 0)
        return;

    KeyVal kvs[] = {
        {KV_I, "time", gametime_string},
        {KV_S, "type", "goal"},
        {KV_I, "team", ftos(player.team_no)},
        {KV_S, "player", getEntityNameOrLogin(player)},
        {KV_I, "playerClass", ftos(player.playerclass)},
    };

    string event = strcat(JSON_Wrap(kvs.length, kvs), ",\n");
    logevent(event);
}


void (entity player) LogEventPickupGoal = {
    flag_update = 1;
    player.touches = player.touches + 1;
    if (canlog == 0)
        return;

    KeyVal kvs[] = {
        {KV_I, "time", gametime_string},
        {KV_S, "type", "pickup"},
        {KV_S, "team", ftos(player.team_no)},
        {KV_S, "player", getEntityNameOrLogin(player)},
        {KV_I, "playerClass", ftos(player.playerclass)},
    };

    string event = strcat(JSON_Wrap(kvs.length, kvs), ",\n");
    logevent(event);
}

void (entity player, float timecarried) LogEventFumble = {
    flag_update = 1;
    if (canlog == 0)
        return;

    KeyVal kvs[] = {
        {KV_I, "time", gametime_string},
        {KV_S, "type", "fumble"},
        {KV_I, "team", ftos(player.team_no)},
        {KV_S, "player", getEntityNameOrLogin(player)},
        {KV_I, "playerClass", ftos(player.playerclass)},
        {KV_I, "timeCarried", ftos(timecarried)},
    };

    string event = strcat(JSON_Wrap(kvs.length, kvs), ",\n");
    logevent(event);
}

void (entity attacker) LogEventAttack = {
    if (canlog == 0)
        return;

    KeyVal kvs[] = {
        {KV_I, "time", gametime_string},
        {KV_S, "type", "attack"},
        {KV_S, "player", getEntityNameOrLogin(attacker)},
        {KV_I, "playerClass", ftos(attacker.playerclass)},
        {KV_S, "inflictor", GetWeaponName(FO_PlayerCurrentWeapon(attacker))},
    };

    string event = strcat(JSON_Wrap(kvs.length, kvs), ",\n");
    logevent(event);
}

void () LogEventGameEnd = {
    if (canlog == 0)
        return;

    KeyVal kvs[] = {
        {KV_I, "time", gametime_string},
        {KV_S, "type", "gameEnd"},
        {KV_S, "wall_time", ISOTimemillis()},
    };

    string event = strcat(JSON_Wrap(kvs.length, kvs), "\n]");
    logevent(event);
}

void () LogEventTeamScores = {
    float win_score = 0;
    float winning_team = 0;

    if (team1score > win_score) {
        win_score = team1score;
        winning_team = 1;
    }

    if (team2score > win_score) {
        win_score = team2score;
        winning_team = 2;
    } else if (team2score == win_score) {
        winning_team = 0;
    }

    if (team3score > win_score) {
        win_score = team3score;
        winning_team = 3;
    } else if (team3score == win_score) {
        winning_team = 0;
    }

    if (team4score > win_score) {
        win_score = team4score;
        winning_team = 4;
    } else if (team4score == win_score) {
        winning_team = 0;
    }

    KeyVal kvs[] = {
        {KV_I, "time", gametime_string},
        {KV_S, "type", "teamScores"},
        {KV_I, "winningTeam", ftos(winning_team)},
        {KV_I, "numTeams", ftos(number_of_teams)},
        {KV_I, "team1Score", ftos(team1score)},
        {KV_I, "team2Score", ftos(team2score)},
        {KV_I, "team3Score", ftos(team2score)},
        {KV_I, "team4Score", ftos(team2score)},
    };

    string event = strcat(JSON_Wrap(kvs.length, kvs), ",\n");
    logevent(event);
}
