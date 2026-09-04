[1mdiff --git a/csqc/main.qc b/csqc/main.qc[m
[1mindex c1062043..d123cbbb 100644[m
[1m--- a/csqc/main.qc[m
[1m+++ b/csqc/main.qc[m
[36m@@ -127,10 +127,10 @@[m [mnoref void(float width, float height, float menushown) CSQC_UpdateView = {[m
     if (!CVARF(fo_fte_hud) || CVARF(fo_legacy_sbar))[m
         setproperty(VF_DRAWENGINESBAR, 1);[m
 [m
[31m-    addentities((intermission?0:WPP_ViewModelMask())|MASK_ENGINE);[m
[31m-[m
     PM_SetupRender();[m
 [m
[32m+[m[32m    addentities((intermission?0:WPP_ViewModelMask())|MASK_ENGINE);[m
[32m+[m
     renderscene();[m
 [m
     ScreenSize = [width, height, menushown];[m
[1mdiff --git a/csqc/pmove.qc b/csqc/pmove.qc[m
[1mindex ec2d04e0..2954145f 100644[m
[1m--- a/csqc/pmove.qc[m
[1m+++ b/csqc/pmove.qc[m
[36m@@ -36,6 +36,8 @@[m [mfloat held_pm_flags;[m
 vector held_origin, held_velocity;[m
 [m
 void PM_StartUpdate() {[m
[32m+[m[32m    if (!PM_Enabled()) return;[m
[32m+[m
     self.movetype = MOVETYPE_WALK;[m
     held_origin = self.origin;[m
     held_velocity = self.velocity;[m
[36m@@ -45,6 +47,8 @@[m [mvoid PM_StartUpdate() {[m
 }[m
 [m
 void PM_EndUpdate() {[m
[32m+[m[32m    if (!PM_Enabled()) return;[m
[32m+[m
     pm_org = self.origin;[m
     pm_vel = self.velocity;[m
     pm_flags = self.flags;[m
[36m@@ -76,8 +80,11 @@[m [mvoid PM_EndUpdate() {[m
 }[m
 [m
 void PM_Frame() {[m
[32m+[m[32m    if (!PM_Enabled()) return;[m
[32m+[m
     float etime = time + pstate_pred.client_time - pstate_server.client_time;[m
[32m+[m[32m    /* printf("PM_Frame\n"); */[m
     /* self.velocity += Phys_GetAdj(0, edict_num(player_localentnum), self.origin, */[m
     /*         etime, input_timelength); */[m
[31m-    /* runstandardplayerphysics(self); */[m
[32m+[m[32m    runstandardplayerphysics(self);[m
 }[m
[1mdiff --git a/csqc/weapon_predict.qc b/csqc/weapon_predict.qc[m
[1mindex 75e04ccd..88dd4a24 100644[m
[1m--- a/csqc/weapon_predict.qc[m
[1m+++ b/csqc/weapon_predict.qc[m
[36m@@ -1349,7 +1349,7 @@[m [mvoid InitWeapPredEnt(entity pe) {[m
     self.renderflags = RF_VIEWMODEL;[m
 [m
     pengine.pweap_ent = pe;[m
[31m-    setsize(pe, '-16 -16 -24', '16 16 32');[m
[32m+[m[32m    /* setsize(pe, '-16 -16 -24', '16 16 32'); */[m
 }[m
 [m
 [m
