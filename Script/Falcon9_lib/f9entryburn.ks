RUNONCEPATH("0:/Falcon9_lib/f9utility.ks").

FUNCTION f9_entry_burn {
    PARAMETER params.
    PARAMETER targetContext.

    IF NOT targetContext["ok"] {
        f9_print_result("ERROR: no valid landing target").
        RETURN FALSE.
    }

    f9_clear_guidance_display().
    pre_entryburn_hook().
    LOCAL entryEngines IS search_engine(params["entryEngineTag"]).
    IF entryEngines:LENGTH = 0 {
        f9_print_result("ERROR: no entry engines found").
        RETURN FALSE.
    }
    LOCAL engineInfo IS get_engines_info(entryEngines).
    IF engineInfo["thrust"] <= 0 {
        f9_print_result("ERROR: entry engines have no thrust").
        RETURN FALSE.
    }
    IF NOT f9_initialize_ltr(params) {
        RETURN FALSE.
    }
    LOCAL vecNormal IS f9_get_surface_normal().

    f9_print_at(11, "Phase: entry - coasting retrograde").
    f9_print_at(
        12,
        "Remaining velocity: waiting for burn trigger"
    ).
    f9_print_at(
        13,
        "Descent target: " + ROUND(params["entryVSpeed"], 1) + " m/s"
    ).
    f9_print_at(16, "Engines: armed  Throttle: 0.00").
    LOCAL steeringTarget IS "KILL".
    SAS OFF.
    LOCK STEERING TO steeringTarget.
    LOCK THROTTLE TO 0.
    RCS ON.

    UNTIL (SHIP:VERTICALSPEED < 0
        AND SHIP:ALTITUDE <= params["entryBurnAlt"]) {
        IF SHIP:verticalspeed >= 0 {
            SET steeringTarget TO f9_get_aero_steering(lookDirUp(vxcl(up:forevector, srfPrograde:forevector), srfPrograde:upvector)).
        }
        ELSE {
            SET steeringTarget TO f9_get_aero_steering(srfPrograde).
        }
        f9_print_recovery_vehicle().
        f9_print_at(
            13,
            "Speed: " + ROUND(MAX(0, -SHIP:VERTICALSPEED), 1)
                + " / " + ROUND(params["entryVSpeed"], 1) + " m/s"
        ).
        WAIT 0.
    }

    IF ship:airspeed <= params["entryVSpeed"] {
        f9_print_at(11, "Phase: entry - burn not required").
        f9_print_at(
            13,
            "Speed: " + ROUND(MAX(0, ship:airspeed), 1)
                + " / " + ROUND(params["entryVSpeed"], 1) + " m/s"
        ).
        UNLOCK THROTTLE.
        UNLOCK STEERING.
        RETURN TRUE.
    }

    LOCAL remainingVelocity IS (ship:airspeed - params["entryVSpeed"]) * srfRetrograde:forevector.
    LOCAL stepRes TO f9_step_entry_vgo(
        params,
        targetContext,
        remainingVelocity,
        vecNormal
    ).
    IF (NOT stepRes["ok"]) {
        f9_print_result("ERROR: " + stepRes["msg"]).
        UNLOCK THROTTLE.
        UNLOCK STEERING.
        RETURN FALSE.
    }
    SET remainingVelocity TO stepRes["vecVGO"].
    f9_print_target_position(targetContext).
    f9_print_recovery_vehicle().
    IF remainingVelocity:MAG < 0.001 {
        f9_print_at(11, "Phase: entry - no burn required").
        f9_print_at(12, "Remaining velocity: 0.0 m/s").
        LOCK throttle TO 0.
        UNLOCK STEERING.
        wait 0.
        UNLOCK THROTTLE.
        RETURN TRUE.
    }

    f9_print_at(11, "Phase: entry - aligning").
    SET steeringTarget TO f9_get_target_steering(
        remainingVelocity,
        engineInfo["TiS"],
        params["targetRoll"],
        vecNormal
    ).
    LOCAL alignmentError IS VANG(
        (SHIP:FACING * engineInfo["TiS"]:INVERSE):FOREVECTOR,
        remainingVelocity
    ).
    f9_print_at(
        12,
        "Remaining velocity: "
            + ROUND(remainingVelocity:MAG, 2) + " m/s"
    ).
    f9_print_at(14, "Alignment error: " + ROUND(alignmentError, 2) + " deg").
    UNTIL alignmentError <= params["burnAlignTolerance"] {
        SET stepRes TO f9_step_entry_vgo(
            params,
            targetContext,
            remainingVelocity,
            vecNormal
        ).
        IF (NOT stepRes["ok"]) {
            f9_print_result("ERROR: " + stepRes["msg"]).
            LOCK throttle TO 0.
            UNLOCK STEERING.
            wait 0.
            UNLOCK THROTTLE.
            RETURN FALSE.
        }
        SET remainingVelocity TO stepRes["vecVGO"].
        SET steeringTarget TO f9_get_target_steering(
            remainingVelocity,
            engineInfo["TiS"],
            params["targetRoll"],
            vecNormal
        ).
        SET alignmentError TO VANG(
            (SHIP:FACING * engineInfo["TiS"]:INVERSE):FOREVECTOR,
            remainingVelocity
        ).
        f9_print_target_position(targetContext).
        f9_print_recovery_vehicle().
        f9_print_at(
            12,
            "Remaining velocity: "
                + ROUND(remainingVelocity:MAG, 2) + " m/s"
        ).
        f9_print_at(
            13,
            "Speed: " + ROUND(ship:airspeed, 1)
                + " / " + ROUND(params["entryVSpeed"], 1) + " m/s"
        ).
        f9_print_at(
            14,
            "Alignment error: " + ROUND(alignmentError, 2) + " deg"
        ).
        WAIT 0.
    }

    f9_print_at(11, "Phase: entry - powered guidance").
    activate_engines(entryEngines).
    LOCK throttle to params["entryThrottle"].
    LOCAL predictionFailed IS FALSE.
    f9_print_at(16, "Engines: active").
    UNTIL SHIP:airspeed <= params["entryVSpeed"] {
        SET stepRes TO f9_step_entry_vgo(
            params,
            targetContext,
            remainingVelocity,
            vecNormal
        ).
        IF (NOT stepRes["ok"]) {
            f9_print_result("ERROR: " + stepRes["msg"]).
            LOCK throttle TO 0.
            UNLOCK STEERING.
            wait 0.
            UNLOCK THROTTLE.
            RETURN FALSE.
        }
        SET remainingVelocity TO stepRes["vecVGO"].
        // When VGO is less than 50m/s stop updating to prevent divergence
        IF remainingVelocity:MAG > 50 {
            SET steeringTarget TO f9_get_target_steering(
                remainingVelocity,
                engineInfo["TiS"],
                params["targetRoll"],
                vecNormal
            ).
        }
        f9_print_target_position(targetContext).
        f9_print_recovery_vehicle().
        f9_print_at(
            12,
            "Remaining velocity: "
                + ROUND(remainingVelocity:MAG, 2) + " m/s"
        ).
        f9_print_at(
            13,
            "Speed: " + ROUND(ship:airspeed, 1)
                + " / " + ROUND(params["entryVSpeed"], 1) + " m/s"
        ).
        f9_print_at(
            16,
            "Engines: active  Throttle: "
                + ROUND(SHIP:CONTROL:MAINTHROTTLE, 2)
        ).
        WAIT 0.
    }

    f9_print_at(11, "Phase: entry - cutoff").
    f9_print_at(16, "Engines: cutoff  Throttle: 0.00").
    LOCK THROTTLE TO 0.
    deactivate_engines(entryEngines).
    UNLOCK THROTTLE.
    UNLOCK STEERING.
    IF predictionFailed {
        f9_print_result("ERROR: LTR entry prediction failed").
        RETURN FALSE.
    }
    RETURN TRUE.
}
