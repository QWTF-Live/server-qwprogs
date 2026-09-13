void () T_MissileTouch;
void () info_player_start;
void (entity targ, entity attacker) ClientObituary;
void () ResetPlayers;
void (entity targ, entity attacker) KillSound;
void (entity Goal, entity AP, float addb) DoResults;
float (entity Goal, entity AP) Activated;
float (entity targ, entity attacker, float damage) TeamEqualiseDamage;
float () CountRemainingTeams;
void () CheckRules;

void () monster_death_use = {
    if (self.flags & FL_FLY)
        self.flags = self.flags - FL_FLY;

    if (self.flags & FL_SWIM)
        self.flags = self.flags - FL_SWIM;

    if (!self.target)
        return;

    activator = self.enemy;
    SUB_UseTargets();
};

float (entity targ, entity inflictor) CanDamage = {
    if (targ.movetype == MOVETYPE_PUSH) {

        traceline(inflictor.origin, 0.5 * (targ.absmin + targ.absmax),
                  TRUE, self);
        if (trace_fraction == 1)
            return (TRUE);
        if (trace_ent == targ)
            return (TRUE);
        return (FALSE);
    }

    traceline(inflictor.origin, targ.origin, TRUE, self);
    if (trace_fraction == 1)
        return (TRUE);
    traceline(inflictor.origin, targ.origin + '15 15 0', TRUE, self);
    if (trace_fraction == 1)
        return (TRUE);
    traceline(inflictor.origin, targ.origin + '-15 -15 0', TRUE, self);
    if (trace_fraction == 1)
        return (TRUE);
    traceline(inflictor.origin, targ.origin + '-15 15 0', TRUE, self);
    if (trace_fraction == 1)
        return (TRUE);
    traceline(inflictor.origin, targ.origin + '15 -15 0', 1, self);
    if (trace_fraction == 1)
        return (TRUE);
    return (FALSE);
};

void () ResetPlayersDelayed = {
    if(duel_reset_timer < 1 && duel_reset_timer > 0) {
        self.nextthink = time + duel_reset_timer;
        duel_reset_timer = 0;
    } else if(duel_reset_timer <= 0) {
        ResetPlayers();
        dremove(self);
    } else {
        bprint(PRINT_HIGH, Q"\sReset in \x10", ftos(duel_reset_timer), "\x11\s\n");
        FO_Sound(self, CHAN_AUTO, "buttons/switch04.wav", 1, ATTN_NONE);
        duel_reset_timer--;
        self.nextthink = time + 1;
    }
};

void () ResetPlayersWithCountdown = {
    local entity reset_timer;
    local float remainder;
    no_fire_mode = 1;
    if(duel_reset_delay) {
        reset_timer = find(world, classname, "duel_reset_timer");
        if(!reset_timer) {
            remainder = duel_reset_delay % 1;
            duel_reset_timer = duel_reset_delay - remainder;
            reset_timer = spawn();
            reset_timer.classname = "duel_reset_timer";
            reset_timer.nextthink = time + remainder;
            reset_timer.think = ResetPlayersDelayed;
        }
    } else {
        ResetPlayers();
    }

}

void (entity targ, entity attacker) Killed = {
    local entity oself;
	KillSound(targ, attacker);
    if (attacker == world && (targ.classname == "building_dispenser" || targ.classname == "building_sentrygun"))
        attacker = targ;

    oself = self;
    self = targ;
    if (self.health < -99)
        self.health = -99;

    if ((self.movetype == MOVETYPE_PUSH) ||
        //make sure unmovable players like those feigning/building are still given an obituary
        //(self.movetype == MOVETYPE_NONE && !self.is_building && !self.is_detpacking && !self.is_feigning)) {
        (self.movetype == MOVETYPE_NONE && self.classname != "player")) {

        self.th_die();
        self = oself;
        return;
    }

    self.enemy = attacker;

    if (self.flags & FL_MONSTER) {

        killed_monsters = killed_monsters + 1;
        WriteByte(MSG_ALL, SVC_KILLEDMONSTER);
    }

    ClientObituary(self, attacker);
    self.takedamage = DAMAGE_NO;
    self.touch = SUB_Null;

    monster_death_use();
    self.th_die();
    self = oself;
    if(duelmode && targ.classname == "player" && !cb_prematch) {
        //Already in no fire mode - implies you're not the first to die
        if(no_fire_mode) {
            if(CountRemainingTeams() == 0) {
                if(!duel_draw_countdown) {
                    ResetPlayers();
                }
            }
        } else {
            if(CountRemainingTeams() < 2) {
                ResetPlayersWithCountdown();
            }
        }
    }
    if(vote_anarchy_mode) {
        UnvoteForMap(targ);
    }
};

void (entity targ, entity inflictor, entity attacker, float damage) HitSound = {
    if(nohitsounds)
        return;
															 	 															   						  	
    if ((attacker.classname == "player") || (attacker.classname == "building_sentrygun") || (attacker.classname == "building_dispenser"))
    {
        if ((targ.classname == "player") || (targ.classname == "building_sentrygun") || (targ.classname == "building_dispenser"))
        {
            local entity trueattacker;

            if (attacker.classname == "building_sentrygun")
            {	// work out correct attacker
                trueattacker = attacker.real_owner;
            }
            else 
            {
                trueattacker = attacker;
            }


            if(zutmode)
                return;	

            if (trueattacker == targ)
                return;

            float hitsound = infokeyf(trueattacker, "hitsound");
            if (hitsound == 1 || hitsound == 2)
            {
                local float crit = 0;

                if((inflictor.weapon == DMSG_ROCKETL) && (damage >= 80)) {
                    crit = 1;
                }
                if ((inflictor.weapon == DMSG_SSHOTGUN) && (damage >= 40)) {
                    crit = 1;
                }
                if ((inflictor.weapon == DMSG_GRENADEL) && (damage >= 85)) {
                    crit = 1;
                }
                if ((inflictor.weapon == DMSG_INCENDIARY) && (damage >= 40)) {
                    crit = 1;
                }

                if (targ.playerclass == PC_SPY && IsFeigned(targ))
                        return;

                float targteam;
                targteam = (targ.undercover_team == 0) ? targ.team_no : targ.undercover_team;

                if (targteam != attacker.team_no) {
                    if (crit == 1)
                        MSG_SoundOne(trueattacker, "misc/hitsoundcrit.wav", CHAN_AUTO, 1);
                    else
                        MSG_SoundOne(trueattacker, "misc/hitsound.wav", CHAN_AUTO, 1);
                }
                else {
                    if (hitsound == 2)
                        MSG_SoundOne(trueattacker, "misc/hitsoundteam.wav", CHAN_AUTO, 1);
                }
            }
        }
    }
};

void (entity targ, entity attacker) KillSound = {


    if ((attacker.classname == "player") || (attacker.classname == "building_sentrygun") || (attacker.classname == "building_dispenser")) {
        if ((targ.classname == "player") || (targ.classname == "building_sentrygun") || (targ.classname == "building_dispenser")) {

            local entity trueattacker;
            if (attacker.classname == "building_sentrygun") {
                trueattacker = attacker.real_owner;
            }
            else {
                trueattacker = attacker;
            }
            
            if(zutmode)
                 return;
                 
            local string killsound = infokey(trueattacker, "killsound");

            if (killsound == "1" || killsound == "2" || killsound == "3"){

                if (targ.team_no != trueattacker.team_no) {
                    MSG_SoundOne(trueattacker, "misc/killsound.wav", CHAN_AUTO, 1);
                    return;
                }
                else {

                    if (trueattacker == targ) {
                        if(killsound == "3") {
                            MSG_SoundOne(trueattacker, "misc/killsoundteam.wav", CHAN_AUTO, 1);
                        }
                        return;
                    }

                    if (killsound == "2" || killsound == "3") {
                        MSG_SoundOne(trueattacker, "misc/killsoundteam.wav", CHAN_AUTO, 1);
                    }

                }
            }
        }
    }
    else {
        if (targ.classname == "player") {
            local string targkillsound = infokey(targ, "killsound");
            if (targkillsound == "3") {
                MSG_SoundOne(targ, "misc/killsoundteam.wav", CHAN_AUTO, 1);
            }
        }
    }
};

static inline float valid_hitflag_target(string name) {
    return (name == "player" || name == "building_sentrygun" ||
            name == "building_dispenser");
}

void BroadcastHitFlag(entity targ, entity inflictor, entity attacker,
        float original_damage, float actual_damage) {
    float hitflag = 0;

    if (!valid_hitflag_target(attacker.classname) ||
        !valid_hitflag_target(targ.classname))
        return;

    if (attacker.classname != "player")
        attacker = attacker.real_owner;

    if ((attacker.tfstate & TFSTATE_FLASHED))
        return;

    // Feigned spies act as corpses unless they're a teammate
    if (targ.playerclass == PC_SPY && IsFeigned(targ) && targ.health > 0 &&
        targ.team_no != attacker.team_no)
        return;

    // server allowances -- just baking in hitflag coz im a lazy as
    if(nohitsounds)
        hitflag |= HITFLAG_NOAUDIO;
    if(nohittext)
        hitflag |= HITFLAG_NOTEXT;

    // no armour left on target -- other games call it "screaming" "cracked" "one shot" etc
    if(targ.armorvalue <= 0 && targ.classname == "player")
        hitflag |= HITFLAG_NOARMOUR;

    // friendly
    if ((targ.team_no == attacker.team_no) ||
        (targ.playerclass == PC_SPY && targ.undercover_team == attacker.team_no))
        hitflag |= HITFLAG_FRIENDLY;

    // kill
    if(targ.health <= 0) {
        hitflag |= HITFLAG_KILLINGBLOW;

        if (targ.playerclass == PC_SPY) {
           if (targ.undercover_team != 0 && targ.team_no != attacker.team_no) {
               hitflag |= HITFLAG_KILLEDUNDERCOVERSPY;
               hitflag &= ~HITFLAG_FRIENDLY;
           }
           if (IsFeigned(targ))
               hitflag |= HITFLAG_FEIGNEDENEMY;
        }
    }

    // meatshot -- this is very lazy, should do t_missile etc
    if (((inflictor.weapon == DMSG_ROCKETL) && (original_damage >= 80)) ||
        ((inflictor.weapon == DMSG_SSHOTGUN) && (original_damage >= 40)) ||
        ((inflictor.weapon == DMSG_GRENADEL) && (original_damage >= 85)) ||
        ((inflictor.weapon == DMSG_INCENDIARY) && (original_damage >= 40)))
            hitflag |= HITFLAG_MEATSHOT;

    // headshot
    if (deathmsg == DMSG_SNIPERHEADSHOT)
        hitflag |= HITFLAG_HEADSHOT;

    // self
    if (attacker == targ)
        hitflag |= HITFLAG_SELF;

    // TODO: cuss - done elsewhere

    msg_entity = attacker;
    WriteByte(MSG_MULTICAST, SVC_CGAMEPACKET);
    WriteByte(MSG_MULTICAST, MSG_HITFLAG);
    WriteCoord(MSG_MULTICAST, targ.origin.x);
    WriteCoord(MSG_MULTICAST, targ.origin.y);
    WriteCoord(MSG_MULTICAST, targ.origin.z);
    WriteShort(MSG_MULTICAST, actual_damage);
    WriteShort(MSG_MULTICAST, original_damage);
    WriteShort(MSG_MULTICAST, hitflag);

    multicast('0 0 0', MULTICAST_ONE_R);
};

void (entity targ, entity inflictor, entity attacker, float damage) T_Damage = {
    local vector dir;
    local entity oldself, te;
    local float save;
    local float take;

    if (!targ.takedamage)
        return;
    if (SpawnProtectedFrom(targ, inflictor, attacker))
        return;

    if (attacker.classname == "player")
        damage = damage * 0.9;

    if (attacker.classname == "player") {

        if (attacker.super_damage_finished > time)
            damage = damage * 4;

        if ((targ.classname != "player") && (targ.classname != "bot")) {

            if (!Activated(targ, attacker)) {

                if (targ.else_goal != 0) {

                    te = Findgoal(targ.else_goal);
                    if (te)
                        AttemptToActivate(te, attacker, targ);
                }
                return;
            }
        }
    }
    damage_attacker = attacker;
    if (teamplay & (TEAMPLAY_LESSSCOREHELP | TEAMPLAY_LESSPLAYERSHELP))
        damage = TeamEqualiseDamage(targ, attacker, damage);

    save = ceil(targ.armortype * damage);
    if (save >= targ.armorvalue) {

        save = targ.armorvalue;
        targ.armortype = 0;
        targ.armorclass = 0;
        targ.items =
            targ.items -
            (targ.items & (IT_ARMOR1 | IT_ARMOR2 | IT_ARMOR3));
    }
    targ.armorvalue = targ.armorvalue - save;
    take = ceil(damage - save);

    if (targ.flags & FL_CLIENT) {
        targ.dmg_take = targ.dmg_take + take;
        targ.dmg_save = targ.dmg_save + save;
        targ.dmg_inflictor = inflictor;
    }
    if ((inflictor != world) && (targ.movetype == MOVETYPE_WALK)) {

        targ.immune_to_check = time + (damage / 20);
        dir = targ.origin - ((inflictor.absmin + inflictor.absmax) * 0.5);
        dir = normalize(dir);
        if (((damage < 60) &&
             ((attacker.classname == "player") &&
              (targ.classname == "player")))
            && (attacker.netname != targ.netname))
            targ.velocity = targ.velocity + dir * damage * 11;
        else
            targ.velocity = targ.velocity + dir * damage * 8;

        PMD_Event(targ, PMDE_DAMAGE);
        if (((rj > 1) &&
             ((attacker.classname == "player") &&
              (targ.classname == "player")))
            && (attacker.netname == targ.netname))
            targ.velocity = (targ.velocity + ((dir * damage) * rj));
    }
    if (targ.flags & FL_GODMODE)
        return;

    if (targ.invincible_finished >= time) {
        if (self.invincible_sound < time) {

            FO_Sound(targ, CHAN_ITEM, "items/protect3.wav", 1, ATTN_NORM);
            self.invincible_sound = time + 2;
        }
        return;
    }
    if ((attacker.classname == "player")
        && ((targ.classname == "player") ||
            (targ.classname == "building_sentrygun"))) {

        if (((targ.team_no > 0) && (targ.team_no == attacker.team_no)) &&
            (targ != attacker)) {

            if (teamplay & TEAMPLAY_NOEXPLOSIVE)
                return;
            else if (teamplay & TEAMPLAY_HALFEXPLOSIVE)
                take = take / 2;
        }
    }
    if ((take < 1) && (take != 0))
        take = 1;

    float damh = (take > targ.health) ? targ.health : take;
    targ.health = targ.health - take;

    if (targ.armorvalue < 1) {
        targ.armorclass = 0;
        targ.armorvalue = 0;
    }
    if ((attacker.classname == "player" || targ.classname == "player") && (take + save > 0)) {
        LogEventDamage(attacker, targ, inflictor, take + save, damh + save);
    }
    if (targ.health <= 0) {
        LogEventKill(attacker, targ, inflictor);
        Killed(targ, attacker);
        return;
    }

    oldself = self;
    self = targ;

    if (self.th_pain) {
        self.th_pain(attacker, take);
        if (skill >= 3)
            self.pain_finished = time + 5;
    }
    self = oldself;
};

void TF_T_Damage(entity targ, entity inflictor, entity attacker,
      float damage, float T_flags, float T_AttackType) {
    local vector dir;
    local entity oldself;
    local entity te;
    local float save;
    local float take;
    local float olddmsg;
    local float no_damage;
    local float original_damage = damage;


    if (targ.takedamage == 0)
        return;

    if (T_AttackType & TF_TD_NOSOUND) {
        targ.health = damage;
        return;
    }
    if (cease_fire)
        return;
    if (SpawnProtectedFrom(targ, inflictor, attacker))
        return;

    float fl = 0;
    if (attacker.classname == "player")
        fl |= KF_SRC_PLAYER;
    if (targ.classname == "player")
        fl |= KF_TARG_PLAYER;
    if (targ == attacker)
        fl |= KF_SELF;

    no_damage = 0;

    // Gated on KF_SRC_PLAYER to match where this used to sit -- inside the
    // player-attacker block -- rather than widening it to any attacker.
    if ((fl & KF_SRC_PLAYER) && attacker.super_damage_finished > time)
        fl |= KF_QUAD;

    // Burn amp, source scale and quad -- shared with the client's knockback
    // nudge so the two agree.  The armour step is applied further down, once
    // T_AttackType is known.
    damage = Damage_Scale(damage, fl,
                          (targ.tfstate & TFSTATE_BURNING) ? DSF_BURNING : 0);

    if (fl & KF_SRC_PLAYER) {
        if ((fl & KF_TARG_PLAYER == 0)
            && (targ.classname != "bot")
            && (targ.classname != "building_sentrygun")
            && (targ.classname != "building_dispenser")
            && (targ.classname != "building_teleporter_entrance")
            && (targ.classname != "building_teleporter_exit")) {

            if (!Activated(targ, attacker)) {
                if (targ.else_goal != 0) {
                    te = Findgoal(targ.else_goal);
                    if (te)
                        AttemptToActivate(te, attacker, targ);
                }
                return;
            }
        }
    }

    HitSound(targ, inflictor, attacker, damage);

    damage_attacker = attacker;

    if (teamplay & (TEAMPLAY_LESSSCOREHELP | TEAMPLAY_LESSPLAYERSHELP))
        damage = TeamEqualiseDamage(targ, attacker, damage);

    if ((targ.armorclass != 0) && (T_AttackType != 0)) {
        if ((targ.armorclass & AT_SAVESHOT) && (T_AttackType & TF_TD_SHOT))
            damage = floor(damage * 0.5);
        if ((targ.armorclass & AT_SAVENAIL) && (T_AttackType & TF_TD_NAIL))
            damage = floor(damage * 0.5);
        if ((targ.armorclass & AT_SAVEEXPLOSION) && (T_AttackType & TF_TD_EXPLOSION))
            damage = Damage_Scale(damage, 0, DSF_SAVE_EXPLOSION);
        if ((targ.armorclass & AT_SAVEELECTRICITY) && (T_AttackType & TF_TD_ELECTRICITY))
            damage = floor(damage * 0.5);
        if ((targ.armorclass & AT_SAVEFIRE) && (T_AttackType & TF_TD_FIRE))
            damage = floor(damage * 0.5);
    }

    if (T_flags & TF_TD_IGNOREARMOR) {
        take = damage;
        save = 0;
    } else {
        save = ceil(targ.armortype * damage);
        if ((fl & KF_SRC_PLAYER)
            && (targ.team_no > 0)
            && (targ.team_no == attacker.team_no)
            && (targ != attacker)
            && (T_flags & 2)) {

            if (T_AttackType & TF_TD_EXPLOSION) {

                if (teamplay & 1024) {
                    save = 0;
                } else if (teamplay & 512) {
                    save = save / 2;
                }

            } else if (teamplay & 256)
                save = 0;
            else if (teamplay & 128)
                save = save / 2;

        }
        if (save >= targ.armorvalue) {

            save = targ.armorvalue;
            targ.armortype = 0;
            targ.armorclass = 0;
            targ.items =
                targ.items -
                (targ.items & (IT_ARMOR1 | IT_ARMOR2 | IT_ARMOR3));

        }
        targ.armorvalue = targ.armorvalue - save;
        take = ceil(damage - save);

    }
    if (targ.flags & FL_CLIENT) {

        targ.dmg_take = targ.dmg_take + take;
        targ.dmg_save = targ.dmg_save + save;
        targ.dmg_inflictor = inflictor;

    }

    if (!(T_AttackType & TF_TD_NOMOMENTUM) && damage) {
        if ((inflictor != world) && (targ.movetype == MOVETYPE_WALK) && !(targ.tfstate & TFSTATE_CANT_MOVE)) {
            if (deathmsg != DMSG_GREN_NAIL && deathmsg != DMSG_GREN_SHOCK && deathmsg != DMSG_GREN_BURST) {
                targ.immune_to_check = time + damage / 20;

                float moment = Class_ScaleMoment(targ.playerclass, damage);
                vector pmd_before = targ.velocity;
                targ.velocity += CalcKnock(inflictor.origin, targ, fl, moment);
                PMD_Knock(targ, targ.velocity - pmd_before, moment);
                Predict_AddFilterEnt(targ, inflictor.filter_ent ?: inflictor);
            }
        }
    }
    
    if (targ.flags & FL_GODMODE)
        return;

    if (targ.invincible_finished >= time) {
        if (self.invincible_sound < time) {
            FO_Sound(targ, CHAN_ITEM, "items/protect3.wav", 1, 1);
            self.invincible_sound = time + 2;
        }
        return;
    }
    if ((attacker.classname == "player")
        && ((targ.classname == "player")
            || (targ.classname == "building_sentrygun")
            || (targ.classname == "building_dispenser")
            || (targ.classname == "building_teleporter_entrance")
            || (targ.classname == "building_teleporter_exit"))) {

        if ((targ.team_no > 0) && (targ.team_no == attacker.team_no)
            && (targ != attacker) && (T_flags & TF_TD_NOTTEAM)) {

            if (T_AttackType & TF_TD_EXPLOSION) {

                if (teamplay & TEAMPLAY_NOEXPLOSIVE)
                    no_damage = TRUE;
                else if (teamplay & TEAMPLAY_HALFEXPLOSIVE)
                    take = take / 2;

            } else if (teamplay & TEAMPLAY_NODIRECT)
                no_damage = TRUE;
            else if (teamplay & TEAMPLAY_HALFDIRECT)
                take = take / 2;
        }
    }

    if (targ.playerclass == PC_SPY) {
        targ.attacked_by = attacker;
        targ.feignmsg = deathmsg;
    }

    if (T_flags & TF_TD_NOTSELF)
        if (targ == attacker)
            return;

    if (take < 1)
        take = 1;

    take = rint(take);

    float damh = (take > targ.health) ? targ.health : take;

    if (no_damage == 0)
        targ.health = (targ.health - take);

    if ((attacker.classname == "player")
        && ((targ.classname == "player")
            || (targ.classname == "building_sentrygun")
            || (targ.classname == "building_dispenser")
            || (targ.classname == "building_teleporter_entrance")
            || (targ.classname == "building_teleporter_exit"))) {

        if ((targ.team_no > 0) && (targ.team_no == attacker.team_no)
            && (targ != attacker) && (T_flags & 2)) {

            olddmsg = deathmsg;

            if (T_AttackType & TF_TD_EXPLOSION) {

                deathmsg = DMSG_TEAMKILL;
                if (teamplay & TP_FULLMIRRORAOE)
                    TF_T_Damage(attacker, world, world, take, 1, 0);
                else if (teamplay & TP_HALFMIRRORAOE)
                    TF_T_Damage(attacker, world, world, take / 2, 1, 0);

            } else {

                deathmsg = DMSG_TEAMKILL;
                if (teamplay & TP_FULLMIRRORDIRECT)
                    TF_T_Damage(attacker, world, world, take, 1, 0);
                else if (teamplay & TP_HALFMIRRORDIRECT)
                    TF_T_Damage(attacker, world, world, take / 2, 1, 0);
            }
            deathmsg = olddmsg;
        }
    }

    if (no_damage == TRUE)
        return;
    
    if ((attacker.classname == "player" || targ.classname == "player") && (take + save > 0)) {
        LogEventDamage(attacker, targ, inflictor, take + save, damh + save);
    }
    if (targ.armorvalue < 1) {
        targ.armorclass = 0;
        targ.armorvalue = 0;
    }

    if (zutmode)
        BroadcastHitFlag(targ, inflictor, attacker, original_damage, damh);

    if (targ.health <= 0) {

        if ((inflictor.classname == "detpack")
            && (inflictor.is_disarming) && (inflictor.enemy == targ))
            deathmsg = DMSG_DETPACK_DIS;
        LogEventKill(attacker, targ, inflictor);
        Killed(targ, attacker);
        return;
    }

    oldself = self;
    self = targ;

    if (self.th_pain) {
        self.th_pain(attacker, take);
        if (skill >= 3) {
            self.pain_finished = time + 5;
        }
    }

    self = oldself;
};

// A player still inside their spawn pass-through window ignores explosions
// from their own team, so the window covers knockback and concussion as well
// as the collision it was built for.  Self is deliberately excluded: rocket
// jumping out of your own spawn still works.
// Transparency rather than a glow.  The quad glow showed through a disguise
// and gave a spy away; alpha rides the existing model, so a disguised spy
// stays whoever they are pretending to be, just faded.
const float kSpawnProtectAlpha = 0.6;
// Pass-through without the exemption: the window has ended but the player is
// still phased, for good for an all-time attacker or during the grace
// below for anyone still wedged in someone.  Less transparent than the
// window itself, so teammates can tell that their splash now lands on them,
// while still readable as pass-through.
const float kSpawnPassthroughAlpha = 0.8;
// Through the window the player's alpha pulses between the protected value
// and what it will be when the window ends, opaque for most and the
// pass-through value for an all-time attacker: slowly at first, the rate
// rising steadily until it is a flash for the last half second, so everyone
// can read how long the exemption has left.  The phase accumulates per frame
// so the rate can change without the pulse jumping.
//
// Every alpha write is a delta to every client that can see the player, and
// a spawn wave is many players at once standing still, so the alpha is
// sampled at kSpawnPulseSampleHz rather than written every frame.
const float kSpawnPulseSlowHz = 0.5;
const float kSpawnPulseFastHz = 8;
const float kSpawnPulseFlashFor = 0.5;
const float kSpawnPulseSampleHz = 16;

static float spawnprotect_maxclients;   // players are the first maxclients edicts

// Once per physics frame, from StartFrame.
void SpawnProtect_Pulse() {
    if (!spawnprotect_maxclients)
        spawnprotect_maxclients = cvar("maxclients");
    for (float i = 1; i <= spawnprotect_maxclients; i++) {
        entity e = edict_num(i);
        if (!e.spawn_protect_until || time > e.spawn_protect_until)
            continue;
        if (e.solid != SOLID_SLIDEBOX)
            continue;

        float ramp = (e.spawn_protect_until - kSpawnPulseFlashFor) - e.spawn_protect_start;
        float frac = ramp > 0 ? bound(0, (time - e.spawn_protect_start) / ramp, 1) : 1;
        float hz = kSpawnPulseSlowHz + (kSpawnPulseFastHz - kSpawnPulseSlowHz) * frac;
        e.spawn_pulse_phase += hz * frametime * 2 * M_PI;

        if (time < e.spawn_pulse_next)
            continue;
        e.spawn_pulse_next = time + 1 / kSpawnPulseSampleHz;
        float mix = 0.5 - 0.5 * cos(e.spawn_pulse_phase);

        float end_alpha = (e.all_time == ALL_TIME_ATTACK) ? kSpawnPassthroughAlpha : 1;
        float a = kSpawnProtectAlpha + (end_alpha - kSpawnProtectAlpha) * mix;
        if (a != e.alpha)
            e.alpha = a;
    }
}

// When the window ends with someone still inside the player, the pass-through
// (not the exemption) lasts up to this much longer, ending the moment they
// come apart; only if they are still overlapping at the end is the other
// player telefragged.
const float kSpawnProtectGrace = 2;


float SpawnProtectActive(entity p) {
    return p.spawn_protect_until && time <= p.spawn_protect_until;
}

// A building's damage is the building's, not its owner's: an engineer
// respawning does not disarm their sentry, and a sentry is never held off a
// phased player.  Its bullets already name the sentry as attacker; its
// rockets name the owner, which is why the inflictor decides this.
static float SpawnProtect_IsBuilding(entity e) {
    return e.classname == "building_sentrygun" ||
           e.classname == "building_sentrygun_base" ||
           e.classname == "building_dispenser";
}

// The window ends: the damage exemption goes now, and with it the alpha that
// marks it.  The pass-through lasts a little longer -- for good for an
// all-time attacker, and for everyone else until the grace check finds them
// clear of other players.
void SpawnProtect_End(entity p) {
    p.spawn_protect_until = 0;
    p.alpha = kSpawnPassthroughAlpha;
    if (p.all_time != ALL_TIME_ATTACK)
        p.spawn_protect_grace = time + kSpawnProtectGrace;
}

// Under spawn protection -- the window, not an all-time attacker's permanent
// pass-through -- damage between the protected player and their own team is
// dropped, in both directions.  Anything involving an enemy is untouched, so
// a phased player fights and is fought exactly as anyone else, and world
// damage still applies.  Their own explosions still hurt and push them, so
// rocket jumping out of spawn works, and the single shotgun is left alone on
// purpose, so a teammate can still push a phased player out of the way.
// Gates every damage path, so knockback is withheld with the damage.
float SpawnProtectedFrom(entity targ, entity inflictor, entity attacker) {
    if (targ == attacker)
        return FALSE;
    if (targ.classname != "player")
        return FALSE;

    // Damage from an enemy ends the window on the spot: it is for a clean
    // spawn, not cover in a fight.  Reached just before the damage lands, and
    // the grace before going solid still applies.
    if (SpawnProtectActive(targ) && attacker.team_no &&
        attacker.team_no != targ.team_no) {
        SpawnProtect_End(targ);
        return FALSE;
    }

    if (SpawnProtect_IsBuilding(inflictor))
        return FALSE;
    if (attacker.classname != "player" || targ.team_no != attacker.team_no)
        return FALSE;
    if (deathmsg == DMSG_SHOTGUN)
        return FALSE;
    return SpawnProtectActive(targ) || SpawnProtectActive(attacker);
}

void (entity inflictor, entity attacker, float damage,
      entity ignore1, entity ignore2 = __NULL__, entity only = __NULL__)
        T_RadiusDamage = {
    local float points;
    local entity head;
    local vector org;

    int count, i;
    entity* rlist = findradius_list(inflictor.origin, damage + 40, count);

    for (i = 0; i < count; i ++) {
        entity e = rlist[i];
        if ((only && e != only) || e == ignore1 || e == ignore2)
            continue;

        if (!e.takedamage)
            continue;

        float fl = e == attacker ? KF_SELF : 0;
        points = CalcRadiusDamage(inflictor.origin, e, fl, damage);
        if (points > 0) {
            if (CanDamage(e, inflictor)) {
                // shambler takes half damage from all explosions
                if (e.classname == "monster_shambler")
                    T_Damage(e, inflictor, attacker,
                            points * 0.5);
                else
                    TF_T_Damage(e, inflictor, attacker, points,
                            TF_TD_NOTTEAM, TF_TD_EXPLOSION);
            }
        }
    }
};


void (entity attacker, float damage) T_BeamDamage = {
    local float points;
    local entity head;

    head = findradius(attacker.origin, damage + 40);
    while (head) {
        if (head.takedamage) {

            points = 0.5 * vlen(attacker.origin - head.origin);
            if (points < 0)
                points = 0;
            points = damage - points;
            if (head == attacker)
                points = points * 0.5;
            if (points > 0)
                if (CanDamage(head, attacker))
                    T_Damage(head, attacker, attacker, points);
        }
        head = head.chain;
    }
};
