void FO_Hud_Editor();
void Hud_Draw(float width, float height);
void FO_Hud_Editor_LoadSettings(string);
void FO_Hud_Editor_LoadDefaultSettings();
void FO_Hud_Editor_List_Panels();
void FO_Hud_Editor_Print_Panel_Setting(string, string setting);
void FO_Hud_Editor_Set_Panel_Setting(string, string setting, string value);
void Hud_WriteCfg(string path);
void AddGrenTimer(float grentype, float offset);
void StopGrenTimers();
float IsValidToUseGrenades();
void Sync_GameState();
float FoLogin(string token, float print_error);
void Perf_Status();
void FO_Hud_Init();
float InFluid(vector point);
float CalculateWaterLevel();
void RenderHitTexts();

void GetSelf() = {
    self = findfloat(world, entnum, player_localentnum);
}

static void BindAlias(TFAlias* tfa) {
    if (tfa->impulse == 0 && tfa->cmd == "")  // Some aliases are !csqc-only
        return;

    if (tfa->impulse)
        localcmd(sprintf("alias %s impulse %d\n", tfa->alias, tfa->impulse));
    else
        localcmd(strcat("alias ", tfa->alias, " \"", tfa->cmd, "\"\n"));
}

static void SetupAliases() {
    float i;

    for (i = 0; i < client_aliases.length; i++)
        BindAlias(&client_aliases[i]);

    for (i = 0; i < csqc_aliases.length; i++)
        BindAlias(&csqc_aliases[i]);

    print("Aliases set\n");
}

DECLARE_PERF_SAMPLER(frame_timing, 60, 0.1);
DECLARE_PERF_SAMPLER(hud_timing, 60, 0.1);
DECLARE_PERF_SAMPLER(hud_partial_timing, 60, 0.1);

void ClientSettings_Check();
void RegisterPlayerListener();

void(float pause) setpause = #531;

noref void(float apiver, string enginename, float enginever) CSQC_Init = {
    print("CSQC Started\n");

    INIT_PERF_SAMPLER(frame_timing);
    INIT_PERF_SAMPLER(hud_timing);
    INIT_PERF_SAMPLER(hud_partial_timing);

    FO_Hud_Init();
    FO_Weapons_Init();
    Predict_InitDefaultConfig();
    FO_Predict_Init();
    CsGrenTimer::Init();
    RegisterPlayerListener();


    registercommand("+slot");
    registercommand("-slot");
    registercommand("+button");
    registercommand("-button");
    registercommand("+holdgren");
    registercommand("-holdgren");

    registercommand("fo_beta_pmove");
    registercommand("fopm_cmd");

    registercommand("login");
    registercommand("fo_hud_editor");
    registercommand("fo_hud_reload");
    registercommand("fo_hud_reset");
    registercommand("fo_hud");
    registercommand("fo_hud_save");
    registercommand("fo_hud_load");

    registercommand("tf_menu");

    registercommand("fo_min_ping");

    registercommand("+aux_attack");
    registercommand("-aux_attack");
    registercommand("+aux_jump");
    registercommand("-aux_jump");
    registercommand("+rj");
    registercommand("-rj");

    registercommand("slot_a");

    registercommand("+fo_showscores");
    registercommand("-fo_showscores");
    registercommand("fo_settings_check");

    registercommand("vote_addmap");
    registercommand("vote_removemap");

    registercommand("wpp_status");
    registercommand("perf_status");
    for(float i = 0; i < MENU_OPTION.length - 1; i++) {
        registercvar(strcat("fo_menu_option_",MENU_OPTION[i]), MENU_OPTION[i]);
    }
    registercvar("fo_menu_option_+", "=");

    FO_Hud_Editor_LoadSettings(FO_HUD_CONFIG_PATH);

    MenuPanel = getHudPanel(HUDP_MENU);

    is_admin = FALSE;

    num_mapvotes = 0;
    vote_selected_item = world;
    vote_selected_index = -1;
    vote_list_offset = 0;
    current_vote = world;
    vote_list_filter = "";

    PM_Init();

    is_demo = isdemo();
    SetupAliases();

    player_menu_type = 0;
    if (!is_demo) {
        TF_Menu_Game(TRUE, TRUE);
    } else {
        setpause(TRUE);
    }

    pengine.view_mask = MASK_VIEWMODEL;  // Start with engine models.
    print("CSQC initialization finished\n");
};

static string ConfigSep = "=";

static void TFL_LoadConfig() {
    float fd = fopen(TFL_CONFIG_PATH, FILE_READ);
    if (fd < 0)
        return;
    while (TRUE) {
        string ln = fgets(fd);
        ln = strreplace("\n", "", ln);
        if (ln == "")
            break;

        float v = tokenizebyseparator(ln, ConfigSep);
        string key = argv(0);
        string val = argv(1);
        for (float i = 2; i < v; i++)
            val = strcat(val, ConfigSep, argv(i));

        switch (key) {
            case "login_token": Config.login_token = val; break;
        }
    }
    fclose(fd);
}

void TFL_SaveConfig() {
    float fd = fopen(TFL_CONFIG_PATH, FILE_WRITE);
    if (fd < 0)
        return;
    fputs(fd, "login_token", ConfigSep, Config.login_token, "\n");
    fclose(fd);
}

void FoLogin_UpdateToken();

static string FoLogin_GetToken() {
    float filehandle = fopen(FO_TOKEN_PATH, FILE_READ);
    if (filehandle == -1)
        return "";

    string token = fgets(filehandle);
    fclose(filehandle);
    return token;
}

static void ClearOldLoginState() {
    localcmd("setinfo _qwtfl_login \"\"\n");
    localcmd("setinfo _qwtfl_nonce \"\"\n");
    localcmd("setinfo _fo_token \"\"\n");
}

static void SendLogin(string login_token = "USE_CONFIG") {
    if (login_token != "USE_CONFIG") {
        localcmd("cmd login ", login_token, "\n");
    } else if (Config.login_token != "") {
        localcmd("cmd login-bg ", Config.login_token, "\n");
        ClearOldLoginState();  // Only after we've saved valid new state.
        return;
    }

    string fo_token = FoLogin_GetToken();
    if (fo_token != "") {
        localcmd("cmd login-migrate ", fo_token, "\n");
        return;
    }

    printf("WARNING: You are missing a login token.  Use '/token' on discord.qwtf.live to get one.\n");
}

noref void() CSQC_WorldLoaded = {
    localcmd("menu_restart\n");
    // Resolve race condition where models packed into map package sometimes do
    // not resolve correctly.
    localcmd("flush\n");
    localcmd("cl_smartjump 0\n");  // replaced by fo_smartjump
    Register_Particles();

    TFL_LoadConfig();
}

void FO_CussView();
void FO_CussCrosshair(float width, float height);
void Hud_UpdateView(float width, float height, float menushown);
void UpdateTeamColorCrosshair();
void PMD_DrawGraphs(float width);
void WP_PreviewSentry();

DEFCVAR_FLOAT(fov, 90);

inline float TrackingPlayer() { return player_localentnum <= 32; }

static inline float ShowDispCam() {
    return pstate_server.playerclass == PC_ENGINEER &&
           SBAR.HasDispenser == BUILD_STATE_BUILT &&
           CVARF(tf_dispcam);
}

static void UpdateRenderSelf() {
    static float walkframe;
    static float last_vel;
    static float next_update, next_refresh;

    entity fp = pengine.renderself;
    fp.origin = PM_Org();
    fp.angles = [0, input_angles.y, input_angles.z];

    if (time < next_update) {
        fp.lerpfrac = 1 - (next_update - time) * 10;
        return;
    }

    if (time > next_refresh) {
        string skin_name = getplayerkeyvalue(player_localnum, "skin");
        string skin_arg = strcat("qwskin ", skin_name, "\n");
        setcustomskin(fp, "", skin_arg);
        next_refresh = time + 1;
    }

    float vel = vlen(PM_Vel());
    float next;

    if ((vel && !last_vel) || (!vel && last_vel))
        walkframe = -1;
    last_vel = vel;


    float base, melee = IsSlotMelee(pstate_pred.current_slot);
    if (pstate_pred.client_time < pstate_pred.attack_finished)
        base = 113 + (melee ? 6 : 0);
    else if (vel)
        base = 0 + (melee ? 0 : 6);  // WHY
    else
        base = 12 + (melee ? 6 : 0);

    static float last_base, ofs;
    if (base != last_base)
        ofs = 0;
    else
        ofs = (ofs + 1) % 5;
    last_base = base;

    next = base + ofs;

    fp.frame = fp.frame2;
    fp.frame2 = next;
    next_update = time + 0.1;
}

static void CSQC_DispCam(float width, float height) {
    const float cam_w = 150;


    if (fo_hud_editor)
        return;

    vector cam_pos = getHudPanel(HUDP_DISPCAM)->Position;
    if (vlen(PM_Org() - dispenser_pos) > DISP_CAM_RANGE) {
        drawstring(cam_pos, "DispCam out of range", '8 8', '1 0 0', 1, 0);
        return;
    }

    clearscene();
    setviewprop(VF_AFOV, 75);

    const vector size = [cam_w, cam_w * 9/16];

    setviewprop(VF_MIN_X, cam_pos.x);
    setviewprop(VF_SIZE_X, size.x);
    setviewprop(VF_MIN_Y, cam_pos.y);
    setviewprop(VF_SIZE_Y, size.y);

    setviewprop(VF_ORIGIN, dispenser_render_pos);
    setviewprop(VF_ANGLES, dispenser_angles);

    addentities(MASK_ENGINE);

    UpdateRenderSelf();
    addentity(pengine.renderself);

    vector bd = '2 2';
    drawfill(cam_pos - bd, size + 2 * bd, '0.5 0.7 0.5', 0.7);
    renderscene();
}

noref void(float width, float height, float menushown) CSQC_UpdateView = {
    clearscene();
    setproperty(VF_DRAWWORLD, 1);     // we want to draw our world!

    if (!is_demo || TrackingPlayer())
      setproperty(VF_DRAWCROSSHAIR, 1);
    FO_CussView();

    if (zoomed_in)
        setviewprop(VF_AFOV, CVARF(fov)/3);

    // Draw original sbar, viewsize honoured automatically.
    if (!CVARF(tf_fte_hud))
        setproperty(VF_DRAWENGINESBAR, 1);

    WP_PreviewSentry();

    float mask = MASK_ENGINE;
    if (!intermission)
        mask |= WPP_ViewModelMask();
    addentities(mask);

    if (PM_Enabled())
        PM_UpdateView();

    renderscene();

    //FO_CussCrosshair(width, height);

    TFxRenderGrenadeTimers();
    RenderHitTexts();
    Hud_UpdateView(width, height, menushown);
    PMD_DrawGraphs(width);

    if (ShowDispCam())
        CSQC_DispCam(width, height);

    // Work around bug in some versions of FTE.  See pmove.qc
    recent_pmove_vel_z = pmove_vel_z;
}

void W_ChangeToSlotAlternate(string opt1, string opt2, string opt3, string opt4);

DEFCVAR_FLOAT(tf_build_preview, 1);
DEFCVAR_FLOAT(tf_build_preview_range, 1);

void WP_ActivateBuildingPreview(float type);
void WP_DeactivateBuildingPreview();


static float BuildPreview(int type, int plus) {
    if (pstate_pred.playerclass != PC_ENGINEER || CVARF(tf_build_preview) == 0)
        return FALSE;

    if (type == 1) {
        if (plus) {
            if (!SBAR.HasSentry) {
                if (WP_GetAmmo(AMMO_CELLS) >= ENG_SENTRY_COST) {
                    localcmd("slot4\n");
                    WP_ActivateBuildingPreview(1);
                } else {
                    cprint(sprintf("You need %d more cells to build a sentry gun",
                                   ENG_SENTRY_COST - WP_GetAmmo(AMMO_CELLS)));
                }
            } else {
                localcmd("cmd build destroy sentry\n");
            }
        } else {
            if (pengine.preview == 1) {
                WP_DeactivateBuildingPreview();
                localcmd(sprintf("weaplast; cmd build sentry %d\n",
                                 pengine.preview_rotation));
            }
        }
    } else if (type == 2) {
        if (plus) {
            if (!SBAR.HasDispenser) {
                if (WP_GetAmmo(AMMO_CELLS) >= ENG_DISPENSER_COST) {
                    localcmd("slot4\n");
                    WP_ActivateBuildingPreview(2);
                } else {
                    cprint(sprintf("You need %d more cells to build a dispenser",
                                   ENG_DISPENSER_COST - WP_GetAmmo(AMMO_CELLS)));
                }
            } else {
                localcmd("cmd build destroy dispenser\n");
            }
        } else {
            if (pengine.preview == 2) {
                WP_DeactivateBuildingPreview();
                localcmd(sprintf("weaplast; cmd build dispenser %d\n",
                                 pengine.preview_rotation));
            }
        }
    }

    return TRUE;
}

static const float kDebounce = 0.025;

struct SlotState {
    float on;
    float activated;
    float until;
    float released;
};

static struct {
    int num, cur;
    SlotState state[4];
    Slot under;
    float impulse;
} plus_slot;

static var struct DebounceButton {
    float button;
    float until;
    float on;
} debounce_button[] = {
    {BUTTON3},
    {BUTTON4},
    {BUTTON5},
    {BUTTON6},
    {BUTTON7},
};

static float next_forced_buttons, forced_buttons, active_buttons, debounced_buttons;

static void CommandButton(int plus, int button) {
    if (button < 3 || button > 7)
        return;
    button -= 3;

    if (button == 0 || button == 1) {
        float alt_mask = 0;
        switch (WP_PlayerClass()) {
            case PC_SOLDIER:
            case PC_PYRO:
                if (button == 1) {
                    localcmd(plus ? "+rj\n" : "-rj\n");
                    alt_mask = BUTTON_SPECIAL2;
                }
                break;
            case PC_ENGINEER:
                if (BuildPreview(2 - button, plus))
                    alt_mask = BUTTON_SPECIAL1 | BUTTON_SPECIAL2;
                break;
        }

        if (alt_mask) {
            active_buttons &= ~alt_mask;
            return;
        }
    }

    float mask = debounce_button[button].button;

    if (plus) {
        debounce_button[button].on = TRUE;
        debounce_button[button].until = time + kDebounce;

        active_buttons |= mask;
    } else {
        debounce_button[button].on = FALSE;
        active_buttons &= ~mask;

        if (time < debounce_button[button].until) {
            debounced_buttons |= mask;
            return;
        }

        debounce_button[button].until = 0;
        debounced_buttons &= ~mask;
    }
}



static Slot ActiveSlot() {
    if (!IsSlotNull(pstate_pred.queue_slot))
        return pstate_pred.queue_slot;
    return pstate_pred.current_slot;
}

static Slot push_stack_one;
static string PushSlotCmd(Slot slot) {
    Slot active = ActiveSlot();
    if (!IsSameSlot(active, slot)) {
        push_stack_one = active;
        return sprintf("impulse %d;", TF_SLOT1 + SlotIndex(slot));
    } else {
        push_stack_one = SlotNull;
        return "";
    }
}

static string PopSlotCmd() {
    if (IsSlotNull(push_stack_one))
        return "";

    string result = sprintf("impulse %d; ", TF_SLOT1 + SlotIndex(push_stack_one));
    push_stack_one = SlotNull;
    return result;
}

static void ActivatePlusSlot(int idx) {
    if (idx < 0 || idx >= TF_NUM_SLOTS)
        return;

    plus_slot.state[idx].on = TRUE;

    if (!plus_slot.state[idx].activated) {
        if (plus_slot.num++ == 0)
            plus_slot.under = ActiveSlot();
    }

    plus_slot.state[idx].activated = time;
    plus_slot.state[idx].until = time + kDebounce;
    plus_slot.cur = idx;
    plus_slot.impulse = TF_SLOT1 + idx;
}

static void DeactivatePlusSlot(int idx) {
    plus_slot.state[idx].on = FALSE;
    if (time < plus_slot.state[idx].until)
        return;

    plus_slot.num--;
    plus_slot.state[idx].activated = 0;
    plus_slot.state[idx].until = 0;

    int next_idx = 3;
    if (plus_slot.num == 0) {
        next_idx = SlotIndex(plus_slot.under);
    } else {
        float recent = 0;
        for (int i = 0; i < 4; i++) {
            if (plus_slot.state[i].activated > recent) {
                recent = plus_slot.state[i].activated;
                next_idx = i;
            }
        }
    }

    plus_slot.cur = next_idx;
    plus_slot.impulse = TF_SLOT1 + next_idx;
}

noref float(string cmd) CSQC_ConsoleCommand = {
    tokenize_console(cmd);

    switch(argv(0)) {
        case "+button":
            CommandButton(TRUE, stoi(argv(1)));
            break;
        case "-button":
            CommandButton(FALSE, stoi(argv(1)));
            break;
        case "+holdgren":
            if (pstate_pred.tfstate & TFSTATE_GREN_MASK_PRIMED == 0) {
                float imp = stoi(argv(1)) != 1 ? TF_GRENADE_2 : TF_GRENADE_1;
                localcmd(sprintf("impulse %d\n", imp));
            }
            break;
        case "-holdgren":
            if (!game_state.is_ceasefire) {
                input_impulse = TF_GRENADE_T;
                localcmd(sprintf("impulse %d\n", TF_GRENADE_T));
            }
            break;
        case "+slot":
            ActivatePlusSlot(stoi(argv(1)) - 1);
            break;
        case "-slot":
            DeactivatePlusSlot(stoi(argv(1)) - 1);
            break;

        case "fo_beta_pmove":
            printf("Please set `fo_pmove 1` instead.\n");
            break;

        case "login":
            string token = argv(1);
            SendLogin(token);
            break;
        case "fo_hud_editor":
            FO_Hud_Editor();
            break;
        case "fo_hud":
            if(argv(1) == "") {
                FO_Hud_Editor_List_Panels();
            } else if(argv(3) == "") {
                FO_Hud_Editor_Print_Panel_Setting(argv(1), argv(2));
            } else {
                FO_Hud_Editor_Set_Panel_Setting(argv(1), argv(2), argv(3));
            }
            break;
        case "fo_hud_save":
            if(argv(1) != "") {
                Hud_WriteCfg(argv(1));
            } else {
                Hud_WriteCfg(FO_HUD_CONFIG_PATH);
            }
            break;
        case "fo_hud_reload":
            FO_Hud_Editor_LoadSettings(FO_HUD_CONFIG_PATH);
            break;
        case "fo_hud_reset":
            FO_Hud_Editor_LoadDefaultSettings();
            break;
        case "fo_hud_load":
            if(argv(1) != "") {
                FO_Hud_Editor_LoadSettings(argv(1));
            }
            break;
        case "tf_menu":
            switch (argv(1)) {
                case "game": TF_Menu_Game(TRUE); break;
                case "team": TF_Menu_Team(TRUE); break;
                case "class": TF_Menu_Class(TRUE); break;
                case "admin": TF_Menu_Admin_Main(TRUE); break;
                case "special": TF_Menu_Special(TRUE); break;
                case "dropammo": TF_Menu_DropAmmo(TRUE); break;
                case "cancel": Menu_Cancel(); break;
                case "disguise":
                    if (WP_PlayerClass() == PC_SPY)
                        TF_Menu_Spy_Skin(TRUE);
                    break;
                case "build":
                    if (WP_PlayerClass() == PC_ENGINEER)
                        TF_Menu_Build(TRUE);
                    break;
                case "vote": showVoteMenu(!getHudPanel(HUDP_MAP_MENU)->Display); break;
                case "main":
                  if(checkcommand("m_main")) {
                      //Use menuqc main menu
                      localcmd("m_main\n");
                  } else {
                      //If menu.dat is missing, fall back to engine menus
                      localcmd("menu_main\n");
                  }
                  break;
                default:
                  printf("unrecognized menu: %s\n", argv(1));
                  break;
            }
            break;
        case "fo_min_ping":
            UpdateFoMinPing(argv(1));
            break;
        case "fo_settings_check":
            ClientSettings_Check();
            break;
        case "+fo_showscores":
            if (CVARF(tf_oldscoreboard) == 1)
            {
                tokenize(findkeysforcommand(argv(0)));

                string key1 = argv(0);
                string key2 = argv(1);
                if (key1 != "") key1 = (key1=="-1")?"":keynumtostring(stof(key1));
                if (key2 != "") key2 = (key2=="-1")?"":keynumtostring(stof(key2));

                if (key1 != "")
                {
                    localcmd(sprintf("unbind %s\n", key1));
                    localcmd(sprintf("bind %s +showscores\n", key1));
                }

                if (key2 != "")
                {
                    localcmd(sprintf("unbind %s\n", key2));
                    localcmd(sprintf("bind %s +showscores\n", key2));
                }
            }
            FO_Show_Scores(TRUE);
            break;
        case "-fo_showscores":
            FO_Show_Scores(FALSE);
            break;
        case "+showscores":
        case "+showteamscores":
            showingscores = TRUE;
            if (CVARF(tf_oldscoreboard) != 1)
            {
                tokenize(findkeysforcommand(argv(0)));

                string key1 = argv(0);
                string key2 = argv(1);
                if (key1 != "") key1 = (key1=="-1")?"":keynumtostring(stof(key1));
                if (key2 != "") key2 = (key2=="-1")?"":keynumtostring(stof(key2));

                if (key1 != "")
                {
                    localcmd(sprintf("unbind %s\n", key1));
                    localcmd(sprintf("bind %s +fo_showscores\n", key1));
                }

                if (key2 != "")
                {
                    localcmd(sprintf("unbind %s\n", key2));
                    localcmd(sprintf("bind %s +fo_showscores\n", key2));
                }
            }
            if(CVARF(tf_fte_hud)) {
                FO_Show_Scores(TRUE);
            }
            break;
        case "-showscores":
        case "-showteamscores":
            showingscores = FALSE;
            if(CVARF(tf_fte_hud)) {
                FO_Show_Scores(FALSE);
            }
            break;
        case "+aux_attack":
            attack_counter++;
            next_forced_buttons |= BUTTON_ATTACK;
            break;
        case "-aux_attack":
            attack_counter--;
            if (attack_counter <= 0) {
                attack_counter = 0;
                next_forced_buttons &= ~BUTTON_ATTACK;
            }
            break;
        case "+aux_jump":
            jump_counter++;
            next_forced_buttons |= BUTTON_JUMP;
            break;
        case "-aux_jump":
            jump_counter--;
            if (jump_counter <= 0) {
                jump_counter = 0;
                next_forced_buttons &= ~BUTTON_JUMP;
            }
            break;
        case "+rj":
            string opt_wait = "";
            switch (WP_PlayerClass()) {
                case PC_SOLDIER:
                case PC_PYRO:
                    localcmd(PushSlotCmd(MakeSlot(1)), "+aux_attack; +aux_jump\n");
                    break;

                case PC_ENGINEER:
                    localcmd(PushSlotCmd(MakeSlot(3)), "+aux_attack; +aux_jump\n");
                    break;

                case PC_DEMOMAN:
                    localcmd("detpipe; +aux_jump;\n");
                    break;
            }
            break;
        case "-rj":
            switch (WP_PlayerClass()) {
                case PC_SOLDIER:
                case PC_PYRO:
                case PC_ENGINEER:
                    localcmd(PopSlotCmd(), "-aux_attack; -aux_jump\n");
                    break;
                case PC_DEMOMAN:
                    localcmd("-aux_jump\n");
                    break;
            }
            break;
        case "wpp_status":
            WPP_Status();
            break;
        case "perf_status":
            Perf_Status();
            break;
        case "vote_addmap":
            AddVoteMap(argv(1),argv(2),argv(3),stof(argv(4)),stof(argv(5)),stof(argv(6)),TRUE);
            break;
        case "vote_removemap":
            RemoveVoteMap(argv(1), TRUE);
            break;
        case "slot_a":  // Alternate between passed options
            W_ChangeToSlotAlternate(argv(1), argv(2), argv(3), argv(4));
            break;
    }

    return FALSE;
};

void(float isnew) CSQC_Ent_Update = {
    float etype = readbyte();
    switch (etype) {
        case ENT_PROJECTILE:
            EntUpdate_Projectile(isnew);
            break;
        default:
            error("Unhandled CSQC entity\n");
            return;
    }
};

void() CSQC_Ent_Remove = {   //the entity in question left the player's pvs, and will no longer be tracked...
    if (self.removefunc)
        self.removefunc();
    remove(self);
};

static float IsFoConced() {
    if (IsClownMode(CLOWN_CONC))
        return TRUE;

    if (!tf_config.fo_concuss)
        return FALSE;

    return pstate_pred.tfstate & TFSTATE_CONC;
}

struct ConcCurve {
    float duration;
    float cycles;
    float amp_end;
    float offset;
};

ConcCurve conc_curve[] = {
    {1, 0.5, 0.0, 0.5},
    {6, 4, 0.2, 0.5},
    {2, 1.5, 0.75},
    {1, 1, 1},
    {0, 0, 1},  // Terminator
};

ConcCurve clown_curve[] = {
    {10, 4, 0.75},
    {0, 0, 0.75},  // Terminator
};

float ClownConcPeriod() { return clown_curve[0].duration; }

static float Blend(float start, float end, float rem, float D) {
    return rem/D * start + (D-rem)/D * end;
}

static vector FO_Conc_Offset() {
    static float last_rem;
    float rem = cuss_state.end_time - time;
    if (rem < 0)
        return '0 0 0';

    ConcCurve* table;
    float len;
    ConcCurve* cur = __NULL__;
    float i, rot = 0;

    if (!IsClownMode(CLOWN_CONC)) {
            table = conc_curve;
            len = conc_curve.length;
    } else {
            table = clown_curve;
            len = clown_curve.length;
    }

    for (i = 0; i < len - 1; i++) {
        cur = &table[i];
        if (rem <= cur->duration)
            break;
        rem -= cur->duration;
    }

    float amp = Blend(table[i+1].amp_end, cur->amp_end, rem, cur->duration);
    float a = (cur->duration - rem) / cur->duration * cur->cycles * 2 * M_PI;
    a += cur->offset * 2 * M_PI;

    return [sin(a), sin(a) * cos(a), amp * pstate_pred.conc_amp];
}

static void FO_UpdateConcAim() {
    makevectors(input_angles);
    vector o = FO_Conc_Offset();

    cuss_state.c_forward = normalize(v_forward * 200 + o.x * o.z * v_right + o.y * o.z * v_up);

    vector vv = o * min(o.z / 4, 20);
    cuss_state.c_view = vectoangles(v_forward * 200 + vv.x * v_right + vv.y * v_up);
    cuss_state.c_view[0] *= -1;
}

DEFCVAR_FLOAT(fo_crossy, 0);  // For people who want to use crossy
DEFCVAR_FLOAT(cl_crossx, 0);
DEFCVAR_FLOAT(cl_crossy, 0);

static void FO_CussView() {
    if (cuss_state.cussed) {
        FO_UpdateConcAim();
        setproperty(VF_ANGLES, cuss_state.c_view);
    }
};

static void FO_CussCrosshair(float width, float height) {
    const float crosshair_hz = 200;
    static float next_update;
    if (time < next_update)
        return;
    next_update = time + 1.0/crosshair_hz;

    if (!IsFoConced()) {
        if (cuss_state.cussed || CVARF(cl_crossx) != 0 ||
                CVARF(cl_crossy) != CVARF(fo_crossy)) {
            // Make sure we restore crosshairs
            localcmd(sprintf("cl_crossx %d; cl_crossy %d;\n", 0, CVARF(fo_crossy)));
            CVARF(cl_crossx) = 0;
            CVARF(cl_crossy) = CVARF(fo_crossy);
            cuss_state.cussed = FALSE;
        }
        return;
    }

    cuss_state.cussed = TRUE;
    makevectors(input_angles);  // updated by input_frame
    vector p = project(PM_Org() + 8000 * cuss_state.c_forward);

    localcmd(sprintf("cl_crossx %d; cl_crossy %d;\n",
                p_x - width / 2, CVARF(fo_crossy) + p_y - height / 2));
}

static void UpdateTeamColorCrosshair() {
    if (!CVARF(fo_team_color_crosshair))
        return;

    if (crosshair_team_no == team_no)
        return;

    string crosshair_color = "0xffffff";
    switch (team_no) {
        case 1:
            crosshair_color = "0x0066ff";
            break;
        case 2:
            crosshair_color = "0xff0000";
            break;
        case 3:
            crosshair_color = "0xffff00";
            break;
        case 4:
            crosshair_color = "0x00ff00";
    }
    localcmd("crosshaircolor ", crosshair_color, "\n");
    crosshair_team_no = team_no;
}

void FO_ApplyCussInput() {
    if (!IsFoConced())
        return;

    float modify_forward = TRUE;

    if ((!pmove_onground && (tf_config.fo_concuss & FOC_EASY_AIR)) ||
        (pmove_onground && (tf_config.fo_concuss & FOC_EASY_GROUND)))
        modify_forward = input_buttons & BUTTON_ATTACK;

    if (modify_forward) {
        input_angles = vectoangles(cuss_state.c_forward);
        makevectors(input_angles);
        input_angles_x *= -1;
    }
}

static void InputFrameDebounce() {
    if (input_impulse == TF_SPECIAL_SKILL2 &&  // Poor man's +rj translation
        (WP_PlayerClass() == PC_SOLDIER || WP_PlayerClass() == PC_PYRO)) {
        ActivatePlusSlot(0);
        DeactivatePlusSlot(0);
        input_impulse = 0;  // Ensure +slot works below
        input_buttons |= BUTTON_ATTACK | BUTTON_JUMP;
    }

    // Button debounce
    if (debounced_buttons) {
        for (int i = 0; i < debounce_button.length; i++)
            if (!debounce_button[i].on && debounce_button[i].until)
                CommandButton(FALSE, i + 3);
    }

    input_buttons |= (forced_buttons | active_buttons | debounced_buttons);
    forced_buttons = next_forced_buttons;

    if (plus_slot.num > 0) {
        for (int i = 0; i < 4; i++)
            if (!plus_slot.state[i].on && plus_slot.state[i].activated)
                DeactivatePlusSlot(i);
    }

    float can_fire = TRUE;
    if (plus_slot.impulse) {
        if (SlotIndex(ActiveSlot()) == plus_slot.cur) {
            plus_slot.impulse = 0;
        } else if (input_impulse == 0) {
            input_impulse = plus_slot.impulse;
            plus_slot.impulse = 0;
        } else {
            can_fire = FALSE;
        }
    }

    if (plus_slot.num > 0 && can_fire)
        input_buttons |= BUTTON_ATTACK;
}

noref void CSQC_Input_Frame() {
    InputFrameDebounce();
    Sync_GameState();

    // Handle zoom
    float prev_zoomed_in = zoomed_in;
    if (WP_PlayerClass() == PC_SNIPER)
        zoomed_in = input_buttons & BUTTON_SPECIAL1;
    else
        zoomed_in = 0;

    if (prev_zoomed_in != zoomed_in)
        setsensitivityscaler(zoomed_in ? 1/3 : 1);

    PM_InputFrame();
    FO_ApplyCussInput();
}

float(float save, float take, vector inflictororg) CSQC_Parse_Damage = {
    if (take > 0)
        painfinished = time + 0.2;

    return 0;
}

void CSQC_Shutdown() {
}

// We can query, but not set via an autocvar.
DEFCVAR_FLOAT(cl_delay_packets, 0);
DEFCVAR_FLOAT(fov, 90);

void WP_UpdatePings();

static string class_names[] = {
    "scout", "sniper", "soldier", "demoman", "medic", "hwguy", "pyro", "spy", "engineer"
};

static void PlayerRespawned() {
    int i = pstate_server.playerclass - 1;
    if (i >= 0 && i < class_names.length) {
        string class = class_names[i];
        localcmd("set tf_class ", class, "\n");
        if (csqc_get_user_setting("ec", "exec_class", "off"))
            localcmd(sprintf("exec %s.cfg\n", class));
    }
    localcmd("f_respawn\n");
}

static void InitActive() {
    SendLogin();
    Register_Particles();
    ClientSettings_Check();
}

float last_servercommandframe;
void _Sync_ServerCommandFrame() {
    // Server command frames are monotonically unique, we can skip processing
    // unless there is new state.
    if (last_servercommandframe == servercommandframe)
        return;
    last_servercommandframe = servercommandframe;

    static float once;
    if (!once && !is_demo) {
        once = TRUE;
        InitActive();
    }

    UpdateCachedCvars();

    prev_game_state = game_state;

    team_no = getstatf(STAT_TEAMNO);
    team_no_attack = getstatf(STAT_TEAMNO_ATTACK);
    if (team_no_attack == 0)
        team_no_attack = 1;

    if (team_no == 0 || stof(getplayerkeyvalue(player_localnum, "*spectator")) || isdemo()) {
        game_state.is_spectator = 1;
        game_state.is_player = 0;
    } else {
        game_state.is_spectator = 0;
        game_state.is_player = 1;
    }

    // Note: When spectating someone, refers to them.
    game_state.is_alive = getstatf(STAT_HEALTH) > 0;
    game_state.spawn_gen = getstatf(STAT_SPAWN_GEN);

    game_state.is_ceasefire = serverkeyfloat("pausestate");
    WP_ServerFrame();

    // Use an undocumented ezquake compat feature to figure out whether we
    // have focus or not, skip updates in this case due to lowered network fps.
    float is_unfocused = getplayerkeyfloat(player_localnum, "chat") & 2;
    if (!is_unfocused)
        WP_UpdatePings();

    CsGrenTimer::UpdateSoundStack();
    UpdateTeamColorCrosshair();

    static float last_playerclass;
    if ((prev_game_state.spawn_gen != game_state.spawn_gen ||
         last_playerclass != pstate_server.playerclass) &&
        game_state.is_player && game_state.is_alive)
        PlayerRespawned();
    last_playerclass = pstate_server.playerclass;
}


// Called for each {client, server} command frame, ensures globals are
// synchronized with server and predicted state.
void Sync_GameState() {
    _Sync_ServerCommandFrame();
    PM_PredictJump_Engine();
}

static string to_precision(float f, float p) {
    string fmt = strcat("%0.", ftos(p), "f");
    return sprintf(fmt, f);
}

static float get_precision() {
    float t = gettime(1);

    // For (debug) clients which have modified gettime to report with more
    // precision.
    return (t*1000 == ceil(t*1000)) ? 3 : 5;
}

static float gettime_lat() {
    const float trials = 1000;
    float s = gettime(1), f, i;
    for (i = 0; i < trials; i++)
        gettime(1);
    return (gettime(1) - s)/trials;
}

// Note while this works with ms
void Perf_Status() {
    printf("Performance Stats:\n");
    float avg, variance, minv, maxv;

    float prec = get_precision();
    if (prec > 3)
        printf("gettime() timing = %0.5f\n", gettime_lat());

    compute_avg(&frame_timing.samples, &avg, &variance);
    compute_maxmin(&frame_timing.samples, &minv, &maxv);
    printf(" Frame render (%d) avg=%s var=%0.3f min=%s max=%s\n",
            (float)min(frame_timing.samples.count, frame_timing.samples.max_count),
            to_precision(avg, prec), variance,
            to_precision(minv, prec), to_precision(maxv, prec));

    compute_avg(&hud_timing.samples, &avg, &variance);
    compute_maxmin(&hud_timing.samples, &minv, &maxv);
    printf(" HUD render (%d) avg=%s var=%0.3f min=%s max=%s\n",
            (float)min(hud_timing.samples.count, hud_timing.samples.max_count),
            to_precision(avg, prec), variance,
            to_precision(minv, prec), to_precision(maxv, prec));

    compute_avg(&hud_partial_timing.samples, &avg, &variance);
    compute_maxmin(&hud_partial_timing.samples, &minv, &maxv);
    printf(" HUD partial (%d) avg=%s var=%0.3f min=%s max=%s\n",
            (float)min(hud_partial_timing.samples.count, hud_partial_timing.samples.max_count),
            to_precision(avg, prec), variance,
            to_precision(minv, prec), to_precision(maxv, prec));
}

void ClientSettings_Check() {
    static string kError = "^1ERROR:^7 ";
    static string kWarn = "^3WARNING:^7 ";
    static string kRec = "^2RECOMMENDED:^7 ";

    localcmd("cl_movespeedkey 1\n");
    if (cvar("worker_count") == 0)
        print(kError, "Please set `worker_count 4` to reduce stuttering!\n");
    if (cvar("r_temporalscenecache") == 0)
        print(kRec, "Please set `r_temporalscenecache 1` to reduce stuttering!\n");
    if (cvar("fo_grentimer") != 2)
        print(kRec, "Set `fo_grentimer 2` for ping correction.\n");
    if (cvar("fo_predict_weapons") != 1)
        print(kWarn, "client-side weapon prediction disabled [fo_predict_weapons 0]\n");
    if (cvar("fo_predict_projectiles") != 1)
        print(kWarn, "client-side projectile prediction disabled [fo_predict_projectiles 0]\n");
}
