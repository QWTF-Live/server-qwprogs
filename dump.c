static float model_cache[32][2];

/*
 * This is a hack so that we can have our client entity be closer to server for
 * shared code.  We'll refactor this on both sides to be cleaner later, but it
 * gets us started
 * for now.
 */
.float reload_rocket_launcher;
.float reload_grenade_launcher;
.float reload_shotgun;
.float reload_super_shotgun;
.float reload_sniper_rifle;

typedef struct prediction_state
{
    int     state;

    int     impulse;
    int     weapon;
    int     items;

    int     frame;

    int     ammo[AMMO_LAST];
    int     clip_fired[5];

    float   attack_finished;
    float   client_time;

    float   client_nextthink;
    int     client_thinkindex;

    int     client_predflags;
    float   client_ping;
};

prediction_state weapon_server;
prediction_state weapon_predicted;

void WeaponPred_Init()
    // Precache Models
    for (float i = 1; i <= WEAP_LAST; i >>= 1) {
        FO_WeapInfo wi;

        FO_FillWeapInfo(world, i, &wi);
        for (float j = 0; j < 2; j++)
            if (wi->model[j] != string_null)
                model_cache[FO_WeapToIndex(weapon)][j] =
                    getmodel_index(wi->model[j]);
    }

    // predicted follows
    weapon_server.weapon = IT_ROCKET_LAUNCHER;
    weapon_server.client_ping = 0.5;

    weapon_predicted = weapon_server;

    fake_predweap = spawn();
    fake_predweap.renderflags = RF_VIEWMODEL;
    fake_predweap.predraw = WeaponPred_Think;
    fake_predweap.drawmask = MASK_ENGINE; // XXX
}

#if 0
entity predweap_entity;

weaponstate weapon_server;
weaponstate weapon_pred;


void WeaponPred_Init()
{
    model_axe           = getmodelindex("progs/v_axe.mdl");
    model_shotgun       = getmodelindex("progs/v_shot.mdl");
    model_sshotgun      = getmodelindex("progs/v_shot2.mdl");
    model_nailgun       = getmodelindex("progs/v_nail.mdl");
    model_snailgun      = getmodelindex("progs/v_nail2.mdl");
    model_grenadel      = getmodelindex("progs/v_rock.mdl");
    model_rocketl       = getmodelindex("progs/v_rock2.mdl");
    model_light         = getmodelindex("progs/v_light.mdl");
    model_hook          = getmodelindex("progs/v_star.mdl");
    model_coilgun       = getmodelindex("progs/v_coil.mdl");

    // predicted follows
    weapon_server.weapon = IT_ROCKET_LAUNCHER;
    weapon_server.client_ping = 0.5;

    weapon_predicted = weapon_server;

    fake_predweap = spawn();
    fake_predweap.renderflags = RF_VIEWMODEL;
    fake_predweap.predraw = WeaponPred_Think;
    fake_predweap.drawmask = MASK_ENGINE; // XXX
}

void EntUpdate_WeaponPred(float is_new) {
    float sendflags = ReadByte();
    weapon_server.state = WEPSTATE_FRESH;
    if (sendflags & WPFL_IMPULSE) {
        weapon_server.impulse = ReadByte();
        weapon_server.slot = ReadByte();
        weapon_server.weapon = ReadShort();
    }

    if (sendflags & WPFL_AMMO_SHELLS)
        weapon_server.ammo[AMMO_SHELLS] = ReadByte();
    if (sendflags & WPFL_AMMO_NAILS)
        weapon_server.ammo[AMMO_NAILS] = ReadByte();
    if (sendflags & WPFL_AMMO_ROCKETS)
        weapon_server.ammo[AMMO_ROCKETS] = ReadByte();
    if (sendflags & WPFL_AMMO_CELLS)
        weapon_server.ammo[AMMO_CELLS] = ReadByte();

    if (sendflags & WPFL_CLIP1)
        weapon_server.clips[0] = ReadByte();
    if (sendflags & WPFL_CLIP2)
        weapon_server.clips[1] = ReadByte();
    if (sendflags & WPFL_CLIP3)
        weapon_server.clips[2] = ReadByte();

    if (sendflags & WPFL_RELOAD) {
        weapon_server.reload_finished = ReadFloat();
    }

    if (sendflags & WPFL_EXPIRIES) {
        weapon_server.attack_finished = ReadFloat();
        weapon_server.client_nextthink = ReadFloat();
        weapon_server.client_thinkindex = ReadByte();
    }

    if (sendflags & 64)
    {
        weapon_server.client_time = ReadFloat();
        weapon_server.frame = ReadByte();
    }

    if (sendflags & 128)
    {
        weapon_server.client_predflags = ReadByte();
        weapon_server.client_ping = ReadByte() / 1000;
    }

    if (is_new)
    {
        self.drawmask = MASK_PRED_VIEWMODEL;
        self.predraw = WeaponPred_Think;
        self.renderflags = RF_VIEWMODEL;
    }
}


}

#endif
