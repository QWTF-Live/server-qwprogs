DEFCVAR_FLOAT(fo_grentimer, 2);  // Sound + Ping adjust
DEFCVAR_STRING(fo_grentimersound, "grentimer.wav");
DEFCVAR_FLOAT(fo_grentimervolume, 1);

// When set (not -1) and spectating, supercedes fo_grentimervolume.
DEFCVAR_FLOAT(fo_spec_grentimervolume, -1);

DEFCVAR_FLOAT(fo_oldscoreboard, 0);
DEFCVAR_FLOAT(fo_default_weapon, 0);
DEFCVAR_FLOAT(fo_team_color_crosshair, 0);

DEFCVAR_FLOAT(fo_hitaudio_enabled, 1);
DEFCVAR_FLOAT(fo_hitaudio_hurtself, 1);
DEFCVAR_FLOAT(fo_hitaudio_hurtteam, 1);
DEFCVAR_FLOAT(fo_hitaudio_hurtenemy, 1);
DEFCVAR_FLOAT(fo_hitaudio_killself, 1);
DEFCVAR_FLOAT(fo_hitaudio_killteam, 1);
DEFCVAR_FLOAT(fo_hitaudio_killenemy, 1);
DEFCVAR_FLOAT(fo_hitaudio_noarmour, 1);

DEFCVAR_FLOAT(fo_hittext_enabled, 1);
DEFCVAR_FLOAT(fo_hittext_size, 16);
DEFCVAR_FLOAT(fo_hittext_speed, 96);
DEFCVAR_FLOAT(fo_hittext_duration, 2);
DEFCVAR_FLOAT(fo_hittext_alpha, 1);
DEFCVAR_FLOAT(fo_hittext_rawdamage, 1);
DEFCVAR_FLOAT(fo_hittext_noarmour, 1);
DEFCVAR_FLOAT(fo_hittext_offset, 32);
DEFCVAR_FLOAT(fo_hittext_friendly, 0);
DEFCVAR_STRING(fo_hittext_colour, "");
DEFCVAR_STRING(fo_hittext_colour2, "");
DEFCVAR_STRING(fo_hittext_colour3, "");

DEFCVAR_FLOAT(fo_hud_idle_alpha, 0.3);
DEFCVAR_FLOAT(fo_adminrefresh, 2);

// 1: Force blue/red
// 2: Force attack/defense colors
// 3: Force enemy/team colors
DEFCVAR_FLOAT(tf_forcecolors, 0);
DEFCVAR_STRING(tf_color_enemy, "");
DEFCVAR_STRING(tf_color_team, "");
DEFCVAR_STRING(tf_color_attack, "");
DEFCVAR_STRING(tf_color_defense, "");

DEFCVAR_FLOAT(r_rocketlight, 1);
DEFCVAR_FLOAT(r_rocketlight, 1);
DEFCVAR_STRING(r_rocketlight_colour, "");  // Radius ignored.

DEFCVAR_STRING(r_dimlight_colour, "");

struct {
    vector r_rocketlight_colour;
    vector tf_color_enemy, tf_color_team;
    vector tf_color_attack, tf_color_defense;

    vector fo_hittext_reg, fo_hittext_noarmor, fo_hittext_friendly;
    vector r_dimlight_colour;
} CVAR;

static vector stov_def(string val, vector def) {
    return (val == "") ? def : stov(val);
}

static float kCvarUpdateInterval = 0.2;
void UpdateCachedCvars() {
    static float next;
    if (time < next)
        return;
    next = time + kCvarUpdateInterval;

    CVAR.r_rocketlight_colour = stov_def(CVARS(r_rocketlight_colour), '2.0 1.0 0.25');
    CVAR.tf_color_enemy = stov_def(CVARS(tf_color_enemy), '0 2 0');
    CVAR.tf_color_team = stov_def(CVARS(tf_color_team), '1 0 1');
    CVAR.tf_color_attack = stov_def(CVARS(tf_color_attack), '0.5 0.5 2');
    CVAR.tf_color_defense = stov_def(CVARS(tf_color_defense), '2 0.5 0.5');

    CVAR.fo_hittext_reg = stov_def(CVARS(fo_hittext_colour), '1 1 1');
    CVAR.fo_hittext_noarmor = stov_def(CVARS(fo_hittext_colour2), '1 0 1');
    CVAR.fo_hittext_friendly = stov_def(CVARS(fo_hittext_colour3), '1 0 0');

    CVAR.r_dimlight_colour = stov_def(CVARS(r_dimlight_colour), '2 1 0.5');
}
