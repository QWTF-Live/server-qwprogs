void (entity player, string login, string secret) performLogin = {
    string data = strcat("login=", login);
    data = strcat(data,"&secret=");
    data = strcat(data,secret);	
    uri_get(loginUrl, BR_LOGIN_REQUEST, "application/x-www-form-urlencoded", data);
    self.login_in_progress = 1;
    dprint(infokey(self,"name"));
    dprint(" [");
    dprint(infokey(self,"ip"));
    dprint("]");
    dprint(" trying to login as ");
    dprint(login);
    dprint("\n");
}

static void MarkFoLogin(entity player, string login, int stored) {
    player.fo_login = login;
    forceinfokey(self,"*tfl_login", login);
    if (stored)
        forceinfokey(player, "*tfl_credential", "1");

    CenterPrint(player, sprintf("You have logged in as %s\n", player.fo_login));
    string msg = sprintf("%s logged in as %s%s\n",
            infokey(self, "name"), self.fo_login,
            stored ? " [using local credential]" : "");
    bprint(PRINT_HIGH, msg);
}

static string GenLoginNonce(entity player) {
    string login = infokey(player, kLoginKey);
    string fo_token = infokey(player, kFoToken);
    if (login == string_null || fo_token == string_null)
        return "INVALID";

    return digest_hex(kLoginHash, login_salt, login, fo_token);
}

static void StoreCred(entity player) {
    if (!login_allow_nonce || player.fo_login == string_null || player.credential_stored)
        return;

    if (infokey(player, "*tfl_credential") != string_null) {
        player.credential_stored = 1;
        return;
    }

    msg_entity = player;
    WriteByte(MSG_MULTICAST, SVC_CGAMEPACKET);
    WriteByte(MSG_MULTICAST, MSG_CACHE_LOGIN);
    WriteString(MSG_MULTICAST, player.fo_login);
    WriteString(MSG_MULTICAST, GenLoginNonce(player));
    multicast('0 0 0', MULTICAST_ONE_R_NOSPECS);

    player.credential_stored = 1;
}

static float LoadCred(entity player) {
    if (!login_allow_nonce)
        return FALSE;

    string login = infokey(player, kLoginKey);
    if (login == string_null)
        return FALSE;

    string nonce = infokey(player, kLoginNonce);
    string comp = GenLoginNonce(player);

    if (nonce == comp && comp != "INVALID") {
        MarkFoLogin(player, login, 1);
        return TRUE;
    } else {
        forceinfokey(player, kLoginKey, string_null);
        return FALSE;
    }
}

void FoLoginIfRequired(entity player) {
    if (!fo_login_required || player.credential_stored) {
        return;
    } else if (player.fo_login != string_null) {
        StoreCred(player);
        return;
    }

    static const float kMaxTries = 3;
    if (player.fo_num_login_tries >= kMaxTries || time < player.fo_next_login_try)
        return;

    if (LoadCred(player))
        return;

    string token = infokey(player, "_fo_token");
    if (token == string_null) {
        player.fo_num_login_tries = kMaxTries;
        return;
    }

    static float next_login;  // Rate limit
    if (time < next_login)
        return;

    next_login = time + 0.25;
    player.fo_num_login_tries++;
    player.fo_next_login_try = time + 2;

    string uri = sprintf("%s/results/api/v1/fo_login", backend_address);
    uri_get(uri, FO_LOGIN_REQUEST, "application/json",
            sprintf("{ \"auth_token\": \"%s\" }", token));
    dprint(sprintf("%s [%s] logging in -> %s\n", infokey(player, "name"), infokey(player, "ip"),
                uri));
}

void FoTryLogin(entity player) {
    player.fo_num_login_tries = 0;
}

void(float reqid, float responsecode, string resourcebody, int resourcebytes) URI_Get_Callback = {
    local float success = !responsecode;

    switch(reqid) {
        case TFL_ANNOUNCE:
            InitAnnounceResult(responsecode);
            break;
        case TFL_RESULT:
            break;

        case FO_QUAD_STARTED_REQUEST:
            local string msg;

            if (success && resourcebody) {
                match_id = resourcebody;
                msg = sprintf("Quad start successfully logged. ID: %s\n", match_id);
                bprint(PRINT_HIGH, msg);
                dprint(msg);
            } else {
                msg = sprintf("Quad start failed to log. Response code: %d\n", responsecode);
                bprint(PRINT_HIGH, msg);
                dprint(msg);
            }

            break;
        case FO_QUAD_FINISHED_REQUEST:
            local string msg;

            if (success && resourcebody == match_id) {
                msg = sprintf("Quad result successfully logged. ID: %s\n", match_id);
                bprint(PRINT_HIGH, msg);
                dprint(msg);
            } else {
                msg = sprintf("Quad result failed to log. Response code: %d\n", responsecode);
                bprint(PRINT_HIGH, msg);
                dprint(msg);
            }

            break;
        case FO_LOGIN_REQUEST:
            local string msg;

            if (!responsecode) {
                MarkFoLogin(self, resourcebody, 0);
                StoreCred(self);
            } else {
                CenterPrint(self, "Login failed\n");
                msg = (sprintf("%s login failed. Response code: %d\n", infokey(self, "name"), responsecode));
                sprint(self, PRINT_HIGH, msg);
                dprint(msg);
            }

            break;
        case BR_LOGIN_REQUEST:
            local float got_one = 0;
            self.login_in_progress = 0;	
            local float csqcactive = infokeyf(self, INFOKEY_P_CSQCACTIVE);
            if (!responsecode) {		
                float num_args = tokenizebyseparator(resourcebody,";");
                self.login = argv(0);
                forceinfokey(self,"*login", self.login);
                bprint(2, infokey(self,"name"));
                bprint(2, " has logged in as \s");
                bprint(2, self.login);
                bprint(2, "\s\n");
                dprint(infokey(self,"name"));
                dprint(" logged in as ");
                dprint(self.login);
                dprint("\n");
                CenterPrint3(self, "You have logged in as ", self.login, "\n");
                if (num_args > 1) {
                    if (argv(1) == "true") {
                        self.is_admin = TRUE;
                        forceinfokey(self,"*admin", ftos(self.is_admin));
                        Admin_Aliases ();
                        bprint(2, self.netname, " \sgains full admin status!\s\n");
                        //				bprint (3, "\n");
                        sprint(self, 2, "Type \scommands\s for admin commands.\n");
                    }
                }
                if(self.team_no == 0 && !intermission_running) {
                    if (clanbattle && (self.has_disconnected != 1)) {
                        if (self.tf_id != 0) {
                            got_one = RejoinWithTfId();
                            ResetAndRespawnPlayer(self);
                        }
                        if (!got_one) {
                            CreateTfIdAndJoin();
                        }
                    }
                    if (!got_one) {
                        if (csqcactive)
                            Menu_Team(0);
                        else
                            Menu_Team(1);
                    }
                }
            } else {
                dprint(infokey(self,"name"));
                dprint(" login failed: ");
                dprint(self.login);
                dprint("\n");
                CenterPrint3(self, ftos(responsecode), " - Login FAILED, invalid Login/Secret", "\n");
            }
            break;
    }
}
