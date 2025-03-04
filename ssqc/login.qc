float TFL_IsLoggedIn() {
    return self.tfl_id != "";
}

void TFL_SendLogin() {
    static const float kMaxTries = 3;

    if (!self.tfl_need_login)
        return;

    if (self.tfl_num_login_tries >= kMaxTries) {
        self.tfl_need_login = FALSE;
        return;
    }

    if (time < self.tfl_next_login_try)
        return;

    self.tfl_num_login_tries++;
    self.tfl_next_login_try = time + 2;

    WEB_MigrateLoginRequest(self);
}

static void TFL_StartTryMigrate(string fo_login, string fo_token) {
    self.tfl_need_login = TRUE;
    self.tfl_num_login_tries = 0;

    self.old_fo_login = fo_login;
    self.old_fo_token = fo_token;

    TFL_SendLogin();
}

static string MakeLoginCookie(string username, string id, string foid) {
    string dig = digest_hex("SHA1", LOGIN_SALT, username, id, foid);
    return substring(dig, 0, 10);
}

void TFL_TestLogin(string token) {
    printf("VERIFY: %s\n", token);
    tokenizebyseparator(token, ":");
    string username = argv(0);
    string id = argv(1);
    string foid = argv(2);
    string dig = argv(3);
    printf("UN: %s ID: %s FOID: %s DIG: %s\n", username, id, foid, dig);

    if (strlen(dig) != 10) {
        printf("Digest wrong length\n");
        return;
    } else {
        string cookie = MakeLoginCookie(username, id, foid);
        printf("DIG: %s COOKIE: %s MATCH: %d\n", dig, cookie, (dig == cookie));
        return;
    }
}

static float TFL_ValidateLogin(string token, float flags = 0) {
    tokenizebyseparator(token, ":");
    string username = argv(0);
    string id = argv(1);
    string foid = argv(2);
    string dig = argv(3);

    if (flags & kCheckLoginDbg) dprint(sprintf(" VAL: %s = %s/%s/%s [%s]\n",
                token, id, foid, dig, MakeLoginCookie(username, id, foid)));

    if (strlen(dig) != 10 || dig != MakeLoginCookie(username, id, foid))
        return FALSE;

    if (flags & kCheckLoginDbg) dprint(sprintf(" VAL SUCCESS: %s\n", token));

    self.tfl_username = username;
    self.tfl_id = id;
    self.tfl_foid = foid;
    self.tfl_raw_token = token;  // Checked on LOGIN_REQUEST response

    forceinfokey(self,"*tfl_token", token);

    switch (username) {
        case "newby":
        case "rev6thecarn":
        case "basic6371":
        case "bone":
            forceinfokey(self, "tdat" , "1");
            self.is_dat = 1;
    }


    return TRUE;
}

void TFL_AutoTeam();

float TFL_CheckLogin(string token, float flags = 0) {
    float is_web_check = flags & kCheckLoginFromWeb;
    if (TFL_IsLoggedIn() && !is_web_check)
        return TRUE;

    if (flags & kCheckLoginDbg) dprint(sprintf("CHECKLOGIN 1: %s\n", token));
    if (token == string_null)
        token = infokey(self, "*tfl_token");
    if (flags & kCheckLoginDbg) dprint(sprintf("CHECKLOGIN 2: %s\n", token));

    if (token != string_null && TFL_ValidateLogin(token, flags)) {
        if (flags & kCheckLoginDbg) dprint(sprintf("CHECKLOGIN PASS: %s\n", token));
        if (!is_web_check)
            WEB_CheckLoginRequest(self, token);
        TFL_AutoTeam();
        return TRUE;
    } else {
        if (flags & kCheckLoginDbg) dprint(sprintf("CHECKLOGIN FAIL: %s\n", token));
        if (flags & kCheckLoginFromWeb == 0)
        forceinfokey(self, "*tfl_token", "");
        return FALSE;
    }
}

void TFL_MigrateLoginStart(string fo_token = "") {
    if (fo_token == string_null)
        fo_token = infokey(self, "_fo_token");

    string fo_login = infokey(self, "_qwtfl_login");
    TFL_StartTryMigrate(fo_login, fo_token);
}

void TFL_ClearLogin(entity player) {
    player.tfl_id = 0;
    player.tfl_foid = 0;
    player.tfl_username = 0;
    player.tfl_raw_token = "";
    forceinfokey(player,"*tfl_token", "");
}
