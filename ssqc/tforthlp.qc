//========================================================
// Functions handling all the help displaying for TeamFortress.
//========================================================
//

// so you can select a team (blindly) while reading the MOTD

void () TeamFortress_HelpMap = {
    local entity te;

    te = get_tfdet();
    if (te) {
        if (te.non_team_broadcast != string_null) {
            sprint(self, PRINT_HIGH, te.non_team_broadcast);
            return;
        }
    }
    sprint(self, PRINT_HIGH, "There is no help for this map\n");
};
