
string WP_GetClip() {
    if (!WP_Enabled())
        return SBAR.ClipSize;

    Slot slot = CurrentSlot();
    FO_WeapInfo* wi = SlotWI(slot);

    if (!wi->needs_reload || IsSlotNull(slot))
        return "";

    float capacity = wi->clip_size;
    float still_loading = 0;
    float fired = *WP_ClipFired(slot);

    if (WP_IsReloading())
        still_loading = FO_NumClipStillLoading(wi, pstate_pred.client_time,
                                               pstate_pred.reload_finished);

    float clip = capacity - fired - still_loading;
    float rem = WP_GetAmmo(wi->ammo_type);

    // It's possible for the amount in clip to exceed remaining ammo (this
    // occurs because we load before we drop for example).  Render a clipped
    // clip when this occurs, with a little notification for those who care.
    if (clip > rem)
        return sprintf("* %d/%d", rem, wi->clip_size);
    else
        return sprintf("%d/%d", clip, wi->clip_size);
}
HUDP_OPTIONS,
    HUDP_CLIPSIZE,
    HUDP_FRAGSTREAK,
    HUDP_CAPS,
    HUDP_GREN1,
    HUDP_GREN2,
    HUDP_SPECIAL,
    HUDP_IDENTIFY,
    HUDP_FLAGINFO,
    HUDP_GRENTIMER,
    HUDP_MENU,
    HUDP_MOTD,
    HUDP_MENU_HINT,
    HUDP_GAME_MODE,
    HUDP_READY,
    HUDP_SHOWSCORES,
    HUDP_TEAMSCORE,
    HUDP_MAP_MENU,
    HUDP_HEALTH,
    HUDP_FACE,
    HUDP_AMMO,
    HUDP_AMMOICON,
    HUDP_ARMOUR,
    HUDP_ARMOURICON,
    HUDP_INVSHELLS,
    HUDP_INVNAILS,
    HUDP_INVROCKETS,
    HUDP_INVCELLS,
    HUDP_GAMECLOCK,
    HUDP_QUAD,
    HUDP_PENT,
    HUDP_RING,
    HUDP_SUIT,
    HUDP_KEY1,
    HUDP_KEY2,
    HUDP_RUNE1,
    HUDP_RUNE2,
    HUDP_RUNE3,
    HUDP_RUNE4,
    HUDP_GUN2,
    HUDP_GUN3,
    HUDP_GUN4,
    HUDP_GUN5,
    HUDP_GUN6,
    HUDP_GUN7,
    HUDP_GUN8,
    HUDP_SPEED,
    HUDP_COUNT,

