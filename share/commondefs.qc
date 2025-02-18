const string kLoginHash = "CRC16";
const string kLoginKey = "_qwtfl_login";
const string kLoginNonce = "_qwtfl_nonce";
const string kFoToken = "_fo_token";

const string kQWTF = "#QWTF.live: ";

struct FPPState {
    int index;
    float expires_at;

#ifdef SSQC
    int flags;
    float dynamic_dt;
#endif

    union {
        int aux;
        int gren_type;
        int ammo_index;
    };
};

.FPPState fpp;

struct ConcState {
    float next, mag;
    float next_push, next_flip;
};
.ConcState conc_state;


enumflags {
    FPF_NO_REWIND,
};

#define TMPL_CONFIG_DATA(_OP) \
    _OP(1, Byte, float, min_ping_ms) \
    _OP(2, Byte,  float, tfx_flags) \
    _OP(2, Short, float, predict_flags) \
    _OP(2, Short, float, rewind_flags) \
    _OP(3, Byte,  float, static_newmis_ms) \
    _OP(3, Byte,  float, dynamic_newmis_ms) \
    _OP(3, Byte,  float, max_rewind_ms) \
    _OP(3, Byte,  float, max_rewind_slow_projectile_ms) \
    _OP(3, Byte,  float, max_rewind_fast_projectile_ms) \
    _OP(3, Short, float, max_rewind_grenade_ms) \
    _OP(3, Short, float, rewind_fast_projectile_thresh) \
    _OP(4, Short, float, clown_flags) \
    _OP(4, Short, float, clown_grav) \
    _OP(5, Byte,  float, old_ng_rof) \
    _OP(5, Byte,  float, gren_beta_disable) \
    _OP(5, Byte,  float, fo_concuss) \
    _OP(6, Float, float, rj) \
    _OP(6, Float, float, pipe_cooldown) \
    _OP(7, Short, float, new_balance) \
    _OP(7, Short, float, new_balance_flags)


var struct {
#define DECLOP(_ig1, _ig2, _type, _field) \
    _type _field;
  TMPL_CONFIG_DATA(DECLOP)
#undef DECLOP
} tf_config;

enumflags {
    REWIND_PROJ_FIRE,
    REWIND_PROJ_TRAVEL,
    REWIND_GRENADES,
    REWIND_SENDEVENT,
    REWIND_FORWARD_PROJ_SELFKNOCK,
    REWIND_DOUBLE_COL,
    REWIND_FORWARD_DOORS,
};

string REWIND_DESC[] = {
    "rewind projectile on firing",
    "rewind on projectile travel",
    "rewind grenade throws",
    "use sendevent augmentation (allows race w/ death rewind)",
    "forward projectile self-knockback",
    "additional collision checks",
    "open doors earlier for hpbs [requires rfd=1]",
};

const float REWIND_DEFAULT_FLAGS = REWIND_PROJ_FIRE |
                                   REWIND_PROJ_TRAVEL |
                                   REWIND_FORWARD_PROJ_SELFKNOCK |
                                   REWIND_SENDEVENT |
                                   REWIND_DOUBLE_COL;


float RewindFlagEnabled(float flag) {
    return tf_config.rewind_flags & flag;
}

enumflags {
    TFX_PREMATCH_EVERYTHING,
    TFX_SCOUT_SEE_ENEMIES,
    TFX_SPEC_OUTLINE,
    TFX_SPEC_SEEFLAG,
    TFX_SPEC_GRENTIMER,
    TFX_OFFENSE_SEEFLAG,
    TFX_DEFENSE_SEEFLAG,
    TFX_OFFENSE_OUTLINE,
    TFX_DEFENSE_OUTLINE,
    TFX_OFFENSE_GRENTIMER,
    TFX_DEFENSE_GRENTIMER,
};

string TFX_DESC[] = {
    "Prematch see everything",
    "Scout sees enemies",
    "Spectators see outlines",
    "Spectators see flags",
    "Spectators see grenade timers",
    "Offense sees flag (always)",
    "Defense sees flag, when not carried",
    "Offense sees grentimers",
    "Defense sees grentimers",
    "Offense sees outlines",
    "Defense sees outlines",
};

float TFxEnabled(float flag) {
    return tf_config.tfx_flags & flag;
}

const float TFX_DEFAULT_FLAGS = 0;

enumflags {
    FOC_ON_DEF,  // apply foc_defaults
    FOC_ON_NODEF,
    FOC_AFF_MED,
    FOC_EASY_AIR,
    FOC_EASY_GROUND,
    FOC_DISTANCE,
    FOC_RED_MED,
};

const float foc_defaults = FOC_AFF_MED | FOC_EASY_AIR;

string FO_CONC[] = {
    "on (w/ defaults)",
    "on (no defaults)",
    "affects medic",
    "easy air control",
    "easy ground control",
    "distance based",
    "reduce medic effect",
};

enumflags {
    CLOWN_FAST_PROJECTILES,
    CLOWN_RUBBERGREN,
    CLOWN_PROJ_GRAVITY,
    CLOWN_LETHAL_TRANQ,
    CLOWN_CONC,
    CLOWN_STICKY_GRENS,
    CLOWN_STICKY_PIPES,
    CLOWN_SPAM_GRENADES,
};

string CLOWN_DESC[] = {
    "fast projectiles",
    "rubber grenades",
    "projectile gravity",
    "elephant tranq",
    "perma conc",
    "sticky grenades",
    "sticky pipes",
    "no grenade prime-time",
};

inline float IsClownMode(int flag) {
    return tf_config.clown_flags & flag;
}

const float SERVER_FPS = 77;
const float SERVER_FRAME_DT = 1/SERVER_FPS;
const float SERVER_FRAME_MS = SERVER_FRAME_DT * 1000.0;

.vector s_origin;

#define MAX_FLAGINFO_LINES  10
#define ENG_BUILDING_DISMANTLE_DISTANCE 100
#define ENG_BUILDING_MAINT_DISTANCE 80
#define ENG_DISPENSER_COST 100
#define ENG_SENTRY_COST 130

#define GAMEMODE_CLAN       1
#define GAMEMODE_QUAD       2
#define GAMEMODE_DUEL       4
#define GAMEMODE_VOTE       8

#define MSG_FLAGINFOINIT    1
#define MSG_FLAGINFO        2
#define MSG_PREDICTSTATE    3

#define MSG_SBAR            4
#define MSG_GRENPRIMED      5
#define MSG_CLIENT_MENU     6
#define MSG_TEAMS_UPDATE    7
#define MSG_CLASSES_UPDATE  8
#define MSG_SENTRY_POS      9
#define MSG_DISPENSER_POS   10
#define MSG_SERVER_ADMIN_INFO   11
#define MSG_CAPTAINS        12
#define MSG_MOTD            13
#define MSG_PREMATCH        14
#define MSG_GRENTHROWN      15
#define MSG_ID              16
#define MSG_TEAM_SCORES     17
#define MSG_VOTE_MAPS       18
#define MSG_VOTE_UPDATE     19
#define MSG_VOTE_MAP_ADD    20
#define MSG_VOTE_MAP_DELETE 21
#define MSG_PAUSE           22
#define MSG_UNPAUSE         23
#define MSG_TFX_GRENTIMER   24
#define MSG_QUAD_ROUND_BEGIN 25
#define MSG_HITFLAG         26
// unused 27
#define MSG_CACHE_LOGIN     28
#define MSG_TFL_CONFIG      29
#define MSG_SOUND           30
#define MSG_NEXT_END_TIME   31
#define MSG_MENU_CANCEL     32
#define MSG_MIGRATE_LOGIN   33

#define FLAGINFO_HOME       1
#define FLAGINFO_CARRIED    2
#define FLAGINFO_DROPPED    3
#define FLAGINFO_RETURNING  4
#define FLAGINFO_LOCATION   5
#define FLAGINFO_NOLOCATION 6

#define FLAGINFO_ICON_FLAG  0
#define FLAGINFO_ICON_BUTTON 1

#define MSG_MENU_SPY_FLAG_IVIS_ONLY     1
#define MSG_MENU_SPY_FLAG_UNDERCOVER    2
#define MSG_MENU_SPY_FLAG_FEIGNING      4

#define CLIENT_MENU_TEAM      1
#define CLIENT_MENU_CLASS     2
#define CLIENT_MENU_DROPAMMO  3
#define CLIENT_MENU_SCOUT     4
#define CLIENT_MENU_SPY       5
#define CLIENT_MENU_SPY_SKIN  6
#define CLIENT_MENU_SPY_TEAM  7
#define CLIENT_MENU_DETPACK   8
#define CLIENT_MENU_BUILD     9
#define CLIENT_MENU_ROTATE_SENTRY  10
#define CLIENT_MENU_FIX_DISPENSER  11
#define CLIENT_MENU_USE_DISPENSER  12
#define CLIENT_MENU_ADMIN  13
#define CLIENT_MENU_ADMIN_KICK  14
#define CLIENT_MENU_ADMIN_BAN  15
#define CLIENT_MENU_ADMIN_FORCE_SPEC  16
#define CLIENT_MENU_ADMIN_QUAD_TIMELIMIT  17
#define CLIENT_MENU_ADMIN_TIMELIMIT  18
#define CLIENT_MENU_ADMIN_FRAGLIMIT  19
#define CLIENT_MENU_VOTE    20
#define CLIENT_MENU_CAPTAIN_1    21
#define CLIENT_MENU_CAPTAIN_2    22
#define CLIENT_MENU_CAPTAIN_PICK   23
#define CLIENT_MENU_MAPS           24

#define BUTTON0 1
/* BUTTON1 not supported */
#define BUTTON2 2
#define BUTTON3 4
#define BUTTON4 8
#define BUTTON5 16
#define BUTTON6 32
#define BUTTON7 64
#define BUTTON8 128
// #define BUTTON9 2048
// #define BUTTON10 4096
// #define BUTTON11 8192
// #define BUTTON12 16384
// #define BUTTON13 32768
// #define BUTTON14 65536
// #define BUTTON15 131072
// #define BUTTON16 262144
//

#define BUTTON_ATTACK   BUTTON0
#define BUTTON_JUMP     BUTTON2
#define BUTTON_SPECIAL1 BUTTON3
#define BUTTON_SPECIAL2 BUTTON4
#define BUTTON_GRENADE1 BUTTON5
#define BUTTON_GRENADE2 BUTTON6
#define BUTTON_DROPFLAG BUTTON7

enumflags {
    HITFLAG_NOARMOUR,
    HITFLAG_KILLINGBLOW,
    HITFLAG_MEATSHOT,
    HITFLAG_HEADSHOT,
    HITFLAG_SELF,
    HITFLAG_FRIENDLY,
    HITFLAG_CUSS,
    HITFLAG_FEIGNEDENEMY,
    HITFLAG_NOAUDIO,
    HITFLAG_NOTEXT,
    HITFLAG_IMFLASHED,
    HITFLAG_KILLEDUNDERCOVERSPY,
};

enumflags {
    CSQC_WEAP_PRED,
    CSQC_PROJ_PRED,
    CSQC_PMOVE,
    CSQC_FORCE_POS,
    CSQC_SNIPER_SIGHT,
};

#ifdef SSQC
float new_balance;
#endif

float NewBalanceActive() {
#ifdef CSQC
    return tf_config.new_balance;
#else
    return new_balance & 1;
#endif
}

enumflags {
    NBF_CONC_NEW_CAP,
    NBF_NO_CAP,
};

string NBF_DESC[] = {
    "Reworked conc speed cap",
    "No conc speed cap",
};

enumflags {
    PMF_JUMP_HELD,
};

enum {
    Eng_NotBuilding = 0,  // Must be 0
    Eng_BuildingDisp,
    Eng_BuildingSentry,
};

#define STATIC_INIT_ONCE() \
    static float _init = FALSE; \
    if (_init) return; \
    _init = TRUE

#define PERIODIC(_p) \
    static float _next; \
    if (time > _next && (_next = time + _p))
