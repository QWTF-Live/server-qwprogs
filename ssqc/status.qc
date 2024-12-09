float (float tno) TeamFortress_TeamGetScore;
float () TeamFortress_TeamGetWinner;
float () TeamFortress_TeamGetSecond;
string(float num) BlueScoreToString;
string(float num) RedScoreToString;
string(float num) YellowScoreToString;
string(float num) GreenScoreToString;
string(entity pl) DetpackToString;
string(entity pl) AuraToString;
string(entity pl) AssaultCannonToString;
string(entity pl) RangeToString;
string(entity pl) ScannerToString;
string(entity pl) DisguiseToString;
string(entity pl) SentryDetailsToString;
string(float pc) TeamFortress_GetClassName;
entity(float ino) Finditem;
void () tfgoalitem_dropthink;
void () tfgoalitem_remove;
float (entity ent, string ps_short, string ps_setting, string ps_default) FO_GetUserSetting;
entity get_tfdet();

static void PrintStatusMessage(entity pl, string message, float duration) {
    centerprint(pl, message);
    pl.clear_status_message = time + duration;
}

void (entity pl, string...count) Status_Print =
{
    float i;
    string s = "";

    for (float i = 0; i < count; i++)
        s = strcat(s, ...(i, string));

    // no printing while menu open
    if (pl.menu_input)
        return;

    PrintStatusMessage(pl, s, 1);
};

void (entity pl, f_void_float func, string...count) Status_Menu =
{
    float i;
    string s = "";

    for (float i = 0; i < count; i++)
        s = strcat(s, ...(i, string));

    PrintStatusMessage(pl, s, 1);
    pl.menu_input = func;
    pl.impulse = 0;
};

void (entity pl) Status_Refresh =
{
    if (pl.StatusRefreshTime == time)
        return;
    pl.StatusRefreshTime = time;
};

void (entity pl, string s1) CenterPrint = {
    Status_Print(pl, s1);
};

void (entity pl, string s1, string s2) CenterPrint2 = {
    Status_Print(pl, s1, s2);
};

void (entity pl, string s1, string s2, string s3) CenterPrint3 = {
    Status_Print(pl, s1, s2, s3);
};

void (entity pl, string s1, string s2, string s3, string s4) CenterPrint4 = {
    Status_Print(pl, s1, s2, s3, s4);
};

void (entity pl, string s1, string s2, string s3, string s4, string s5) CenterPrint5 = {
    Status_Print(pl, s1, s2, s3, s4, s5);
};

void (entity pl, string s1, string s2, string s3, string s4, string s5, string s6) CenterPrint6 = {
    Status_Print(pl, s1, s2, s3, s4, s5, s6);
};

string getLocationName(vector location);

void (entity Player, float index, entity Item, float icon) InitClientFlagStatus = {
    msg_entity = Player;
    WriteByte(MSG_MULTICAST, SVC_CGAMEPACKET); 
    WriteByte(MSG_MULTICAST, MSG_FLAGINFOINIT);
    WriteFloat(MSG_MULTICAST, index);
    WriteFloat(MSG_MULTICAST, Item.goal_no);
    WriteString(MSG_MULTICAST, Item.mdl);
    WriteFloat(MSG_MULTICAST, Item.skin);
    WriteFloat(MSG_MULTICAST, Item.owned_by);
    WriteFloat(MSG_MULTICAST, icon);

    if (msg_entity != world)
        multicast('0 0 0', MULTICAST_ONE_R_NOSPECS);
    else {
        multicast('0 0 0', MULTICAST_ALL_R);  // For MVD pickup.
    }
}

void (entity Player) InitAllStatuses = {
    entity tfdet = get_tfdet();
    if(tfdet) {
        InitClientFlagStatus(Player, 0, Finditem(tfdet.display_item_status1), FLAGINFO_ICON_FLAG);
        InitClientFlagStatus(Player, 1, Finditem(tfdet.display_item_status2), FLAGINFO_ICON_FLAG);
        InitClientFlagStatus(Player, 2, Finditem(tfdet.display_item_status3), FLAGINFO_ICON_FLAG);
        InitClientFlagStatus(Player, 3, Finditem(tfdet.display_item_status4), FLAGINFO_ICON_FLAG);
    }

    int c;
    entity* goals = find_list(classname, "info_tfgoal", EV_STRING, c);
    for (int i = 0; i < c; i ++) {
        if (goals[i].track_goal)
            InitClientFlagStatus(Player, -1, goals[i], FLAGINFO_ICON_BUTTON);
    }
};

float laststate;
void (entity Goal, entity only) UpdateClientsButtonStatus = {
    WriteByte(MSG_MULTICAST, SVC_CGAMEPACKET);
    WriteByte(MSG_MULTICAST, MSG_FLAGINFO);
    WriteFloat(MSG_MULTICAST, Goal.goal_no);
    if(Goal.goal_no == 11) {
        if(Goal.goal_state != laststate) {
            laststate = Goal.goal_state;
        }
    }
    if(Goal.goal_state == TFGS_DELAYED) {
        WriteFloat(MSG_MULTICAST, FLAGINFO_DROPPED);
        WriteFloat(MSG_MULTICAST, rint(Goal.bubble_count));
        //WriteFloat(MSG_MULTICAST, FLAGINFO_NOLOCATION);
        WriteFloat(MSG_MULTICAST, FLAGINFO_LOCATION);
        WriteCoord(MSG_MULTICAST, Goal.origin_x);
        WriteCoord(MSG_MULTICAST, Goal.origin_y);
        WriteCoord(MSG_MULTICAST, Goal.origin_z);
        //WriteString(MSG_MULTICAST, getLocationName(Item.origin));
        if(Goal.team_str_moved) {
            WriteString(MSG_MULTICAST, Goal.team_str_moved);
        } else {
            WriteString(MSG_MULTICAST,"\sOffline\s");
        }
    } else {
        WriteFloat(MSG_MULTICAST, FLAGINFO_HOME);
    }

    if (only) {
        msg_entity = only;
        multicast('0 0 0', MULTICAST_ONE_R_NOSPECS);
    } else {
        multicast('0 0 0', MULTICAST_ALL_R);
    }
}

void UpdateClientsFlagStatus(entity Item, entity only) {
    WriteByte(MSG_MULTICAST, SVC_CGAMEPACKET);
    WriteByte(MSG_MULTICAST, MSG_FLAGINFO);
    WriteFloat(MSG_MULTICAST, Item.goal_no);
    if (Item.goal_state == 1 && Item.owner != world) {
        WriteFloat(MSG_MULTICAST, FLAGINFO_CARRIED);
        WriteString(MSG_MULTICAST, Item.owner.netname);
    } else {
        if (Item.origin != Item.oldorigin) {
            if((Item.nextthink - time) >= 0) {
                WriteFloat(MSG_MULTICAST, FLAGINFO_DROPPED);
                if(noreturn) {
                    WriteFloat(MSG_MULTICAST, -1);
                } else {
                    WriteFloat(MSG_MULTICAST, rint(Item.bubble_count));
                }
                if ((Item.think == tfgoalitem_dropthink ||
                     Item.think == tfgoalitem_remove) && !Item.owner) {
                    WriteFloat(MSG_MULTICAST, FLAGINFO_LOCATION);
                    WriteCoord(MSG_MULTICAST, Item.origin_x);
                    WriteCoord(MSG_MULTICAST, Item.origin_y);
                    WriteCoord(MSG_MULTICAST, Item.origin_z);
                    WriteString(MSG_MULTICAST, getLocationName(Item.origin));
                } else {
                    WriteFloat(MSG_MULTICAST, FLAGINFO_NOLOCATION);
                }
            } else {
                WriteFloat(MSG_MULTICAST, FLAGINFO_RETURNING);
            }
        } else {
            WriteFloat(MSG_MULTICAST, FLAGINFO_HOME);
        }
    }
    if (only) {
        msg_entity = only;
        multicast('0 0 0', MULTICAST_ONE_R_NOSPECS);
    } else {
        multicast('0 0 0', MULTICAST_ALL_R);
    }
}

string (entity Player, entity Item, float teamno) GetItemStatus = {
    local string st = "";
    switch (teamno)
    {
        case 1:
            st = "Blue Flag";
            break;
        case 2:
            st = "Red Flag";
            break;
        case 3:
            st = "Yellow Flag";
            break;
        case 4:
            st = "Green Flag";
            break;
    }
    if (Player.team_no == Item.owned_by) {
        st = strcat(Q"\x10", st ,Q"\x11");
    }
    if (Item.goal_state == 1 && Item.owner != world) {
        if (Player == Item.owner) {
            st = strcat(st, Q"\s: Carried by \sYOU");
        } else {
            st = strcat(st, Q"\s: Carried by \s", Item.owner.netname);
        }
    } else {
        if (Item.origin != Item.oldorigin) {
            //When the item is thrown, there is a touch think with a pad of 4.25s before the normal timer kicks in
            if((Item.nextthink - time) >= 0) {
                if(!noreturn) {
                    st = strcat(st, Q"\s: Return: \s", ftos(rint(Item.bubble_count - time)));
                } else {
                    st = strcat(st, Q"\s: Dropped\s");
                }
            } else {
                st = strcat(st, Q"\s: Returning\s NOW!");
            }
        } else {
            st = strcat(st, Q"\s: Safe\s");
        }
    }

    return st;
}

void UpdateClientGrenadePrimed(entity pl, float grentype, float explodes_at) = {
#if 0  // Not needed until we re-enable TFX.
    msg_entity = pl;
    WriteByte(MSG_MULTICAST, SVC_CGAMEPACKET);
    WriteByte(MSG_MULTICAST, MSG_GRENPRIMED);
    WriteEntity(MSG_MULTICAST, pl);
    WriteByte(MSG_MULTICAST, grentype);
    WriteFloat(MSG_MULTICAST, explodes_at);

    multicast('0 0 0', MULTICAST_ALL);  // Actual primer has reliable transport.
#endif
}

void UpdateClientGrenadeThrown(entity pl) = {
#if 0  // Not needed until we re-enable TFX.
    msg_entity = pl;
    WriteByte(MSG_MULTICAST, SVC_CGAMEPACKET);
    WriteByte(MSG_MULTICAST, MSG_GRENTHROWN);
    WriteEntity(MSG_MULTICAST, pl);
    multicast('0 0 0', MULTICAST_ALL);
#endif
}

void UpdateClientIDString(entity pl, string ident) {
    msg_entity = pl;
    WriteByte(MSG_MULTICAST, SVC_CGAMEPACKET);
    WriteByte(MSG_MULTICAST, MSG_ID);
    WriteString(MSG_MULTICAST, ident);
    multicast('0 0 0', MULTICAST_ONE);
}

void UpdateClientStatusBar(entity pl)
{
    // if we ever change to fte only, this could be changed to stats
    string msg = "";
    msg_entity = pl;

    WriteByte(MSG_MULTICAST, SVC_CGAMEPACKET); 
    WriteByte(MSG_MULTICAST, MSG_SBAR);
    WriteFloat(MSG_MULTICAST, pl.fragstreak);
    WriteFloat(MSG_MULTICAST, pl.caps);

    WriteFloat(MSG_MULTICAST, pl.playerclass); // just in case we get a packet from "last life" after changing playerclass

    // class info
    switch (pl.playerclass)
    {
        case PC_SCOUT:
            // off, on
            WriteFloat(MSG_MULTICAST, pl.ScannerOn);
            
            if (pl.ScannerOn)
            {
                entity te;
                te = find(world, netname, "scanner");
                while ((te != world) && (te.owner != pl)) {
                    te = find(te, netname, "scanner");
                }
                WriteFloat(MSG_MULTICAST, te.health); // range to person, 0 or less if no one
                if (te.health)
                {
                    WriteFloat(MSG_MULTICAST, te.team_no);
                    WriteFloat(MSG_MULTICAST, te.playerclass);
                    WriteFloat(MSG_MULTICAST, te.tf_items_flags); // nothing, friendly, enemy
                }
            }
            break;
        case PC_SNIPER:
            float dam = pl.heat;
            WriteFloat(MSG_MULTICAST, dam);
            break;
        case PC_DEMOMAN:
            WriteFloat(MSG_MULTICAST, pl.is_detpacking);
            WriteFloat(MSG_MULTICAST, pl.detpack_left);
            break;
        case PC_MEDIC:
            WriteFloat(MSG_MULTICAST, medicaura);

            if (medicaura)
            {
                WriteFloat(MSG_MULTICAST, pl.aura_active);

                if (pl.aura_active) 
                {
                    float c, a;
                    c = (time < pl.aura_healtime) ? pl.aura_healcount : 0;
                    a = (time < pl.aura_healtime) ? pl.aura_healamount : 0;
                    WriteFloat(MSG_MULTICAST, c);
                    WriteFloat(MSG_MULTICAST, a);
                    // state
                    float s = PC_MEDIC_AURA_ACTIVE;
                    if (pl.ammo_cells < ceil(PC_MEDIC_MAXAMMO_CELL / 2))
                    {
                        s = PC_MEDIC_AURA_OUTOFPOWER;
                    }
                    else if (pl.ammo_cells < floor(PC_MEDIC_MAXAMMO_CELL * 0.95))
                    {
                        s = PC_MEDIC_AURA_RECHARGING;
                    }
                    WriteFloat(MSG_MULTICAST, s);
                }
            }
            break;
        case PC_HVYWEAP:
            break;
        case PC_PYRO:
            break;
        case PC_SPY:
            WriteFloat(MSG_MULTICAST, pl.is_undercover);
            
            if (pl.is_undercover == SPY_DISGUISED) {
                WriteFloat(MSG_MULTICAST, pl.undercover_team);
                WriteFloat(MSG_MULTICAST, pl.undercover_skin);
            } else if (pl.is_undercover == SPY_DISGUISING) {
                WriteFloat(MSG_MULTICAST, pl.undercover_timer);
                WriteFloat(MSG_MULTICAST, pl.undercover_team);
                WriteFloat(MSG_MULTICAST, pl.disguise_team);
                WriteFloat(MSG_MULTICAST, pl.queue_team);
                WriteFloat(MSG_MULTICAST, pl.undercover_skin);
                WriteFloat(MSG_MULTICAST, pl.disguise_skin);
                WriteFloat(MSG_MULTICAST, pl.queue_skin);
            }
            break;
        case PC_ENGINEER:
            // building status??
            WriteFloat(MSG_MULTICAST, pl.is_building);
            if (pl.is_building)
                WriteFloat(MSG_MULTICAST, pl.building_finish);

            WriteFloat(MSG_MULTICAST, pl.has_sentry);
            if (pl.has_sentry) {
                WriteFloat(MSG_MULTICAST, pl.sentry_ent.weapon); // level
                WriteFloat(MSG_MULTICAST, pl.sentry_ent.health);
                WriteFloat(MSG_MULTICAST, pl.sentry_ent.ammo_shells);
                WriteFloat(MSG_MULTICAST, pl.sentry_ent.ammo_rockets);
            }

            WriteFloat(MSG_MULTICAST, pl.has_dispenser);
            if (pl.has_dispenser) {
                entity disp;
                disp = find(world, classname, "building_dispenser");
                while (disp) {
                    if (disp.real_owner == pl) {
                        WriteFloat(MSG_MULTICAST, disp.health);
                        WriteFloat(MSG_MULTICAST, disp.ammo_cells);
                        break;
                    }
                    disp = find(disp, classname, "building_dispenser");
                }
            }
            break;
    }

    multicast('0 0 0', MULTICAST_ONE_NOSPECS);
}

void HandleStatusString(entity pl) {
    if (pl.clear_status_message && time > pl.clear_status_message) {
        centerprint(pl, "");
        pl.clear_status_message = 0;
    }
}

void (entity pl) RefreshStatusBar = {
    pl.StatusRefreshTime = time + 1.5;
    if (pl.classname != "observer")
        UpdateClientStatusBar(pl);
};

string(float num) BlueScoreToString =
{
    if (num > 999)
        num = 999;

    return strcat(Q"\sBlue\s:", strpadl(ftos(floor(num)), 3));
};

string(float num) RedScoreToString =
{
    if (num > 999)
        num = 999;

    return strcat(Q"\sRed\s :", strpadl(ftos(floor(num)), 3));
};

string(float num) YellowScoreToString =
{
    if (num > 999)
        num = 999;

    return strcat(Q"\sYell\s:", strpadl(ftos(floor(num)), 3));
};

string(float num) GreenScoreToString =
{
    if (num > 999)
        num = 999;

    return strcat(Q"\sGren\s:", strpadl(ftos(floor(num)), 3));
};

string(entity pl) DisguiseToString =
{
    local string st = "";
    local string skin = "";
    local string team = "";

    if (pl.is_undercover == SPY_DISGUISED) {
        st = Q"\sUndercover\s: ";
        if (pl.undercover_team) {
            st = strcat(st, TeamToString(pl.undercover_team));
            st = strcat(st, " ");
        }
        if (pl.undercover_skin)
            st = strcat(st, ClassToString(pl.undercover_skin));
    } else if (pl.is_undercover == SPY_DISGUISING) {
        if (pl.disguise_team) {
            team = strcat(team, "(");
            team = strcat(team, TeamToString(pl.disguise_team));
            if (!pl.queue_skin)
                team = strcat(team, ") ");
        } else if (pl.queue_team) {
            team = strcat(team, "(");
            team = strcat(team, TeamToString(pl.queue_team));
            team = strcat(team, " ");
        } else if (pl.undercover_team) {
            team = strcat(team, TeamToString(pl.undercover_team));
            team = strcat(team, " ");
        }
        if (pl.disguise_skin) {
            if (!pl.queue_team)
                skin = strcat(skin, "(");
            skin = strcat(skin, ClassToString(pl.disguise_skin));
            skin = strcat(skin, ")");
        } else if (pl.queue_skin) {
            skin = strcat(skin, " ");
            skin = strcat(skin, ClassToString(pl.queue_skin));
            skin = strcat(skin, ")");
        } else if (pl.undercover_skin) {
            skin = strcat(skin, ClassToString(pl.undercover_skin));
        }
        st = Q"\sUndercover\s: ";
        st = strcat(st, team);
        st = strcat(st, skin);
    }

    return st;
};

string(entity pl) DetpackToString =
{
    local string st = "";

    if (pl.is_detpacking) {
        st = Q"\sDetpack\s: ";
        st = strcat(st, ftos(pl.detpack_left));
        st = strcat(st, " (");
        st = strcat(st, ftos(pl.is_detpacking));
        st = strcat(st, ")");
        st = strcat(st, " seconds left");
    } else if (pl.detpack_left) {
        st = Q"\sDetpack\s: ";
        st = strcat(st, ftos(pl.detpack_left));
        st = strcat(st, " seconds left");
    }

    return st;
};

string(entity pl) AuraToString =
{
    local string st;

    if (medicaura) {
        st = Q"\sHealing Aura\s: ";

        if (pl.aura_active) {
            if (time < pl.aura_healtime && pl.aura_healcount) {
                st = strcat(st, ftos(pl.aura_healcount));
                st = strcat(st, " players healed for ");
                st = strcat(st, ftos(pl.aura_healamount));
                st = strcat(st, " hp");
            }
            else if (pl.ammo_cells < ceil(PC_MEDIC_MAXAMMO_CELL / 2))
                st = strcat(st, "out of power");
            else if (pl.ammo_cells < floor(PC_MEDIC_MAXAMMO_CELL * 0.95))
                st = strcat(st, "recharging");
            else
                st = strcat(st, "on");
        } else {
            st = strcat(st, "off");
        }
    } else {
        st = "";
    }

    return st;
};

string(entity pl) AssaultCannonToString =
{
    if (FO_CurrentWeapon() == WEAP_ASSAULT_CANNON && (pl.tfstate & TFSTATE_LOCK))
        return Q"\sAssault Cannon Locked\s";
    else
        return "";
};

string(entity pl) RangeToString =
{
    local entity te;
    local float num;

    if (!pl.ScannerOn) {
        return "";
    }

    te = find(world, netname, "scanner");
    while ((te != world) && (te.owner != pl)) {
        te = find(te, netname, "scanner");
    }

    num = te.health;

    if (num <= 0) {
        return "";
    }

    if (num > 99) {
        return "99+ m";
    }

    return strcat(strpadl(ftos(floor(num)), 3), " m");
};

string(entity pl) ScannerToString =
{
    local entity te;
    local string st = "";
    local string scanfor = "";
    local string range = "";
    local float pad;

    st = Q"\sScanner\s: ";

    if (pl.ScannerOn != TRUE) {
        return strcat(st, "off");
    }

    te = find(world, netname, "scanner");
    while ((te != world) && (te.owner != pl)) {
        te = find(te, netname, "scanner");
    }

    if (te.health > 0) {
        st = strcat(st, TeamToString(te.team_no));
        st = strcat(st, " ");
        st = strcat(st, ClassToString(te.playerclass));
        st = strpadr(st, 26);
        range = Q"\srange\s: ";
        range = strcat(range, RangeToString(pl));
        pad = 40 - strlen(range);
        st = strpadr(st, pad);
        st = strcat(st, range);
    } else {
        st = strcat(st, "on");
        st = strcat(st, Q"  \sScanning\s: ");

        if (self.tf_items_flags & NIT_SCANNER_FRIENDLY) {
            scanfor = "team";
        }

        if (self.tf_items_flags & NIT_SCANNER_ENEMY) {
            if (self.tf_items_flags & NIT_SCANNER_FRIENDLY) {
                scanfor = strcat(scanfor, ", ");
            }

            scanfor = strcat(scanfor, "enemy");
        }

        if (!strlen(scanfor)) {
            scanfor = "nothing";
        }

        st = strcat(st, scanfor);
    }

    return st;
};

string(entity pl) SentryDetailsToString =
{
    local string ammo    = "";
    local string shells  = "";
    local string rockets = "";
    local string hp      = "";
    local string st      = "";

    if (self.has_sentry) {
        hp = strcat(strpadl(ftos(floor(self.sentry_ent.health)), 3), " hp");
        shells = ftos(floor(self.sentry_ent.ammo_shells));

        if (self.sentry_ent.weapon == 3) {
            rockets = ftos(floor(self.sentry_ent.ammo_rockets));
            ammo = strcat(Q"  \sAmmo\s: ", strcat(shells, strcat("/", rockets)));
        } else {
            ammo = strcat(Q"  \sAmmo\s: ", shells);
        }

        st = strcat(Q"\sSentry\s: ", strcat(hp, ammo));
        st = strpadr(st, 32);
        st = strcat(st, strcat(Q"\slevel\s: ", ftos(self.sentry_ent.weapon)));
    }

    return st;
};

void UpdateClient_SetNextEndTime(float next) {
    round_end_time = next;
    WriteByte(MSG_MULTICAST, SVC_CGAMEPACKET);
    WriteByte(MSG_MULTICAST, MSG_NEXT_END_TIME);
    WriteFloat(MSG_MULTICAST, next);
    multicast('0 0 0', MULTICAST_ALL_R);
}

void UpdateClient_SetLoginToken(entity player, string token) {
    msg_entity = player;
    WriteByte(MSG_MULTICAST, SVC_CGAMEPACKET);
    WriteByte(MSG_MULTICAST, MSG_MIGRATE_LOGIN);
    WriteString(MSG_MULTICAST, token);
    multicast('0 0 0', MULTICAST_ONE_R_NOSPECS);
}
