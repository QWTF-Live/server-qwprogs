void ParseSBAR();
CsGrenTimer ParseGrenPrimed(float grentype, float explodes_at,
                            float timer_flags = 0);
void ParseHitFlag(vector targpos, float mitdmg, float rawdmg, float hitflag);														 
float StartGrenTimer(float primed_at, float expires_at, float grentype, float play_sound);
float FoLogin(string token, float print_error);
void Hud_CenterPrint(string msg);

void() CSQC_Parse_Event = {
    float msgtype = readbyte();
    local float goalno;
    entity te;

    switch (msgtype) {
        case MSG_PREDICTSTATE:
            TFL_RecvPredictState();
            break;

        case MSG_TFL_CONFIG:
            TFL_ReceiveConfig();
            break;

        case MSG_FLAGINFOINIT:
            float index = readfloat();
            goalno = readfloat();
            string mdl = readstring();
            float skinindex = readfloat();
            float ownerteam = readfloat();
            float iconindex = readfloat();

            //use next available
            if(index < 0) {
                for (float i = 0; i < FlagInfoLines.length; i++) {
                    if (FlagInfoLines[i].id == 0 || FlagInfoLines[i].id == goalno) {
                        index = i;
                        break;
                    }
                }
            }
            if (index >= 0 && index < MAX_FLAGINFO_LINES) {
                FlagInfoLines[index].id = goalno;
                FlagInfoLines[index].team_no = ownerteam;
                if (mdl)
                    precache_model(mdl);
                te = spawn();
                te.renderflags = RF_VIEWMODEL | RF_DEPTHHACK | RF_NOSHADOW;
                te.skin = skinindex;
                te.owned_by = ownerteam;

                string iconname = "sb_key1";
                vector iconcolour = '1 1 1';
                if (iconindex == FLAGINFO_ICON_FLAG) {
                    iconname = strcat("flag_", ftos(ownerteam));
                    iconcolour = '1 1 1';
                } else if (iconindex == FLAGINFO_ICON_BUTTON) {
                    iconname = strcat("off_icon_glow_", ftos(ownerteam));
                    iconcolour = '1 1 1';
                }
                FlagInfoLines[index].icon.filename = iconname;
                FlagInfoLines[index].icon.colour = iconcolour;
                FlagInfoLines[index].model = te;
            }
            break;
        case MSG_FLAGINFO:
            goalno = readfloat();
            float state = readfloat();
            float time_return = -1;
            vector droploc = '0 0 0';
            string carrier = "";
            string locname = "";
            switch (state) {
                case FLAGINFO_HOME:
                    break;
                case FLAGINFO_CARRIED:
                    carrier = readstring();

                    float is_self = carrier ==
                        getplayerkeyvalue(player_localentnum - 1, INFOKEY_P_NAME);
                    break;
                case FLAGINFO_DROPPED:
                    time_return = readfloat();
                    float showloc = readfloat();
                    if (showloc == FLAGINFO_LOCATION) {
                        droploc_x = readcoord();
                        droploc_y = readcoord();
                        droploc_z = readcoord();
                        locname = readstring();
                    }
                    break;
                case FLAGINFO_RETURNING:
                    break;
            }
            for (float i = 0; i < FlagInfoLines.length; i++) {
                FlagInfoLine* fil = &FlagInfoLines[i];
                if (fil->id != goalno)
                    continue;

                fil->time_return = time_return;
                fil->state = state;
                fil->loc = droploc;
                string prev_carrier = fil->carrier;
                fil->carrier = carrier;
                fil->locname = locname;

#if 0
                string message = "";
                float team_flag = team_no == i + 1;
                string name = getplayerkeyvalue(player_localentnum - 1, INFOKEY_P_NAME);
                float self = (carrier == name || prev_carrier == name);

                switch (state) {
                    case FLAGINFO_CARRIED:
                        carrier = strdecolorize(carrier);
                        if (self)
                            message = "^2You have the enemy flag!";
                        else if (team_flag)
                            message = sprintf("^1%s took your flag!", carrier);
                        else
                            message = sprintf("^x595%s took the enemy flag!", carrier);
                        break;
                    case FLAGINFO_DROPPED:
                        carrier = strdecolorize(carrier);
                        if (self)
                            message = "^1You dropped the enemy flag!";
                        else if (team_flag)
                            message = sprintf("^2%s dropped your flag!", prev_carrier);
                        else
                            message = sprintf("^3%s dropped the enemy flag!", prev_carrier);
                        break;
                    case FLAGINFO_RETURNING:
                        message = "XXX";
                        break;
                    case FLAGINFO_HOME:
                        if (team_flag)
                            message = "^2Your flag returned!";
                        else
                            message = "^1The enemy flag is returning!";
                        break;
                }

                if (message)
                    Hud_CenterPrint(message);
#endif
                break;
            }
            break;
        case MSG_SBAR:
            ParseSBAR();
            break;
        case MSG_ID:
            id_state.id_time = time;
            id_state.spawn_gen = game_state.spawn_gen;
            SBAR.Identify = readstring();
            break;
        case MSG_GRENPRIMED:
            float entno = readentitynum();
            float grentype = readbyte();
            float explodes_at = readfloat();
            break;
        case MSG_GRENTHROWN:
            float entno = readentitynum();
            break;
        case MSG_TFX_GRENTIMER:
            float entnum = readentitynum();
            float explodes_at = readfloat();
            TFxGrenTimerUpdate(entnum, explodes_at);
            break;
        case MSG_HITFLAG:
            vector targpos;
            targpos_x = readcoord();
            targpos_y = readcoord();
            targpos_z = readcoord();
            float mitdmg = readshort();
            float rawdmg = readshort();
            float hitflag = readshort();
            ParseHitFlag(targpos, mitdmg, rawdmg, hitflag);
            break;
        case MSG_CLIENT_MENU:
            float menutype = readfloat();
            switch (menutype) {
                case CLIENT_MENU_TEAM:
                    number_of_teams = readfloat();
                    for(float i = 0; i < 4; i++) {
                        if(i < number_of_teams) {
                            FO_MENU_TEAM.options[i].value = ftos(readbyte());
                            FO_MENU_TEAM.options[i].state = FO_MENU_STATE_NORMAL;
                        } else {
                            FO_MENU_TEAM.options[i].state = FO_MENU_STATE_DISABLED;
                        }
                    }

                    if(SBAR.GameMode & GAMEMODE_QUAD) {
                        switch (getstatf(STAT_ALL_TIME)) {
                            case ALL_TIME_ATTACK:
                                FO_MENU_TEAM.options[6].state = FO_MENU_STATE_DISABLED;
                                FO_MENU_TEAM.options[7].state = FO_MENU_STATE_NORMAL;
                                break;
                            case ALL_TIME_DEFENCE:
                                FO_MENU_TEAM.options[6].state = FO_MENU_STATE_NORMAL;
                                FO_MENU_TEAM.options[7].state = FO_MENU_STATE_DISABLED;
                                break;
                            default:
                                FO_MENU_TEAM.options[6].state = FO_MENU_STATE_NORMAL;
                                FO_MENU_TEAM.options[7].state = FO_MENU_STATE_NORMAL;
                        }
                    } else {
                        FO_MENU_TEAM.options[6].state = FO_MENU_STATE_DISABLED;
                        FO_MENU_TEAM.options[7].state = FO_MENU_STATE_DISABLED;
                    }
                    TF_Menu_Team(2);
                    break;
                case CLIENT_MENU_CLASS:
                    TF_Menu_Class(2);
                    break;
                case CLIENT_MENU_DROPAMMO:
                    TF_Menu_DropAmmo(FALSE);
                    break;
                case CLIENT_MENU_SCOUT:
                    float scanner_on = readbyte();
                    float scanner_flags = readfloat();

                    TF_Menu_Scout(2, scanner_on, scanner_flags);
                    break;
                case CLIENT_MENU_SPY:
                    last_selected_skin = readfloat();
                    last_team = readfloat();
                    TF_Menu_Spy(2);
                    break;
                case CLIENT_MENU_SPY_SKIN:
                    TF_Menu_Spy_Skin(2);
                    break;
                case CLIENT_MENU_SPY_TEAM:
                    TF_Menu_Spy_Team(FALSE);
                    break;
                case CLIENT_MENU_DETPACK:
                    TF_Menu_Detpack(2, readbyte());
                    break;
                case CLIENT_MENU_BUILD:
                    TF_Menu_Build(2);
                    break;
                case CLIENT_MENU_ROTATE_SENTRY:
                    TF_Menu_Rotate_Sentry(FALSE);
                    break;
                case CLIENT_MENU_FIX_DISPENSER:
                    TF_Menu_Dispenser_Fix(FALSE, readbyte());
                    break;
                case CLIENT_MENU_USE_DISPENSER:
                    touched_dispenser_pos = [readfloat(),readfloat(),readfloat()];
                    TF_Menu_Dispenser_Use(FALSE);
                    break;
                case CLIENT_MENU_ADMIN:
                    TF_Menu_Admin_Main(TRUE);
                    break;
                case CLIENT_MENU_ADMIN_KICK:
                    TF_Menu_Admin_Players(TRUE, CLIENT_MENU_ADMIN_KICK, 0);
                    break;
                case CLIENT_MENU_VOTE:
                    mapvote_expiry = time + readfloat();
                    FO_MENU_VOTE.options[0].name = readstring();
                    FO_MENU_VOTE.options[0].value = ftos(readfloat());
                    FO_MENU_VOTE.options[1].name = readstring();
                    FO_MENU_VOTE.options[1].value = ftos(readfloat());
                    FO_MENU_VOTE.options[2].name = readstring();
                    FO_MENU_VOTE.options[2].value = ftos(readfloat());
                    FO_MENU_VOTE.options[3].name = readstring();
                    FO_MENU_VOTE.options[3].value = ftos(readfloat());
                    FO_MENU_VOTE.options[5].name = readstring();
                    FO_MENU_VOTE.options[5].value = ftos(readfloat());
                    TF_Menu_Vote(FALSE);
                    break;
                case CLIENT_MENU_CAPTAIN_PICK:
                    TF_Menu_Admin_Players(TRUE, CLIENT_MENU_CAPTAIN_PICK, 0);
                    break;
                case CLIENT_MENU_MAPS:
                    showVoteMenu(!getHudPanel(HUDP_MAP_MENU)->Display);
                    break;
            }
            break;
        case MSG_CLASSES_UPDATE:
            float civonly = readbyte();
            for(float i = 0; i < 10; i++) {
                if(civonly) {
                    FO_MENU_CLASS.options[i].value = "-";
                    if(fo_hud_menu_active && CurrentMenu == &FO_MENU_CLASS) {
                        Menu_Cancel();
                    }
                } else {
                    float class_max = readfloat();
                    if(class_max < 0) {
                        FO_MENU_CLASS.options[i].value = "-";
                        FO_MENU_CLASS.options[i].state = FO_MENU_STATE_DISABLED;
                    } else {
                        FO_MENU_CLASS.options[i].value = strcat(ftos(readbyte()),"/",ftos(class_max));
                        FO_MENU_CLASS.options[i].state = FO_MENU_STATE_NORMAL;
                    }
                }
            }

            break;
        case MSG_SENTRY_POS:
            sentry_pos = [readfloat(),readfloat(),readfloat()];
            break;
        case MSG_DISPENSER_POS:
            dispenser_pos = [readfloat(),readfloat(),readfloat()];
            dispenser_angles = [readangle(),readangle(),readangle()];

            makevectors(dispenser_angles);
            dispenser_render_pos = dispenser_pos + v_forward * 16 + v_up * 32;
            break;
        case MSG_SERVER_ADMIN_INFO:
            is_admin = TRUE;
            SERVER_ADMIN.ceasefire = readbyte();
            SERVER_ADMIN.quad_rounds = readfloat();
            SERVER_ADMIN.quad_round_time = readfloat();
            SERVER_ADMIN.login_required = readfloat();
            SERVER_ADMIN.timelimit = readfloat();
            SERVER_ADMIN.fraglimit = readfloat();
            SERVER_ADMIN.clanmode = readfloat();
            SERVER_ADMIN.quadmode = readfloat();
            SERVER_ADMIN.duelmode = readfloat();
            SERVER_ADMIN.new_balance = readfloat();
            SERVER_ADMIN.pubmode =  (((SERVER_ADMIN.clanmode & 1) || (SERVER_ADMIN.quadmode & 1) || (SERVER_ADMIN.duelmode & 1))?1:0) + 
                                    (((SERVER_ADMIN.clanmode & 2) || (SERVER_ADMIN.quadmode & 2) || (SERVER_ADMIN.duelmode & 2))?2:0);
            SERVER_ADMIN.pubmode = 3 - SERVER_ADMIN.pubmode; //Invert
            SERVER_ADMIN.captainmode = readfloat();
            break;
        case MSG_CAPTAINS:
            captain1 = readfloat();
            captain2 = readfloat();
            break;
        case MSG_MOTD:
            SBAR.MOTD = strcat(readstring(), "\n", readstring());
            SBAR.GameMode = readfloat();
            SBAR.CountdownStarted = FALSE;
            motd_expiry = time + MOTD_TIME;
            quad_rounds_total = readfloat();
            number_of_teams = readfloat();
            break;
        case MSG_PREMATCH:
            prematch = readbyte();
            round_active = readbyte();
            round_over = readbyte();
            SBAR.CountdownStarted = readbyte();
            //SBAR.GameMode = SBAR.GameMode - (SBAR.GameMode & 8) + ((prematch & 1)?8:0);
            //SBAR.GameMode = SBAR.GameMode - (SBAR.GameMode & 16) + ((prematch & 2)?16:0);
            //SBAR.GameMode = SBAR.GameMode - (SBAR.GameMode & 32) + ((prematch & 4)?32:0);
            //motd_expiry = time + MOTD_TIME;
            quad_round = readfloat();
            //game_started = readbyte();
            local float rtr = readfloat();
            if(rtr) {
                round_ending = time + rtr;
            }
            FO_Hud_ShowPanel(HUDP_MOTD);
            break;
        case MSG_QUAD_ROUND_BEGIN:
            break;
        case MSG_NEXT_END_TIME:
            // Inject external time for demo_jump
            pengine.next_end_time = readfloat();
            break;
        case MSG_TEAM_SCORES:
            TeamScore[0] = readfloat();
            TeamScore[1] = readfloat();
            TeamScore[2] = readfloat();
            TeamScore[3] = readfloat();
            break;
        case MSG_VOTE_UPDATE:
            te = AddVoteMap(readstring(), "","",0,0,0,FALSE);
            te.votecount = readfloat();
            if(readbyte()) {
                current_vote = te;
            } else {
                if(current_vote == te) {
                    current_vote = world;
                }
            }
            break;
        case MSG_VOTE_MAP_ADD:
            te = AddVoteMap(readstring(), readstring(), readstring(), readfloat(), readfloat(), readfloat(), FALSE);
            te.votecount = readfloat();
            if(readbyte()) {
                current_vote = te;
            } else {
                if(current_vote == te) {
                    current_vote = world;
                }
            }
            break;
        case MSG_VOTE_MAP_DELETE:
            RemoveVoteMap(readstring(), FALSE);
            break;
        case MSG_PAUSE:
            CsGrenTimer::SyncPause();
            break;
        case MSG_UNPAUSE:
            CsGrenTimer::SyncUnpause();
            break;
        case MSG_CACHE_LOGIN:
            string login = readstring();
            string nonce = readstring();

            localcmd("setinfo ", kLoginKey, " ", login, "\n");
            localcmd("setinfo ", kLoginNonce, " ", nonce, "\n");

            printf("Local cache of login credentials complete\n");
            break;
        case MSG_MIGRATE_LOGIN:
            printf("%sLogin saved.\n", kQWTF);
            Config.login_token = readstring();
            TFL_SaveConfig();
            break;

        case MSG_SOUND:
            float stime, vol, chan, targ;
            vector org;
            string samp;

            stime = readfloat();
            targ  = readentitynum();
            org_x = readcoord();
            org_y = readcoord();
            org_z = readcoord();
            samp  = readstring();
            chan  = readfloat();
            vol   = readfloat();

            Predictable_Sound(stime, targ, samp, chan, org, vol);
            break;
        case MSG_MENU_CANCEL:
            Menu_Cancel();
            break;
    }
}

string cached_timer;
string GetGrenTimerSound() {
    string wav = CVARS(fo_grentimersound);

    if (cached_timer != wav) {
        precache_sound(wav);
        cached_timer = wav;
    }
    return wav;
}

static float GrenTimerVolume() {
    if (game_state.is_spectator && CVARF(fo_spec_grentimervolume) != -1)
        return CVARF(fo_spec_grentimervolume);
    return CVARF(fo_grentimervolume);
}

void CsGrenTimer::StartSound() {
    if !(this.flags_ & FL_GT_SOUND)
        return;

    string wav = GetGrenTimerSound();

    // Note there's a bug where soundupdate returns false for a new sample, even
    // though it's started.
    soundupdate(this, CHAN_VOICE, wav, GrenTimerVolume(), 0, 0, 0, sound_offset());
    this.playing_ = TRUE;
}

void CsGrenTimer::Set(float expires_at, float _grentype, float timer_flags) {
    grentype_ = _grentype;
    raw_expires_at_ = expires_at_ = expires_at;
    flags_ = timer_flags;
    playing_ = FALSE;

    if (this.flags_ & FL_GT_ADJPING) {
        float rtt = pstate_pred.client_ping * CVARF(fo_grentimer_ping_frac);
        if (RewindFlagEnabled(REWIND_GRENADES))
            rtt = max(0, rtt - (100 + FO_RewindGrenMs(_grentype)));
        expires_at_ -= rtt / 1000;
    }

    if (!CVARF(fo_grentimer_nostack))
        StartSound();
    else
        UpdateSoundStack();
}

void CsGrenTimer::Stop() {
    raw_expires_at_ = -1;
    expires_at_ = -1;
    PauseSound();  // Pause is really stop.
    flags_ = 0;
}

void StopGrenTimers() {
    // New style.
    for (float i = 0; i < NUM_GREN_TIMERS; i++)
        grentimers[i].Stop();
}

CsGrenTimer ParseGrenPrimed(float grentype, float explodes_at,
                            float timer_flags = 0) {
    if (grentype == GREN_FLARE || grentype == GREN_CALTROP)
        return world;

    float timer_mode = CVARF(fo_grentimer);
    switch (timer_mode) {
        case 0: break;
        case 1: timer_flags = FL_GT_SOUND; break;
        // 2 [and something sane for anything we don't recognize.]
        default: timer_flags |= FL_GT_SOUND | FL_GT_ADJPING; break;
    }

    if (game_state.is_spectator)
        timer_flags &= ~FL_GT_ADJPING;

    float debug_print_state = CVARF(fo_grentimer_debug) & 1;

    CsGrenTimer timer = CsGrenTimer::GetNext();
    timer.Set(explodes_at, grentype, timer_flags);

    if (debug_print_state) {
        float ping = getplayerkeyfloat(player_localnum, INFOKEY_P_PING) / 1000;

        float expires_at = timer.expiry();

        print(sprintf("expires_at=%0.2f explodes_at=%0.2f\n", expires_at, explodes_at));
    }

    return timer;
}
#define HITFLAG(_fl_name) (hitflags & (HITFLAG_##_fl_name))

static void PlayHitSound(float hitflags) {
    float wantsnoarmoursound = CVARF(fo_hitaudio_noarmour);
    float wantshurtselfsound = CVARF(fo_hitaudio_hurtself);
    float wantshurtenemysound = CVARF(fo_hitaudio_hurtenemy);
    float wantshurtteamsound = CVARF(fo_hitaudio_hurtteam);

    float wantskillselfsound = CVARF(fo_hitaudio_killself);
    float wantskillenemysound = CVARF(fo_hitaudio_killenemy);
    float wantskillteamsound = CVARF(fo_hitaudio_killteam);

    string snd = "", snd2 = "";

    if (HITFLAG(SELF)) {
        if (wantshurtselfsound)
            snd = SND_HURTSELF;
        if (wantskillselfsound && HITFLAG(KILLINGBLOW))
            snd2 = SND_KILLSELF;
    } else if (HITFLAG(FRIENDLY)) {
        if (wantshurtteamsound)
            snd = SND_HURTTEAM;
        if (wantskillteamsound && HITFLAG(KILLINGBLOW))
            snd2 = SND_KILLTEAM;
    } else {
        if (wantshurtenemysound)
            snd = HITFLAG(MEATSHOT) ? SND_HURTENEMY_MEATSHOT : SND_HURTENEMY;
        if (wantskillenemysound && HITFLAG(KILLINGBLOW))
            snd2 = SND_KILLENEMY;

        if (HITFLAG(HEADSHOT))
            localsound(SND_HEADSHOT, CHAN_AUTO, 1);
        if (HITFLAG(NOARMOUR) && wantsnoarmoursound)
            localsound(SND_NOARMOUR, CHAN_AUTO, 1);
    }

    if (snd != "")
        localsound(snd, CHAN_AUTO, 1);
    if (snd2 != "")
        localsound(snd2, CHAN_AUTO, 1);
}

void NewHittext(entity hittext);

void ParseHitFlag(vector targpos, float mitdmg, float rawdmg, float hitflags) {
        if (HITFLAG(IMFLASHED))
            return;

        float want_hittext = CVARF(fo_hittext_enabled) && !HITFLAG(NOTEXT);
        float want_hitsound = CVARF(fo_hitaudio_enabled) && !HITFLAG(NOAUDIO);

        if (want_hitsound)
            PlayHitSound(hitflags);

        if (!want_hittext)
            return;

        if (HITFLAG(SELF) ||
            (HITFLAG(FRIENDLY) && !CVARF(fo_hittext_friendly)))
            return;

        entity te = spawn();

        te.hittext_str = ftos((CVARF(fo_hittext_rawdamage)) ?  rawdmg : mitdmg);
        te.classname = CN_HITTEXT;
        te.hittext_expires = time + CVARF(fo_hittext_duration);
        te.hittext_hitflags = hitflags;

        setorigin(te,
                  [targpos_x, targpos_y, targpos_z + CVARF(fo_hittext_offset)]);

        NewHittext(te);
};

#undef HITFLAG

void ParseSBAR()
{
    SBAR.FragStreak = readfloat();
    SBAR.Caps = readfloat();
    float class_info = readfloat();

    switch (class_info)
    {
        case PC_SCOUT:
            SBAR.ScannerOn = readfloat();
            if (SBAR.ScannerOn)
            {
                SBAR.ScannerRange = readfloat();

                if (SBAR.ScannerRange)
                {
                    SBAR.ScannerTeamNo = readfloat();
                    SBAR.ScannerPlayerClass = readfloat();
                    SBAR.ScannerTFItemsFlags = readfloat();
                }
            }
            break;
        case PC_SNIPER:
            SBAR.SniperDam = readfloat();
            break;
        case PC_DEMOMAN:
            SBAR.IsDetpacking = readfloat();
            SBAR.DetpackLeft = readfloat();
            break;
        case PC_MEDIC:
            float medicaura = readfloat();
            if (medicaura)
            {
                SBAR.AuraActive = readfloat();
                if (SBAR.AuraActive)
                {
                    SBAR.HealCount = readfloat();
                    SBAR.HealAmount = readfloat();
                    SBAR.AuraStatus = readfloat();
                }
            }
            break;
        case PC_HVYWEAP:
            break;
        case PC_PYRO:
            break;
        case PC_SPY:
            SBAR.IsUndercover = readfloat();

            if (SBAR.IsUndercover == 1)
            {
                SBAR.UndercoverTeam = readfloat();
                SBAR.UndercoverSkin = readfloat();
            }
            else if (SBAR.IsUndercover == 2)
            {
                SBAR.UndercoverTimer = readfloat();
                SBAR.UndercoverTeam = readfloat();
                SBAR.DisguiseTeam = readfloat();
                SBAR.QueueTeam = readfloat();
                SBAR.UndercoverSkin = readfloat();
                SBAR.DisguiseSkin = readfloat();
                SBAR.QueueSkin = readfloat();
            }
            break;
        case PC_ENGINEER:
            SBAR.IsBuilding = readfloat();
            if (SBAR.IsBuilding)
                SBAR.BuildFinish = readfloat();

            SBAR.HasSentry = readfloat();
            if (SBAR.HasSentry) {
                SBAR.SentryLevel = readfloat();
                SBAR.SentryHealth = readfloat();
                SBAR.SentryAmmoShells = readfloat();
                SBAR.SentryAmmoRockets = readfloat();
            }

            SBAR.HasDispenser = readfloat();
            if (SBAR.HasDispenser) {
                SBAR.DispenserHealth = readfloat();
                SBAR.DispenserCells = readfloat();
            }
            break;
    }
}

float CSQC_Event_Sound(float ent_num, float channel, string soundname,
                       float vol, float attenuation, vector pos,
                       float pitchmod) = {
    return 0;
}
