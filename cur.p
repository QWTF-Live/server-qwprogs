diff --git a/csqc/pmove.qc b/csqc/pmove.qc
index be11965b7..2cf6bffb9 100644
--- a/csqc/pmove.qc
+++ b/csqc/pmove.qc
@@ -3,6 +3,7 @@ DEFCVAR_FLOAT(fo_jumpvolume, 1);
 static float pm_enabled;
 inline float PM_Enabled() { return pm_enabled; }
 
+#define ERRORTIME 0.05
 #define STEPTIME 0.125
 
 enumflags {
@@ -16,16 +17,15 @@ enumflags {
 // constant for this frame.
 struct PMS_Data {
     vector org, vel;
-    float seq, server_seq;
+    float seq;
     float interp_t;
 } pm_s, pm_so, pm_c;
 
-struct {
+struct PMS_State {
     entity ent;
     float last_vel_z;
     PMS_Data* active_pmsd;
 
-
     float seq, server_seq;
     float interp_t;
 
@@ -35,7 +35,9 @@ struct {
     float step, steptime, step_oldz;
 
     vector vieworg;
-} pm;
+};
+
+static PMS_State pm;
 
 vector PM_Org() { return PM_Enabled() ? pm.ent.origin : pmove_org; }
 vector PM_Vel() { return PM_Enabled() ? pm.ent.velocity : pmove_vel; }
@@ -159,9 +161,7 @@ void PM_PredictJump_Engine() {
 enum {
     SERVER,
     PMOVE,
-    ERROR_POS,
-    ERROR_VEL,
-    ERROR_VIEW,
+    ERROR,
     NUM_DBG_GRAPH_TYPES,
 };
 
@@ -172,6 +172,7 @@ DEFCVAR_FLOAT(fopm_nocache, 0);
 DEFCVAR_FLOAT(fopm_nostep, 0);
 DEFCVAR_FLOAT(fopm_nonudge, 0);
 DEFCVAR_FLOAT(fopm_errortime, 0);
+DEFCVAR_FLOAT(fopm_debug, 0);
 
 DEFCVAR_FLOAT(fopmd_graph_x, -10);
 DEFCVAR_FLOAT(fopmd_graph_y, 100);
@@ -181,33 +182,11 @@ DEFCVAR_FLOAT(fopmd_graph_h, 100);
 DEFCVAR_FLOAT(v_viewheight, 0);
 
 enumflags {
-    PMDG_ON,              //  1 for laziness..
-    PMDG_NO_ALIGN_INTERP, //  2
-    PMDG_ERROR_VEL,       //  4
-    PMDG_ERROR_POS,       //  8
-    PMDG_ERROR_VIEW,      // 16
+    PMDG_ON,
+    PMDG_NO_ALIGN_INTERP,
 };
 DEFCVAR_FLOAT(fopmd_graph, 0);
 
-static const float NHIST = 21;
-struct PM_History {
-    vector org, vel;
-    vector seq;
-};
-static PM_History hist[NHIST];
-
-void PMH_Log(float seq) {
-    PM_History* pmh = &hist[seq % NHIST];
-    pmh->org = PM_Org();
-    pmh->vel = PM_Vel();
-    pmh->seq = seq;
-}
-
-PM_History* PMH_Get(float seq) {
-    PM_History* pmh = &hist[seq % NHIST];
-    return pmh->seq == seq ? pmh : 0;
-}
-
 void PM_Init() {
     pm.ent = spawn();
     pm.ent.solid = SOLID_NOT;
@@ -216,48 +195,82 @@ void PM_Init() {
 
 // Should be invoked immediately after RunMovement() to ensure correctness of
 // `seq` versus state.  On server packets we manually set `seq` to sf + 1.
-static void PM_SavePMS(PMS_Data *pmsd) {
+static inline void PM_SavePMS(PMS_Data *pms) {
     entity ent = pm.ent;
-    pmsd->org = ent.origin;
-    pmsd->vel = ent.velocity;
+    pms->org = ent.origin;
+    pms->vel = ent.velocity;
 
-    pmsd->seq = pm.seq;
-    pmsd->server_seq = pm.server_seq;
-    pmsd->interp_t = pm.interp_t;
+    pms->seq = pm.seq;
+    pms->interp_t = pm.interp_t;
 }
 
-static void PM_ActivatePMS(PMS_Data *pmsd) {
+static inline void PM_ActivatePMS(PMS_Data *pms) {
     entity ent = pm.ent;
-    ent.origin = pmsd->org;
-    ent.velocity = pmsd->vel;
-
-    pm.seq = pmsd->seq;
-    pm.server_seq = pmsd->server_seq;
-    pm.interp_t = pmsd->interp_t;
-    pm.active_pmsd = pmsd;
-
-    pm.ent.pmove_flags = 0;  // With auto-bunny we only care about clearing
+    ent.origin = pms->org;
+    ent.velocity = pms->vel;
+    pm.seq = pms->seq;
+    pm.interp_t = pms->interp_t;
 };
 
-static PMS_Data* SimPMSD() {
-    return CVARF(fopm_nocache) ? &pm_s : &pm_c;
-}
-
 void PM_InputFrame();
 
 enum {
     NT_CONC,
     NT_DASH,
+    NT_EXPLOSION,
 };
 
 struct PM_Nudge {
-    float itime, type;
-    vector nudge;
+    entity src;
+    float src_no;
+
+    float seq, itime, type;
+    vector vecx;
+    float aux;
+    float start_frame, expire_frame;
 };
 
+MLog srv, oldc;
+MLog* mlog;
+
 static PM_Nudge nudges[10];
 static float num_nudges;
 
+static PM_Nudge* find_nudge_slot() {
+    for (float i = 0; i < nudges.length; i++) {
+        PM_Nudge* n = &nudges[(num_nudges++) % nudges.length];
+        if (n->itime < pm_s.interp_t - SERVER_FRAME_DT * 2) {
+            n->seq = 0;
+            n->itime = 0;
+            n->expire_frame = 0;
+            return n;
+        }
+    }
+
+    if (CVARF(fopm_debug))
+        printf("ERROR: no nudge slots!\n");
+    return 0;
+}
+
+static void PM_RemoveNudges(entity ent, float entno, float rem_seq) {
+    /* ASSERTF_EQ(rem_seq, servercommandframe); */
+    for (float i = 0; i < nudges.length; i++) {
+        PM_Nudge* n = &nudges[i];
+        if (n->itime && !n->expire_frame &&
+            ((entno && n->src_no == entno) || (!entno && n->src == ent))) {
+            printf("[%0.3f/%d] REMOVED %d REM_SEQ=%d [%0.3f, %0.3f)\n", time,
+                    servercommandframe,
+                    rem_seq, entno ?: ent.entnum,
+                    pstate_server.server_time, pstate_server.server_time + 0.12);
+            n->expire_frame = rem_seq;
+        }
+    }
+}
+
+static void PM_RemoveSelfNudges() {
+    PM_RemoveNudges(self, 0, -1); //servercommandframe);
+}
+
 void PM_AddConcNudge(float itime, float mag, float flip) {
     // This is kind of painful but not much easier..
     static float filter_itime;
@@ -265,38 +278,151 @@ void PM_AddConcNudge(float itime, float mag, float flip) {
         return;
     filter_itime = itime;
 
-    PM_Nudge* n = &nudges[(num_nudges++) % nudges.length];
+    PM_Nudge* n = find_nudge_slot();
+    if (!n)
+        return;
 
     n->type = NT_CONC;
     n->itime = itime;
-    n->nudge.x = mag;
-    n->nudge.y = flip;
+    n->vecx.x = mag;
+    n->vecx.y = flip;
 }
 
 static void PM_NudgeConc(PM_Nudge* nudge, entity ent) {
     if (pointcontents(ent.origin) == CONTENT_WATER)
         ent.flags |= FL_INWATER;  // pmove doesn't usually maintain this.
-    Conc_Stumble(ent, nudge->nudge.x, nudge->nudge.y);
+    Conc_Stumble(ent, nudge->vecx.x, nudge->vecx.y);
 }
 
 static void PM_NudgeDash(PM_Nudge* nudge, entity ent) {
-    ent.velocity = nudge->nudge;
+    ent.velocity = nudge->vecx;
 }
 
 void PM_AddDashNudge(float itime) {
-    PM_Nudge* n = &nudges[(num_nudges++) % nudges.length];
+    PM_Nudge* n = find_nudge_slot();
+    if (!n)
+        return;
     n->type = NT_DASH;
     n->itime = itime;
 
-    n->nudge = v_forward * 540;
-    n->nudge.z = 181 + SERVER_FRAME_DT * 800;  // TODO: fix this...
+    n->vecx = v_forward * 540;
+    n->vecx.z = 181 + SERVER_FRAME_DT * 800;  // TODO: fix this...
+}
+
+static vector PM_NudgeExplosion(PM_Nudge* nudge, entity ent) {
+    float dmg = nudge->aux;
+    if (vlen(ent.origin - nudge->vecx) > dmg + 40)
+        return '0 0 0';
+
+    float is_self = TRUE;
+    float fl = KF_SELF | KF_BOTH_PLAYER;
+
+    float moment = CalcKnockPoints(nudge->src, ent, fl, 92);
+    vector knock = CalcKnock(nudge->src, ent, fl, moment);
+
+    ML_tag(mlog, 0, sprintf("NT_EXP(%d,%d) m=%d", 
+                nudge->src_no, nudge->expire_frame, moment));
+
+    return knock;
+}
+
+// Can be either by {seq + itime} for predicted projectiles, or by {itime} for
+// server projectiles.
+void PM_AddExplosionNudge(float seq, float itime, entity ent, float dmg) {
+    if (vlen(PM_Org() - ent.origin) > dmg * 3)  // Fine tune this..
+        return;
+
+    PM_Nudge* n = find_nudge_slot();
+    if (!n)
+        return;
+
+    vector org = ent.origin; //(ent.absmin + ent.absmax) * 0.5
+
+    n->type = NT_EXPLOSION;
+    n->seq = seq;
+    n->itime = itime;
+    n->vecx = org;
+    n->aux = dmg;
+
+    n->src = ent;
+    n->src_no = ent.entnum;
+    n->start_frame = ent.created_seq;
+    ent.removefunc = PM_RemoveSelfNudges;
+}
+
 // TODO: This obviously wants to be smarter
-static void PM_ApplyNudges(entity ent, float sitime, float eitime) {
+static vector PM_ApplyNudges(entity ent, float seq, float sitime, float eitime) {
+    vector result = '0 0 0';
     for (float i = 0; i < nudges.length; i++) {
         PM_Nudge* n = &nudges[i];
-        if (n->itime >= sitime && n->itime < eitime) {
+
+
+        // Addressing is either {seq}, {seq + itime} --> seq, or {itime}
+        float nseq = n->seq, itime = n->itime;
+        if (nseq && itime)
+            nseq += floor(itime / SERVER_FRAME_DT);
+
+        if (n->expire_frame)
+            nseq = n->expire_frame;
+
+        ASSERTF_GT(seq, 0);
+
+        if (nseq == seq || (!nseq && itime >= sitime && itime < eitime)) {
+
+        // Nudge expires due to inclusion in #expire_frame
+        // Predictions which start after this should exclude it.
+        if (n->expire_frame == -1 ||
+           (n->expire_frame > 0 && pm.server_seq >= n->expire_frame)) {
+            ML_addflag(mlog, "e");
+            continue;
+        }
+
+#if 0
+        // Exclude nudges which originated after this simulation was started.
+        if (n->start_frame && n->start_frame >= pm.start_seq) {
+            ML_addflag(mlog, "s");
+            continue;
+        }
+#endif
             switch (n->type) {
                 case NT_CONC:
                     PM_NudgeConc(n, ent);
@@ -304,26 +430,41 @@ static void PM_ApplyNudges(entity ent, float sitime, float eitime) {
                 case NT_DASH:
                     PM_NudgeDash(n, ent);
                     break;
             }
         }
     }
+
+    return result;
 }
 
 static void RunPlayerPhysics() {
     entity ent = pm.ent;
-
     pm.last_vel_z = ent.velocity_z;
     runstandardplayerphysics(ent);
 }
 
-static void PM_RunMovement(PMS_Data* pmsd, float endframe) {
+static void PM_RunMovement(float endframe) {
     entity ent = pm.ent;
+    if (servercommandframe >= pm_s.seq + 63) {
+        // We're meant to be updating the player faster than this
+        // hopefully its just that we're throttled...
+        // Uncommenting this block will result in the player continuing to be
+        // predicted rather than frozen.
+        pm_s.seq = servercommandframe - 63;
+        return;
+    }
 
-    if (pm.active_pmsd != pmsd || endframe < pm.seq) {
-        ASSERTF_GT(endframe, pm.server_seq);
-        PM_ActivatePMS(pmsd);
+    if (endframe < pm.seq) {
+        if (endframe >= pm_c.seq && !CVARF(fopm_nocache))
+            PM_ActivatePMS(&pm_c);
+        else
+            PM_ActivatePMS(&pm_s);
     }
 
+
     if (!game_state.is_spectator && !game_state.is_alive) {
         pm.seq = clientcommandframe;
         //just update the angles
@@ -331,10 +472,13 @@ static void PM_RunMovement(PMS_Data* pmsd, float endframe) {
         return;
     }
 
+    ML_reset(mlog);
+    pm.ent.pmove_flags = 0;  // With auto-bunny we only care about clearing
     while (pm.seq <= endframe) {
         if (!getinputstate(pm.seq))
             break;
 
+        ML_start(mlog, pm.interp_t, pm.seq, pm.ent.origin, pm.ent.velocity);
         // We have to apply this on the leading edge since INPUT_FRAME
         // modifications do not occur until the frame is finalized.
         if (pm.seq == clientcommandframe)
@@ -342,15 +486,27 @@ static void PM_RunMovement(PMS_Data* pmsd, float endframe) {
 
         RunPlayerPhysics();
 
+        vector nudge = '0 0 0';
         if (!CVARF(fopm_nonudge) && pm.seq < clientcommandframe)
-            PM_ApplyNudges(ent, pm.interp_t, pm.interp_t + input_timelength);
+            nudge = PM_ApplyNudges(ent, pm.seq,
+                                   pm.interp_t, pm.interp_t + input_timelength);
+        ent.velocity += nudge;
+
+
+        if (input_buttons & BUTTON2)
+            ML_addflag(mlog, "J");
+        if (ent.pmove_flags & PMF_JUMP_HELD)
+            ML_addflag(mlog, "!");
+
+        runstandardplayerphysics(ent);
 
         pm.seq++;
         pm.interp_t += input_timelength;
+        ML_end(mlog, pm.interp_t, pm.ent.origin, pm.ent.velocity);
     }
 
-    // Add in anything that was applied after (for low packet rate protocols)
-    input_angles = view_angles;
+    if (endframe == clientcommandframe)
+        input_angles = view_angles;
 }
 
 static void PM_SetEnabled(float enabled) {
@@ -375,6 +531,15 @@ static float ErrorTime() {
     return min(CVARF(fopm_errortime), kMax);
 }
 
+void MLDump(string desc) {
+    float gap = max(clientcommandframe - servercommandframe + 1, 10);
+    printf("  **********************************\n");
+    ML_print(0, desc, gap);
+    ML_print(&oldc, sprintf("Prev Predict [%d/%d]", pm_so.seq, pm_so.server_seq), 10);
+    ML_print(&srv, sprintf("Received Server Frames [%d]", servercommandframe), 10);
+    printf("  **********************************\n");
+}
+
 static void PM_UpdateError() {
     entity ent = pm.ent;
 
@@ -385,25 +550,39 @@ static void PM_UpdateError() {
         return;
     }
 
+    vector old_vel;
+
+    mlog = &oldc;
     // Run prior prediction to present.
-    PM_RunMovement(&pm_so, clientcommandframe);
+    PM_ActivatePMS(&pm_so);
+    PM_RunMovement(clientcommandframe);
     vector err = ent.origin;
+    vector old_vel = ent.velocity;
+    mlog = 0;
 
     // Repeat with updated state.
-    PM_RunMovement(&pm_s, clientcommandframe);
+    PM_ActivatePMS(&pm_s);
+    PM_RunMovement(clientcommandframe);
+
+    if (pm_s.server_seq == pm_c.server_seq)
+        return;
 
+    ASSERTF_GT(pm_s.server_seq, pm_c.server_seq);
+    /* printf("Compute %d/%d/%d -> %d/%d/%d\n", */
+    /*         pm_c.server_seq, pm_c.seq, old_seq, pm_s.server_seq, pm_s.seq, new_seq); */
     err -= ent.origin;
     float nerr = vlen(err);
-    if (nerr > 128) {  // teleport
+    if (0 && nerr > 128) {  // teleport
         pm.error = '0 0 0';
         pm.errortime = 0;
+        printf("TELE\n");
     } else { // figure out the error amount, and add it to accumulated lerp
-        pm.error *= max(pm.errortime - time, 0) / ErrorTime();
+        pm.error *= max(pm.errortime - time, 0) / ERRORTIME;
         pm.error += err;
 
-        if (vlen(pm.error) > 1)
+        if (vlen(pm.error) > 1) {
             pm.errortime = time + ErrorTime();
-        else {
+        } else {
             pm.error = '0 0 0';
             pm.errortime = 0;
         }
@@ -413,9 +592,10 @@ static void PM_UpdateError() {
 static void PM_UpdateLocalMovement() {
     entity ent = pm.ent;
 
-    PM_RunMovement(SimPMSD(), clientcommandframe);
+    PM_RunMovement(clientcommandframe);
     vector org = pm.ent.origin;
 
+
     // Smooth stair stepping
     if (org_z > pm.step_oldz + 8 && org_z < pm.step_oldz + 24 &&
         ent.velocity_z == 0) { // Evaluate out the remaining old step
@@ -439,9 +619,9 @@ static void PM_UpdateLocalMovement() {
     pm.vieworg = org;
     pm.vieworg.z += getstatf(STAT_VIEWHEIGHT) + viewheight;
 
-    // Correct view position over ErrorTime()
+    // Correct view position over ERRORTIME
     if (pm.errortime - time > 0)
-        pm.vieworg += (pm.errortime - time) * (1 / ErrorTime()) * pm.error;
+        pm.vieworg += (pm.errortime - time) * (1 / ERRORTIME) * pm.error;
 
     if (!CVARF(fopm_nostep))
         if (pm.steptime - time > 0)
@@ -455,14 +635,31 @@ void PM_SyncTo(float seq) {
         return;
 
     entity ent = pm.ent;
-    PM_RunMovement(SimPMSD(), seq);
+
+    PM_RunMovement(seq - 1);
+    float of = ent.flags;
+    float last_vel_z = ent.velocity_z;
+
+    PM_RunMovement(seq);
+    float nf = ent.flags;
+
+    if (!CSQC_JumpSounds_Active())
+        return;
 
     // Note: ~FL_ONGROUND and jump occur in same frame, produces JUMP_HELD
     float jumping = input_buttons & BUTTON2;
-    float landing = pm.last_vel_z < 0 && (ent.flags & FL_ONGROUND);
+    float landing = (!(of & FL_ONGROUND) && (nf & FL_ONGROUND));
     float jump_frame = ent.pmove_flags & PMF_JUMP_HELD;
 
-    PM_Sounds(jumping, jump_frame, landing, pm.last_vel_z);
+    PM_Sounds(jumping, jump_frame, landing, last_vel_z);
+}
+
+static void PM_HandleRemovedNudges() {
+    if (!pstate_server.num_filter_ents)
+        return;
+
+    for (float i = 0; i < pstate_server.num_filter_ents; i++)
+        PM_RemoveNudges(0, pstate_server.filter_ents[i], pstate_server.seq - 1);
 }
 
 void PM_Update(float sendflags) {
@@ -476,25 +673,24 @@ void PM_Update(float sendflags) {
     if (sendflags & FOWP_PMOVE == 0)
         return;
 
+    PM_HandleRemovedNudges();
+
+    ML_inc(&srv, pstate_server.server_time, servercommandframe + 1,
+          pm.ent.origin, pm.ent.velocity);
+
     pm_so = pm_s;
-    pm.server_seq = servercommandframe;
     pm.seq = servercommandframe + 1;  // server state includes move
     pm.interp_t = pstate_server.server_time;
     PM_SavePMS(&pm_s);
 
-    if (!CVARF(fopm_nocache)) {
-        // Pre-compute predicted movement for all locked frames (e.g. seq <
-        // clientcommandframe) so that we can accelerate the common case of
-        // computation at clientcommandframe (which does require constant
-        // re-evaluation).  In the case there's no separation (e.g. lan pings) then
-        // the server frame is directly used as the cache frame.
-        if (clientcommandframe > servercommandframe + 1)
-            PM_RunMovement(&pm_s, clientcommandframe - 1);
-        PM_SavePMS(&pm_c);
-    }
-
-    if (enabled && was_enabled)
-        PM_UpdateError();
+    // Pre-compute predicted movement for all locked frames (e.g. seq <
+    // clientcommandframe) so that we can accelerate the common case of
+    // computation at clientcommandframe (which does require constant
+    // re-evaluation).  In the case there's no separation (e.g. lan pings) then
+    // the server frame is directly used as the cache frame.
+    if (clientcommandframe > servercommandframe + 1)
+        PM_RunMovement(clientcommandframe - 1);
+    PM_SavePMS(&pm_c);
 
     PMD_UpdateImpulse(servercommandframe);
 }
@@ -509,7 +705,7 @@ void PM_Refresh() {
         ent.movetype = MOVETYPE_WALK;
         ent.solid = SOLID_SLIDEBOX;
     } else {
-        ent.owner = 0;  // Needs more than this for spec..
+        ent.owner = world;  // Needs more than this for spec..
         ent.movetype = MOVETYPE_NOCLIP;
         ent.solid = SOLID_NOT;
     }
@@ -629,11 +825,8 @@ static void PMD_UpdateImpulse(int seq) {
         return;
     old_seq = seq;
 
-    float cseq = clientcommandframe - 1;
     if (PM_Enabled())
-        PM_RunMovement(SimPMSD(), cseq);
-
-    PMH_Log(cseq);
+        PM_RunMovement(clientcommandframe);
 
     vector sv = pm_s.vel;
     vector pv = PM_Vel();
@@ -647,26 +840,25 @@ static void PMD_UpdateImpulse(int seq) {
     PMD_AddPoint(ERROR_VIEW, vlen(pm.error) / 128 * 1200);
 
     PM_History* hist = PMH_Get(servercommandframe);
+    if (!hist)
+        return;
+
     PMD_AddPoint(ERROR_POS, hist ? vlen(pm_s.org - hist.org) : 0);
     PMD_AddPoint(ERROR_VEL, hist ? vlen(pm_s.vel - hist.vel) : 0);
 
-#if 0
-    static vector last_sv, last_pv;
-    float p = FALSE;
-    if (vlen(sv - last_sv) > 200) {
-        printf("[%0.3f] S sf=%d st=%0.3f i=%0.3f\n", time, servercommandframe, pm_s.interp_t, vlen(sv-last_sv));
-        p = TRUE;
+    vector err = pm_s.vel - hist.vel;
+    if (vlen(err) > 64) {
+        printf("[%v] [%v] [%v]\n", err, pm_s.vel, hist.vel);
+        string desc = sprintf("Cur [%d/%d] err=%0.2f sf=%d cf=%d",
+                pm.seq, pm.server_seq, vlen(err),
+                servercommandframe, clientcommandframe);
+        MLDump(desc);
     }
-    last_sv = sv;
 
-    if (vlen(pv - last_pv) > 200) {
-        printf("[%0.3f] C cf=%d ct=%0.3f i=%0.3f\n", time, clientcommandframe, 
-                pm.interp_t, vlen(pv-last_pv));
-        p = TRUE;
-    }
-    last_pv = pv;
-    if (p) printf("\n");
-#endif
+
+    PMD_AddPoint(SERVER, vlen(sv));
+    PMD_AddPoint(PMOVE,  vlen(pv));
+    PMD_AddPoint(ERROR, vlen(pm.error) / 128 * 1200);
 }
 
 static void PMD_Graph(int type, int offset, vector c1, vector c2, vector rgb) {
@@ -718,18 +910,11 @@ void PMD_DrawGraphs(float width) {
     drawfill(c2, '5 5 5', '1 0 0', 1);
 
     float offset = (CVARF(fopmd_graph) & PMDG_NO_ALIGN_INTERP) ? 0 :
-        clientcommandframe - servercommandframe - 1;
+        clientcommandframe - servercommandframe;
 
     offset = max(0, offset);
     PMD_Graph(PMOVE, 0, c1, c2, '0 0 1');
-    PMD_Graph(SERVER, offset, c1, c2, '0 1 0');
-
-    if ((CVARF(fopmd_graph) & PMDG_ERROR_VIEW) &&
-            (pstate_server.predict_flags & PF_PMOVE))
-        PMD_Graph(ERROR_VIEW, 0, c1, c2, '1 0 1');
-    if ((CVARF(fopmd_graph) & PMDG_ERROR_VEL))
-        PMD_Graph(ERROR_VEL, 0, c1, c2, '1 1 0');
-    if ((CVARF(fopmd_graph) & PMDG_ERROR_POS))
-        PMD_Graph(ERROR_POS, 0, c1, c2, '1 0 0');
-
+    PMD_Graph(SERVER, offset, c1, c2, '1 0 0');
+    if (pstate_server.predict_flags & PF_PMOVE)
+        PMD_Graph(ERROR, 0, c1, c2, '0 1 0');
 }
