void () player_run;

void () TeamFortress_DisplayDetectionItems;
float (vector veca, vector vecb) crossproducttf;

void (vector org, float damage) SpawnBlood;

void () SuperDamageSound;

void (Slot slot) W_ChangeWeaponSlot;
void () W_ChangeToBestWeapon;
void () W_PrintWeaponMessage;

void () button_fire;

void (entity pl, float fr) TF_AddFrags;

void () DropGoalItems;

void () TeamFortress_DisplayLegalClasses;

void () TeamFortress_ShowIDs;
void () TeamFortress_ShowTF;

void TeamFortress_PrimeGrenade(float inp, float is_player);
void () TeamFortress_ThrowGrenade;
void (float inp) TeamFortress_PrimeThrowGrenade;

void () PipebombTouch;

void () SniperSight_Create;

void (float zoom_to) Sniper_Zoom;

void () Help_Show;
void () TeamFortress_Inventory;
void () TeamFortress_SaveMe;
void (entity pe_player, float f_type) CF_Identify;
void () TeamFortress_ReloadNext;
void () Sniper_ZoomToggle;
void (float zoom_in) Sniper_ZoomAdjust;
void () TeamFortress_StatusQuery;
void () CF_Scout_Dash;
void () CF_Spy_DisguiseStop;
void Scout_ToggleScanner(float toggle_mask);
void () TeamFortress_DetpackMenu;
void () CF_Medic_AuraToggle;
void () FO_Airblast;
void () TeamFortress_EngineerBuild;
void () TeamFortress_EngineerBuildStop;
void () TeamFortress_Scan;
void () TeamFortress_Discard;
void () TeamFortress_Discard_DropAmmo;
void (float issilent) FO_Spy_FeignCmd;
void () FO_Engineer_ToggleDispenser;
void () FO_Engineer_ToggleSentry;
void TeamFortress_QueuedDetpipe();
float TeamFortress_DetonatePipebombs(float force);
void (float timer) TeamFortress_ToggleDetpack;
void (float timer) TeamFortress_SetDetpack;
void () TeamFortress_DetpackStop;
void (entity e) TeamFortress_PlacePracticeSpawn;
void (entity e) TeamFortress_RemovePracticeSpawn;
void () DropKey;
void () RemoveFlare;
void () ScannerSwitch;
float () FO_CheckForReload;

void (float all) TeamFortress_TeamShowScores;
void (entity Player) TeamFortress_TeamShowMemberClasses;

void () Admin_CountPlayers;
void () Admin_CycleDeal;
void () Admin_DoKick;
void () Admin_DoBan;
void () Admin_CeaseFire;
void () Admin_UpdateServer;
void () Admin_ListIPs;

void () fadetoblack;
void () fadefromblack;
void () fadetowhite;
void () fadefromwhite;

void (entity disp) Engineer_UseDispenser;
void (entity gun) Engineer_UseSentryGun;

void () TeamFortress_HelpMap;
void () TeamFortress_NailGrenInfo;

void () BioInfection_Decay;
void () BioInfection_MonsterDecay;

float (float weap) W_GetSlot;
float (float weap) W_OldGetSlot;
void () W_FireFlame;
void W_FireIncendiaryCannon(vector org, vector angles, float use_ctime=0);
void () W_FireTranq;
void () W_FireRailgun;
void () W_FireImpeller;

void () HallucinationTimer;
void () TranquiliserTimer;

void () TeamFortress_CTF_FlagInfo;
void () ClanMode;
void () QuadMode;
void () PlayerReady;
void () PlayerNotReady;
void () Broadcast_Players_NotReady;
void () StartTimer;

void () ToggleInvincibility;

float () GetMaxWeaponInput;
float () IsUsingOldImpulses;
float () IsUsingCFImpulses;

void (entity pl) W_UpdateCurrentWeapon;

void (entity ent, float num) SetFlameCount;

void () W_Precache = {
    precache_sound("weapons/r_exp3.wav");
    precache_sound("weapons/rocket1i.wav");
    precache_sound("weapons/sgun1.wav");
    precache_sound("weapons/guncock.wav");
    precache_sound("weapons/ric1.wav");
    precache_sound("weapons/ric2.wav");
    precache_sound("weapons/ric3.wav");
    precache_sound("weapons/spike2.wav");
    precache_sound("weapons/tink1.wav");
    precache_sound("weapons/grenade.wav");
    precache_sound("weapons/bounce.wav");
    precache_sound("weapons/shotgn2.wav");
    precache_sound("wizard/wattack.wav");
    precache_sound("items/r_item1.wav");
    precache_sound("items/r_item2.wav");
    precache_model("progs/flame2.mdl");
    precache_sound("ambience/fire1.wav");
    precache_model2("progs/v_spike.mdl");
    precache_sound("hknight/hit.wav");
    precache_sound("weapons/detpack.wav");
    precache_sound("weapons/turrset.wav");
    precache_sound("weapons/turrspot.wav");
    precache_sound("weapons/turridle.wav");
    precache_sound("weapons/sniper.wav");
    precache_sound("weapons/flmfire2.wav");
    precache_sound("weapons/flmgrexp.wav");
    precache_sound("misc/vapeur2.wav");
    precache_sound("weapons/asscan1.wav");
    precache_sound("weapons/asscan2.wav");
    precache_sound("weapons/asscan3.wav");
    precache_sound("weapons/asscan4.wav");
    precache_sound("weapons/railgun.wav");
    precache_sound("weapons/dartgun.wav");
    precache_sound("misc/hitsound.wav");
    precache_sound("misc/hitsoundcrit.wav");
    precache_sound("misc/hitsoundteam.wav");
    precache_sound("weapons/flashgrenburst.wav");
    precache_sound("misc/killsound.wav");
    precache_sound("misc/killsoundteam.wav");
};

float () crandom = {
    return (2 * (random() - 0.5));
};

void (float att_delay) Attack_Finished = {
    if (self.tfstate & TFSTATE_TRANQUILISED)
        att_delay *= 2;

    self.attack_finished = self.client_time + att_delay;
    self.last_attack_ctime = self.client_time;
};

float* W_ammo_to_p(entity player, AmmoType ammo_type) {
    switch (ammo_type) {
        case AMMO_SHELLS: return &player.ammo_shells;
        case AMMO_CELLS: return &player.ammo_cells;
        case AMMO_NAILS: return &player.ammo_nails;
        case AMMO_ROCKETS:  return &player.ammo_rockets;
        default:
        case AMMO_NONE:
                        return __NULL__;
    }
    return __NULL__;
}

float W_ConsumeAmmoIfPossible(float ammo_type, float amount) {
    float *ammo = W_ammo_to_p(self, ammo_type);

    if (*ammo < amount)
        return FALSE;
    *ammo -= amount;
    return TRUE;
}


int () W_FireAxe = {
    local vector source;
    local vector org;
    local vector def;

    makevectors(self.v_angle);
    source = self.origin + '0 0 16';
    traceline(source, source + v_forward * 64, FALSE, self);
    if (trace_fraction == 1)
        return FALSE;

    org = trace_endpos - v_forward * 4;
    if (trace_ent.takedamage) {
        trace_ent.axhitme = 1;
        SpawnBlood(org, 20);

        deathmsg = DMSG_AXE;
        TF_T_Damage(trace_ent, self, self, 20, TF_TD_NOTTEAM, TF_TD_OTHER);
        return TRUE;
    } else {                    // hit wall
        FO_Sound(self, CHAN_WEAPON, "player/axhit2.wav", 1, ATTN_NORM);
        WriteByte(MSG_MULTICAST, SVC_TEMPENTITY);
        WriteByte(MSG_MULTICAST, TE_GUNSHOT);
        WriteByte(MSG_MULTICAST, 3);
        WriteCoord(MSG_MULTICAST, org_x);
        WriteCoord(MSG_MULTICAST, org_y);
        WriteCoord(MSG_MULTICAST, org_z);
        multicast(org, MULTICAST_PVS);
        return TRUE;
    }
};

int () W_FireKnife = {
    local vector source;
    local vector org;
    local vector def;

    makevectors(self.v_angle);
    source = self.origin + '0 0 16';
    traceline(source, source + v_forward * 64, FALSE, self);

    if (trace_fraction == 1)
        return FALSE;

    org = trace_endpos - v_forward * 4;
    if (trace_ent.takedamage) {
        trace_ent.axhitme = 1;
        SpawnBlood(org, 20);

        // TODO: Rework knife bloodying

        // Check direction of Attack
        makevectors(trace_ent.v_angle);
        def = v_right;
        makevectors(self.v_angle);

        // Backstab
        if (crossproducttf(def, v_forward) > 0) {
            deathmsg = DMSG_BACKSTAB;
            TF_T_Damage(trace_ent, self, self, 120,
                    TF_TD_NOTTEAM | TF_TD_IGNOREARMOR,
                    TF_TD_OTHER);
        } else {
            deathmsg = DMSG_KNIFE;
            TF_T_Damage(trace_ent, self, self, 40, TF_TD_NOTTEAM,
                    TF_TD_OTHER);
        }

        return TRUE;
    } else {                    // hit wall
        FO_Sound(self, CHAN_WEAPON, "player/axhit2.wav", 1, ATTN_NORM);
        WriteByte(MSG_MULTICAST, SVC_TEMPENTITY);
        WriteByte(MSG_MULTICAST, TE_GUNSHOT);
        WriteByte(MSG_MULTICAST, 3);
        WriteCoord(MSG_MULTICAST, org_x);
        WriteCoord(MSG_MULTICAST, org_y);
        WriteCoord(MSG_MULTICAST, org_z);
        multicast(org, MULTICAST_PVS);

        return TRUE;
    }
};

int () W_FireSpanner = {
    local vector source;
    local vector org;
    local float healam;
    local entity te;

    makevectors(self.v_angle);
    source = self.origin + '0 0 16';
    traceline(source, source + v_forward * 64, FALSE, self);

    if (trace_fraction == 1)
        return FALSE;

    org = trace_endpos - v_forward * 4;

    // It may be a trigger that can be activated by the engineer's spanner
    if (trace_ent.goal_activation & TFGA_SPANNER) {
        if (Activated(trace_ent, self)) {
            DoResults(trace_ent, self, TRUE);

            if (trace_ent.classname == "func_button") {
                trace_ent.enemy = self;
                other = self;
                self = trace_ent;
                self.dont_do_triggerwork = TRUE;
                button_fire();
                self = other;
            }
        } else if (trace_ent.else_goal != 0) {
            te = Findgoal(trace_ent.else_goal);
            if (te)
                AttemptToActivate(te, self, trace_ent);
        } else {
            FO_Sound(self, CHAN_WEAPON, "player/axhit2.wav", 1, ATTN_NORM);
            WriteByte(MSG_MULTICAST, SVC_TEMPENTITY);
            WriteByte(MSG_MULTICAST, TE_GUNSHOT);
            WriteByte(MSG_MULTICAST, 3);
            WriteCoord(MSG_MULTICAST, org_x);
            WriteCoord(MSG_MULTICAST, org_y);
            WriteCoord(MSG_MULTICAST, org_z);
            multicast(org, MULTICAST_PVS);
        }
        return TRUE;
    }

    if (trace_ent.takedamage) {
        if (trace_ent.classname == "building_dispenser") {
            Engineer_UseDispenser(trace_ent);
            return TRUE;

        } else if (trace_ent.classname == "building_sentrygun") {
            Engineer_UseSentryGun(trace_ent);
            return TRUE;

        } else if (trace_ent.classname == "building_sentrygun_base") {
            if (trace_ent.oldenemy)
                Engineer_UseSentryGun(trace_ent.oldenemy);
            return TRUE;

        } else if (trace_ent.classname == "player") {
            if ((((trace_ent.team_no == self.team_no) && (self.team_no != 0)) && teamplay) || coop) {

                healam = WEAP_SPANNER_REPAIR;

                if (self.ammo_cells < healam)
                    healam = self.ammo_cells;

                if (trace_ent.armortype == 0)
                    return TRUE;

                if ((trace_ent.maxarmor - trace_ent.armorvalue) < (healam * 4))
                    healam = ceil((trace_ent.maxarmor - trace_ent.armorvalue) / 4);

                if (healam > 0) {
                    trace_ent.armorvalue = trace_ent.armorvalue + healam * 4;

                    if (trace_ent.armorvalue > trace_ent.maxarmor)
                        trace_ent.armorvalue = trace_ent.maxarmor;

                    self.ammo_cells = self.ammo_cells - healam;

                    FO_Sound(trace_ent, CHAN_WEAPON, "items/r_item1.wav", 1, ATTN_NORM);

                    WriteByte(MSG_MULTICAST, SVC_TEMPENTITY);
                    WriteByte(MSG_MULTICAST, TE_GUNSHOT);
                    WriteByte(MSG_MULTICAST, 3);
                    WriteCoord(MSG_MULTICAST, org_x);
                    WriteCoord(MSG_MULTICAST, org_y);
                    WriteCoord(MSG_MULTICAST, org_z);
                    multicast(org, MULTICAST_PVS);
                }

                return TRUE;
            }

            trace_ent.axhitme = 1;
            SpawnBlood(org, 20);
            deathmsg = DMSG_SPANNER;
            TF_T_Damage(trace_ent, self, self, 20, TF_TD_NOTTEAM, TF_TD_OTHER);
        } else {
            TF_T_Damage(trace_ent, self, self, 20, TF_TD_NOTTEAM, TF_TD_OTHER);
        }
        return TRUE;
    } else {
        FO_Sound(self, CHAN_WEAPON, "player/axhit2.wav", 1, ATTN_NORM);
        WriteByte(MSG_MULTICAST, SVC_TEMPENTITY);
        WriteByte(MSG_MULTICAST, TE_GUNSHOT);
        WriteByte(MSG_MULTICAST, 3);
        WriteCoord(MSG_MULTICAST, org_x);
        WriteCoord(MSG_MULTICAST, org_y);
        WriteCoord(MSG_MULTICAST, org_z);
        multicast(org, MULTICAST_PVS);
        return TRUE;
    }
};

void RemoveConc(entity player, float remove_timer = TRUE);
entity FindConcTimer(entity player);

int () W_FireMedikit = {
    local vector source;
    local vector org;
    local float healam;
    local entity te;
    local entity BioInfection;

    source = self.origin + '0 0 16';
    traceline(source, (source + (v_forward * 64)), 0, self);

    if (trace_fraction == 1)
        return FALSE;

    org = trace_endpos - v_forward * 4;

    if (trace_ent.takedamage) {
        if (trace_ent.classname == "player") {

            if (((trace_ent.team_no == self.team_no) &&
                 (self.team_no != 0)) || coop) {

                healam = 200;
                if (trace_ent.tfstate & TFSTATE_CONC) {
                    SpawnBlood(org, 20);

                    bprint(PRINT_MEDIUM, self.netname, " cured ",
                           trace_ent.netname, "'s concussion\n");

                    entity te = FindConcTimer(trace_ent);
                    if (te.team_no != self.team_no)
                        TF_AddFrags(self, 1);

                    RemoveConc(trace_ent);
                }

                if (trace_ent.tfstate & TFSTATE_HALLUCINATING) {

                    te = find(world, classname, "timer");
                    while (((te.owner != trace_ent) ||
                            (te.think != HallucinationTimer)) &&
                           (te != world))
                        te = find(te, classname, "timer");

                    if (te != world) {

                        trace_ent.tfstate =
                            trace_ent.tfstate -
                            (trace_ent.tfstate & TFSTATE_HALLUCINATING);
                        SpawnBlood(org, 20);

                        bprint(PRINT_MEDIUM, self.netname, " healed ",
                               trace_ent.netname,
                               " of his hallucinations\n");

                        if (old_grens == TRUE)
                            stuffcmd(trace_ent, "v_cshift; wait; bf\n");

                        if (te.team_no != self.team_no)
                            TF_AddFrags(self, 1);

                        dremove(te);
                    } else
                        dprint
                            ("Warning: Error in Hallucination Timer logic.\n");
                }
                if (trace_ent.tfstate & TFSTATE_TRANQUILISED) {

                    te = find(world, classname, "timer");
                    while (((te.owner != trace_ent) ||
                            (te.think != TranquiliserTimer)) &&
                           (te != world))
                        te = find(te, classname, "timer");

                    if (te != world) {

                        trace_ent.tfstate &= ~TFSTATE_TRANQUILISED;
                        SpawnBlood(org, 20);

                        bprint(PRINT_MEDIUM, self.netname, " healed ",
                               trace_ent.netname, "'s tranquilisation\n");

                        if (te.team_no != self.team_no)
                            TF_AddFrags(self, 1);

                        dremove(te);
                    } else
                        dprint
                            ("Warning: Error in Tranquilisation Timer logic.\n");
                }
                if (trace_ent.FlashTime > 0) {

                    te = find(world, netname, "flashtimer");
                    while (((te.owner != trace_ent) ||
                            (te.classname != "timer")) && (te != world))
                        te = find(te, netname, "flashtimer");

                    if (te != world) {

                        trace_ent.FlashTime = 0;
                        SpawnBlood(org, 20);

                        bprint(PRINT_MEDIUM, self.netname, " cured ",
                               trace_ent.netname, "'s blindness\n");

                        if (te.team_no != self.team_no)
                            TF_AddFrags(self, 1);

                        dremove(te);
                    } else {
                        dprint("Warning: Error in Flash Timer logic.\n");
                        trace_ent.FlashTime = 0;
                    }
                }
                if (trace_ent.tfstate & TFSTATE_INFECTED) {

                    healam = rint(trace_ent.health / 2);
                    trace_ent.tfstate =
                        trace_ent.tfstate -
                        (trace_ent.tfstate & TFSTATE_INFECTED);
                    deathmsg = DMSG_MEDIKIT;
                    T_Damage(trace_ent, self, self, healam);
                    SpawnBlood(org, 30);

                    if (self.classname == "player") {

                        bprint(PRINT_MEDIUM, self.netname, " cured ",
                               trace_ent.netname, "'s infection\n");

                        if (trace_ent.infection_team_no != self.team_no)
                            TF_AddFrags(self, 1);
                    }
                    return TRUE;
                }
                if (trace_ent.numflames > 0) {

                    FO_Sound(trace_ent, CHAN_WEAPON, "items/r_item1.wav", 1,
                          ATTN_NORM);
                    SetFlameCount(trace_ent, 0);

                    if (self.classname == "player") {
                        bprint(PRINT_MEDIUM, self.netname, " put out ",
                               trace_ent.netname, "'s fire.\n");
                    }
                    return TRUE;
                }
                if (trace_ent.health < (trace_ent.max_health + 50)) {

                    if (self.ammo_cells >= ceil(PC_MEDIC_MAXAMMO_CELL / 2)) {
                        healam = trace_ent.max_health - trace_ent.health + 50;
                        self.ammo_cells = 0;
                        if (trace_ent.saveme_time <= (time - PC_MEDIC_SAVEME_GRACE))
                            self.regen_cooldown = time + PC_MEDIC_CELL_REGEN_CD;
                        FO_Sound(trace_ent, CHAN_ITEM, "items/r_item2.wav", 1, ATTN_NORM);
                    }
                    else {
                        healam = min(10, ((trace_ent.max_health + 50) - trace_ent.health));
                        self.ammo_cells = self.ammo_cells - min(self.ammo_cells, ceil((PC_MEDIC_MAXAMMO_CELL / 20)));
                        FO_Sound(trace_ent, CHAN_WEAPON, "items/r_item1.wav", 1, ATTN_NORM);
                    }

                    Status_Refresh(self);
                    T_Heal(trace_ent, healam, 1);

                    if (trace_ent.health > trace_ent.max_health) {
                        if (!(trace_ent.items & IT_SUPERHEALTH)) {
                            trace_ent.items = trace_ent.items | IT_SUPERHEALTH;
                            newmis = spawn();
                            newmis.nextthink = time + 5;
                            newmis.think = item_megahealth_rot;
                            newmis.owner = trace_ent;
                        }
                    }
                }
            } else {
                // musn't be on their team, so we infect them
                trace_ent.axhitme = 1;
                SpawnBlood(org, 20);
                deathmsg = DMSG_BIOWEAPON_ATT;
                T_Damage(trace_ent, self, self, 10);

                if (trace_ent.playerclass == PC_MEDIC)
                    return TRUE;
                if (cb_prematch)
                    return TRUE;
                if (trace_ent.tfstate & TFSTATE_INFECTED)
                    return TRUE;

                trace_ent.tfstate = trace_ent.tfstate | TFSTATE_INFECTED;
                BioInfection = spawn();
                BioInfection.classname = "timer";
                BioInfection.owner = trace_ent;
                BioInfection.nextthink = time + 1;
                BioInfection.think = BioInfection_Decay;
                BioInfection.enemy = self;
                LogEventAffliction(self, trace_ent, TFSTATE_INFECTED);
                trace_ent.infection_team_no = self.team_no;
            }
        } else {
            TF_T_Damage(trace_ent, self, self, 20, TF_TD_NOTTEAM, TF_TD_OTHER);
        }
        return TRUE;

    } else {
        // hit wall
        FO_Sound(self, CHAN_WEAPON, "player/axhit2.wav", 1, ATTN_NORM);
        WriteByte(MSG_MULTICAST, SVC_TEMPENTITY);
        WriteByte(MSG_MULTICAST, TE_GUNSHOT);
        WriteByte(MSG_MULTICAST, 3);
        WriteCoord(MSG_MULTICAST, org_x);
        WriteCoord(MSG_MULTICAST, org_y);
        WriteCoord(MSG_MULTICAST, org_z);
        multicast(org, MULTICAST_PVS);
        return TRUE;
    }
};

vector () wall_velocity =
{
    local vector vel;

    vel = normalize(self.velocity);
    vel =
        normalize(vel + v_up * (random() - 0.5) +
                  v_right * (random() - 0.5));
    vel = vel + 2 * trace_plane_normal;
    vel = vel * 200;
    return (vel);
};

void (vector org, vector vel) SpawnMeatSpray = {
    local entity missile;

    missile = spawn();
    missile.owner = self;
    missile.movetype = MOVETYPE_BOUNCE;
    missile.solid = SOLID_NOT;
    makevectors(self.angles);
    missile.velocity = vel;
    missile.velocity_z = missile.velocity_z + 250 + 50 * random();
    missile.avelocity = '3000 1000 2000';
    missile.nextthink = time + 1;
    missile.think = SUB_Remove;
    FO_SetModel(missile, "progs/zom_gib.mdl");
    setsize(missile, '0 0 0', '0 0 0');
    setorigin(missile, org);
};

void (vector org, float damage) SpawnBlood = {
    WriteByte(MSG_MULTICAST, SVC_TEMPENTITY);
    WriteByte(MSG_MULTICAST, TE_BLOOD);
    WriteByte(MSG_MULTICAST, 1);
    WriteCoord(MSG_MULTICAST, org_x);
    WriteCoord(MSG_MULTICAST, org_y);
    WriteCoord(MSG_MULTICAST, org_z);
    multicast(org, MULTICAST_PVS);
};

void (float damage) spawn_touchblood = {
    local vector vel;

    vel = wall_velocity() * 0.2;
    SpawnBlood(self.origin + vel * 0.01, damage);

};

void (vector org, vector vel) SpawnChunk = {
    particle(org, vel * 0.02, 0, 10);
};

entity multi_ent;
float multi_damage;
vector blood_org;
float blood_count;
vector puff_org;
float puff_count;

void () ClearMultiDamage = {
    multi_ent = world;
    multi_damage = 0;
    blood_count = 0;
    puff_count = 0;
};

void () ApplyMultiDamage = {
    if (!multi_ent)
        return;

    TF_T_Damage(multi_ent, self, self, multi_damage, TF_TD_NOTTEAM,
                TF_TD_SHOT);
};

void (entity hit, float damage) AddMultiDamage = {
    if (!hit)
        return;

    if (hit != multi_ent) {
        ApplyMultiDamage();
        multi_damage = damage;
        multi_ent = hit;
    } else
        multi_damage = multi_damage + damage;
};

void () Multi_Finish = {
    if (puff_count) {
        WriteByte(MSG_MULTICAST, SVC_TEMPENTITY);
        WriteByte(MSG_MULTICAST, TE_GUNSHOT);
        WriteByte(MSG_MULTICAST, puff_count);
        WriteCoord(MSG_MULTICAST, puff_org_x);
        WriteCoord(MSG_MULTICAST, puff_org_y);
        WriteCoord(MSG_MULTICAST, puff_org_z);
        multicast(puff_org, MULTICAST_PVS);
    }
    if (blood_count) {
        WriteByte(MSG_MULTICAST, SVC_TEMPENTITY);
        WriteByte(MSG_MULTICAST, TE_BLOOD);
        WriteByte(MSG_MULTICAST, blood_count);
        WriteCoord(MSG_MULTICAST, blood_org_x);
        WriteCoord(MSG_MULTICAST, blood_org_y);
        WriteCoord(MSG_MULTICAST, blood_org_z);
        multicast(puff_org, MULTICAST_PVS);
    }
};

void (float damage, vector dir) TraceAttack = {
    local vector vel;
    local vector org;

    vel = normalize(dir + v_up * crandom() + v_right * crandom());
    vel = vel + 2 * trace_plane_normal;
    vel = vel * 200;
    org = trace_endpos - dir * 4;
    if (trace_ent.takedamage) {

        blood_count = blood_count + 1;
        blood_org = org;
        AddMultiDamage(trace_ent, damage);

    } else
        puff_count = puff_count + 1;
};

void (float shotcount, vector dir, vector spread) FireBullets = {
    local vector direction;
    local vector src;

    makevectors(self.v_angle);

    src = self.origin + v_forward * 10;
    src_z = self.absmin_z + self.size_z * 0.7;

    ClearMultiDamage();

    traceline(src, src + dir * 2048, MOVE_LAGGED, self);
    puff_org = trace_endpos - dir * 4;

    while (shotcount > 0) {

        direction =
            dir + crandom() * spread_x * v_right +
            crandom() * spread_y * v_up;

        traceline(src, (src + (direction * 2048)), MOVE_LAGGED, self);
        if (trace_fraction != 1) {
            if (FO_CurrentWeapon() != WEAP_ASSAULT_CANNON)
                TraceAttack(4, direction);
            else
                TraceAttack(8, direction);
        }
        shotcount = shotcount - 1;

        if (FO_CurrentWeapon() == WEAP_ASSAULT_CANNON) {
            puff_org = trace_endpos + direction;
            Multi_Finish();
        }
    }
    ApplyMultiDamage();
    if (FO_CurrentWeapon() != WEAP_ASSAULT_CANNON)
        Multi_Finish();
};

void () W_FireShotgun = {
    local vector dir;

    Pred_Sound(SND_SG);

    KickPlayer(-2, self);
    self.ammo_shells = self.ammo_shells - 1;
    dir = aim(self, 100000);
    deathmsg = DMSG_SHOTGUN;
    FireBullets(6, dir, '0.04 0.04 0');
};

void () W_FireSuperShotgun = {
    local vector dir;

    if (self.ammo_shells == 1) {
        W_FireShotgun();
        return;
    }
    Pred_Sound(SND_SSG);

    KickPlayer(-4, self);
    self.ammo_shells = self.ammo_shells - 2;
    dir = aim(self, 100000);
    deathmsg = DMSG_SSHOTGUN;
    FireBullets(14, dir, '0.14 0.08 0');
};

void (vector direction, float damage) FireSniperBullet = {
    local vector src;

    makevectors(self.v_angle);
    src = self.origin + v_forward * 10;
    src_z = self.absmin_z + self.size_z * 0.7;
    ClearMultiDamage();

    KickPlayer(-3, self);

    traceline(src, src + direction * 4096, MOVE_LAGGED, self);
    if (trace_fraction != 1)
        TraceAttack(damage, direction);

    FireBullets(1, direction, '0 0 0');

    ApplyMultiDamage();
};

void () W_FireSniperRifle = {
    local vector dir;
    local vector src;
    local float dam_mult;
    local float zdif;
    local float use_this;
    local float x;
    local vector f;
    local vector g;
    local vector h;
    dir = '0 0 0';

    Pred_Sound(SND_SNIPER_RIFLE);
    KickPlayer(-2, self);
    self.ammo_shells = self.ammo_shells - 1;

    makevectors(self.v_angle);
    src = self.origin + v_forward * 10;
    src_z = self.absmin_z + self.size_z * 0.7;

    KickPlayer(-4, self);

    dir = aim(self, 10000);
    float range = old_sniperrange ? 3072 : 9192;  // Super arbitrary but ok.
    traceline(src, src + dir * range, MOVE_LAGGED, self);

    deathmsg = DMSG_SNIPERRIFLE;
    dam_mult = 1;
    if (trace_fraction < 1 && trace_ent && trace_ent.classname == "player") {
        f = trace_endpos - src;

        g_x = trace_endpos_x;
        g_y = trace_endpos_y;
        g_z = 0;

        h_x = trace_ent.origin_x;
        h_y = trace_ent.origin_y;
        h_z = 0;

        x = vlen(g - h);
        f = (normalize(f) * x) + trace_endpos;

        zdif = f_z - trace_ent.origin_z;
        deathmsg = DMSG_SNIPERRIFLE;

        trace_ent.head_shot_vector = '0 0 0';
        if (zdif < 0) {

            dam_mult = 0.5;
            trace_ent.leg_damage = trace_ent.leg_damage + 1;
            TeamFortress_SetSpeed(trace_ent);
            deathmsg = DMSG_SNIPERLEGSHOT;
            TF_T_Damage(trace_ent, self, self, self.heat * dam_mult, TF_TD_NOTTEAM,
                    TF_TD_SHOT);

            if (trace_ent.health > 0) {
                sprint(trace_ent, PRINT_LOW, "Leg injury!\n");
                sprint(self, PRINT_MEDIUM,
                        "Leg shot - that'll slow him down!\n");
            }
            return;

        } else if (zdif > 20) {

            dam_mult = 2;
            stuffcmd(trace_ent, "bf\n");
            trace_ent.head_shot_vector =
                trace_ent.origin - self.origin;
            deathmsg = DMSG_SNIPERHEADSHOT;
            TF_T_Damage(trace_ent, self, self, (self.heat * dam_mult),
                    TF_TD_NOTTEAM, TF_TD_SHOT);

            if (trace_ent.health > 0) {
                sprint(trace_ent, PRINT_LOW, "Head injury!\n");
                sprint(self, PRINT_MEDIUM,
                        "Head shot - that's gotta hurt!\n");
            }

        } else {
            deathmsg = DMSG_SNIPERRIFLE;
        }
    }

    if (trace_fraction < 1) {
        ClearMultiDamage();
        TraceAttack(self.heat * dam_mult, dir);
        ApplyMultiDamage();
    } else {
        FireBullets(1, dir, '0 0 0');
    }
};

void () W_FireAutoRifle = {
    local vector dir;

    FO_Sound(self, CHAN_WEAPON, "weapons/sniper.wav", 1, ATTN_NORM);

    KickPlayer(-1, self);
    self.ammo_shells = self.ammo_shells - 1;
    makevectors(self.v_angle);
    dir = v_forward;
    deathmsg = DMSG_AUTORIFLE;
    FireSniperBullet(dir, 8);
};

void () W_FireAssaultCannon = {
    FO_WeapState ws;
    FO_FillCurrentWeapState(&ws);

    *ws->clip_fired += 1;
    *ws->ammo_remaining -= (ws->wi)->ammo_per_shot;

    local vector dir;

    KickPlayer(-4, self);

    dir = aim(self, 100000);
    deathmsg = DMSG_ASSAULTCANNON;

    WeapPred_FireAssCan(self.v_angle, 5, '0.04 0.04 0');

    LogEventAttack(self);
};

void (entity pe_flame) CF_ExtinguishFlame = {
    local float rn;

    rn = random();
    if (rn < 0.5) {
        FO_Sound(pe_flame, CHAN_VOICE, "misc/water1.wav", 1, ATTN_NORM);
    } else {
        FO_Sound(pe_flame, CHAN_VOICE, "misc/water2.wav", 1, ATTN_NORM);
    }
    dremove(pe_flame);
};

void () s_explode1 =[0, s_explode2] {
    if (!server_faithful && self.classname == "flamerflame") {
        if (pointcontents(self.origin) < -1) {
            CF_ExtinguishFlame(self);
        }
    }
};

void () s_explode2 =[1, s_explode3] {
    if (!server_faithful && self.classname == "flamerflame") {
        if (pointcontents(self.origin) < -1) {
            CF_ExtinguishFlame(self);
        }
    }
};

void () s_explode3 =[2, s_explode4] {
    if (!server_faithful && self.classname == "flamerflame") {
        if (pointcontents(self.origin) < -1) {
            CF_ExtinguishFlame(self);
        }
    }
};

void () s_explode4 =[3, s_explode5] {
    if (!server_faithful && self.classname == "flamerflame") {
        if (pointcontents(self.origin) < -1) {
            CF_ExtinguishFlame(self);
        }
    }
};

void () s_explode5 =[4, s_explode6] {
    if (!server_faithful && self.classname == "flamerflame") {
        if (pointcontents(self.origin) < -1) {
            CF_ExtinguishFlame(self);
        }
    }
};

void () s_explode6 =[5, SUB_Remove] {
    if (!server_faithful && self.classname == "flamerflame") {
        if (pointcontents(self.origin) < -1) {
            CF_ExtinguishFlame(self);
        }
    }
};

void () BecomeExplosion = {
    dremove(self);
};

static void Antilag_Knock(entity e) {
    T_RadiusDamage(e, e.owner, e.heat, __NULL__, __NULL__, e.owner);
    dremove(e);
}

void T_Knock_Antilag() {
    Antilag_Knock(self);
}

float AntilagKnock(entity e, float dmg) {
    e.forward_knock = -1;
    // Only applies during initial antilag forward
    if (e.flags & FL_FORWARD_KNOCK == 0)
        return FALSE;

    entity knock_e = spawn();

    setorigin(knock_e, e.origin);
    setsize(knock_e, '0 0 0', '0 0 0');
    knock_e.s_origin = e.s_origin;
    knock_e.owner = e.owner;
    knock_e.classname = e.classname;
    knock_e.oldenemy = other;
    knock_e.heat = dmg;
    knock_e.filter_ent = e;

    vector diff = e.origin - e.s_origin;
    float ttime = vlen(diff) / vlen(e.velocity);

    if (ttime > SERVER_FRAME_DT) {
        knock_e.think = T_Knock_Antilag;
        knock_e.nextthink = time + ttime;
        e.forward_knock = time + ttime;
    } else {
        Antilag_Knock(knock_e);
    }

    return TRUE;
}

void () T_MissileTouch = {
    local float damg;

    if (self.voided)
        return;
    self.voided = 1;

    damg = 92 + random() * 20;

    deathmsg = self.weapon;

    if (other.health)
        TF_T_Damage(other, self, self.owner, damg, TF_TD_NOTTEAM,
                    TF_TD_OTHER);

    float dmg = (self.owner.classname == "building_sentrygun") ? 150 : 92;
    entity ignore_self = AntilagKnock(self, dmg) ? self.owner : __NULL__;
    T_RadiusDamage(self, self.owner, dmg, other, ignore_self);

    self.origin = self.origin - 8 * normalize(self.velocity);

    WriteByte(MSG_MULTICAST, SVC_TEMPENTITY);
    WriteByte(MSG_MULTICAST, TE_EXPLOSION);
    WriteCoord(MSG_MULTICAST, self.origin_x);
    WriteCoord(MSG_MULTICAST, self.origin_y);
    WriteCoord(MSG_MULTICAST, self.origin_z);
    multicast(self.origin, MULTICAST_PHS);

    dremove_sent(self);
};

void W_FireRocket(vector org, vector v_ang, float use_ctime=0) = {
    entity proj = FOProj_Create(FPP_ROCKET);
    proj.owner = self;
    proj.movetype = MOVETYPE_FLYMISSILE;
    proj.solid = SOLID_BBOX;

    makevectors(v_ang);
    proj.velocity = v_forward * FPP_Get(FPP_ROCKET)->speed;
    proj.angles = vectoangles(proj.velocity);

    proj.touch = T_MissileTouch;
    proj.voided = 0;

    proj.nextthink = time + 5;
    proj.think = SUB_Remove;

    proj.weapon = DMSG_ROCKETL;
    proj.classname = "proj_rocket";
    proj.origin = org + v_forward * 8 + '0 0 16';

    FOProj_Finalize(proj, use_ctime);

    KickPlayer(-2, self);
};

void (entity from, float damage) LightningHit = {
    WriteByte(MSG_MULTICAST, SVC_TEMPENTITY);
    WriteByte(MSG_MULTICAST, TE_LIGHTNINGBLOOD);
    WriteCoord(MSG_MULTICAST, trace_endpos_x);
    WriteCoord(MSG_MULTICAST, trace_endpos_y);
    WriteCoord(MSG_MULTICAST, trace_endpos_z);
    multicast(trace_endpos, MULTICAST_PVS);

    TF_T_Damage(trace_ent, from, from, damage, TF_TD_NOTTEAM,
                TF_TD_ELECTRICITY);
};

void (vector p1, vector p2, entity from, float damage) LightningDamage = {
    local entity e1;
    local entity e2;
    local vector f;

    f = p2 - p1;
    normalize(f);
    f_x = 0 - f_y;
    f_y = f_x;
    f_z = 0;
    f = f * 16;
    e2 = world;
    e1 = world;

    traceline(p1, p2, 0, self);
    if (trace_ent.takedamage) {

        LightningHit(from, damage);
        if (self.classname == "player")
            if (other.classname == "player")
                trace_ent.velocity_z = trace_ent.velocity_z + 400;
    }
    e1 = trace_ent;
    traceline(p1 + f, p2 + f, 0, self);
    if ((trace_ent != e1) && trace_ent.takedamage)
        LightningHit(from, damage);

    e2 = trace_ent;
    traceline((p1 - f), (p2 - f), 0, self);
    if (((trace_ent != e1) && (trace_ent != e2)) && trace_ent.takedamage)
        LightningHit(from, damage);
};

void () W_FireLightning = {
    local vector org;
    local float cells;

    if (self.ammo_cells < 1) {
        W_ChangeToBestWeapon();
        return;
    }
    if (self.waterlevel > 1) {
        cells = self.ammo_cells;
        self.ammo_cells = 0;
        W_UpdateCurrentWeapon(self);
        deathmsg = DMSG_LIGHTNING;
        T_RadiusDamage(self, self, 35 * cells, world);
        return;
    }
    if (self.t_width < time) {
        FO_Sound(self, CHAN_WEAPON, "weapons/lhit.wav", 1, ATTN_NORM);
        self.t_width = time + 0.6;
    }
    KickPlayer(-2, self);

    self.ammo_cells = self.ammo_cells - 1;

    org = self.origin + '0 0 16';
    traceline(org, org + v_forward * 600, 1, self);

    WriteByte(MSG_MULTICAST, SVC_TEMPENTITY);
    WriteByte(MSG_MULTICAST, TE_LIGHTNING2);
    WriteEntity(MSG_MULTICAST, self);
    WriteCoord(MSG_MULTICAST, org_x);
    WriteCoord(MSG_MULTICAST, org_y);
    WriteCoord(MSG_MULTICAST, org_z);
    WriteCoord(MSG_MULTICAST, trace_endpos_x);
    WriteCoord(MSG_MULTICAST, trace_endpos_y);
    WriteCoord(MSG_MULTICAST, trace_endpos_z);
    multicast(org, MULTICAST_PHS);

    LightningDamage(self.origin, trace_endpos + v_forward * 4, self, 30);
};

void RenderExplosion(vector origin) {
    WriteByte(MSG_MULTICAST, SVC_TEMPENTITY);
    WriteByte(MSG_MULTICAST, TE_EXPLOSION);
    WriteCoord(MSG_MULTICAST, origin_x);
    WriteCoord(MSG_MULTICAST, origin_y);
    WriteCoord(MSG_MULTICAST, origin_z);
    multicast(origin, MULTICAST_PHS);
}
void T_RadiusBounce(entity inflictor, entity attacker, float bounce,
                    entity ignore);

// REQUIRES: e.gren_type is set and supported by FO_GrenGetExp
void FO_GrenExplode(entity e) {
    FO_GrenExp exp;
    ASSERTF_TRUE(FO_GrenGetExp(e.fpp.gren_type, exp));

    deathmsg = exp.deathmsg;
    if (exp.type == kRadiusDamage)
        T_RadiusDamage(self, self.owner, exp.dmg, world);
    else if (exp.type == kRadiusBounce)
        T_RadiusBounce(self, self.owner, exp.dmg, world);

    RenderExplosion(e.origin);
}

void FO_T_GrenExplode() {
    FO_GrenExplode(self);
    dremove(self);
}

void () GrenadeExplode = {
    local entity te;
    float use_antilag = FALSE;

    if (self.voided)
        return;
    self.voided = 1;

    if (self.owner.has_disconnected != 1) {
        deathmsg = self.weapon;
        T_RadiusDamage(self, self.owner, 120, world);
    }

    if (self.no_active_nail_grens != 0) {

        self.no_active_nail_grens = 0;
        self.owner.no_active_nail_grens =
            self.owner.no_active_nail_grens - 1;

        te = find(world, classname, "grenade");
        while (te) {
            if ((te.owner == self.owner) && (te.no_active_nail_grens > 0))
                te.no_active_nail_grens = te.no_active_nail_grens - 1;
            te = find(te, classname, "grenade");
        }
    }

    RenderExplosion(self.origin);
    dremove(self);
};

void () GrenadeTouch = {
    if (other == self.owner)
        return;

    if (other.takedamage == DAMAGE_AIM) {
        GrenadeExplode();
        return;
    }
    FO_Sound(self, CHAN_WEAPON, "weapons/bounce.wav", 1, ATTN_NORM);

    if (self.velocity == '0 0 0')
        self.avelocity = '0 0 0';
};

void () ExplodeOldestPipebomb = {
    local entity pipe;
    local entity oldest = world;
    local float numpipes = 0;
    local float numpipes_total = 0;
    local float detpipe_limit = rint(GetTeamRole(self.team_no)->detpipe_limit);
    Team_Role * r = GetTeamRole(self.team_no);
    
    pipe = find(world, classname, "pipebomb");
    while (pipe != world) {
        if (pipe.owner == self) {
            numpipes = numpipes + 1;
            if (oldest == world || oldest.nextthink > pipe.nextthink)
                oldest = pipe;
        }
        if (pipe.owner.team_no == self.team_no)
            numpipes_total = numpipes_total + 1;
        pipe = find(pipe, classname, "pipebomb");
    }

    if (((numpipes >= detpipe_limit && detpipe_limit >= 0)
                || (numpipes_total >= detpipe_limit_world && detpipe_limit_world >= 0))
                && oldest != world) {
        oldest.nextthink = time + 0.5;
    }
};

void W_FireGrenade(vector org, vector v_ang, float use_ctime=0) {
    Pred_Sound(SND_GREN);
    KickPlayer(-2, self);

    entity proj = FOProj_Create(FPP_GRENADE);
    proj.voided = 0;
    proj.owner = self;
    proj.movetype = MOVETYPE_BOUNCE;
    proj.solid = SOLID_BBOX;
    if (FO_CurrentWeapon() == WEAP_GRENADE_LAUNCHER || cb_prematch) {
        proj.weapon = 5;
        proj.classname = "grenade";
        proj.touch = GrenadeTouch;
        proj.nextthink = time + 2.5;
        proj.fpp.gren_type = GREN_RED;
    } else {
        self.pipecooldown = time + tf_config.pipe_cooldown;
        ExplodeOldestPipebomb();
        proj.classname = "pipebomb";
        proj.touch = PipebombTouch;
        proj.nextthink = time + 120;
        proj.weapon = 11;
        proj.team_no = self.team_no;
        proj.fpp.gren_type = GREN_PIPE;
    }
    makevectors(v_ang);
    if (self.v_angle_x) {
        proj.velocity = (v_forward * 600) +
            (200 + shared_crandom(PRNG_WEAP) * 10) * v_up +
            (shared_crandom(PRNG_WEAP) * 10 * v_right);
    } else {
        proj.velocity = aim(self, 10000);
        proj.velocity = proj.velocity * 600;
        proj.velocity_z = 200;
    }
    proj.angles = vectoangles(proj.velocity);
    proj.think = GrenadeExplode;
    setorigin(proj, org);

    FOProj_Finalize(proj, use_ctime);
};

void () spike_touch;
void () superspike_touch;

entity (int fpp_type, vector offset) W_FireNail = {
    entity proj = FOProj_Create(fpp_type);
    proj.voided = 0;
    proj.owner = self;
    proj.movetype = MOVETYPE_FLYMISSILE;
    proj.solid = SOLID_BBOX;

    proj.angles = vectoangles(aim(self, 1000));
    proj.classname = "spike";
    proj.think = SUB_Remove;
    proj.nextthink = time + 6;
    setorigin(proj, self.origin + offset + '0 0 16');

    proj.velocity = aim(self, 1000) * FPP_Get(fpp_type)->speed;

    if (fpp_type == FPP_NAIL) {
        proj.weapon = DMSG_NAILGUN;
        proj.touch = spike_touch;
    } else { // fpp_type == FPP_SUPER_NAIL
        proj.weapon = DMSG_SNAILGUN;
        proj.touch = superspike_touch;
    }

    FOProj_Finalize(proj);

    return proj;
};

void (float ox) W_FireSpikes = {
    FO_WeapState ws;
    FO_FillCurrentWeapState(&ws);
    FO_WeapInfo* wi = ws->wi;

    makevectors(self.v_angle);

    if (self.ammo_nails < wi->ammo_per_shot) {
        W_ChangeToBestWeapon();
        return;
    }

    *ws->ammo_remaining -= wi->ammo_per_shot;
    if (wi->needs_reload)
        *ws->clip_fired += wi->ammo_per_shot;

    if (wi->weapon == WEAP_NAILGUN)
        W_FireNail(FPP_NAIL, v_right * ox);
    else
        W_FireNail(FPP_SUPER_NAIL, '0 0 0');

    LogEventAttack(self);
    KickPlayer(-3, self);
    Attack_Finished(wi->attack_time);
};

void () t_climb = {

	if (time < self.heat)
		return;
		
	self.heat = time + 0.1;

	if (other.classname != "player")
	return;

	if (spurs_enabled == 0)
	return;

	if (other.items & IT_KEY1 && spurs_flag == 0 )
	return;
	    
	if (other.items & IT_KEY2 && spurs_flag == 0 )
	return;

	if(other == self.owner || spurs_enabled == 3 || ((self.owner.team_no == other.team_no) && spurs_enabled == 2))
		{
			if (self.origin_z > other.origin_z){
				other.velocity_z = spurs_boost;

			}
			
		if(spurs_consume)
			dremove(self);
		}

};

void (entity e) ConvertToSpurs =
{
	e.origin = self.origin + ( normalize(self.velocity) * -5);
	e.movetype = MOVETYPE_NONE;
	e.velocity = '0 0 0';
	e.solid = SOLID_TRIGGER;
	e.touch = t_climb;
	e.think = SUB_Remove;
	e.nextthink = time + spurs_duration;
	e.heat = time;
};

void () spike_touch = {
    if (self.voided)
        return;
    self.voided = 1;

    if (other.solid == SOLID_TRIGGER)
        return;

    if (other.takedamage) {
        spawn_touchblood(9);
        deathmsg = self.weapon;
        if (self.owner.classname == "grenade") {
            TF_T_Damage(other, self, self.owner.owner, 9, TF_TD_NOTTEAM,
                        TF_TD_NAIL);
        } else {
            TF_T_Damage(other, self, self.owner, ng_damage, TF_TD_NOTTEAM,
                    TF_TD_NAIL);
        }

        dremove_sent(self);
    } else {
        WriteByte(MSG_MULTICAST, SVC_TEMPENTITY);
        if (self.classname == "wizspike")
            WriteByte(MSG_MULTICAST, TE_WIZSPIKE);
        else if (self.classname == "knightspike")
            WriteByte(MSG_MULTICAST, TE_KNIGHTSPIKE);
        else
            WriteByte(MSG_MULTICAST, TE_SPIKE);
        WriteCoord(MSG_MULTICAST, self.origin_x);
        WriteCoord(MSG_MULTICAST, self.origin_y);
        WriteCoord(MSG_MULTICAST, self.origin_z);
        multicast(self.origin, MULTICAST_PHS);

        if(other.classname == "worldspawn" && spurs_enabled > 0) {
            if(self.owner.playerclass == PC_SCOUT && spurs_scout == 1 ||
               self.owner.playerclass == PC_SPY && spurs_spy == 1) {
                ConvertToSpurs(self);
                return;
            }
        }

        dremove_sent(self);
   }
};

void () superspike_touch = {
    local float ndmg;

    if (self.voided)
        return;
    self.voided = 1;

    if (other == self.owner)
        return;

    if (other.solid == SOLID_TRIGGER)
        return;

    if (other.takedamage) {
        spawn_touchblood(18);
        deathmsg = self.weapon;
        if (deathmsg == DMSG_GREN_NAIL || deathmsg == DMSG_GREN_BURST) {
            ndmg = 40;
        }
        else {
            ndmg = sng_damage;
        }

        if (self.owner.classname == "grenade")
            TF_T_Damage(other, self, self.owner.owner, ndmg, TF_TD_NOTTEAM,
                        TF_TD_NAIL);
        else
            TF_T_Damage(other, self, self.owner, ndmg, TF_TD_NOTTEAM,
                        TF_TD_NAIL);
    } else {
        WriteByte(MSG_MULTICAST, SVC_TEMPENTITY);
        WriteByte(MSG_MULTICAST, TE_SUPERSPIKE);
        WriteCoord(MSG_MULTICAST, self.origin_x);
        WriteCoord(MSG_MULTICAST, self.origin_y);
        WriteCoord(MSG_MULTICAST, self.origin_z);
        multicast(self.origin, MULTICAST_PHS);
    }
    dremove_sent(self);
};

void W_UpdateWeaponModel(entity pl) {
    FO_WeapState ws;
    FO_FillWeapState(pl, pl.current_slot, &ws);
    FO_WeapInfo* wi = ws.wi;

    if (pl.tfstate & (TFSTATE_RELOADING | TFSTATE_NO_WEAPON) == 0)
        pl.weaponmodel = (wi->models)->model;
    else
        pl.weaponmodel = "";
}

void (entity pl) W_UpdateCurrentWeapon = {
    entity oldself;

    if ((pl.health <= 0) || IsSlotNull(pl.current_slot))
        return;

    FO_WeapState ws;
    FO_FillWeapState(pl, pl.current_slot, &ws);
    FO_WeapInfo* wi = ws.wi;

    pl.items &= ~(IT_SHELLS | IT_NAILS | IT_ROCKETS | IT_CELLS);
    // TODO: Shouldn't this always be union?  Carrying prior behavior for now.
    pl.items |= (wi->items)->ammo_mask;
    pl.weapon = (wi->items)->it_weapon;

    W_UpdateWeaponModel(pl);
    pl.weaponframe = 0;

    // refresh engineer build menu when ammo updated
    if (pl.menu_input == Menu_Engineer_Input)
        Menu_Engineer(pl);
    else if (pl.menu_input == Menu_Drop_Input) {
        oldself = self;
        self = pl;
        Menu_Drop();
        self = oldself;
    }
};

Slot W_BestWeaponSlot()  {
    FO_WeapState ws;
    for (float i = 1; i <= TF_NUM_SLOTS; i++) {
        Slot slot = MakeSlot(i);
        FO_FillWeapState(self, slot, &ws);
        FO_WeapInfo* wi = ws->wi;

        // We don't need to handle out of ammo medi/spanner here because of
        // fallback below.
        if (ws.weapon != WEAP_NONE &&
            (wi->ammo_type == AMMO_NONE || (*ws.ammo_remaining >= wi->ammo_per_shot)))
            return slot;
    }
    return SlotMelee;
};

void () W_ChangeToBestWeapon = {
    W_ChangeWeaponSlot(W_BestWeaponSlot());
}

void () player_axe1;
void () player_axeb1;
void () player_spanner1;
void () player_knife1;
void () player_knifeb1;
void () player_shot1;
void () player_nail1;
void () player_light1;
void () player_rocket1;
void () player_autorifle1;

void () player_asscan_up1;

void () player_medikit1;
void () player_medikitb1;

float AssCanTryBeginFire();

void () W_Attack = {
    FO_WeapState ws;
    FO_FillCurrentWeapState(&ws);
    FO_WeapInfo* wi = ws->wi;

    if (self.has_disconnected == TRUE)
        return;

    if (self.tfstate & TFSTATE_RELOADING ||
        self.tfstate & TFSTATE_NO_WEAPON)
        return;

    if (no_fire_mode)
        return;

    // Out of ammo?
    if (wi->ammo_type != AMMO_NONE &&
        *ws->ammo_remaining < wi->ammo_per_shot) {
        W_ChangeToBestWeapon();
        return;
    }

    // Fired into forced reload?
    if (FO_CheckForReload())
        return;

    if ((self.is_undercover || (self.undercover_team != 0)) ||
        (self.undercover_skin != 0))
        Spy_RemoveDisguise(self);

    makevectors(self.v_angle);
    self.show_hostile = time + 1;

    if (ws.weapon == WEAP_AXE) {
        Pred_Sound(SND_AXE);
        if (shared_prng(PRNG_WEAP) < 0.5)
            player_axe1();
        else
            player_axeb1();
    } else if (ws.weapon == WEAP_KNIFE) {
        Pred_Sound(SND_AXE);
        if (shared_prng(PRNG_WEAP) < 0.5)
            player_knife1();
        else
            player_knifeb1();
    } else if (ws.weapon == WEAP_SPANNER) {
        Pred_Sound(SND_AXE);
        player_spanner1();
    } else if (ws.weapon == WEAP_SHOTGUN) {
        player_shot1();
        W_FireShotgun();
    } else if (ws.weapon == WEAP_SUPER_SHOTGUN) {
        player_shot1();
        W_FireSuperShotgun();
    } else if (ws.weapon == WEAP_NAILGUN) {
        player_nail1();
    } else if (ws.weapon == WEAP_SUPER_NAILGUN) {
        player_nail1();
    } else if (ws.weapon == WEAP_GRENADE_LAUNCHER) {
        player_rocket1();
        self.ammo_rockets = self.ammo_rockets - 1;
        W_FireGrenade(self.origin, self.v_angle);
    } else if (ws.weapon == WEAP_PIPE_LAUNCHER) {
        player_rocket1();
        self.ammo_rockets = self.ammo_rockets - 1;
        W_FireGrenade(self.origin, self.v_angle);
    } else if (ws.weapon == WEAP_ROCKET_LAUNCHER) {
        player_rocket1();
        self.ammo_rockets = self.ammo_rockets - 1;
        W_FireRocket(self.origin, self.v_angle);
    } else if (ws.weapon == WEAP_LIGHTNING) {
        player_light1();
        FO_Sound(self, CHAN_AUTO, "weapons/lstart.wav", 1, ATTN_NORM);
    } else if (ws.weapon == WEAP_SNIPER_RIFLE) {
        if (self.flags & FL_ONGROUND) {
            player_shot1();
            W_FireSniperRifle();
        }
    } else if (ws.weapon == WEAP_AUTO_RIFLE) {
        player_autorifle1();
        W_FireAutoRifle();
    } else if (ws.weapon == WEAP_ASSAULT_CANNON) {
        self.immune_to_check = time + 5;
        if (!AssCanTryBeginFire())
            W_ChangeToBestWeapon();
    } else if (ws.weapon == WEAP_FLAMETHROWER) {
        player_flamethrower1();
        W_FireFlame();
        if (self.waterlevel > 2)
            Attack_Finished(1);
        else
            Attack_Finished(0.15);
    } else if (ws.weapon == WEAP_INCENDIARY) {
        if (self.ammo_rockets >= 3) {
            player_rocket1();
            self.ammo_rockets = self.ammo_rockets - 3;
            W_FireIncendiaryCannon(self.origin, self.v_angle);
        } else if (time >= self.antispam_incendiary_cannon) {
            sprint(self, PRINT_HIGH, "Not enough ammo\n");
            self.antispam_incendiary_cannon = time + 3;
        }
    } else if (ws.weapon == WEAP_MEDIKIT) {
        Pred_Sound(SND_AXE);
        if (shared_prng(PRNG_WEAP) < 0.5)
            player_medikit1();
        else
            player_medikitb1();
    } else if (ws.weapon == WEAP_TRANQ) {
        player_shot1();
        W_FireTranq();
    } else if (ws.weapon == WEAP_RAILGUN) {
        player_shot1();
        W_FireRailgun();
    } else if (ws.weapon == WEAP_IMPELLER) {
        if (time < self.special_next)
            return;

        player_shot1();
        W_FireImpeller();
    }

    if (!wi->fire_in_anim) {
        Attack_Finished(wi->attack_time);
        if (wi->needs_reload) {
            *ws->clip_fired += wi->ammo_per_shot;
            FO_CheckForReload();
        }
    }

    //These weapons have to log each projectile launched/bullet fired
    // TODO: probably equivalent to fire_in_anim...
    if (ws.weapon != WEAP_ASSAULT_CANNON || ws.weapon != WEAP_NAILGUN ||
        ws.weapon != WEAP_SUPER_NAILGUN)
        LogEventAttack(self);
};

float WeaponReady() {
    if (self.client_time >= self.attack_finished &&
        !(self.tfstate & (TFSTATE_RELOADING | TFSTATE_NO_WEAPON)))
        return TRUE;

    return FALSE;
}

void () W_PrintWeaponMessage = {
    switch (FO_CurrentWeapon())
    {
        case WEAP_GRENADE_LAUNCHER:
            sprint(self, PRINT_MEDIUM, "Normal grenade mode\n");
            break;
        case WEAP_PIPE_LAUNCHER:
            if (cb_prematch)
                sprint(self, PRINT_MEDIUM, "Pipebomb mode not available in prematch\n");
            else
                sprint(self, PRINT_MEDIUM, "Pipebomb mode\n");
            break;
        case WEAP_SNIPER_RIFLE:
            sprint(self, PRINT_MEDIUM, "Sniper rifle ready\n");
            break;
        case WEAP_AUTO_RIFLE:
            sprint(self, PRINT_MEDIUM, "Sniper rifle on fully automatic mode\n");
            break;
    }
};

float (float weap) W_GetSlot = {
    local float cf_pyro_impulses = FO_GetUserSetting(self, "cf_pyro_impulses", "cfpi", "off");
    if (weap == WEAP_ROCKET_LAUNCHER
                || weap == WEAP_SUPER_NAILGUN
                || weap == WEAP_SNIPER_RIFLE
                || (!cf_pyro_impulses && weap == WEAP_INCENDIARY)
                || (cf_pyro_impulses && weap == WEAP_FLAMETHROWER)
                || weap == WEAP_TRANQ
                || weap == WEAP_RAILGUN
                || weap == WEAP_ASSAULT_CANNON) {
        return 1;
    } else if (weap == WEAP_SUPER_SHOTGUN
                || weap == WEAP_AUTO_RIFLE
                || (!cf_pyro_impulses && weap == WEAP_FLAMETHROWER)
                || (cf_pyro_impulses && weap == WEAP_INCENDIARY)) {
        return 2;
    } else if (weap == WEAP_SHOTGUN) {
        if (self.playerclass == PC_SCOUT)
            return 2;
        else
            return 3;
    } else if (weap == WEAP_NAILGUN) {
        if (self.playerclass == PC_SCOUT)
            return 1;
        else
            return 3;
    }
    return 0;
};

float (float weap) W_OldGetSlot = {
    if (weap == WEAP_AXE
            || weap == WEAP_KNIFE
            || weap == WEAP_MEDIKIT
            || weap == WEAP_SPANNER)
        return 1;
    else if (weap == WEAP_SHOTGUN
                || weap == WEAP_SNIPER_RIFLE
                || weap == WEAP_TRANQ
                || weap == WEAP_RAILGUN)
        return 2;
    else if (weap == WEAP_SUPER_SHOTGUN
                || weap == WEAP_AUTO_RIFLE)
        return 3;
    else if (weap == WEAP_NAILGUN)
        return 4;
    else if (weap == WEAP_SUPER_NAILGUN
                || weap == WEAP_FLAMETHROWER)
        return 5;
    else if (weap == WEAP_FLAMETHROWER)
        return 6;
    else if (weap == WEAP_ROCKET_LAUNCHER                
                || weap == WEAP_ASSAULT_CANNON
                || weap == WEAP_INCENDIARY)
        return 7;
    else if (weap == WEAP_GRENADE_LAUNCHER)
        return 6;
    else if (weap == WEAP_PIPE_LAUNCHER)
        return 7;

    return 0;
};

void W_ChangeWeaponSlot(Slot slot) {
    if (self.playerclass == 0)
        return;

    if (IsSlotNull(slot))
        slot = SlotMelee;  // Make Nulls noticeable...

    FO_WeapState ws;
    FO_FillWeapState(self, slot, &ws);
    if (ws.weapon == WEAP_NONE || !FO_WeapAvailable(ws.weapon))
        return;

    // queue next weapon if queue is not empty or has changed
    if (IsSlotNull(self.queue_slot) || !IsSameSlot(slot, self.queue_slot))
        self.queue_slot = slot;

    // halt if weapon is not ready to be fired
    if (!WeaponReady())
        return;

    self.queue_slot = SlotNull;

    // We still allow swapping to medikit/spanner with no ammo.
    if (*ws->ammo_remaining == 0 && !IsSlotMelee(slot)) {
        sprint(self, PRINT_HIGH, "Not enough ammo\n");
        return;
    }

    if (IsSameSlot(slot, self.current_slot))
        return;

    self.last_slot = self.current_slot;
    self.current_slot = slot;

    W_UpdateCurrentWeapon(self);
    W_PrintWeaponMessage();
};

void W_ChangeQueuedWeaponIfReady() {
    if (!IsSlotNull(self.queue_slot) && WeaponReady())
        W_ChangeWeaponSlot(self.queue_slot);
}

void W_ChangeWeaponLast() {
    // Clearing queued counts as swap to whatever was pre-queued.
    if (!IsSlotNull(self.queue_slot))
        self.queue_slot = SlotNull;
    else if (!IsSlotNull(self.last_slot))
        W_ChangeWeaponSlot(self.last_slot);
};

void W_ChangeWeaponNext() {
    Slot slot = IsSlotNull(self.current_slot) ? SlotMelee : self.current_slot;
    W_ChangeWeaponSlot(FO_FindPrevNextWeaponSlot(self.playerclass, slot, FALSE));
}

void W_ChangeWeaponPrev() {
    Slot slot = IsSlotNull(self.current_slot) ? SlotMelee : self.current_slot;
    W_ChangeWeaponSlot(FO_FindPrevNextWeaponSlot(self.playerclass, slot, TRUE));
}

static struct {
    int special1;
    int special2;
} special_impulses[] = {
    {0, 0},
    {TF_DASH, TF_SCAN},
    {TF_ZOOMTOGGLE, 0},
    {0, 0},
    {TF_PB_DETONATE, TF_DETPACK_5},
    {TF_MEDIC_AURA_TOGGLE, 0},
    {TF_HVYWEAP_LOCK_TOGGLE, 0},
    {TF_AIRBLAST, 0},
    {TF_SPY_FEIGN, TF_DISGUISE_LAST_SPAWNED},
    {TF_ENGINEER_TOGGLEDISPENSER, TF_ENGINEER_TOGGLESENTRY},
};

static int ImpulseAllowed(int impulse) {
    switch (impulse) {  // Always allowed
        case TF_SHOWTF:
        case TF_CLASSHELP:
        case TF_SHOWLEGALCLASSES:
        case TF_CHANGEPC_SCOUT:
        case TF_CHANGEPC_SNIPER:
        case TF_CHANGEPC_SOLDIER:
        case TF_CHANGEPC_DEMOMAN:
        case TF_CHANGEPC_MEDIC:
        case TF_CHANGEPC_HVYWEAP:
        case TF_CHANGEPC_PYRO:
        case TF_CHANGEPC_SPY:
        case TF_CHANGEPC_ENGINEER:
        case TF_CHANGEPC_RANDOM:
        case TF_CHANGETEAM:
        case TF_CHANGECLASS:
        case TF_HELP_MAP:
        case TF_NAILGREN_INFO:
        case TF_STATUS_QUERY:
        case TF_TEAM_1:
        case TF_TEAM_2:
        case TF_TEAM_3:
        case TF_TEAM_4:
        case TF_TEAM_SCORES:
        case TF_TEAM_CLASSES:
        case TF_PLAYER_READY:
        case TF_PLAYER_NOT_READY:
            return TRUE;  // Always allowed
    }

    if (cease_fire || self.deadflag || self.playerclass == 0)
        return FALSE;

    if (cb_prematch) {
        // Only impulses below allowed
        switch (impulse) {
            case TF_PREMATCH_INVULN:
                return TRUE;
            case TF_WEAPNEXT:
            case TF_WEAPPREV:
            case TF_INVENTORY:
            case TF_ID:
            case FLAG_INFO:
            case TF_GRENADE_1:
            case TF_GRENADE_2:
            case TF_GRENADE_T:
            case TF_GRENADE_PT_1:
            case TF_GRENADE_PT_2:
                break;
            default:
                return FALSE;
        }
    }

    if (IsFeigned(self)) {
        // Only impulses below allowed
        switch (impulse) {
            case TF_SPECIAL_SKILL1:
            case TF_SPECIAL_SKILL2:
            case TF_MEDIC_HELPME:
            case TF_SPY_FEIGN:
            case TF_SPY_FEIGN_SILENT:
            case TF_SPY_UNFEIGN:
            case TF_GRENADE_1:
            case TF_GRENADE_2:
            case TF_GRENADE_PT_1:
            case TF_GRENADE_PT_2:
                break;
            default:
                return FALSE;
        }
    }

    if (self.tfstate & TFSTATE_NO_WEAPON) {
        // Impulses below blocked, others allowed
        switch (impulse) {
            case TF_WEAPNEXT:
            case TF_WEAPPREV:
            case TF_RELOAD:
            case TF_RELOAD_SLOT1:
            case TF_RELOAD_SLOT2:
            case TF_RELOAD_SLOT3:
            case TF_RELOAD_NEXT:
            case TF_DETPACK_5:
            case TF_DETPACK_20:
            case TF_DETPACK_50:
            case TF_DROP_AMMO:
                return FALSE;
        }
    }

    // Final filter
    switch (impulse) {
        case TF_PREMATCH_INVULN:
            return FALSE;  // Only allowed higher
                           //
        case TF_DASH:
        case TF_SCAN:
        case TF_SCAN_ENEMY:
        case TF_SCAN_FRIENDLY:
        case TF_SCAN_SOUND:
            return self.playerclass == PC_SCOUT;

        case TF_SPY_SPY:
        case TF_SPY_FEIGN:
        case TF_SPY_FEIGN_SILENT:
        case TF_SPY_UNFEIGN:
        case TF_DISGUISE_RESET:
        case TF_DISGUISE_SCOUT:
        case TF_DISGUISE_SNIPER:
        case TF_DISGUISE_SOLDIER:
        case TF_DISGUISE_DEMOMAN:
        case TF_DISGUISE_MEDIC:
        case TF_DISGUISE_HWGUY:
        case TF_DISGUISE_PYRO:
        case TF_DISGUISE_ENGINEER:
        case TF_DISGUISE_BLUE:
        case TF_DISGUISE_RED:
        case TF_DISGUISE_YELLOW:
        case TF_DISGUISE_GREEN:
        case TF_DISGUISE_ENEMY:
        case TF_DISGUISE_LAST:
        case TF_DISGUISE_LAST_SPAWNED:
            return self.playerclass == PC_SPY;

        case TF_ENGINEER_BUILD:
        case TF_ENGINEER_DETSENTRY:
        case TF_ENGINEER_DETDISP:
        case TF_ENGINEER_TOGGLEDISPENSER:
        case TF_ENGINEER_TOGGLESENTRY:
            return self.playerclass == PC_ENGINEER;

        case TF_AIRBLAST:
            return self.playerclass == PC_PYRO;

        case TF_HVYWEAP_LOCK_TOGGLE:
            return self.playerclass == PC_HVYWEAP;

        case TF_DEMOMAN_DETPACK:
        case TF_DETPACK:
        case TF_DETPACK_5:
        case TF_DETPACK_20:
        case TF_DETPACK_50:
            return self.playerclass == PC_DEMOMAN;

        case TF_ADMIN_CEASEFIRE:
        case TF_ADMIN_COUNTPLAYERS:
        case TF_ADMIN_CYCLEDEAL:
        case TF_ADMIN_KICK:
        case TF_ADMIN_BAN:
        case TF_ADMIN_NEXT:
        case TF_ADMIN_LISTIPS:
        case TF_ADMIN_CLANMODE:
        case TF_ADMIN_QUADMODE:
        case TF_ADMIN_DUELMODE:
        case TF_ADMIN_ADMINMENU:
        case TF_ADMIN_FORCESTARTMATCH:
        case TF_ADMIN_READYSTATUS:
            return self.is_admin;

        default:
            return TRUE;
    }
}

void ExecImpulseCommand(int impulse, int arg = 0) {
    if (impulse == TF_SPECIAL_SKILL1) {
        if (cb_prematch)
            impulse = TF_PREMATCH_INVULN;
        else
            impulse = special_impulses[self.playerclass].special1;
    } else if (impulse == TF_SPECIAL_SKILL2) {
        impulse = special_impulses[self.playerclass].special2;
    }

    if (!impulse || !ImpulseAllowed(impulse))
        return;

    switch (impulse) {
        case TF_SHOWTF:
            TeamFortress_ShowTF(); break;
        case TF_CLASSHELP:
            Help_Show(); break;
        case TF_SHOWLEGALCLASSES:
            TeamFortress_DisplayLegalClasses(); break;
        case TF_CHANGEPC_SCOUT:
            TeamFortress_ChangeClass(PC_SCOUT); break;
        case TF_CHANGEPC_SNIPER:
            TeamFortress_ChangeClass(PC_SNIPER); break;
        case TF_CHANGEPC_SOLDIER:
            TeamFortress_ChangeClass(PC_SOLDIER); break;
        case TF_CHANGEPC_DEMOMAN:
            TeamFortress_ChangeClass(PC_DEMOMAN); break;
        case TF_CHANGEPC_MEDIC:
            TeamFortress_ChangeClass(PC_MEDIC); break;
        case TF_CHANGEPC_HVYWEAP:
            TeamFortress_ChangeClass(PC_HVYWEAP); break;
        case TF_CHANGEPC_PYRO:
            TeamFortress_ChangeClass(PC_PYRO); break;
        case TF_CHANGEPC_SPY:
            TeamFortress_ChangeClass(PC_SPY); break;
        case TF_CHANGEPC_ENGINEER:
            TeamFortress_ChangeClass(PC_ENGINEER); break;
        case TF_CHANGEPC_RANDOM:
            TeamFortress_ChangeClass(PC_RANDOM); break;
        case TF_CHANGETEAM:
            if (self.playerclass != 0 && deathmatch == 3 && !cb_prematch)
                Menu_Team(0);
            break;
        case TF_CHANGECLASS:
            if (self.playerclass != 0 && deathmatch == 3 && !cb_prematch)
                Menu_Class(0);
            break;
        case TF_HELP_MAP:
            TeamFortress_HelpMap(); break;
        case TF_NAILGREN_INFO:
            TeamFortress_NailGrenInfo(); break;
        case TF_STATUS_QUERY:
            TeamFortress_StatusQuery(); break;
        case TF_TEAM_1:
            if (number_of_teams > 0)
                TeamFortress_TeamSet(1);
            break;
        case TF_TEAM_2:
            if (number_of_teams > 1)
                TeamFortress_TeamSet(2);
            break;
        case TF_TEAM_3:
            if (number_of_teams > 2)
                TeamFortress_TeamSet(3);
            break;
        case TF_TEAM_4:
            if (number_of_teams > 3)
                TeamFortress_TeamSet(4);
            break;
        case TF_TEAM_SCORES:
            TeamFortress_TeamShowScores(0); break;
        case TF_TEAM_CLASSES:
            TeamFortress_TeamShowMemberClasses(self); break;
        case TF_PLAYER_READY:
            if (clanbattle == 1) {
                if (!cb_prematch)
                    sprint (self, 2, "Match already in progress...\n");
                else
                    PlayerReady();
            }
            break;
        case TF_PLAYER_NOT_READY:
            if (clanbattle == 1) {
                if (!cb_prematch)
                    sprint (self, 2, "Match already in progress...\n");
                else
                    PlayerNotReady();
            }
            break;
        case TF_PREMATCH_INVULN:
            ToggleInvincibility(); break;
        case TF_GRENADE_1:
            TeamFortress_PrimeGrenade(1, TRUE); break;
        case TF_GRENADE_2:
            TeamFortress_PrimeGrenade(2, TRUE); break;
        case TF_GRENADE_T:
            TeamFortress_ThrowGrenade(); break;
        case TF_GRENADE_PT_1:
            TeamFortress_PrimeThrowGrenade(1); break;
        case TF_GRENADE_PT_2:
            TeamFortress_PrimeThrowGrenade(2); break;
        case TF_WEAPLAST:
            W_ChangeWeaponLast(); break;
        case TF_TOGGLEVOTE:
            Vote_ToggleMenu(self); break;
        case TF_WEAPNEXT:
            W_ChangeWeaponNext(); break;
        case TF_WEAPPREV:
            W_ChangeWeaponPrev(); break;
        case TF_RELOAD:
            FO_ReloadSlot(self.current_slot, FALSE); break;
        case TF_RELOAD_SLOT1:
            FO_ReloadSlot(MakeSlot(1), FALSE); break;
        case TF_RELOAD_SLOT2:
            FO_ReloadSlot(MakeSlot(2), FALSE); break;
        case TF_RELOAD_SLOT3:
            FO_ReloadSlot(MakeSlot(3), FALSE); break;
        case TF_RELOAD_NEXT:
            TeamFortress_ReloadNext(); break;
        case TF_DETPACK:
            TeamFortress_SetDetpack(arg); break;
        case TF_DETPACK_5:
            TeamFortress_SetDetpack(5); break;
        case TF_DETPACK_20:
            TeamFortress_SetDetpack(20); break;
        case TF_DETPACK_50:
            TeamFortress_SetDetpack(50); break;
        case TF_DROP_AMMO:
            Menu_Drop(); break;
        case TF_PRACSPAWN_PLACE:
            TeamFortress_PlacePracticeSpawn(self); break;
        case TF_PRACSPAWN_REMOVE:
            TeamFortress_RemovePracticeSpawn(self); break;
        case TF_INVENTORY:
            TeamFortress_Inventory(); break;
        case TF_MEDIC_HELPME:
            TeamFortress_SaveMe(); break;
        case TF_ID:
            CF_Identify(self, 1); break;
        case TF_ID_TEAM:
            CF_Identify(self, 2); break;
        case TF_ID_ENEMY:
            CF_Identify(self, 3); break;
        case TF_SHOW_IDS:
            TeamFortress_ShowIDs(); break;
        case TF_DROPFLAG:
            DropGoalItems(); break;
        case TF_DISCARD:
            TeamFortress_Discard(); break;
        case TF_DISCARD_DROP_AMMO:
            TeamFortress_Discard_DropAmmo(); break;
        case TF_SCAN:
            ScannerSwitch(); break;
        case TF_SCAN_SOUND:
            Scout_ToggleScanner(NIT_SCANNER_SOUND); break;
        case TF_SCAN_ENEMY:
            Scout_ToggleScanner(NIT_SCANNER_ENEMY); break;
        case TF_SCAN_FRIENDLY:
            Scout_ToggleScanner(NIT_SCANNER_FRIENDLY); break;
        case TF_DASH:
            CF_Scout_Dash(); break;
        case TF_PB_DETONATE:
            TeamFortress_DetonatePipebombs(0); break;
        case TF_DETPACK_STOP:
            TeamFortress_DetpackStop(); break;
        case TF_MEDIC_AURA_TOGGLE:
            CF_Medic_AuraToggle(); break;
        case TF_HVYWEAP_LOCK_TOGGLE:
            self.tfstate ^= TFSTATE_LOCK;
            break;
        case TF_AIRBLAST:
            FO_Airblast(); break;
        case TF_ENGINEER_BUILD:
            TeamFortress_EngineerBuild(); break;
        case TF_ENGINEER_DETSENTRY:
            DestroyBuilding(self, "building_sentrygun", TRUE); break;
        case TF_ENGINEER_DETDISP:
            DestroyBuilding(self, "building_dispenser", TRUE); break;
        case TF_ENGINEER_TOGGLEDISPENSER:
            FO_Engineer_ToggleDispenser(); break;
        case TF_ENGINEER_TOGGLESENTRY:
            FO_Engineer_ToggleSentry(); break;
        case TF_SPY_SPY:
            Menu_Spy_Skin(); break;
        case TF_SPY_FEIGN:
            FO_Spy_FeignCmd(0); break;
        case TF_SPY_FEIGN_SILENT:
            FO_Spy_FeignCmd(1); break;
        case TF_SPY_UNFEIGN:
            FO_Spy_Unfeign(); break;
        case TF_DISGUISE_RESET:
            CF_Spy_ChangeSkin(self, 8, TRUE);
            CF_Spy_ChangeColor(self, self.team_no, TRUE);
            break;
        case TF_DISGUISE_SCOUT:
            CF_Spy_ChangeSkin(self, 1, TRUE); break;
        case TF_DISGUISE_SNIPER:
            CF_Spy_ChangeSkin(self, 2, TRUE); break;
        case TF_DISGUISE_SOLDIER:
            CF_Spy_ChangeSkin(self, 3, TRUE); break;
        case TF_DISGUISE_DEMOMAN:
            CF_Spy_ChangeSkin(self, 4, TRUE); break;
        case TF_DISGUISE_MEDIC:
            CF_Spy_ChangeSkin(self, 5, TRUE); break;
        case TF_DISGUISE_HWGUY:
            CF_Spy_ChangeSkin(self, 6, TRUE); break;
        case TF_DISGUISE_PYRO:
            CF_Spy_ChangeSkin(self, 7, TRUE); break;
        case TF_DISGUISE_ENGINEER:
            CF_Spy_ChangeSkin(self, 9, TRUE); break;
        case TF_DISGUISE_BLUE:
            CF_Spy_ChangeColor(self, 1, TRUE); break;
        case TF_DISGUISE_RED:
            CF_Spy_ChangeColor(self, 2, TRUE); break;
        case TF_DISGUISE_YELLOW:
            CF_Spy_ChangeColor(self, 3, TRUE); break;
        case TF_DISGUISE_GREEN:
            CF_Spy_ChangeColor(self, 4, TRUE); break;
        case TF_DISGUISE_ENEMY:
            if (number_of_teams > 2)
                Menu_Spy_Color();
            else if (self.team_no == 1)
                CF_Spy_ChangeColor(self, 2, TRUE);
            else
                CF_Spy_ChangeColor(self, 1, TRUE);
            break;
        case TF_DISGUISE_LAST:
            FO_Spy_DisguiseLast(self, TRUE); break;
        case TF_DISGUISE_LAST_SPAWNED:
            FO_Spy_DisguiseLastSpawned(self, TRUE); break;
        case TF_DEMOMAN_DETPACK:
            TeamFortress_DetpackMenu(); break;
        case FLAG_INFO:
            if (CTF_Map == 1)
                TeamFortress_CTF_FlagInfo();
            else
                TeamFortress_DisplayDetectionItems();
            break;
        case TF_DISPLAYLOCATION:
            display_location(); break;


        case TF_ADMIN_CEASEFIRE:
            Admin_CeaseFire();
        case TF_ADMIN_COUNTPLAYERS:
            Admin_CountPlayers();
        case TF_ADMIN_CYCLEDEAL:
            Admin_CycleDeal();
        case TF_ADMIN_KICK:
            if (self.admin_mode == 1)
                Admin_DoKick();
            break;
        case TF_ADMIN_BAN:
            if (self.admin_mode == 1)
                Admin_DoBan();
            break;
        case TF_ADMIN_NEXT:
           if (self.admin_mode == 1)
               Admin_CycleDeal();
           break;
        case TF_ADMIN_LISTIPS:
           Admin_ListIPs(); break;
        case TF_ADMIN_CLANMODE:
           ClanMode(); break;
        case TF_ADMIN_QUADMODE:
           QuadMode(); break;
        case TF_ADMIN_DUELMODE:
            DuelMode(); break;
        case TF_ADMIN_ADMINMENU:
            self.current_menu_page = 1;
            Menu_Admin();
            break;
        case TF_ADMIN_FORCESTARTMATCH:
            StartTimer(); break;
        case TF_ADMIN_READYSTATUS:
            Broadcast_Players_NotReady(); break;
        default:
            sprint(self, PRINT_HIGH, "Unrecognized impulse: ", itos(impulse), "\n");
    }
}

// Handles self.impulse --> Exec
void ImpulseCommands() {
    if (self.impulse == TF_DETPACK)
        self.last_impulse = self.impulse;
    else if (self.last_impulse == TF_DETPACK)
        ExecImpulseCommand(TF_DETPACK, self.impulse);
    else
        ExecImpulseCommand(self.impulse);

    self.impulse = 0;
}

void () ButtonFrame = {
    float changed_buttons = input_buttons ^ self.oldbuttons;
    self.oldbuttons = input_buttons;

    float keydowns = changed_buttons & input_buttons;
    float keyups = changed_buttons & ~input_buttons;

    if (input_buttons & BUTTON_SPECIAL1) {
        if (cb_prematch) {
                if (keydowns & BUTTON_SPECIAL1)
                    ExecImpulseCommand(TF_SPECIAL_SKILL1);
        } else {
            switch (self.playerclass) {
                case PC_SCOUT:
                case PC_DEMOMAN:
                case PC_PYRO:
                    ExecImpulseCommand(TF_SPECIAL_SKILL1);
                    break;
                case PC_MEDIC:
                case PC_HVYWEAP:
                case PC_SPY:
                case PC_ENGINEER:
                    if (keydowns & BUTTON_SPECIAL1)
                        ExecImpulseCommand(TF_SPECIAL_SKILL1);
                    break;
            }
        }
    }

    if (keyups & BUTTON_SPECIAL1) {
        switch (self.playerclass) {
            case PC_SPY:
                if (FO_GetUserSetting(self, "hold_feign", "hf", "off"))
                    FO_Spy_Unfeign();
                break;
        }
    }

    if (input_buttons & BUTTON_SPECIAL2) {
        switch (self.playerclass) {
            case PC_SCOUT:
            case PC_DEMOMAN:
            case PC_SPY:
            case PC_ENGINEER:
                if (keydowns & BUTTON_SPECIAL2)
                    ExecImpulseCommand(TF_SPECIAL_SKILL2);
                break;
        }
    }

    if (keyups & BUTTON_SPECIAL2) {
        switch (self.playerclass) {
            case PC_DEMOMAN:
                ExecImpulseCommand(TF_DETPACK_STOP);
                break;
        }
    }

    float hold_grens = FO_GetUserSetting(self, "hold_grens", "hg", "off");
    if (keydowns & BUTTON_GRENADE1)
        ExecImpulseCommand(hold_grens ? TF_GRENADE_1 : TF_GRENADE_PT_1);
    if (keydowns & BUTTON_GRENADE2)
        ExecImpulseCommand(hold_grens ? TF_GRENADE_2 : TF_GRENADE_PT_2);
    if ((keyups & (BUTTON_GRENADE1 | BUTTON_GRENADE2)) && hold_grens)
        ExecImpulseCommand(TF_GRENADE_T);

    if (input_buttons & BUTTON_DROPFLAG)
        DropGoalItems();
}

void () W_WeaponFrame = {
    TeamFortress_QueuedDetpipe();

    if (self.menu_input) {
        if (self.impulse > 0 && self.impulse <= 10) {
            Menu_Input(self.impulse);
            return;
        }
    }

    if (self.impulse == TF_CLASSMENU && self.playerclass != PC_MEDIC) {
        switch (self.playerclass) {
            case PC_ENGINEER: Menu_Engineer(self); break;
            case PC_SCOUT: Menu_Scout(); break;
            case PC_SPY: Menu_Spy(self); break;
            case PC_DEMOMAN: TeamFortress_DetpackMenu(); break;
        }

        self.impulse = 0;
        return;
    }

    if (self.impulse == TF_WEAPLAST && self.is_undercover != SPY_DISGUISING) {
        W_ChangeWeaponLast();
        self.impulse = 0;
    }

    // slot 1-4 (or 1-7) binds
    if (self.impulse >= 1 && self.impulse <= GetMaxWeaponInput() ||
        self.impulse >= TF_SLOT1 && self.impulse <= TF_SLOT4) {
        Slot slot = FO_SlotByInput(self.playerclass, self.impulse);
        if (!IsSlotNull(slot))
            W_ChangeWeaponSlot(slot);
        self.impulse = 0;
    }
    W_ChangeQueuedWeaponIfReady();

    if (self.impulse == TF_CHANGETEAM) {
        Menu_Team(0);
        self.impulse = 0;
        return;
    } else if (self.impulse == TF_CHANGECLASS) {
        Menu_Class(0);
        self.impulse = 0;
        return;
    }
    if (intermission_running)
        return;

    // hwguy assault cannon special
    if (self.playerclass == PC_HVYWEAP) {
        if (cannon_lock &&
                ((self.impulse == TF_LOCKON) ||
                 (self.impulse == TF_LOCKOFF) ||
                 (self.impulse == TF_HVYWEAP_LOCK_TOGGLE))) {
            if (self.impulse == TF_LOCKON)
                self.tfstate = self.tfstate | TFSTATE_LOCK;
            else if (self.impulse == TF_LOCKOFF)
                self.tfstate = self.tfstate - (self.tfstate & TFSTATE_LOCK);
            else if (self.impulse == TF_HVYWEAP_LOCK_TOGGLE)
                self.tfstate ^= TFSTATE_LOCK;
            self.impulse = 0;
            return;
        }
    }

    if (self.playerclass == PC_SNIPER) {
        if (self.impulse == TF_SPECIAL_SKILL1 || self.impulse == TF_ZOOMTOGGLE) {
            Sniper_ZoomToggle();
            self.impulse = 0;
            return;
        } else if (self.impulse == TF_ZOOMIN || (self.is_zooming && self.impulse == TF_WEAPPREV)) {
            Sniper_ZoomAdjust(1);
            self.impulse = 0;
            return;
        } else if (self.impulse == TF_ZOOMOUT || (self.is_zooming && self.impulse == TF_WEAPNEXT)) {
            Sniper_ZoomAdjust(0);
            self.impulse = 0;
            return;
        }
    }

    // Whitelist of commands that can be used even when reloading
    // Note: ImpulseCommands will clear impulse so we can continue processing
    switch (self.impulse)
    {
        case TF_SPECIAL_SKILL1:
        case TF_SPECIAL_SKILL2:
        case TF_PB_DETONATE:
        case TF_MEDIC_HELPME:
        case TF_DASH:
        case TF_DISCARD:
        case TF_DROPFLAG:
        case TF_CHANGEPC_SCOUT:
        case TF_CHANGEPC_SNIPER:
        case TF_CHANGEPC_SOLDIER:
        case TF_CHANGEPC_DEMOMAN:
        case TF_CHANGEPC_MEDIC:
        case TF_CHANGEPC_HVYWEAP:
        case TF_CHANGEPC_PYRO:
        case TF_CHANGEPC_SPY:
        case TF_CHANGEPC_ENGINEER:
        case TF_CHANGEPC_RANDOM:
        case TF_INVENTORY:
        case FLAG_INFO:
        case TF_SPY_FEIGN:
        case TF_SPY_UNFEIGN:
        case TF_SPY_FEIGN_SILENT:
        case TF_PLAYER_READY:
        case TF_PLAYER_NOT_READY:
        case TF_GRENADE_1:
        case TF_GRENADE_2:
        case TF_GRENADE_T:
        case TF_GRENADE_PT_1:
        case TF_GRENADE_PT_2:
            ImpulseCommands();
            break;
        case TF_DEMOMAN_DETPACK:
        case TF_DETPACK:
        case TF_DETPACK_STOP:
        case TF_DETPACK_5:
        case TF_DETPACK_20:
        case TF_DETPACK_50:
            // allows setting detpack while reloading on toggle, defaults to off
            if (detpack_when_reloading)
                ImpulseCommands();
            break;
    }

    if (!WeaponReady())
        return;

    if (self.impulse != 0 && self.has_disconnected == 0)
        ImpulseCommands();
    if (cease_fire)
        return;

    if (self.button0) {
        if (FO_CurrentWeapon() == WEAP_SNIPER_RIFLE) {
            if (self.tfstate & TFSTATE_AIMING == 0) {
                vector tv = self.velocity;
                tv_z = 0;
                if (vlen(tv) <= 50) {
                    SniperSight_Create();
                    self.heat = 50;
                    self.tfstate |= TFSTATE_AIMING;
                }
            }
        } else if (FO_CurrentWeapon() == WEAP_ASSAULT_CANNON) {
            if (self.flags & FL_ONGROUND || cannon_air) {
                SuperDamageSound();
                W_Attack();
            } else if (self.antispam_cannon_air < time) {
                sprint(self, PRINT_MEDIUM, "You cannot fire the assault cannon without your feet on the ground...\n");
                self.antispam_cannon_air = time + 3;
            }
        } else {
            SuperDamageSound();
            W_Attack();
        }
    } else if (self.tfstate & TFSTATE_AIMING) {
        W_Attack();
        self.tfstate &= ~TFSTATE_AIMING;
        self.heat = 0;
    }
};

void () SuperDamageSound = {
    if (self.super_damage_finished > time) {
        if (self.super_sound < time) {
            self.super_sound = time + 1;
            FO_Sound(self, CHAN_BODY, "items/damage3.wav", 1, ATTN_NORM);
        }
    }
    return;
};

void () ToggleInvincibility = {
    if(self.pstate & PSTATE_INVINCIBLE) {
        self.items &= ~IT_INVULNERABILITY;
        self.invincible_time = 0;
        self.invincible_finished = 0;
        self.pstate &= ~PSTATE_INVINCIBLE;
        self.effects &= ~(EF_RED | EF_DIMLIGHT | EF_BRIGHTLIGHT);
    } else {
        self.items |= IT_INVULNERABILITY;
        self.invincible_time = 1;
        self.pstate |= PSTATE_INVINCIBLE;
        self.invincible_finished = time + 666;
    }
};

// TODO: trust the client less, validate more.
// TODO: Could support hitscan (e.g. sg/ssg)
void (int weap, float ctime, vector pos, vector angles) CSEv_Attack_ifvv = {
    if (!RewindFlagEnabled(REWIND_SENDEVENT))
        return;

    // Only applies to attacks before the last death.   We can't use
    // attack_finished here as there's an 0.3s lockout on spawn that obscures.
    float lockout = 15*MSEC;  // Be a tiny bit conservative
    if (ctime >= self.last_death_ctime - lockout ||
        ctime < self.last_attack_ctime - lockout)
        return;

    switch (weap) {
        case WEAP_ROCKET_LAUNCHER:
            W_FireRocket(pos, angles, ctime);
            break;
        case WEAP_INCENDIARY:
            W_FireIncendiaryCannon(pos, angles, ctime);
            break;
        case WEAP_GRENADE_LAUNCHER:
            W_FireGrenade(pos, angles, ctime);
            break;
    }
};
