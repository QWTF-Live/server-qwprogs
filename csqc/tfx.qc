.entity outline;
.entity csqc_player;
.float grentimer_expires;  // TODO: integrate this
.float teamno;
static entity local_player;
static float shader_team[2], shader_flag, shader_over_outline;

enum {
    TeamNone = 0,
    TeamBlue = 1,
    TeamRed = 2,
};


static float LocalTeam() {
    static float next, teamno;
    if (time >= next) {
        teamno = getstatf(STAT_TEAMNO);
        next = time + 0.1;
    }
    return teamno;
}

static float FlagCarried() {  // Just awful.
    for (int i = 0; i < FlagInfoLines.length; i++)
        if (FlagInfoLines[i].state == FLAGINFO_CARRIED)
            return TRUE;
    return FALSE;
}

// Until we network player entities we need somewhere to stash things.
struct EntHash {
    int entnum;
    float grentimer_expires;
};
static EntHash ent_hash[43];

static EntHash* EntGet(int ent_num) {
    EntHash* he = __NULL__;

    for (int i = 0; i < ent_hash.length; i++) {
        he = &ent_hash[(i + ent_num) % ent_hash.length];
        if (he->entnum == ent_num)
            return he;
        else if (!he->entnum)
            break;
    }

    he->entnum = ent_num;
    return he;
}

static float TeamNo(entity player) {
    // This is horrific, but the most immediately accessible thing we seem to
    // have.  getentity() is just unreliable.
    float pc = stof(infokey(player, INFOKEY_P_BOTTOMCOLOR));
    switch (pc) {
        case 13: return TeamBlue;
        case 4: return TeamRed;
    }
    return TeamNone;
}

static inline float AttackingTeamNo() { return getstatf(STAT_TEAMNO_ATTACK); }

static float IsAttacking(entity player) {
    /* return TeamNo(player) == getstatf(STAT_TEAMNO_ATTACK); */
    return player.teamno == AttackingTeamNo();
}

static float ShowPlayerOutline(entity player) {
    if (player.entnum == player_localentnum || player.teamno == TeamNone)
        return FALSE;

    if (prematch && TFxEnabled(TFX_PREMATCH_EVERYTHING))
        return TRUE;

    if (!game_state.is_player)
        return TFxEnabled(TFX_SPEC_OUTLINE);

    if ((TFxEnabled(TFX_DEFENSE_OUTLINE) && !IsAttacking(player)) ||
        (TFxEnabled(TFX_OFFENSE_OUTLINE) && IsAttacking(player)))
        return player.teamno == local_player.teamno;

    if (TFxEnabled(TFX_SCOUT_SEE_ENEMIES) && player.teamno != team_no &&
            pstate_pred.playerclass == PC_SCOUT) {
        vector diff = player.origin - PM_Org();
        float dz = diff_z;
        diff_z = 0;

        if ((vlen(diff) < 900) && (fabs(dz) < 400))
            return TRUE;
    }

    return FALSE;
}

static void RemoveAttached() {
    if (self.outline != __NULL__)
        remove(self.outline);
    if (self.csqc_player != __NULL__)
        remove(self.csqc_player);
}

static void AddOutline(entity ent) {
    entity o = spawn();
    setmodelindex(o, ent.modelindex);
    o.classname = "outline";
    setsize(o, PLAYER_MINS, PLAYER_MAXS);

    ent.outline = o;
    ent.removefunc = RemoveAttached;
}

static void UpdateOutline(entity player) {
    entity o = player.outline;
    if (!ShowPlayerOutline(player)) {
        o.drawmask = 0;
        self.forceshader = 0;
        return;
    }

    self.forceshader = shader_over_outline;
    o.forceshader = shader_team[TeamNo(player) - TeamBlue];
    o.drawmask = MASK_ENGINE;
    o.frame = player.frame;
    o.angles = player.angles;
    if (player.entnum == player_localentnum)
        o.renderflags |= RF_EXTERNALMODEL;
    setorigin(o, player.origin);

}

float UpdatePlayer(float isnew) {
    if (isnew) {
        AddOutline(self);
    }

    if (self.entnum == player_localentnum)
        self.renderflags |= RF_EXTERNALMODEL;
    else
        self.renderflags &= ~RF_EXTERNALMODEL;

    self.teamno = TeamNo(self);

    UpdateOutline(self);
    return TRUE;
}

static void AddCSQCPlayer(entity src) {
    if (src.csqc_player)
        return;  // Should never happen...

    entity csqc = spawn();
    csqc.classname = "csqc_player";

    setmodelindex(csqc, src.modelindex);
    setsize(csqc, PLAYER_MINS, PLAYER_MAXS);

    csqc.drawmask = 0;
    src.removefunc = RemoveAttached;
    src.csqc_player = csqc;
}

static string class_skins[] = {
    "sco", "sni", "sol", "dem", "med", "hwg", "pyr", "spy", "eng",
};

static string ConvertClassic(string suffix) {
    switch (suffix) {
        case "sco": return "scout";
        case "sni": return "snipe";
        case "sol": return "sold";
        case "dem": return "demo";
        case "med": return "medic";
        case "hwg": return "hwguy";
        case "pyr": return "pyro";

        // spy, eng
        default: return suffix;
    }
};


void(entity e, float skinobj) applycustomskin = #378;
float(string skinfilename, optional string skindata) loadcustomskin = #377;


static void CSQC_UpdateSkin(entity src) {
    entity csqc = src.csqc_player;
    int enemy = 0, player_team = 0, is_attack;
    string skin_name = "base";

    string skin_name = getplayerkeyvalue(self.colormap - 1, "skin");
    if (tokenizebyseparator(skin_name, "_") == 2) {
        player_team = argv(0) == "blue" ? 1 : 2;
        is_attack = player_team == team_no_attack;
        enemy = team_no != player_team;

        string skin_prefix = "hv";
        if (CVARF(tf_forcecolors) == 1)
            skin_prefix = is_attack ? "blue" : "red";

        skin_name = strcat(skin_prefix, "_", argv(1));
    } else {
        csqc.skin = src.skin;
        return;
    }

    string skin_arg = strcat("qwskin ", skin_name, "\n");
    setcustomskin(csqc, "", skin_arg);

    switch (CVARF(tf_forcecolors)) {
        case 1:
            csqc.colormod = src.colormod;
            csqc.glowmod = src.glowmod;
            break;  // Only skin swap
        case 2:
            csqc.colormod = is_attack ? CVAR.tf_color_attack : CVAR.tf_color_defense;
            csqc.glowmod = csqc.colormod;
            break;
        case 3:
            csqc.colormod = enemy ? CVAR.tf_color_enemy : CVAR.tf_color_team;
            csqc.glowmod = csqc.colormod;
            break;
    }
}

.float next_skin_update;

float CSQC_UpdatePlayer(float isnew) {
    if (isnew)
        AddCSQCPlayer(self);

    if (self.entnum == player_localentnum)
        self.renderflags |= RF_EXTERNALMODEL;
    else
        self.renderflags &= ~RF_EXTERNALMODEL;

    // Needs this for both cases since deltalisten() inadvertently blocks.
    if (self.effects & EF_DIMLIGHT)
        dynamiclight_add(self.origin, 200, CVAR.r_dimlight_colour);

    entity csqc = self.csqc_player;
    if (!CVARF(tf_forcecolors) || game_state.is_spectator) {
        self.drawmask = MASK_ENGINE;
        csqc.drawmask = 0;
        return TRUE;
    }

    if (csqc.origin == self.origin && csqc.angles == self.angles &&
        csqc.frame == self.frame && fabs(csqc.lerpfrac - self.lerpfrac) < 0.01 &&
        csqc.frame2 == self.frame2)
        return TRUE; // No update to propagate

    // Prepare to draw CSQC model below.
    self.drawmask = 0;
    csqc.drawmask = MASK_ENGINE;
    csqc.renderflags = self.renderflags;

    csqc.frame2 = self.frame2;
    csqc.frame = self.frame;
    csqc.lerpfrac = self.lerpfrac;
    csqc.angles = self.angles;
    setorigin(csqc, self.origin);

    if (time > self.next_skin_update) {
        CSQC_UpdateSkin(self);

        self.next_skin_update = time + 0.1;
    }

    return TRUE;
}


static float ShowTeamGrenTimer(float team, float my_team) {
    if (!game_state.is_player && TFxEnabled(TFX_SPEC_GRENTIMER))
        return TRUE;

    if (prematch && TFxEnabled(TFX_PREMATCH_EVERYTHING))
        return TRUE;

    if (team == AttackingTeamNo()) {
        if (TFxEnabled(TFX_OFFENSE_GRENTIMER) && team == my_team)
            return TRUE;
    } else {
        if (TFxEnabled(TFX_DEFENSE_GRENTIMER) && team == my_team)
            return TRUE;
    }

    return FALSE;
}

static entity gren_list[20];
static int num_gren_list;
static float next_grenlist_update;

static float RenderGrenTimer(entity p, float test_only) {
    const float maxd = 1000, mind = 200;
    vector po = p.origin + '0 0 40';
    vector o = PM_Org();

    if (p.entnum == player_localentnum)
        return FALSE;

    float diff = vlen(po - o);
    if (diff > maxd)
        return FALSE;

    traceline(o, po, 3, p);
    if (trace_fraction < 1)
        return FALSE;

    EntHash* he = EntGet(p.entnum);
    float rem = he->grentimer_expires - time;
    if (rem < 0)
        return FALSE;

    if (test_only)
        return TRUE;

    vector colors[] = { '1 0 0', '0.8 0.8 0.4', '0.8 0.5 0.5', '1 1 1'};
    vector c = project(po);
    vector size = '8 8 8' * (maxd - max(diff, mind)) / (maxd - mind);
    string str = ftos(ceil(rem));
    c.x -= stringwidth(str, FALSE, size) / 2;
    drawstring(c, str, size, colors[floor(rem)], 1, 0);

    return TRUE;
}

entity*(.__variant fld, __variant match, int type=EV_STRING, __out int count) find_list = #0:find_list;

static void UpdateGrenList() {
    if (time < next_grenlist_update)
        return;
    next_grenlist_update = time + 0.1;
    num_gren_list = 0;

    float teams[] = {TeamRed, TeamBlue};

    for (int i = 0; i < teams.length; i++) {
        float team = teams[i];
        if (!ShowTeamGrenTimer(team, local_player.teamno))
                continue;

        int count;
        entity* players = find_list(teamno, team, EV_FLOAT, count);
        for (int j = 0; j < count; j++) {
            entity p = players[j];

            if (RenderGrenTimer(p, TRUE))
                gren_list[num_gren_list++] = p;
        }
    }
}

void TFxRenderGrenadeTimers() {
    return; // TODO: filter properly
    UpdateGrenList();

    for (int i = 0; i < num_gren_list; i++) {
        entity p = gren_list[i];
        RenderGrenTimer(p, FALSE);
    }
}

static float ShowFlagOutline() {
    if (!game_state.is_player && TFxEnabled(TFX_SPEC_SEEFLAG))
        return TRUE;

    if (prematch && TFxEnabled(TFX_PREMATCH_EVERYTHING))
        return TRUE;

    if (TFxEnabled(TFX_OFFENSE_SEEFLAG) && IsAttacking(local_player))
        return TRUE;

    if (TFxEnabled(TFX_DEFENSE_SEEFLAG) && !IsAttacking(local_player) &&
        !FlagCarried())
        return TRUE;

    return FALSE;
}

static void UpdateFlagOutline(entity flag) {
    entity o = flag.outline;
    if (!ShowFlagOutline()) {
        o.drawmask = 0;
        return;
    }

    o.forceshader = shader_flag;
    o.drawmask = MASK_ENGINE;
    o.angles = flag.angles;
    o.frame = flag.frame;
    setorigin(o, flag.origin);
}

float UpdateFlag(float isnew) {
#if 0
    if (isnew) {
        float mindex = self.modelindex;
        AddOutline(self);
        // Flags have their own shader already, just make them shiny for now.
    }

    UpdateFlagOutline(self);
#endif

    if (self.skin == team_no) {
        const float m_alpha = 0.5, min_d = 50, max_d = 150;

        float d = vlen(PM_Org() - self.origin);

        d = max(d - min_d, 0);
        d = d > max_d ? 1 : d / max_d;
        self.alpha = m_alpha + d * (1 - m_alpha);
    }

    EffectToDynamicLight(self.origin, self.effects);
    return TRUE;
}

void TFxGrenTimerUpdate(float ent_num, float expiry) {
    EntHash* he = EntGet(ent_num);
    he->grentimer_expires = expiry;
}

static string OutlineShader(string texture) {
    return sprintf(
"{\
  sort 6\
  {\
     map %s\
     rgbGen lightingDiffuse\
     blendfunc GL_ONE GL_ONE_MINUS_SRC_COLOR\
     tcgen environment\
     tcmod rotate 30\
     nodepthtest\
     depthfunc greater\
  }\
}", texture);
}

static string rnds(string prefix) {
#if 0
    // Debugging convenience, concatenates a random string when enabled so that
    // shaders don't get cached on-client between builds.
    for (int i = 0; i < 5; i++)
            prefix = strcat(prefix, chr2str('a' + floor(random() * 26)));
#endif
    return prefix;
}

void RegisterPlayerListener() {
    STATIC_INIT_ONCE();

    if (!CVARF(tf_forcecolors) || isdemo())
        return;  // Must be set on connect currently

    printf("PLAYER DELTALISTEN ACTIVE\n");
    deltalisten("progs/player.mdl", CSQC_UpdatePlayer, 0);
}

void TFX_Init() {
    STATIC_INIT_ONCE();

    printf("TFX active.\n");

    /* RegisterPlayerListener(); */

    shader_team[0] = shaderforname(rnds("blue_team_outline"), OutlineShader("textures/sfx/quad.tga"));
    shader_team[1] = shaderforname(rnds("red_team_outline"), OutlineShader("textures/sfx/pent.tga"));
    shader_flag = shaderforname(rnds("flag_outline"), OutlineShader("textures/sfx/specular.tga"));

    shader_over_outline = shaderforname(rnds("over_outline"), "{ sort 7 }");
    /* pengine.viewmodel.shader = shader_over_outline; */
    pengine.viewmodel.effects |= EF_NODEPTHTEST;
}

void TFX_Flag_Init() {
    STATIC_INIT_ONCE();

    deltalisten("progs/ff_flag.mdl", UpdateFlag, 0);
    deltalisten("progs/tf_flag.mdl", UpdateFlag, 0);
    deltalisten("progs/tf_stan.mdl", UpdateFlag, 0);
}
