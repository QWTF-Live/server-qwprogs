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
    float grentimer_span;    // fuse length at receipt, for the pie fraction
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
    //
    // getplayerkeyvalue, not infokey: infokey is an SSQC builtin and does not
    // exist in CSQC.  Player indices are 0-based, entity numbers 1-based.
    float pc = stof(getplayerkeyvalue(player.entnum - 1, "bottomcolor"));
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

#if 0
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
#endif

// Team-coloured silhouette: an inverted hull.  A copy of the player scaled up
// a few percent rendering only its back faces, so what draws is the inside of
// the far side of the shell -- which sits behind the real player and is hidden
// by the depth test everywhere except the rim.  Depth testing is left normal,
// so world geometry occludes it exactly as it occludes the player, with no
// extra tracing needed.
//
// Note "cull back" is what renders the inside: Q3 shader "cull front" is the
// default and means cull *back* faces, i.e. draw normally -- which paints the
// enlarged hull straight over the player and z-fights with it.
//
// Deliberately not the TFX_*_OUTLINE shader, which uses nodepthtest +
// depthfunc greater to draw only where the model FAILS the depth test.  That
// one is an x-ray for seeing players through walls; this is the opposite.
static float shader_silhouette;
static float shader_sil_push;
static float shader_sil_ready;

// Inverted hull: the player drawn again with only back faces kept, expanded
// slightly along vertex normals.  The far side of that shell sits behind the
// real player, so the depth test hides it everywhere except the rim -- and
// because depth testing is left normal, world geometry occludes the outline
// exactly as it occludes the player, with no tracing needed.
//
// "cull back" is what keeps the inside: Q3 "cull front" is the default and
// means cull *back* faces, i.e. draw normally.
//
// The expansion is baked into the shader rather than being per-entity, so the
// shader is rebuilt when the width changes.
// shaderforname caches by name on the client, and that cache survives a
// csprogs reload -- so a name reused across builds keeps returning the first
// version compiled, broken or not.  Same reason rnds() exists further down.
//
// FO_NAME_SUFFIX is a hash of the client sources, which serves both needs at
// once: editing a shader body changes the hash and so the name, escaping the
// stale cache, while an unchanged build keeps the same name and the cache
// still hits.  It also keeps a fixed name from being a standing override
// target -- "nodepthtest" on a player outline is a wallhack.
static string SilSuffix() {
    return FO_NAME_SUFFIX;
}

// cg_player_outline: 0 off, 1 auto, 2 force shader script, 3 force GLSL.
// Auto resolves to the shader script -- the GLSL path holds a constant
// on-screen thickness but is the one that can fail to compile on an unknown
// client, so it is opt-in until it has more mileage.
static float SilUseGLSL() {
    return CVARF(cg_player_outline) == 3;
}

static float SilhouetteShader(float push) {
    // Rounded: every distinct value mints a shader that is never freed, so
    // sweeping the cvar should not be able to exhaust them.
    float dist = rint(bound(0, CVARF(cg_player_outline_dist), 1) * 20) / 20;

    float key = push + SilUseGLSL() * 1000 + dist * 10000000;
    if (shader_sil_ready && shader_sil_push == key)
        return shader_silhouette;

    // Backend 2: the same hull, expanded in an inline GLSL vertex stage
    // instead of by deformVertexes.  Ships inside csprogs.dat -- no client
    // package.  Kept because the program block is a foothold for effects that
    // plain shader script cannot express.
    //
    // v_position is a vec4, hence the .xyz: adding a vec3 to it directly is
    // what produced "could not implicitly convert operands".
    if (SilUseGLSL()) {
        // Expansion is done in clip space rather than world space, so the
        // rim is a constant thickness on screen instead of shrinking with
        // distance -- which is the thing plain shader script cannot express
        // and the main reason to be in GLSL at all.
        //
        // Offsetting by c.w cancels the perspective divide that follows.
        // "%f" not "%g": %g prints a whole number as "1", which GLSL reads as
        // an int and refuses to multiply against a float.  %f gives
        // "1.000000" and always parses as a float.
        // blendfunc is ignored while a program block is present, so appearance
        // has to come out of the fragment stage rather than blend state.
        //
        // Clamped to match the fallback: that path goes through fixed-function
        // rgbGen entity, which treats colormod above 1 differently to writing
        // it straight out here, so the two modes drifted apart in colour.
        string frag = "min(e_colourident, vec4(1.0))";

        shader_silhouette = shaderforname(
            sprintf("fo_silhouette_glsl_%g_%g_%s", push,
                    dist, SilSuffix()),
            sprintf(
"{\
  cull back\
  program\
  {\
     !!permu FRAMEBLEND\
     #include \"sys/defs.h\"\
     #ifdef VERTEX_SHADER\
     void main()\
     {\
        /* ftetransform() applies the engine frame blend; transforming\
           v_position by hand does not, which detaches the outline from an\
           animating model.  The raw attributes are still fine for deriving a\
           direction, where being a frame behind is not visible. */\
        vec4 c = ftetransform();\
        vec4 b = m_modelviewprojection * vec4(v_position.xyz, 1.0);\
        vec4 o = m_modelviewprojection * vec4(v_position.xyz + v_normal, 1.0);\
        vec2 d = o.xy / o.w - b.xy / b.w;\
        float dl = length(d);\
        if (dl > 0.0 && b.w > 1.0 && o.w > 1.0 && c.w > 1.0)\
           c.xy += (d / dl) * %f * mix(dl, 0.004, %f) * c.w;\
        gl_Position = c;\
     }\
     #endif\
     #ifdef FRAGMENT_SHADER\
     void main()\
     {\
        gl_FragColor = %s;\
     }\
     #endif\
  }\
}", push, dist, frag));

        shader_sil_push = key;
        shader_sil_ready = TRUE;
        return shader_silhouette;
    }

    shader_silhouette = shaderforname(
        sprintf("fo_silhouette_%g_%s", push, SilSuffix()),
        sprintf("{ cull back deformVertexes wave 100 sin %g 0 0 0 "
                "{ map $whiteimage rgbGen entity "
                "blendfunc GL_ONE GL_ZERO depthwrite } }", push));

    shader_sil_push = key;
    shader_sil_ready = TRUE;
    return shader_silhouette;
}

static float ShowPlayerSilhouette(entity player) {
    if (!CVARF(cg_player_outline) || player.entnum == player_localentnum)
        return FALSE;

    return player.teamno != TeamNone;
}

static void UpdateSilhouette(entity player) {
    entity o = player.outline;

    if (!ShowPlayerSilhouette(player)) {
        if (o != __NULL__)
            o.drawmask = 0;
        return;
    }

    if (o == __NULL__) {
        AddOutline(player);
        o = player.outline;
    }

    // Capped: past this the hull stops reading as a border and starts
    // swallowing the player, and in the fallback mode limbs displace far
    // enough to emerge through the torso.
    o.forceshader =
        SilhouetteShader(bound(0, CVARF(cg_player_outline_width), 2));
    // Explicit override if one is set, otherwise follow the team colour.
    vector col;
    if (player.teamno == team_no)
        col = CVAR.outline_friendly;
    else
        col = CVAR.outline_enemy;

    if (col == '0 0 0') {
        if (player.teamno == TeamRed)
            col = '1.0 0.45 0.40';
        else
            col = '0.45 0.75 1.0';
    }

    o.colormod = col;

    o.scale = 1;   // expansion is in the shader now, not geometric
    o.drawmask = MASK_ENGINE;

    o.frame = player.frame;
    o.frame2 = player.frame2;
    o.lerpfrac = player.lerpfrac;
    o.angles = player.angles;
    o.renderflags = player.renderflags;
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

    /* UpdateOutline(self); */
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
.float next_team_update;

float CSQC_UpdatePlayer(float isnew) {
    if (self.entnum == player_localentnum)
        self.renderflags |= RF_EXTERNALMODEL;
    else
        self.renderflags &= ~RF_EXTERNALMODEL;

    UpdateSilhouette(self);

    // .teamno is what find_list() matches on in UpdateGrenList.  It used to be
    // set only in UpdatePlayer(), which deltalisten never registers -- so it
    // stayed TeamNone on every player and the grenade timer list came back
    // empty no matter what.  Set it here, on the callback that actually runs,
    // and throttle it the way the skin update below is: TeamNo() is an
    // infokey+stof and this is a per-player per-frame path.
    if (time > self.next_team_update) {
        self.teamno = TeamNo(self);
        self.next_team_update = time + 0.1;
    }

    // Needs this for both cases since deltalisten() inadvertently blocks.
    if (PowerupGlowVisible(self.entnum == player_localentnum) &&
        (self.effects & EF_DIMLIGHT))
        dynamiclight_add(self.origin, 200, CVAR.r_dimlight_colour);

    entity csqc = self.csqc_player;
    if (!CVARF(tf_forcecolors) || game_state.is_spectator) {
        self.drawmask = MASK_ENGINE;
        if (csqc != __NULL__)
            csqc.drawmask = 0;
        return TRUE;
    }

    // Spawn the colour-forced duplicate lazily.  This callback now runs for
    // every player regardless of tf_forcecolors -- it is what feeds the
    // grenade timers -- so creating the copy up front would leave an unused
    // entity per player on every client with the colour feature off.
    if (csqc == __NULL__) {
        AddCSQCPlayer(self);
        csqc = self.csqc_player;
    }

    // Ahead of the early-out below, which only compares position and frames:
    // spawn protection changes alpha and nothing else, so an alpha-only change
    // would otherwise never reach the copy.  The networked entity is hidden
    // while the copy is drawn, so if the copy does not carry it, it is lost.
    csqc.alpha = self.alpha;

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


// game_state.is_player is false whenever team_no reads 0, which includes a
// real player mid class change, mid respawn, or before the stat first lands --
// not just an actual spectator.  Keying the spectator allowance off !is_player
// therefore handed those players both teams' timers for a moment.  Ask whether
// we are genuinely spectating instead, and fail closed.
static float ViewerIsSpectator() {
    return isdemo() ||
           stof(getplayerkeyvalue(player_localnum, "*spectator")) != 0;
}

static float ShowTeamGrenTimer(float team, float my_team) {
    if (ViewerIsSpectator() && TFxEnabled(TFX_SPEC_GRENTIMER))
        return TRUE;

    if (prematch && TFxEnabled(TFX_PREMATCH_EVERYTHING))
        return TRUE;

    // Gated on the viewer's role rather than whose timer it is, so a defence
    // that may not see them does not start seeing them by looking at an
    // attacker.  Own team, and for a spy the other team too -- no disguise
    // required.
    float role = (my_team == AttackingTeamNo()) ? TFX_OFFENSE_GRENTIMER
                                                : TFX_DEFENSE_GRENTIMER;
    if (TFxEnabled(role) &&
        (team == my_team || WP_PlayerClass() == PC_SPY))
        return TRUE;

    return FALSE;
}

static entity gren_list[20];
static int num_gren_list;
static float next_grenlist_update;

// Death animations occupy frames 41..102 -- axdeth, then deatha through
// deathe; see the anim_player_die* tables in ssqc/player.qc.  Living frames sit
// below (stand/run/attack/pain/axstnd) and above (the weapon attacks from 103),
// so the range is unambiguous, and player_die_extra() parks a corpse on its
// final death frame so it keeps testing dead.
//
// This is a local check, so it holds even if the server's clear message is
// lost.  It does not replace that message: a grenade also gets destroyed while
// its owner is alive and upright (class change, team change, respawn), which
// no amount of looking at the model can tell us about.
const float kGrenTimerAlpha = 0.8;   // wedge only; the number stays opaque

#define FRAME_DEATH_FIRST 41
#define FRAME_DEATH_LAST  102

static float PlayerLooksDead(entity p) {
    return p.frame >= FRAME_DEATH_FIRST && p.frame <= FRAME_DEATH_LAST;
}

// Filled disc sweeping away clockwise from twelve o'clock as the fuse burns
// down.  R_BeginPolygon builds a triangle fan from the vertex list, so centre
// first then the arc gives a pie slice directly; flags&4 draws it immediately
// in 2D, matching how sui_sys.qc renders its quads.
static void DrawGrenPie(vector centre, float radius, float frac, vector rgb,
                        float alpha) {
    const float kMaxSeg = 24;

    frac = bound(0, frac, 1);
    float segs = ceil(kMaxSeg * frac);
    if (segs < 1)
        return;

    R_BeginPolygon("", 4);
    R_PolygonVertex(centre, '0 0 0', rgb, alpha);
    for (float i = 0; i <= segs; i++) {
        // Screen y grows downward, so increasing angle sweeps clockwise.
        float a = ((i / segs) * frac - 0.25) * 6.28318531;
        R_PolygonVertex(centre + [cos(a), sin(a), 0] * radius,
                        '0 0 0', rgb, alpha);
    }
    R_EndPolygon();
}

static float RenderGrenTimer(entity p, float test_only) {
    const float maxd = 1000, mind = 200;
    vector po = p.origin + '0 0 40';
    vector o = PM_Org();

    if (p.entnum == player_localentnum)
        return FALSE;

    if (PlayerLooksDead(p))
        return FALSE;

    float diff = vlen(po - o);
    if (diff > maxd)
        return FALSE;

    // project() has no notion of behind the camera -- a point at your back
    // lands on screen just the same, so the timer would draw over empty space
    // in front of you.  Same guard RenderHitText uses.
    makevectors(getviewprop(VF_ANGLES));
    if (v_forward * (po - o) <= 0)
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

    // Indexed by floor(rem), so it reads bottom-up as the fuse burns down:
    // green at full, through yellow, to red on the last second.
    vector colors[] = { '1.00 0.25 0.20',    // 0s -- about to go off
                        '1.00 0.55 0.15',
                        '1.00 0.90 0.20',
                        '0.30 0.90 0.35' };  // freshly primed
    vector c = project(po);
    vector size = '7 7 7' * (maxd - max(diff, mind)) / (maxd - mind);
    float ci = bound(0, floor(rem), colors.length - 1);
    vector rgb = colors[ci];
    float style = CVARF(tfx_grentimer_style);

    if (style != 0) {
        float radius = size.x * 1.2;
        DrawGrenPie(c, radius, 1, '0 0 0', 0.45);            // backing disc
        DrawGrenPie(c, radius, rem / he->grentimer_span, rgb,
                    kGrenTimerAlpha);
    }

    if (style != 1) {
        string str = ftos(ceil(rem));
        vector tc = c;
        tc.x -= stringwidth(str, FALSE, size) / 2;
        tc.y -= size.y / 2;
        drawstring(tc, str, size, rgb, 1, 0);
    }

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
        if (!ShowTeamGrenTimer(team, team_no))
            continue;

        int count;
        entity* players = find_list(teamno, team, EV_FLOAT, count);
        for (int j = 0; j < count && num_gren_list < gren_list.length; j++) {
            entity p = players[j];

            if (RenderGrenTimer(p, TRUE))
                gren_list[num_gren_list++] = p;
        }
    }
}

void TFxRenderGrenadeTimers() {
    // Checked before UpdateGrenList so turning it off also skips the scan and
    // its per-player traces, not just the drawing.
    if (!CVARF(cg_draw_grentimer))
        return;

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

    // Remember how long the fuse was when we heard about it, so the pie can
    // show a fraction without hardcoding the duration from ssqc/tfort.qc.
    he->grentimer_span = max(0.1, expiry - time);
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
    // Was a debugging convenience for defeating the on-client shader cache
    // between builds.  Now always on and build-stable rather than random:
    // these names are the same override target as the silhouette shader --
    // see SilSuffix() above.
    return strcat(prefix, FO_NAME_SUFFIX);
}

void RegisterPlayerListener() {
    STATIC_INIT_ONCE();

    // deltalisten can only be established on connect, so this cannot wait on
    // anything server-supplied.  It used to bail unless tf_forcecolors was set
    // -- which defaults off -- so CSQC_UpdatePlayer never ran at all on a
    // default client, and player entities were reachable from nowhere.
    // Register unconditionally: the callback's !tf_forcecolors path restores
    // drawmask = MASK_ENGINE, so players draw normally with the colour feature
    // off, exactly as the flag listeners in TFX_Flag_Init() do.
    if (isdemo() || !CVARF(cg_player_listener))
        return;

    deltalisten("progs/player.mdl", CSQC_UpdatePlayer, 0);
}

void TFX_Init() {
    STATIC_INIT_ONCE();

    printf("TFX active.\n");

#if 0
    RegisterPlayerListener();

    shader_team[0] = shaderforname(rnds("blue_team_outline"), OutlineShader("textures/sfx/quad.tga"));
    shader_team[1] = shaderforname(rnds("red_team_outline"), OutlineShader("textures/sfx/pent.tga"));
    shader_flag = shaderforname(rnds("flag_outline"), OutlineShader("textures/sfx/specular.tga"));

    shader_over_outline = shaderforname(rnds("over_outline"), "{ sort 7 }");
#endif
}

void TFX_Flag_Init() {
    STATIC_INIT_ONCE();

    deltalisten("progs/ff_flag.mdl", UpdateFlag, 0);
    deltalisten("progs/tf_flag.mdl", UpdateFlag, 0);
    deltalisten("progs/tf_stan.mdl", UpdateFlag, 0);
}
