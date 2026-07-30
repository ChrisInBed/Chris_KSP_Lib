RUNONCEPATH("0:/Falcon9_lib/params.ks").
RUNONCEPATH("0:/Falcon9_lib/f9utility.ks").

FUNCTION f9_entry_burn {
    PARAMETER params.
    PARAMETER targetContext.

    IF NOT targetContext["ok"] {
        f9_print_result("ERROR: no valid landing target").
        RETURN FALSE.
    }

    f9_clear_guidance_display().
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
    LOCAL steeringTarget IS f9_get_target_steering(
        SRFRETROGRADE:FOREVECTOR,
        engineInfo["TiS"],
        params["targetRoll"]
    ).
    SAS OFF.
    LOCK STEERING TO steeringTarget.
    LOCK THROTTLE TO 0.
    RCS ON.

    UNTIL (SHIP:VERTICALSPEED < 0
        AND SHIP:ALTITUDE <= params["entryBurnAlt"]) {
        SET steeringTarget TO f9_get_target_steering(
            SRFRETROGRADE:FOREVECTOR,
            engineInfo["TiS"],
            params["targetRoll"]
        ).
        f9_print_recovery_vehicle().
        f9_print_at(
            13,
            "Descent: " + ROUND(MAX(0, -SHIP:VERTICALSPEED), 1)
                + " / " + ROUND(params["entryVSpeed"], 1) + " m/s"
        ).
        WAIT 0.
    }

    IF -SHIP:VERTICALSPEED <= params["entryVSpeed"] {
        f9_print_at(11, "Phase: entry - burn not required").
        f9_print_at(
            13,
            "Descent: " + ROUND(MAX(0, -SHIP:VERTICALSPEED), 1)
                + " / " + ROUND(params["entryVSpeed"], 1) + " m/s"
        ).
        UNLOCK THROTTLE.
        UNLOCK STEERING.
        RETURN TRUE.
    }

    f9_refresh_target(targetContext).
    LOCAL targetPosition IS f9_get_target_position(targetContext).
    LOCAL remainingVelocity IS f9_get_entry_vgo(
        targetPosition,
        params["entryVSpeed"]
    ).
    f9_print_target_position(targetContext).
    f9_print_recovery_vehicle().
    IF remainingVelocity:MAG < 0.001 {
        f9_print_at(11, "Phase: entry - no burn required").
        f9_print_at(12, "Remaining velocity: 0.0 m/s").
        UNLOCK THROTTLE.
        UNLOCK STEERING.
        RETURN TRUE.
    }

    f9_print_at(11, "Phase: entry - aligning").
    SET steeringTarget TO f9_get_target_steering(
        remainingVelocity,
        engineInfo["TiS"],
        params["targetRoll"]
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
        f9_refresh_target(targetContext).
        SET targetPosition TO f9_get_target_position(targetContext).
        SET remainingVelocity TO f9_get_entry_vgo(
            targetPosition,
            params["entryVSpeed"]
        ).
        SET steeringTarget TO f9_get_target_steering(
            remainingVelocity,
            engineInfo["TiS"],
            params["targetRoll"]
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
            "Descent: " + ROUND(MAX(0, -SHIP:VERTICALSPEED), 1)
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
    f9_print_at(16, "Engines: active").
    UNTIL SHIP:VERTICALSPEED >= -params["entryVSpeed"] {
        f9_refresh_target(targetContext).
        SET targetPosition TO f9_get_target_position(targetContext).
        SET remainingVelocity TO f9_get_entry_vgo(
            targetPosition,
            params["entryVSpeed"]
        ).
        IF remainingVelocity:MAG > 0.001 {
            SET steeringTarget TO f9_get_target_steering(
                remainingVelocity,
                engineInfo["TiS"],
                params["targetRoll"]
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
            "Descent: " + ROUND(MAX(0, -SHIP:VERTICALSPEED), 1)
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
    RETURN TRUE.
}
