CLEARSCREEN.
WAIT UNTIL SHIP:UNPACKED.
SWITCH TO 0.

RUNONCEPATH("0:/Falcon9_lib/params.ks").
RUNONCEPATH("0:/Falcon9_lib/f9utility.ks").
RUNONCEPATH("0:/Falcon9_lib/f9boostback.ks").
RUNONCEPATH("0:/Falcon9_lib/entryburn.ks").
RUNONCEPATH("0:/Falcon9_lib/f9landingburn.ks").

FUNCTION gof9d_main {
    SET CONFIG:IPU TO F9_PARAMS["kOSIPU"].
    IF NOT f9_validate_recovery_params(F9_PARAMS) {
        PRINT "F9 booster executive: invalid recovery configuration".
        RETURN FALSE.
    }
    IF NOT ADDONS:TR:AVAILABLE {
        PRINT "F9 booster executive: Trajectories is required".
        RETURN FALSE.
    }

    LOCAL targetContext IS f9_initialize_target(F9_PARAMS).
    IF NOT targetContext["ok"] {
        PRINT "F9 booster executive: recovery target is unavailable".
        RETURN FALSE.
    }
    f9_init_recovery_display(targetContext).

    IF NOT f9_boostback(F9_PARAMS, targetContext) {
        RETURN FALSE.
    }
    IF NOT f9_entry_burn(F9_PARAMS, targetContext) {
        RETURN FALSE.
    }
    IF NOT f9_landing_burn(F9_PARAMS, targetContext) {
        RETURN FALSE.
    }

    f9_print_result("Recovery complete").
    RETURN TRUE.
}

// set vecXTrue to vecDraw({return V(0,0,0).}, {return ship:facing:starvector * 50.}, RGB(0, 255, 0), "X", 1, true).
// set vecYTrue to vecDraw({return V(0,0,0).}, {return ship:facing:topvector * 50.}, RGB(0, 0, 255), "Y", 1, true).
// set vecZTrue to vecDraw({return V(0,0,0).}, {return ship:facing:forevector * 50.}, RGB(255, 0, 0), "Z", 1, true).
// if (steering:hassuffix("forvector")) {
//     set vecXRef to vecDraw({return V(0,0,0).}, {return steering:starvector * 50.}, RGB(0, 255, 0), "X", 1, true).
//     set vecYRef to vecDraw({return V(0,0,0).}, {return steering:topvector * 50.}, RGB(0, 0, 255), "Y", 1, true).
//     set vecZRef to vecDraw({return V(0,0,0).}, {return steering:forevector * 50.}, RGB(255, 0, 0), "Z", 1, true).
// }
gof9d_main().
