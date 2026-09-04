// weap, attack time, ammo, clip size, ammo/shot reload time/clip
//

enum {
    FOWEAP_RL,
    FOWEAP_IL,
    FOWEAP_FT,
    FOWEAP_GL,
    FOWEAP_SNG,
    FOWEAP_NG,
    FOWEAP_SG,
    FOWEAP_SSG,
    FOWEAP_AC,
    FOWEAP_RAIL,
    FOWEAP_SNIPE,
    FOWEAP_TRANQ,
    FOWEAP_AXE,
    FOWEAP_TYPES
};

enum {
    AMMO_ROCKETS,
    AMMO_CELLS,
    AMMO_NAILS,
    AMMO_SHELLS,
    AMMO_TYPES
};

struct weapon_info {
    int id;
    float attack_time;
    int ammo_type;
    int clip_size;
    int ammo_per_shot;
    float reload_per_shot;
    string model;
};

struct weapon_state {
    int impulse;
    int slot;
    int weapon;

    int ammo[AMMO_TYPES];
    int clips[3];

    float reload_finished;
    int reload_index;

    float attack_finished;
    float client_nextthink;
    int client_thinkindex;

};

enumflags WeaponPredFlags {
    WPFL_IMPULSE,
    WPFL_AMMO_SHELLS,
    WPFL_AMMO_NAILS,
    WPFL_AMMO_ROCKETS,
    WPFL_AMMO_CELLS,
    WPFL_CLIP1,
    WPFL_CLIP2,
    WPFL_CLIP3,
    WPFL_RELOAD,
    WPFL_EXPIRIES,
};

weapon_info weaps[FOWEAP_TYPES] = {
    { FOWEAP_RL, 0.8, AMMO_ROCKETS, 4, 1, 5/4, "progs/v_rock.mdl" },
};
#if 0
{
/* FOWEAP_IL,   */ { 0 },
/* FOWEAP_FT,   */ { 0 },
/* FOWEAP_GL,   */ { 0 },
/* FOWEAP_SNG,  */ { 0 },
/* FOWEAP_NG,   */ { 0 },
/* FOWEAP_SG,   */ 
/* FOWEAP_AC,   */ { 0 },
/* FOWEAP_RAIL, */ { 0 },
/* FOWEAP_SNIPE,*/ { 0 },
/* FOWEAP_TRANQ,*/ { 0 },
/* FOWEAP_AXE,  */ { 0 },
/* FOWEAP_TYPES */
};

void InitWeaps() {
    weaps[FOWEAP_RL] = { 0.8, AMMO_ROCKETS, 4, 1, 5/4, "progs/v_rock.mdl" };
    weaps[FOWEAP_SG] = { 0.4, AMMO_SHELLS, 8, 1, 0.25, "progs/v_shot.mdl" };
    weaps[FOWEAP_SSG] = { 0.7, AMMO_SHELLS, 16, 2, 0.375/2, "progs/v_shot2.mdl" };
}

float CanFire() {
    if (weapon_predicted.reloading_until < time)
        return FALSE;
    if (weapon_predicted.ammo[nweap->ammo_type] < nweap->ammo_per_shot)
        return FALSE;
    return true;
}

void W_Attack() {
    weapon_predicted.attack_finished += nweap->attack_time;
    weapon_predicted.ammo[nweap->ammo_type] -= nweap->ammo_per_shot;

}
#endif

class FOState {
    float class_;
    float ammo_[AMMO_TYPES];
    float max_ammo_[AMMO_TYPES];
    float clip_;

};

class FOWeapon {
    string name_;
    string ammo_type;
    string ammo;
    string clip_size;
};

FOWeapon weapons[FOWEAP_TYPES];

