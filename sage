[33mcommit edc5379c1ec442997b469406e2c6807ffa37df91[m[33m ([m[1;36mHEAD[m[33m -> [m[1;32mdev-cur[m[33m, [m[1;32mstaging[m[33m)[m
Author: newby <newby@rakis.net>
Date:   Mon Jul 15 15:07:21 2024 -0700

    qwtf: emit rev info, etc

[1mdiff --git a/csqc/status.qc b/csqc/status.qc[m
[1mindex 91a5dba9c..e1dd143a4 100644[m
[1m--- a/csqc/status.qc[m
[1m+++ b/csqc/status.qc[m
[36m@@ -437,7 +437,7 @@[m [mvoid(PanelID panelid, string text) drawMOTDPanel = {[m
             );[m
             */[m
             if(strlen(SBAR.MOTD) <= 1) {[m
[31m-                motd = "Welcome to FortressOne\nwww.fortressone.org";[m
[32m+[m[32m                motd = "Welcome to QWTF.Live\nlogs.qwtf.live";[m
             } else {[m
                 motd = SBAR.MOTD;[m
             }[m
[1mdiff --git a/ssqc/world.qc b/ssqc/world.qc[m
[1mindex ec1d85a5b..244e8c810 100644[m
[1m--- a/ssqc/world.qc[m
[1m+++ b/ssqc/world.qc[m
[36m@@ -112,10 +112,10 @@[m [mvoid () worldspawn = {[m
         localcmd(strcat("serverinfo starttime \"", timestamp, "\"\n"));[m
     }[m
 [m
[31m-    localcmd("serverinfo fo_rev \"");[m
[32m+[m[32m    localcmd("serverinfo qwtf_rev \"");[m
     localcmd(REV);[m
     localcmd("\"\n");[m
[31m-    localcmd("serverinfo gametype \"fortressone\"\n");[m
[32m+[m[32m    localcmd("serverinfo gametype \"qwtflive\"\n");[m
 [m
     st = infokey(world, "*sv_gamedir");[m
     if ((st != string_null) && (st != "fortress"))[m

[33mcommit d0387a8db23efe99712e99b8fb8ba7ea72cc442e[m[33m ([m[1;31mtfl/staging[m[33m)[m
Author: newby <newby@rakis.net>
Date:   Sun Jul 14 01:08:50 2024 -0700

    mvds: insert mvd-readable flag-init after recording is started

[1mdiff --git a/csqc/events.qc b/csqc/events.qc[m
[1mindex 0fb00bf2a..a559ce64b 100644[m
[1m--- a/csqc/events.qc[m
[1m+++ b/csqc/events.qc[m
[36m@@ -29,17 +29,17 @@[m [mvoid() CSQC_Parse_Event = {[m
 [m
             //use next available[m
             if(index < 0) {[m
[31m-                for(float i = 0; i < FlagInfoLines.length; i++) {[m
[31m-                    if(FlagInfoLines[i].id == 0) {[m
[32m+[m[32m                for (float i = 0; i < FlagInfoLines.length; i++) {[m
[32m+[m[32m                    if (FlagInfoLines[i].id == 0 || FlagInfoLines[i].id == goalno) {[m
                         index = i;[m
                         break;[m
                     }[m
                 }[m
             }[m
[31m-            if(index >= 0 && index < MAX_FLAGINFO_LINES) {[m
[32m+[m[32m            if (index >= 0 && index < MAX_FLAGINFO_LINES) {[m
                 FlagInfoLines[index].id = goalno;[m
                 FlagInfoLines[index].message = "";[m
[31m-                if(mdl)[m
[32m+[m[32m                if (mdl)[m
                     precache_model(mdl);[m
                 te = spawn();[m
                 te.renderflags = RF_VIEWMODEL | RF_DEPTHHACK | RF_NOSHADOW;[m
[36m@@ -50,10 +50,10 @@[m [mvoid() CSQC_Parse_Event = {[m
 [m
                 string iconname = "sb_key1";[m
                 vector iconcolour = '1 1 1';[m
[31m-                if(iconindex == FLAGINFO_ICON_FLAG) {[m
[32m+[m[32m                if (iconindex == FLAGINFO_ICON_FLAG) {[m
                     iconname = strcat("flag_", ftos(ownerteam));[m
                     iconcolour = '1 1 1';[m
[31m-                } else if(iconindex == FLAGINFO_ICON_BUTTON) {[m
[32m+[m[32m                } else if (iconindex == FLAGINFO_ICON_BUTTON) {[m
                     iconname = strcat("off_icon_glow_", ftos(ownerteam));[m
                     iconcolour = '1 1 1';[m
                 }[m
[1mdiff --git a/csqc/hud.qc b/csqc/hud.qc[m
[1mindex d0bdb8f72..859b18dea 100644[m
[1m--- a/csqc/hud.qc[m
[1m+++ b/csqc/hud.qc[m
[36m@@ -618,8 +618,9 @@[m [mvoid Hud_DrawFlagStatusBar()[m
 [m
             HRC_drawpic([pos_x, pos_y + sizey * i, 0], icon, [sizex, sizey, 0], iconcolour, alpha, 0);[m
 [m
[32m+[m[32m            // TODO: ping correct[m
             if (FlagInfoLines[i].time_return >= 0) {[m
[31m-                float ret = max(FlagInfoLines[i].time_return - pstate_pred.server_time, 0);[m
[32m+[m[32m                float ret = max(FlagInfoLines[i].time_return - time, 0);[m
                 string stime = sprintf("%0.1f", ret);[m
                 float smallfont = 6 * getHudPanel(HUDP_FLAGINFO)->Scale;[m
                 HRC_drawstring([m
[1mdiff --git a/ssqc/clan.qc b/ssqc/clan.qc[m
[1mindex 2ee4ee510..444712142 100644[m
[1m--- a/ssqc/clan.qc[m
[1m+++ b/ssqc/clan.qc[m
[36m@@ -331,6 +331,9 @@[m [mvoid () PreMatch_Think = {[m
                     logfilehandle = fopen(str, FILE_WRITE);[m
                 }[m
             }[m
[32m+[m[32m        } else if (self.cnt2 == 1) {[m
[32m+[m[32m            InitAllStatuses(world);[m
[32m+[m[32m            flag_update = 1;[m
         }[m
         num = strzone(ftos(self.cnt2));[m
         p = find(world, classname, "player");[m
[1mdiff --git a/ssqc/status.qc b/ssqc/status.qc[m
[1mindex 89cac8491..df6563ece 100644[m
[1m--- a/ssqc/status.qc[m
[1m+++ b/ssqc/status.qc[m
[36m@@ -581,9 +581,6 @@[m [mvoid (entity pl, string s1, string s2, string s3, string s4, string s5, string s[m
 string getLocationName(vector location);[m
 [m
 void (entity Player, float index, entity Item, float icon) InitClientFlagStatus = {[m
[31m-    if(!infokeyf(Player, INFOKEY_P_CSQCACTIVE) || !CF_GetSetting("ssbfi", "server_sbflaginfo", "1")) {[m
[31m-        return;[m
[31m-    }[m
     msg_entity = Player;[m
     WriteByte(MSG_MULTICAST, SVC_CGAMEPACKET); [m
     WriteByte(MSG_MULTICAST, MSG_FLAGINFOINIT);[m
[36m@@ -593,7 +590,12 @@[m [mvoid (entity Player, float index, entity Item, float icon) InitClientFlagStatus[m
     WriteFloat(MSG_MULTICAST, Item.skin);[m
     WriteFloat(MSG_MULTICAST, Item.owned_by);[m
     WriteFloat(MSG_MULTICAST, icon);[m
[31m-    multicast('0 0 0', MULTICAST_ONE_R_NOSPECS); [m
[32m+[m
[32m+[m[32m    if (msg_entity != world)[m
[32m+[m[32m        multicast('0 0 0', MULTICAST_ONE_R_NOSPECS);[m
[32m+[m[32m    else {[m
[32m+[m[32m        multicast('0 0 0', MULTICAST_ALL_R);  // For MVD pickup.[m
[32m+[m[32m    }[m
 }[m
 [m
 void (entity Player) InitAllStatuses = {[m

[33mcommit 84b53c1e12450d029e511391caba6fd9fe6a986a[m
Author: newby <newby@rakis.net>
Date:   Sun Jul 14 00:21:15 2024 -0700

    init: remove fo_serverscripts MSG_INIT-cvar

[1mdiff --git a/ssqc/world.qc b/ssqc/world.qc[m
[1mindex 9e8e84bac..ec1d85a5b 100644[m
[1m--- a/ssqc/world.qc[m
[1m+++ b/ssqc/world.qc[m
[36m@@ -88,11 +88,6 @@[m [mvoid WorldSpawnPost()[m
 }[m
 [m
 void () worldspawn = {[m
[31m-    // Set this variable on connect so the client knows it has access to[m
[31m-    // FortressOne aliases.[m
[31m-    WriteByte(MSG_INIT, 9/*svc_stufftext*/);[m
[31m-    WriteString(MSG_INIT, "set fo_serverscripts 1\n");[m
[31m-[m
     round_end_time = 0;[m
 [m
     vote_started = -1;[m

[33mcommit 002bc59748f786e213417f217b72c45e7e77cc3d[m
Author: newby <newby@rakis.net>
Date:   Sat Jul 13 23:59:42 2024 -0700

    flaginfo: move out of status_refresh

[1mdiff --git a/csqc/csextradefs.qc b/csqc/csextradefs.qc[m
[1mindex 175917a0d..c8ae41614 100644[m
[1m--- a/csqc/csextradefs.qc[m
[1m+++ b/csqc/csextradefs.qc[m
[36m@@ -364,7 +364,7 @@[m [mtypedef struct {[m
     string message;[m
     //string model;[m
     entity model;[m
[31m-    float timeleft;[m
[32m+[m[32m    float time_return;[m
     float state;[m
     vector loc;[m
     string carrier;[m
[1mdiff --git a/csqc/events.qc b/csqc/events.qc[m
[1mindex f79d65195..0fb00bf2a 100644[m
[1m--- a/csqc/events.qc[m
[1m+++ b/csqc/events.qc[m
[36m@@ -66,7 +66,7 @@[m [mvoid() CSQC_Parse_Event = {[m
             string message = "";[m
             goalno = readfloat();[m
             float state = readfloat();[m
[31m-            float timeleft = -1;[m
[32m+[m[32m            float time_return = -1;[m
             vector droploc = '0 0 0';[m
             string carrier = "";[m
             string locname = "";[m
[36m@@ -80,9 +80,9 @@[m [mvoid() CSQC_Parse_Event = {[m
                     break;[m
                 case FLAGINFO_DROPPED:[m
                     message = "^3DROPPED^7";[m
[31m-                    timeleft = readfloat();[m
[32m+[m[32m                    time_return = readfloat();[m
                     float showloc = readfloat();[m
[31m-                    if(showloc == FLAGINFO_LOCATION) {[m
[32m+[m[32m                    if (showloc == FLAGINFO_LOCATION) {[m
                         droploc_x = readcoord();[m
                         droploc_y = readcoord();[m
                         droploc_z = readcoord();[m
[36m@@ -94,14 +94,15 @@[m [mvoid() CSQC_Parse_Event = {[m
                     message = "^4RETURNING";[m
                     break;[m
             }[m
[31m-            for(float i = 0; i < FlagInfoLines.length; i++) {[m
[31m-                if(FlagInfoLines[i].id == goalno) {[m
[32m+[m[32m            for (float i = 0; i < FlagInfoLines.length; i++) {[m
[32m+[m[32m                if (FlagInfoLines[i].id == goalno) {[m
                     FlagInfoLines[i].message = message;[m
[31m-                    FlagInfoLines[i].timeleft = timeleft;[m
[32m+[m[32m                    FlagInfoLines[i].time_return = time_return;[m
                     FlagInfoLines[i].state = state;[m
                     FlagInfoLines[i].loc = droploc;[m
                     FlagInfoLines[i].carrier = carrier;[m
                     FlagInfoLines[i].locname = locname;[m
[32m+[m[32m                    break;[m
                 }[m
             }[m
             break;[m
[1mdiff --git a/csqc/hud.qc b/csqc/hud.qc[m
[1mindex 409806b56..d0bdb8f72 100644[m
[1m--- a/csqc/hud.qc[m
[1m+++ b/csqc/hud.qc[m
[36m@@ -618,11 +618,16 @@[m [mvoid Hud_DrawFlagStatusBar()[m
 [m
             HRC_drawpic([pos_x, pos_y + sizey * i, 0], icon, [sizex, sizey, 0], iconcolour, alpha, 0);[m
 [m
[31m-            if (FlagInfoLines[i].timeleft >= 0) [m
[31m-            {[m
[31m-                string stime = ftos(FlagInfoLines[i].timeleft);[m
[32m+[m[32m            if (FlagInfoLines[i].time_return >= 0) {[m
[32m+[m[32m                float ret = max(FlagInfoLines[i].time_return - pstate_pred.server_time, 0);[m
[32m+[m[32m                string stime = sprintf("%0.1f", ret);[m
                 float smallfont = 6 * getHudPanel(HUDP_FLAGINFO)->Scale;[m
[31m-                HRC_drawstring([pos_x + sizex - stringwidth(stime, 1, [smallfont, smallfont]), pos_y + sizey * (i + 1) - smallfont, 0], stime, [smallfont, smallfont], '1 1 1', 1, 0);[m
[32m+[m[32m                HRC_drawstring([m
[32m+[m[32m                    [pos_x + sizex + smallfont * 1.5 -[m
[32m+[m[32m                        stringwidth(stime, 1, [smallfont, smallfont]),[m
[32m+[m[32m                     pos_y + sizey * (i + 1) -[m
[32m+[m[32m                       smallfont, 0],[m
[32m+[m[32m                    stime, [smallfont, smallfont], '1 1 1', 1, 0);[m
             }[m
         }[m
     }[m
[1mdiff --git a/ssqc/client.qc b/ssqc/client.qc[m
[1mindex 4c2b274f5..f460881ac 100644[m
[1m--- a/ssqc/client.qc[m
[1m+++ b/ssqc/client.qc[m
[36m@@ -827,9 +827,6 @@[m [mvoid () DecodeLevelParms = {[m
 	deathammo_cells = CF_GetSetting("dac", "deathammo_cells", "50");[m
 	deathammo_rockets = CF_GetSetting("dar", "deathammo_rockets", "10");[m
 [m
[31m-        // enable server-side flaginfo on statusbar [on][m
[31m-        //        server_sbflaginfo = CF_GetSetting("ssbfi", "server_sbflaginfo", "1");[m
[31m-[m
         reverse_cap = CF_GetSetting("rcap","reverse_cap", "0");[m
 [m
         if (reverse_cap) [m
[36m@@ -3107,6 +3104,8 @@[m [mvoid CheckClientAdmin() {[m
     }[m
 }[m
 [m
[32m+[m[32mvoid ClientsFlagUpdate(entity only);[m
[32m+[m
 void () ClientConnect = {[m
     if (!infokeyf(self,INFOKEY_P_CSQCACTIVE)) {[m
         sprint(self, PRINT_HIGH, "FTE/CSQC is required for this server, please download the latest client package at www.fortressone.org\n");[m
[36m@@ -3148,6 +3147,7 @@[m [mvoid () ClientConnect = {[m
     }[m
 [m
     InitAllStatuses(self);[m
[32m+[m[32m    ClientsFlagUpdate(self);[m
     UpdateClientMOTD(self);[m
     UpdateClientTeamScores(self);[m
     UpdateClientPrematch(self, !cb_prematch);[m
[36m@@ -3920,8 +3920,32 @@[m [mvoid () InitReverseCap = {[m
 [m
 }[m
 [m
[32m+[m[32mvoid ClientsFlagUpdate(entity only) {[m
[32m+[m[32m    if (only) {[m
[32m+[m[32m        // forced[m
[32m+[m[32m    } else if (flag_update) {[m
[32m+[m[32m        flag_update = 0;[m
[32m+[m[32m    } else {[m
[32m+[m[32m        return;[m
[32m+[m[32m    }[m
[32m+[m
[32m+[m[32m    entity tfdet = find(world, classname, "info_tfdetect");[m
[32m+[m[32m    if (tfdet) {[m
[32m+[m[32m        float item_status[] = {tfdet.display_item_status1, tfdet.display_item_status2,[m
[32m+[m[32m                               tfdet.display_item_status3, tfdet.display_item_status4};[m
[32m+[m
[32m+[m[32m        for (float i = 0; i < item_status.length; i++) {[m
[32m+[m[32m            entity fe = Finditem(item_status[i]);[m
[32m+[m[32m            if (fe)[m
[32m+[m[32m                UpdateClientsFlagStatus(fe, only);[m
[32m+[m[32m        }[m
[32m+[m[32m    }[m
[32m+[m[32m}[m
[32m+[m
 void EndFrame() {[m
     AnnounceUpdate();[m
[32m+[m
[32m+[m[32m    ClientsFlagUpdate(world);[m
 }[m
 [m
 #if 0[m
[1mdiff --git a/ssqc/events.qc b/ssqc/events.qc[m
[1mindex 831817dd8..956f2b833 100644[m
[1m--- a/ssqc/events.qc[m
[1m+++ b/ssqc/events.qc[m
[36m@@ -309,6 +309,7 @@[m [mvoid (entity attacker, entity target, float tfstate) LogEventAffliction = {[m
 };[m
 [m
 void (entity player) LogEventGoal = {[m
[32m+[m[32m    flag_update = 1;[m
     if(player == world)[m
         return;[m
 [m
[36m@@ -332,6 +333,7 @@[m [mvoid (entity player) LogEventGoal = {[m
 [m
 [m
 void (entity player) LogEventPickupGoal = {[m
[32m+[m[32m    flag_update = 1;[m
     player.touches = player.touches + 1;[m
     if (canlog == 0)[m
         return;[m
[36m@@ -349,6 +351,7 @@[m [mvoid (entity player) LogEventPickupGoal = {[m
 }[m
 [m
 void (entity player, float timecarried) LogEventFumble = {[m
[32m+[m[32m    flag_update = 1;[m
     if (canlog == 0)[m
         return;[m
 [m
[1mdiff --git a/ssqc/qw.qc b/ssqc/qw.qc[m
[1mindex ef1d93dcf..541d13e83 100644[m
[1m--- a/ssqc/qw.qc[m
[1m+++ b/ssqc/qw.qc[m
[36m@@ -785,4 +785,6 @@[m [mstring game_token;[m
 .float periodic_think_time;[m
 float min_ping_limit_ms;[m
 [m
[32m+[m[32mfloat flag_update;[m
[32m+[m
 string mvd_name;[m
[1mdiff --git a/ssqc/spect.qc b/ssqc/spect.qc[m
[1mindex 975c586f4..014fc896d 100644[m
[1m--- a/ssqc/spect.qc[m
[1m+++ b/ssqc/spect.qc[m
[36m@@ -41,6 +41,7 @@[m [mvoid () SpectatorConnect = {[m
     self.motd = 0;[m
     if(infokeyf(self, INFOKEY_P_CSQCACTIVE)) {[m
         InitAllStatuses(self);[m
[32m+[m[32m        ClientsFlagUpdate(self);[m
         UpdateClientMOTD(self);[m
         UpdateClientTeamScores(self);[m
         UpdateClientPrematch(self, !cb_prematch);[m
[1mdiff --git a/ssqc/status.qc b/ssqc/status.qc[m
[1mindex ca6b19b3a..89cac8491 100644[m
[1m--- a/ssqc/status.qc[m
[1m+++ b/ssqc/status.qc[m
[36m@@ -646,20 +646,13 @@[m [mvoid (entity Player, entity Goal) UpdateClientButtonStatus = {[m
     multicast('0 0 0', MULTICAST_ONE_NOSPECS);    [m
 }[m
 [m
[31m-void (entity Player, entity Item) UpdateClientFlagStatus = {[m
[31m-    if(!infokeyf(Player, INFOKEY_P_CSQCACTIVE))[m
[31m-        return;[m
[31m-    msg_entity = Player;[m
[31m-    WriteByte(MSG_MULTICAST, SVC_CGAMEPACKET); [m
[31m-    WriteByte(MSG_MULTICAST, MSG_FLAGINFO); [m
[32m+[m[32mvoid UpdateClientsFlagStatus(entity Item, entity only) {[m
[32m+[m[32m    WriteByte(MSG_MULTICAST, SVC_CGAMEPACKET);[m
[32m+[m[32m    WriteByte(MSG_MULTICAST, MSG_FLAGINFO);[m
     WriteFloat(MSG_MULTICAST, Item.goal_no);[m
     if (Item.goal_state == 1 && Item.owner != world) {[m
         WriteFloat(MSG_MULTICAST, FLAGINFO_CARRIED);[m
[31m-        if (Player == Item.owner) {[m
[31m-            WriteString(MSG_MULTICAST, "YOU");[m
[31m-        } else {[m
[31m-            WriteString(MSG_MULTICAST, Item.owner.netname);[m
[31m-        }[m
[32m+[m[32m        WriteString(MSG_MULTICAST, Item.owner.netname);[m
     } else {[m
         if (Item.origin != Item.oldorigin) {[m
             if((Item.nextthink - time) >= 0) {[m
[36m@@ -667,9 +660,10 @@[m [mvoid (entity Player, entity Item) UpdateClientFlagStatus = {[m
                 if(noreturn) {[m
                     WriteFloat(MSG_MULTICAST, -1);[m
                 } else {[m
[31m-                    WriteFloat(MSG_MULTICAST, rint(Item.bubble_count - time));[m
[32m+[m[32m                    WriteFloat(MSG_MULTICAST, rint(Item.bubble_count));[m
                 }[m
[31m-                if((Item.think == tfgoalitem_dropthink || Item.think == tfgoalitem_remove) && !Item.owner) {[m
[32m+[m[32m                if ((Item.think == tfgoalitem_dropthink ||[m
[32m+[m[32m                     Item.think == tfgoalitem_remove) && !Item.owner) {[m
                     WriteFloat(MSG_MULTICAST, FLAGINFO_LOCATION);[m
                     WriteCoord(MSG_MULTICAST, Item.origin_x);[m
                     WriteCoord(MSG_MULTICAST, Item.origin_y);[m
[36m@@ -685,7 +679,12 @@[m [mvoid (entity Player, entity Item) UpdateClientFlagStatus = {[m
             WriteFloat(MSG_MULTICAST, FLAGINFO_HOME);[m
         }[m
     }[m
[31m-    multicast('0 0 0', MULTICAST_ONE_NOSPECS); [m
[32m+[m[32m    if (only) {[m
[32m+[m[32m        msg_entity = only;[m
[32m+[m[32m        multicast('0 0 0', MULTICAST_ONE_R_NOSPECS);[m
[32m+[m[32m    } else {[m
[32m+[m[32m        multicast('0 0 0', MULTICAST_ALL_R);[m
[32m+[m[32m    }[m
 }[m
 [m
 string (entity Player, entity Item, float teamno) GetItemStatus = {[m
[36m@@ -990,32 +989,6 @@[m [mvoid (entity pl) RefreshStatusBar = {[m
 [m
     csqcactive = infokeyf(pl, INFOKEY_P_CSQCACTIVE);[m
     if(pl.classname == "observer" && csqcactive) {[m
[31m-        if (tfdet)[m
[31m-        {[m
[31m-            for (float t = 1; t <= number_of_teams; t++) [m
[31m-            {[m
[31m-                switch (t)[m
[31m-                {[m
[31m-                    case 1:[m
[31m-                        te = Finditem(tfdet.display_item_status1);[m
[31m-                        break;[m
[31m-                    case 2:[m
[31m-                        te = Finditem(tfdet.display_item_status2);[m
[31m-                        break;[m
[31m-                    case 3:[m
[31m-                        te = Finditem(tfdet.display_item_status3);[m
[31m-                        break;[m
[31m-                    case 4:[m
[31m-                        te = Finditem(tfdet.display_item_status4);[m
[31m-                        break;[m
[31m-                }[m
[31m-[m
[31m-                if (te)[m
[31m-                {[m
[31m-                    UpdateClientFlagStatus(pl, te);[m
[31m-                }[m
[31m-            }[m
[31m-        }[m
         tg = find(world, classname, "info_tfgoal");[m
         while (tg) {[m
             if (tg.track_goal) {[m
[36m@@ -1054,37 +1027,10 @@[m [mvoid (entity pl) RefreshStatusBar = {[m
         {[m
             //pl.StatusRefreshTime = time + 1;[m
             UpdateClientStatusBar(pl);[m
[31m-            [m
[32m+[m
             // flag info[m
             if (CF_GetSetting("ssbfi", "server_sbflaginfo", "1"))[m
             {[m
[31m-                if (tfdet)[m
[31m-                {[m
[31m-                    for (float t = 1; t <= number_of_teams; t++) [m
[31m-                    {[m
[31m-                        switch (t)[m
[31m-                        {[m
[31m-                            case 1:[m
[31m-                                te = Finditem(tfdet.display_item_status1);[m
[31m-                                break;[m
[31m-                            case 2:[m
[31m-                                te = Finditem(tfdet.display_item_status2);[m
[31m-                                break;[m
[31m-                            case 3:[m
[31m-                                te = Finditem(tfdet.display_item_status3);[m
[31m-                                break;[m
[31m-                            case 4:[m
[31m-                                te = Finditem(tfdet.display_item_status4);[m
[31m-                                break;[m
[31m-                        }[m
[31m-[m
[31m-                        if (te)[m
[31m-                        {[m
[31m-                            UpdateClientFlagStatus(pl, te);[m
[31m-                        }[m
[31m-                    }[m
[31m-                }[m
[31m-[m
                 tg = find(world, classname, "info_tfgoal");[m
                 while (tg) {[m
                     if (tg.track_goal) {[m
[36m@@ -1097,42 +1043,6 @@[m [mvoid (entity pl) RefreshStatusBar = {[m
         else if (CF_GetSetting("ssbfi", "server_sbflaginfo", "1")) // no csqc but has sbflaginfo on and server_sbflaginfo is enabled[m
         {[m
             ct = "";[m
[31m-            i = number_of_teams; // Extra newlines[m
[31m-            for (float t = 1; t <= number_of_teams; t++) {[m
[31m-                switch (t)[m
[31m-                {[m
[31m-                    case 1:[m
[31m-                        te = Finditem(tfdet.display_item_status1);[m
[31m-                        break;[m
[31m-                    case 2:[m
[31m-                        te = Finditem(tfdet.display_item_status2);[m
[31m-                        break;[m
[31m-                    case 3:[m
[31m-                        te = Finditem(tfdet.display_item_status3);[m
[31m-                        break;[m
[31m-                    case 4:[m
[31m-                        te = Finditem(tfdet.display_item_status4);[m
[31m-                        break;[m
[31m-                }[m
[31m-[m
[31m-                if (te)[m
[31m-                {[m
[31m-                    if(number_of_teams < 4) {[m
[31m-                        ct = strcat(ct, strpadr(GetItemStatus(pl, te, t),40),"\n");[m
[31m-                        if((te.think == tfgoalitem_dropthink || te.think == tfgoalitem_remove) && !te.owner && (te.origin != te.oldorigin)) {[m
[31m-                            ct = strcat(ct, strpadr(strcat("\s Location: \s", getLocationName(te.origin)),40));[m
[31m-                        }[m
[31m-                        i += 1;[m
[31m-                    } else {[m
[31m-                        if((te.think == tfgoalitem_dropthink || te.think == tfgoalitem_remove) && !te.owner && (te.origin != te.oldorigin)) {[m
[31m-                            ct = strcat(ct, strpadr(strcat(GetItemStatus(pl, te, t),"\s: \s", getLocationName(te.origin)),40));[m
[31m-                        } else {[m
[31m-                            ct = strcat(ct, strpadr(GetItemStatus(pl, te, t),40));[m
[31m-                        }[m
[31m-                    }[m
[31m-                }[m
[31m-                ct = strcat(ct, "\n");[m
[31m-            }[m
             tg = find(world, classname, "info_tfgoal");[m
             while (tg) {[m
                 if (tg.track_goal && i < 6 && tg.goal_state == TFGS_DELAYED) {[m
[1mdiff --git a/ssqc/tfortmap.qc b/ssqc/tfortmap.qc[m
[1mindex 4bc6d119b..b2e6d77cb 100644[m
[1m--- a/ssqc/tfortmap.qc[m
[1m+++ b/ssqc/tfortmap.qc[m
[36m@@ -612,19 +612,11 @@[m [mvoid (entity AD) ParseTFDetect = {[m
 [m
 entity(float ino) Finditem =[m
 {[m
[31m-    local entity tg;[m
[31m-    //local string st;[m
[31m-[m
[31m-    tg = find(world, classname, "item_tfgoal");[m
[31m-    while (tg) {[m
[31m-        if (tg.goal_no == ino)[m
[31m-            return (tg);[m
[31m-        tg = find(tg, classname, "item_tfgoal");[m
[31m-    }[m
[31m-    //dprint("Could not find an item with a goal_no of ");[m
[31m-    //st = ftos(ino);[m
[31m-    //dprint(st);[m
[31m-    //dprint(".\n");[m
[32m+[m[32m    int n;[m
[32m+[m[32m    entity* list = find_list(classname, "item_tfgoal", EV_STRING, n);[m
[32m+[m[32m    for (int i = 0; i < n; i++)[m
[32m+[m[32m        if (list[i].goal_no == ino)[m
[32m+[m[32m            return list[i];[m
     return world;[m
 };[m
 [m
[36m@@ -2300,6 +2292,7 @@[m [mvoid () ReturnItem = {[m
 [m
     if (self.enemy.touch == item_tfgoal_hidden_touch)[m
         return;[m
[32m+[m[32m    flag_update = 1;[m
 [m
     self.enemy.goal_state = 2;[m
     if ((self.enemy.goal_activation & 8192) &&[m

[33mcommit 7be9a9649cf1efb4d42547515b25b41123d4ca91[m
Author: newby <newby@rakis.net>
Date:   Sat Jul 13 14:42:25 2024 -0700

    core: rework identify, reduce packet spam

[1mdiff --git a/csqc/csextradefs.qc b/csqc/csextradefs.qc[m
[1mindex 89bed89c8..175917a0d 100644[m
[1m--- a/csqc/csextradefs.qc[m
[1m+++ b/csqc/csextradefs.qc[m
[36m@@ -866,7 +866,11 @@[m [mfloat all_time;[m
 float painfinished;[m
 float jump_counter;[m
 float attack_counter;[m
[31m-float last_id_time;[m
[32m+[m[32mstruct {[m
[32m+[m[32m    float id_time;[m
[32m+[m[32m    float spawn_gen;[m
[32m+[m[32m} id_state;[m
[32m+[m
 [m
 vector FO_Hud_Icon_Size = [24, 24, 0];[m
 vector FO_Hud_Icon_Font_Size = [8, 8, 0];[m
[1mdiff --git a/csqc/events.qc b/csqc/events.qc[m
[1mindex 21e794440..f79d65195 100644[m
[1m--- a/csqc/events.qc[m
[1m+++ b/csqc/events.qc[m
[36m@@ -109,7 +109,8 @@[m [mvoid() CSQC_Parse_Event = {[m
             ParseSBAR();[m
             break;[m
         case MSG_ID:[m
[31m-            last_id_time = time;[m
[32m+[m[32m            id_state.id_time = time;[m
[32m+[m[32m            id_state.spawn_gen = game_state.spawn_gen;[m
             SBAR.Identify = readstring();[m
             break;[m
         case MSG_GRENPRIMED:[m
[1mdiff --git a/csqc/hud.qc b/csqc/hud.qc[m
[1mindex 083c688dc..409806b56 100644[m
[1m--- a/csqc/hud.qc[m
[1m+++ b/csqc/hud.qc[m
[36m@@ -1064,8 +1064,9 @@[m [mvoid Hud_DrawIdentifyPanel(string identify) {[m
         // click event[m
     }[m
 [m
[31m-    if (time > last_id_time + 3)[m
[31m-        return;[m
[32m+[m[32m    if (time > id_state.id_time + 3 || is_demo ||[m
[32m+[m[32m        game_state.spawn_gen != id_state.spawn_gen)[m
[32m+[m[32m          return;[m
 [m
     vector fontSize = FO_Hud_Icon_Font_Size * panel->Scale;[m
 [m
[1mdiff --git a/csqc/status.qc b/csqc/status.qc[m
[1mindex 34912009d..91a5dba9c 100644[m
[1m--- a/csqc/status.qc[m
[1m+++ b/csqc/status.qc[m
[36m@@ -17,11 +17,7 @@[m [mvoid(PanelID ignored, string text) drawClipSize = {[m
 };[m
 [m
 void(PanelID ignored, string text) drawIdentify = {[m
[31m-    if (time > last_id_time + 5)[m
[31m-        return;[m
[31m-[m
[31m-    if (strlen(text) > 0 || fo_hud_editor)[m
[31m-        Hud_DrawIdentifyPanel(text);[m
[32m+[m[32m    Hud_DrawIdentifyPanel(text);[m
 };[m
 [m
 void(PanelID ignored, string text) drawTeamScorePanel = {[m
[1mdiff --git a/ssqc/actions.qc b/ssqc/actions.qc[m
[1mindex 753824c78..bc5f879fe 100644[m
[1m--- a/ssqc/actions.qc[m
[1m+++ b/ssqc/actions.qc[m
[36m@@ -214,253 +214,229 @@[m [mvoid (entity pe_player) FO_SpecTrackPoint = {[m
     }[m
 }[m
 [m
[31m-void (entity pe_player) FO_Spectator_Identify = {[m
[31m-    //ezquake draws player ids over their heads[m
[31m-    if(pe_player.classname != "observer" || !infokeyf(pe_player, INFOKEY_P_CSQCACTIVE)) {[m
[31m-        return;[m
[31m-    }[m
[31m-    [m
[32m+[m[32mstatic string TF_Spectator_Identify(entity pe_player) {[m
     makevectors(pe_player.v_angle);[m
     //start just forward of the player in case you're speccing someone[m
[31m-    traceline(pe_player.origin + v_forward * 96, pe_player.origin + v_forward * 4096, MOVE_EVERYTHING, pe_player);[m
[31m-    [m
[31m-    if (trace_ent != world) {[m
[31m-        local string s_id_string = "";[m
[31m-        if(trace_ent.classname == "player") {[m
[31m-            //s_id_string = strcat(trace_ent.netname, "\n", TeamFortress_TeamGetColorString(trace_ent.team_no), " ", TeamFortress_GetClassName(trace_ent.playerclass), "\n");[m
[31m-            s_id_string = strcat(trace_ent.netname, "\n");[m
[31m-            if(trace_ent.playerclass == PC_SPY) {[m
[31m-                if (trace_ent.undercover_team || trace_ent.undercover_skin) {[m
[31m-                    s_id_string = strcat(s_id_string, "\sDisguised as: \s ");[m
[31m-                    if (trace_ent.undercover_team != 0)[m
[31m-                        s_id_string = strcat(s_id_string, TeamFortress_TeamGetColorString(trace_ent.undercover_team));[m
[31m-                    if (trace_ent.undercover_skin != 0)[m
[31m-                        s_id_string = strcat(s_id_string, " ", TeamFortress_GetClassName(trace_ent.undercover_skin));[m
[31m-                    s_id_string = strcat(s_id_string, "\n");[m
[31m-                }[m
[32m+[m[32m    traceline(pe_player.origin + v_forward * 96,[m
[32m+[m[32m              pe_player.origin + v_forward * 4096, MOVE_NORMAL, pe_player);[m
[32m+[m
[32m+[m[32m    if (trace_ent == world)[m
[32m+[m[32m        return "";[m
[32m+[m
[32m+[m[32m    string s_id_string = "";[m
[32m+[m[32m    if(trace_ent.classname == "player") {[m
[32m+[m[32m        s_id_string = strcat(trace_ent.netname, "\n");[m
[32m+[m[32m        if(trace_ent.playerclass == PC_SPY) {[m
[32m+[m[32m            if (trace_ent.undercover_team || trace_ent.undercover_skin) {[m
[32m+[m[32m                s_id_string = strcat(s_id_string, "\sDisguised as: \s ");[m
[32m+[m[32m                if (trace_ent.undercover_team != 0)[m
[32m+[m[32m                    s_id_string = strcat(s_id_string, TeamFortress_TeamGetColorString(trace_ent.undercover_team));[m
[32m+[m[32m                if (trace_ent.undercover_skin != 0)[m
[32m+[m[32m                    s_id_string = strcat(s_id_string, " ", TeamFortress_GetClassName(trace_ent.undercover_skin));[m
[32m+[m[32m                s_id_string = strcat(s_id_string, "\n");[m
             }[m
[31m-            s_id_string = strcat(s_id_string, "\sH:\s ", ftos(trace_ent.health));[m
[31m-            s_id_string = strcat(s_id_string, " \sA:\s ", ftos(trace_ent.armorvalue), "\n");[m
[31m-        } else if(trace_ent.classname == "building_sentrygun") {[m
[31m-            s_id_string = strcat(trace_ent.real_owner.netname, "'s Sentry Gun (", TeamFortress_TeamGetColorString(trace_ent.team_no), ")\n");[m
[31m-            s_id_string = strcat(s_id_string, "\sLevel:\s ", ftos(trace_ent.weapon), "\n");[m
[31m-            s_id_string = strcat(s_id_string, "\sH:\s ", ftos(rint(trace_ent.health)), "\n");[m
[31m-        } else if(trace_ent.classname == "building_sentrygun_base") {[m
[31m-            s_id_string = strcat(trace_ent.real_owner.netname, "'s Sentry Gun (", TeamFortress_TeamGetColorString(trace_ent.team_no), ")\n");[m
[31m-            s_id_string = strcat(s_id_string, "\sLevel:\s ", ftos(trace_ent.oldenemy.weapon), "\n");[m
[31m-            s_id_string = strcat(s_id_string, "\sH:\s ", ftos(rint(trace_ent.oldenemy.health)), "\n");[m
[31m-        } else if(trace_ent.classname == "building_dispenser") {[m
[31m-            s_id_string = strcat(trace_ent.real_owner.netname, "'s Dispenser (", TeamFortress_TeamGetColorString(trace_ent.team_no), ")\n");[m
[31m-            s_id_string = strcat(s_id_string, "\sH:\s ", ftos(rint(trace_ent.health)), "\n");[m
[31m-        } else if(trace_ent.classname == "detpack") {[m
[31m-            s_id_string = strcat(trace_ent.owner.netname, "'s Detpack (", TeamFortress_TeamGetColorString(trace_ent.team_no), ")\n");[m
[31m-            s_id_string = strcat(s_id_string, "\sTime Left:\s ", ftos(trace_ent.detpack_left), " seconds\n");[m
[31m-        }[m
[31m-[m
[31m-       // refresh status bar[m
[31m-        pe_player.ident_time = time + 0.5;[m
[31m-        if(pe_player.ident_string != s_id_string) {[m
[31m-            pe_player.ident_string = s_id_string;[m
[31m-            UpdateClientIDString(pe_player);[m
         }[m
[32m+[m[32m        s_id_string = strcat(s_id_string, "\sH:\s ", ftos(trace_ent.health));[m
[32m+[m[32m        s_id_string = strcat(s_id_string, " \sA:\s ", ftos(trace_ent.armorvalue), "\n");[m
[32m+[m[32m    } else if (trace_ent.classname == "building_sentrygun") {[m
[32m+[m[32m        s_id_string = strcat(trace_ent.real_owner.netname, "'s Sentry Gun (", TeamFortress_TeamGetColorString(trace_ent.team_no), ")\n");[m
[32m+[m[32m        s_id_string = strcat(s_id_string, "\sLevel:\s ", ftos(trace_ent.weapon), "\n");[m
[32m+[m[32m        s_id_string = strcat(s_id_string, "\sH:\s ", ftos(rint(trace_ent.health)), "\n");[m
[32m+[m[32m    } else if (trace_ent.classname == "building_sentrygun_base") {[m
[32m+[m[32m        s_id_string = strcat(trace_ent.real_owner.netname, "'s Sentry Gun (", TeamFortress_TeamGetColorString(trace_ent.team_no), ")\n");[m
[32m+[m[32m        s_id_string = strcat(s_id_string, "\sLevel:\s ", ftos(trace_ent.oldenemy.weapon), "\n");[m
[32m+[m[32m        s_id_string = strcat(s_id_string, "\sH:\s ", ftos(rint(trace_ent.oldenemy.health)), "\n");[m
[32m+[m[32m    } else if (trace_ent.classname == "building_dispenser") {[m
[32m+[m[32m        s_id_string = strcat(trace_ent.real_owner.netname, "'s Dispenser (", TeamFortress_TeamGetColorString(trace_ent.team_no), ")\n");[m
[32m+[m[32m        s_id_string = strcat(s_id_string, "\sH:\s ", ftos(rint(trace_ent.health)), "\n");[m
[32m+[m[32m    } else if (trace_ent.classname == "detpack") {[m
[32m+[m[32m        s_id_string = strcat(trace_ent.owner.netname, "'s Detpack (", TeamFortress_TeamGetColorString(trace_ent.team_no), ")\n");[m
[32m+[m[32m        s_id_string = strcat(s_id_string, "\sTime Left:\s ", ftos(trace_ent.detpack_left), " seconds\n");[m
     }[m
[32m+[m
[32m+[m[32m    return s_id_string;[m
 }[m
 [m
[31m-void (entity pe_player, float f_type) CF_Identify = {[m
[31m-    if(pe_player.classname == "observer") {[m
[31m-        FO_Spectator_Identify(pe_player);[m
[31m-        return;[m
[31m-    }[m
[31m-    [m
[31m-    local vector v_source;[m
[31m-    [m
[32m+[m[32mstatic string TF_Player_Identify(entity pe_player, float f_type) {[m
[32m+[m[32m    vector v_source;[m
     makevectors(pe_player.v_angle);[m
     v_source = pe_player.origin + v_forward * 10;[m
     v_source_z = pe_player.absmin_z + pe_player.size_z * 0.7;[m
 [m
     traceline(v_source, v_source + v_forward * 2048, MOVE_LAGGED, pe_player);[m
[31m-    if (trace_ent != world) {[m
[31m-        local string s_id_string = "", s_class = "", s_name = "";[m
[31m-        local float f_health = 0, f_maxhealth = 0, f_armor = 0, f_maxarmor = 0, f_friendly = 0, f_fakefriendly = 0, f_sentryhealth = 0, f_maxsentryhealth = 0;[m
[31m-[m
[31m-        // don't identify targets above water if player is under water[m
[31m-        if (pe_player.waterlevel == 3 && !trace_ent.waterlevel)[m
[31m-            return;[m
[31m-[m
[31m-        // don't identify targets under water if player is above water[m
[31m-        if (pe_player.waterlevel < 3 && trace_ent.waterlevel == 3)[m
[31m-            return;[m
[31m-[m
[31m-        // show as friendly if target is on your team or disguised as your team[m
[31m-        if (pe_player.team_no) {[m
[31m-[m
[31m-            if (pe_player.team_no == trace_ent.team_no) {[m
[31m-[m
[31m-                // ignore teammates if type is set to enemies only[m
[31m-                if (f_type == 3)[m
[31m-                    return;[m
[31m-[m
[31m-                f_friendly = 1;[m
[31m-[m
[31m-            } else if (pe_player.team_no == trace_ent.undercover_team) {[m
[31m-[m
[31m-                // ignore teammates if type is set to enemies only[m
[31m-                if (f_type == 3)[m
[31m-                    return;[m
[31m-[m
[31m-                f_fakefriendly = 1;[m
[31m-[m
[32m+[m[32m    if (trace_ent == world)[m
[32m+[m[32m        return "";[m
[32m+[m[32m    string s_id_string = "", s_class = "", s_name = "";[m
[32m+[m[32m    float f_health = 0, f_maxhealth = 0, f_armor = 0, f_maxarmor = 0,[m
[32m+[m[32m          f_friendly = 0, f_fakefriendly = 0, f_sentryhealth = 0,[m
[32m+[m[32m          f_maxsentryhealth = 0;[m
[32m+[m
[32m+[m[32m    // don't identify targets above water if player is under water[m
[32m+[m[32m    // don't identify targets under water if player is above water[m
[32m+[m[32m    if ((pe_player.waterlevel == 3 && !trace_ent.waterlevel) ||[m
[32m+[m[32m        (pe_player.waterlevel < 3 && trace_ent.waterlevel == 3))[m
[32m+[m[32m            return "";[m
[32m+[m
[32m+[m[32m    // show as friendly if target is on your team or disguised as your team[m
[32m+[m[32m    if (pe_player.team_no) {[m
[32m+[m[32m        if (pe_player.team_no == trace_ent.team_no) {[m
[32m+[m[32m            // ignore teammates if type is set to enemies only[m
[32m+[m[32m            if (f_type == 3)[m
[32m+[m[32m                return "";[m
[32m+[m[32m            f_friendly = 1;[m
[32m+[m[32m        } else if (pe_player.team_no == trace_ent.undercover_team) {[m
[32m+[m[32m            // ignore teammates if type is set to enemies only[m
[32m+[m[32m            if (f_type == 3)[m
[32m+[m[32m                return "";[m
[32m+[m[32m            f_fakefriendly = 1;[m
             // ignore enemies if type is set to team only[m
[31m-            } else if (f_type == 2)[m
[31m-                return;[m
[31m-[m
[32m+[m[32m        } else if (f_type == 2) {[m
[32m+[m[32m            return "";[m
         }[m
[32m+[m[32m    }[m
 [m
[31m-        // alive player is found[m
[31m-        if (trace_ent.classname == "player" && trace_ent.health) {[m
[31m-            [m
[31m-            s_name = trace_ent.netname;[m
[31m-            if(votemode) {[m
[31m-                if(trace_ent.vote_map) {[m
[31m-                    s_class = trace_ent.vote_map.netname;[m
[31m-                } else {[m
[31m-                    s_class = "Has not voted";[m
[31m-                }[m
[32m+[m[32m    // alive player is found[m
[32m+[m[32m    if (trace_ent.classname == "player" && trace_ent.health) {[m
[32m+[m[32m        s_name = trace_ent.netname;[m
[32m+[m[32m        if(votemode) {[m
[32m+[m[32m            if(trace_ent.vote_map) {[m
[32m+[m[32m                s_class = trace_ent.vote_map.netname;[m
             } else {[m
[31m-                // set class and name[m
[31m-                s_class = TeamFortress_GetClassName(trace_ent.playerclass);[m
[31m-[m
[31m-                // set health if you're a medic[m
[31m-                if (pe_player.playerclass == PC_MEDIC) {[m
[31m-                    f_health = trace_ent.health;[m
[31m-                    f_maxhealth = trace_ent.max_health;[m
[31m-                }[m
[32m+[m[32m                s_class = "Has not voted";[m
[32m+[m[32m            }[m
[32m+[m[32m        } else {[m
[32m+[m[32m            // set class and name[m
[32m+[m[32m            s_class = TeamFortress_GetClassName(trace_ent.playerclass);[m
 [m
[31m-                // set armor if you're an engineer[m
[31m-                else if (pe_player.playerclass == PC_ENGINEER) {[m
[31m-                    f_armor = trace_ent.armorvalue;[m
[31m-                    f_maxarmor = trace_ent.maxarmor;[m
[31m-                }[m
[32m+[m[32m            // set health if you're a medic[m
[32m+[m[32m            if (pe_player.playerclass == PC_MEDIC) {[m
[32m+[m[32m                f_health = trace_ent.health;[m
[32m+[m[32m                f_maxhealth = trace_ent.max_health;[m
[32m+[m[32m            }[m
 [m
[31m-                // target is an enemy spy[m
[31m-                if (trace_ent.playerclass == PC_SPY && !f_friendly) {[m
[32m+[m[32m            // set armor if you're an engineer[m
[32m+[m[32m            else if (pe_player.playerclass == PC_ENGINEER) {[m
[32m+[m[32m                f_armor = trace_ent.armorvalue;[m
[32m+[m[32m                f_maxarmor = trace_ent.maxarmor;[m
[32m+[m[32m            }[m
 [m
[31m-                    // don't identify feigning enemy spies[m
[31m-                    if (IsFeigned(trace_ent))[m
[31m-                        return;[m
[32m+[m[32m            // target is an enemy spy[m
[32m+[m[32m            if (trace_ent.playerclass == PC_SPY && !f_friendly) {[m
[32m+[m[32m                // don't identify feigning enemy spies[m
[32m+[m[32m                if (IsFeigned(trace_ent))[m
[32m+[m[32m                    return "";[m
 [m
[31m-                    // use undercover name if available[m
[31m-                    if (trace_ent.undercover_name != string_null)[m
[31m-                        s_name = trace_ent.undercover_name;[m
[32m+[m[32m                // use undercover name if available[m
[32m+[m[32m                if (trace_ent.undercover_name != string_null)[m
[32m+[m[32m                    s_name = trace_ent.undercover_name;[m
 [m
[31m-                    // set class to undercover skin[m
[31m-                    if (trace_ent.undercover_skin)[m
[31m-                        s_class = TeamFortress_GetClassName(trace_ent.undercover_skin);[m
[32m+[m[32m                // set class to undercover skin[m
[32m+[m[32m                if (trace_ent.undercover_skin)[m
[32m+[m[32m                    s_class = TeamFortress_GetClassName(trace_ent.undercover_skin);[m
 [m
[31m-                }[m
             }[m
[32m+[m[32m        }[m
[32m+[m[32m    } else if (trace_ent.classname == "building_dispenser") {[m
 [m
[31m-        // dispenser is found[m
[31m-        } else if (trace_ent.classname == "building_dispenser") {[m
[31m-[m
[31m-            if (pe_player == trace_ent.real_owner)[m
[31m-                s_name = "Your dispenser";[m
[31m-            else[m
[31m-                s_name = strcat(trace_ent.real_owner.netname, "'s dispenser");[m
[31m-[m
[31m-            s_class = "";[m
[32m+[m[32m        if (pe_player == trace_ent.real_owner)[m
[32m+[m[32m            s_name = "Your dispenser";[m
[32m+[m[32m        else[m
[32m+[m[32m            s_name = strcat(trace_ent.real_owner.netname, "'s dispenser");[m
 [m
[31m-        // sentry gun is found[m
[31m-        } else if (trace_ent.classname == "building_sentrygun" || trace_ent.classname == "building_sentrygun_base") {[m
[31m-            if (pe_player == trace_ent.real_owner)[m
[31m-                s_name = "Your sentry gun";[m
[31m-            else {[m
[31m-                s_name = strcat(trace_ent.real_owner.netname, "'s sentry gun");[m
[32m+[m[32m        s_class = "";[m
[32m+[m[32m    } else if (trace_ent.classname == "building_sentrygun" ||[m
[32m+[m[32m            trace_ent.classname == "building_sentrygun_base") {[m
[32m+[m[32m        if (pe_player == trace_ent.real_owner) {[m
[32m+[m[32m            s_name = "Your sentry gun";[m
[32m+[m[32m        } else {[m
[32m+[m[32m            s_name = strcat(trace_ent.real_owner.netname, "'s sentry gun");[m
 [m
[31m-                if (pe_player.team_no == trace_ent.team_no) {[m
[31m-                    f_sentryhealth = trace_ent.health;[m
[31m-                    f_maxsentryhealth = trace_ent.max_health;[m
[31m-                }[m
[32m+[m[32m            if (pe_player.team_no == trace_ent.team_no) {[m
[32m+[m[32m                f_sentryhealth = trace_ent.health;[m
[32m+[m[32m                f_maxsentryhealth = trace_ent.max_health;[m
             }[m
[31m-[m
[31m-            s_class = "";[m
[31m-        } else {[m
[31m-            return;[m
         }[m
[32m+[m[32m        s_class = "";[m
[32m+[m[32m    } else {[m
[32m+[m[32m        return "";[m
[32m+[m[32m    }[m
 [m
[31m-        s_name = strdecolorize(s_name);[m
[32m+[m[32m    s_name = strdecolorize(s_name);[m
 [m
[31m-        // set name + health (if medic)[m
[31m-        if (f_maxhealth && (f_friendly || f_fakefriendly)) {[m
[31m-            s_id_string = strcat(s_name, "\n");[m
[31m-            s_id_string = strcat(s_id_string, ftos(f_health));[m
[31m-            if (id_extended) {[m
[31m-                s_id_string = strcat(s_id_string, "/");[m
[31m-                s_id_string = strcat(s_id_string, ftos(f_maxhealth));[m
[31m-            }[m
[31m-            s_id_string = strcat(s_id_string, " hp\n");[m
[32m+[m[32m    // set name + health (if medic)[m
[32m+[m[32m    if (f_maxhealth && (f_friendly || f_fakefriendly)) {[m
[32m+[m[32m        s_id_string = strcat(s_name, "\n");[m
[32m+[m[32m        s_id_string = strcat(s_id_string, ftos(f_health));[m
[32m+[m[32m        if (id_extended) {[m
[32m+[m[32m            s_id_string = strcat(s_id_string, "/");[m
[32m+[m[32m            s_id_string = strcat(s_id_string, ftos(f_maxhealth));[m
[32m+[m[32m        }[m
[32m+[m[32m        s_id_string = strcat(s_id_string, " hp\n");[m
 [m
         // set name + armor (if engineer)[m
[31m-        } else if (f_maxarmor && (f_friendly || f_fakefriendly)) {[m
[31m-            s_id_string = strcat(s_name, "\n");[m
[31m-            s_id_string = strcat(s_id_string, ftos(f_armor));[m
[31m-            if (id_extended) {[m
[31m-                s_id_string = strcat(s_id_string, "/");[m
[31m-                s_id_string = strcat(s_id_string, ftos(f_maxarmor));[m
[31m-            }[m
[31m-            s_id_string = strcat(s_id_string, " armor\n");[m
[32m+[m[32m    } else if (f_maxarmor && (f_friendly || f_fakefriendly)) {[m
[32m+[m[32m        s_id_string = strcat(s_name, "\n");[m
[32m+[m[32m        s_id_string = strcat(s_id_string, ftos(f_armor));[m
[32m+[m[32m        if (id_extended) {[m
[32m+[m[32m            s_id_string = strcat(s_id_string, "/");[m
[32m+[m[32m            s_id_string = strcat(s_id_string, ftos(f_maxarmor));[m
[32m+[m[32m        }[m
[32m+[m[32m        s_id_string = strcat(s_id_string, " armor\n");[m
 [m
         // set name + health (if sentry + engineer)[m
[31m-        } else if (f_maxsentryhealth) {[m
[31m-            s_id_string = strcat(s_name, "\n");[m
[31m-            if (id_extended) {[m
[31m-                s_id_string = strcat(s_id_string, ftos(floor(f_sentryhealth)));[m
[31m-                s_id_string = strcat(s_id_string, "/");[m
[31m-                s_id_string = strcat(s_id_string, ftos(floor(f_maxsentryhealth)));[m
[31m-                s_id_string = strcat(s_id_string, " health");[m
[31m-            }[m
[31m-            s_id_string = strcat(s_id_string, "\n");[m
[32m+[m[32m    } else if (f_maxsentryhealth) {[m
[32m+[m[32m        s_id_string = strcat(s_name, "\n");[m
[32m+[m[32m        if (id_extended) {[m
[32m+[m[32m            s_id_string = strcat(s_id_string, ftos(floor(f_sentryhealth)));[m
[32m+[m[32m            s_id_string = strcat(s_id_string, "/");[m
[32m+[m[32m            s_id_string = strcat(s_id_string, ftos(floor(f_maxsentryhealth)));[m
[32m+[m[32m            s_id_string = strcat(s_id_string, " health");[m
[32m+[m[32m        }[m
[32m+[m[32m        s_id_string = strcat(s_id_string, "\n");[m
 [m
         // just set name (if other class)[m
[31m-        } else {[m
[31m-            s_id_string = strcat("\n", s_name);[m
[31m-            s_id_string = strcat(s_id_string, "\n");[m
[31m-        }[m
[32m+[m[32m    } else {[m
[32m+[m[32m        s_id_string = strcat("\n", s_name);[m
[32m+[m[32m        s_id_string = strcat(s_id_string, "\n");[m
[32m+[m[32m    }[m
 [m
[31m-        if (votemode) {[m
[31m-            // in a voting scenario, set same vs different vote indicator[m
[31m-            if(pe_player.vote_map && trace_ent.vote_map) {[m
[31m-                if(pe_player.vote_map == trace_ent.vote_map) {[m
[31m-                    s_id_string = strcat(s_id_string, "\bComrade\b\n");[m
[31m-                } else {[m
[31m-                    s_id_string = strcat(s_id_string, "\bOpposition\b\n");[m
[31m-                }[m
[32m+[m[32m    if (votemode) {[m
[32m+[m[32m        // in a voting scenario, set same vs different vote indicator[m
[32m+[m[32m        if(pe_player.vote_map && trace_ent.vote_map) {[m
[32m+[m[32m            if(pe_player.vote_map == trace_ent.vote_map) {[m
[32m+[m[32m                s_id_string = strcat(s_id_string, "\bComrade\b\n");[m
[32m+[m[32m            } else {[m
[32m+[m[32m                s_id_string = strcat(s_id_string, "\bOpposition\b\n");[m
             }[m
[31m-        } else {[m
[31m-            // set friendly/enemy[m
[31m-            if (f_friendly || f_fakefriendly)[m
[31m-                s_id_string = strcat(s_id_string, "Friendly");[m
[31m-            else[m
[31m-                s_id_string = strcat(s_id_string, "Hostile");[m
[31m-        }[m
[31m-        [m
[31m-        // set class[m
[31m-        if (s_class != "") {[m
[31m-            s_id_string = strcat(s_id_string, " ");[m
[31m-            s_id_string = strcat(s_id_string, s_class);[m
         }[m
[32m+[m[32m    } else {[m
[32m+[m[32m        // set friendly/enemy[m
[32m+[m[32m        if (f_friendly || f_fakefriendly)[m
[32m+[m[32m            s_id_string = strcat(s_id_string, "Friendly");[m
[32m+[m[32m        else[m
[32m+[m[32m            s_id_string = strcat(s_id_string, "Hostile");[m
[32m+[m[32m    }[m
 [m
[31m-        pe_player.ident_time = time + 0.5;[m
[32m+[m[32m    // set class[m
[32m+[m[32m    if (s_class != "") {[m
[32m+[m[32m        s_id_string = strcat(s_id_string, " ");[m
[32m+[m[32m        s_id_string = strcat(s_id_string, s_class);[m
[32m+[m[32m    }[m
 [m
[31m-        // don't update memory when the id string is the same[m
[31m-        if (pe_player.ident_string == s_id_string) {[m
[31m-            Status_Refresh(pe_player);[m
[31m-            return;[m
[31m-        }[m
[32m+[m[32m    return s_id_string;[m
[32m+[m
[32m+[m[32m}[m
[32m+[m
[32m+[m[32mvoid (entity player, float f_type) CF_Identify = {[m
[32m+[m[32m    if (time < self.owner.ident_time)[m
[32m+[m[32m        return;[m
[32m+[m
[32m+[m[32m    string id_string = player.classname == "observer" ?[m
[32m+[m[32m        TF_Spectator_Identify(player) : TF_Player_Identify(player, f_type);[m
 [m
[31m-        // refresh status bar[m
[31m-        pe_player.ident_string = strzone(s_id_string);[m
[31m-        Status_Refresh(pe_player);[m
[32m+[m[32m    if (id_string != "") {[m
[32m+[m[32m        UpdateClientIDString(player, id_string);[m
[32m+[m[32m        player.ident_time = time + 0.5;[m
     }[m
 };[m
 [m
[1mdiff --git a/ssqc/qw.qc b/ssqc/qw.qc[m
[1mindex 6c67b9f85..ef1d93dcf 100644[m
[1m--- a/ssqc/qw.qc[m
[1m+++ b/ssqc/qw.qc[m
[36m@@ -111,7 +111,6 @@[m [mfloat remote_client_time();[m
 .entity observer_list;          // Used by undefined classes, see TF_MovePlayer[m
 [m
 // Identify variables[m
[31m-.string ident_string;           // Status bar string for identify[m
 .float ident_time;              // The time when last identify found a player[m
 .float autoid_type;             // 0 = ignore noone, 1 = ignore teammates, 2 = ignore enemies[m
 .float autoid_time;             // Time when autoid settings were last checked[m
[1mdiff --git a/ssqc/status.qc b/ssqc/status.qc[m
[1mindex 72905d750..ca6b19b3a 100644[m
[1m--- a/ssqc/status.qc[m
[1m+++ b/ssqc/status.qc[m
[36m@@ -791,12 +791,7 @@[m [mvoid UpdateClientGrenadeThrown(entity pl) = {[m
 #endif[m
 }[m
 [m
[31m-void UpdateClientIDString(entity pl) {[m
[31m-    string ident = time < pl.ident_time ? pl.ident_string : "";[m
[31m-[m
[31m-    if (ident == "")  // No need to send null, we'll expire clientside.[m
[31m-        return;[m
[31m-[m
[32m+[m[32mvoid UpdateClientIDString(entity pl, string ident) {[m
     msg_entity = pl;[m
     WriteByte(MSG_MULTICAST, SVC_CGAMEPACKET);[m
     WriteByte(MSG_MULTICAST, MSG_ID);[m
[36m@@ -1028,8 +1023,6 @@[m [mvoid (entity pl) RefreshStatusBar = {[m
             }[m
             tg = find(tg, classname, "info_tfgoal");[m
         }[m
[31m-        UpdateClientIDString(pl);[m
[31m-        [m
         return;[m
     }[m
 [m
[36m@@ -1061,7 +1054,6 @@[m [mvoid (entity pl) RefreshStatusBar = {[m
         {[m
             //pl.StatusRefreshTime = time + 1;[m
             UpdateClientStatusBar(pl);[m
[31m-            UpdateClientIDString(pl);[m
             [m
             // flag info[m
             if (CF_GetSetting("ssbfi", "server_sbflaginfo", "1"))[m
[36m@@ -1170,80 +1162,6 @@[m [mvoid (entity pl) RefreshStatusBar = {[m
             ct = strzone("\n\n\n\n\n\n");[m
         }[m
     }[m
[31m-[m
[31m-    if (!csqcactive)[m
[31m-    {[m
[31m-        // status line 1 column 1 - grenade timer[m
[31m-        if (pl.StatusGrenTime > 0) {[m
[31m-            st1 = strcat(Q"\sGrenade\s: ", ftos(pl.StatusGrenTime));[m
[31m-            if (pl.fragstreak > 1 && pl.caps)[m
[31m-                st1 = strcat(st1, " sec");[m
[31m-            else[m
[31m-                st1 = strcat(st1, " seconds");[m
[31m-        } else[m
[31m-            st1 = "";[m
[31m-        // status line 1 column 3 - kill streak & caps[m
[31m-        if (pl.fragstreak > 1) {[m
[31m-            st2 = Q"\sKill Streak\s: ";[m
[31m-            st2 = strcat(st2, strpadl(ftos(pl.fragstreak),2));[m
[31m-        } else[m
[31m-            st2 = "";[m
[31m-        if (pl.caps) {[m
[31m-            if (pl.fragstreak > 1)[m
[31m-                st2 = strcat(st2, "  ");[m
[31m-            st3 = Q"\sCaps\s: ";[m
[31m-            st3 = strcat(st3, strpadl(ftos(pl.caps),2));[m
[31m-        } else[m
[31m-            st3 = "";[m
[31m-        st2 = strcat(st2, st3);[m
[31m-        // status line 1[m
[31m-        if (pl.fragstreak > 1 && pl.caps) {[m
[31m-            st2 = strpadl(st2, 25);[m
[31m-            s1 = strpadr(st1, 15);[m
[31m-        } else {[m
[31m-            st2 = strpadl(st2, 20);[m
[31m-            s1 = strpadr(st1, 20);[m
[31m-        }[m
[31m-        s1 = strcat(s1, st2);[m
[31m-        s1 = strcat(s1, "\n");[m
[31m-        s1 = strzone(s1);[m
[31m-[m
[31m-        // status line 2 column 1 - class specific information[m
[31m-        st1 = GetSBClassInfo(pl, csqcactive);[m
[31m-        [m
[31m-        // status line 2[m
[31m-        s2 = strpadr(st1, 40);[m
[31m-        s2 = strcat(s2, "\n");[m
[31m-        s2 = strzone(s2);[m
[31m-[m
[31m-        st1 = "";[m
[31m-        st2 = "";[m
[31m-[m
[31m-        // status line 3 column 2 - clip size[m
[31m-        st2 = strcat(Q"\sClip\s: ", ClipSizeToString(pl, csqcactive));[m
[31m-[m
[31m-        // status line 3 column 3 - grenade 1 count[m
[31m-        st3 = strcat(Q"\sGren1\s: ", ftos(pl.no_grenades_1));[m
[31m-[m
[31m-        // status line 3 column 4 - grenade 2 count[m
[31m-        st4 = strcat(Q"\sGren2\s: ", ftos(pl.no_grenades_2));[m
[31m-[m
[31m-        // status line 3[m
[31m-        s3 = strcat(st1, st2);[m
[31m-        s3 = strpadr(s3, 19);[m
[31m-        s3 = strcat(s3, strpadl(strcat(st3, strcat("  ", st4)), 21));[m
[31m-        s3 = strcat(s3, "\n");[m
[31m-        s3 = strzone(s3);[m
[31m-[m
[31m-        // identify[m
[31m-        if (pl.ident_string != string_null && time < pl.ident_time) {[m
[31m-            ident = strcat(pl.ident_string, "\n\n");[m
[31m-        } else {[m
[31m-            ident = "\n\n\n\n";[m
[31m-        }[m
[31m-    }[m
[31m-    centerprint(pl, pl.StatusString, pad, ident, ct, s1, s2, s3);[m
[31m-    strunzone(pad); strunzone(ct); strunzone(s1); strunzone(s2); strunzone(s3);[m
 };[m
 [m
 string(float num) BlueScoreToString =[m
[1mdiff --git a/ssqc/tfort.qc b/ssqc/tfort.qc[m
[1mindex 1be5619b6..03b527e30 100644[m
[1m--- a/ssqc/tfort.qc[m
[1m+++ b/ssqc/tfort.qc[m
[36m@@ -11,7 +11,7 @@[m [mvoid (entity pe_player, float f_type) CF_Identify;[m
 [m
 float () CloseToSpawnPoint;[m
 [m
[31m-void () AutoId = {[m
[32m+[m[32mstatic void ThinkAutoId() {[m
 [m
     // read autoid settings every 5 seconds[m
     if (time > self.owner.autoid_time) {[m
[36m@@ -25,18 +25,8 @@[m [mvoid () AutoId = {[m
         return;[m
     }[m
 [m
[31m-    if (time > self.ident_time || !self.ident_time) {[m
[31m-[m
[31m-        // remove ident string from memory[m
[31m-        if (self.ident_string != string_null) {[m
[31m-            strunzone(self.ident_string);[m
[31m-            self.ident_string = string_null;[m
[31m-        }[m
[31m-[m
[31m-        CF_Identify(self.owner, self.owner.autoid_type);[m
[31m-    }[m
[31m-[m
[31m-    self.nextthink = time + 0.03;[m
[32m+[m[32m    CF_Identify(self.owner, self.owner.autoid_type);[m
[32m+[m[32m    self.nextthink = time + 0.1;[m
 };[m
 [m
 void () RemoveAutoIdTimer = {[m
[36m@@ -1855,7 +1845,7 @@[m [mvoid () TeamFortress_StartTimers = {[m
     // start autoid timer[m
     timer = spawn();[m
     timer.nextthink = time + 0.3;[m
[31m-    timer.think = AutoId;[m
[32m+[m[32m    timer.think = ThinkAutoId;[m
     timer.owner = self;[m
     timer.classname = "aitimer";[m
 }[m

[33mcommit 4769f124ea146546da6abbeefbebca3e5d91673b[m
Author: newby <newby@rakis.net>
Date:   Sat Jul 13 00:07:45 2024 -0700

    mvd: show active pov

[1mdiff --git a/csqc/csextradefs.qc b/csqc/csextradefs.qc[m
[1mindex 86f53f9f1..89bed89c8 100644[m
[1m--- a/csqc/csextradefs.qc[m
[1m+++ b/csqc/csextradefs.qc[m
[36m@@ -907,3 +907,4 @@[m [mvoid cvar_parse4(string s, __out veci target) {[m
 }[m
 [m
 float servertime;[m
[32m+[m[32mfloat is_demo;[m
[1mdiff --git a/csqc/hud.qc b/csqc/hud.qc[m
[1mindex 558b4b6d8..083c688dc 100644[m
[1m--- a/csqc/hud.qc[m
[1m+++ b/csqc/hud.qc[m
[36m@@ -1123,6 +1123,26 @@[m [mvoid Hud_Draw(float width, float height)[m
     HudSettings.MousePos = [Mouse.x, Mouse.y];[m
 }[m
 [m
[32m+[m[32mvoid Hud_Demo(float width, float height) {[m
[32m+[m[32m    if (!TrackingPlayer())[m
[32m+[m[32m        return;[m
[32m+[m
[32m+[m[32m    static vector pos;[m
[32m+[m[32m    static float next_update;[m
[32m+[m[32m    static string text;[m
[32m+[m
[32m+[m[32m    const vector size = '14 14 0';[m
[32m+[m[32m    if (time > next_update) {[m
[32m+[m[32m        text = "^9POV:^7";[m
[32m+[m[32m        text = strcat(text, getplayerkeyvalue(player_localentnum - 1, INFOKEY_P_NAME));[m
[32m+[m[32m        float tw = stringwidth(text, TRUE, size);[m
[32m+[m[32m        pos = [(width - tw) / 2, height - size.y - 60, 0];[m
[32m+[m[32m        next_update = time + 0.25;[m
[32m+[m[32m    }[m
[32m+[m
[32m+[m[32m    drawstring(pos, text, size, '1 1 1', 1, 0);[m
[32m+[m[32m}[m
[32m+[m
 static const float HUDP_COUNT = HUDP_LAST - HUDP_FIRST + 1;[m
 [m
 struct {[m
[36m@@ -1130,16 +1150,17 @@[m [mstruct {[m
     float idx;[m
 } incremental_hud;[m
 [m
[31m-void Hud_UpdateView(float width, float height, float menushown, float perf_sample) {[m
[32m+[m[32mvoid Hud_UpdateView(float width, float height, float menushown) {[m
     ScreenSize = [width, height, menushown];[m
 [m
[32m+[m[32m    if (is_demo)[m
[32m+[m[32m      Hud_Demo(width, height);[m
[32m+[m
     if (HRC_NewFrame()) {[m
[31m-        float hts = perf_start_sample(&hud_timing, perf_sample);[m
         sui_begin(width, height);[m
         Menu_Draw(width, height, menushown);[m
         Hud_Draw(width, height);[m
         sui_end();[m
[31m-        perf_finish_sample(&hud_timing, hts);[m
         return;[m
     }[m
 [m
[36m@@ -1169,7 +1190,6 @@[m [mvoid Hud_UpdateView(float width, float height, float menushown, float perf_sampl[m
     PanelID id = idx + HUDP_FIRST;[m
     // Time ordered and oldest.[m
     if (time >= incremental_hud.last_draw[idx] + HRC_fps_time()) {[m
[31m-        float hts = perf_start_sample(&hud_partial_timing, perf_sample);[m
         FO_Hud_Panel* p = getHudPanel(id);[m
 [m
         sui_begin(width, height);[m
[36m@@ -1177,7 +1197,6 @@[m [mvoid Hud_UpdateView(float width, float height, float menushown, float perf_sampl[m
         HRC_SetActive(p);[m
         Hud_DrawPanel(getHudPanel(id));[m
         sui_end();[m
[31m-        perf_finish_sample(&hud_partial_timing, hts);[m
 [m
         incremental_hud.last_draw[idx] = time;[m
         // We'll start searching from here for next incremental update.[m
[1mdiff --git a/csqc/main.qc b/csqc/main.qc[m
[1mindex 2e4466774..7d5a1facc 100644[m
[1m--- a/csqc/main.qc[m
[1m+++ b/csqc/main.qc[m
[36m@@ -135,12 +135,13 @@[m [mnoref void(float apiver, string enginename, float enginever) CSQC_Init = {[m
 [m
     PM_Init();[m
 [m
[31m-    if (!isdemo)[m
[32m+[m[32m    is_demo = isdemo();[m
[32m+[m[32m    if (!is_demo)[m
         ClientSettings_Check();[m
     SetupAliases();[m
 [m
     player_menu_type = 0;[m
[31m-    if (!isdemo())[m
[32m+[m[32m    if (!is_demo)[m
         FO_Menu_Game(TRUE);[m
     else[m
         setpause(TRUE);[m
[36m@@ -164,19 +165,20 @@[m [mnoref void() CSQC_WorldLoaded = {[m
 [m
 void FO_CussView();[m
 void FO_CussCrosshair(float width, float height);[m
[31m-void Hud_UpdateView(float width, flo