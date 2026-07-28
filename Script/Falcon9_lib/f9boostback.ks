RUNONCEPATH("0:/Falcon9_lib/params.ks").
RUNONCEPATH("0:/Falcon9_lib/f9utility.ks").

FUNCTION f9_boostback {
    PARAMETER params.
    PARAMETER targetContext.

    IF NOT targetContext["ok"] {
        f9_print_result("ERROR: no valid landing target").
        RETURN FALSE.
    }

    f9_clear_guidance_display().
    f9_print_at(11, "Phase: boostback - waiting for separation").
    UNTIL SHIP:MASS < params["boostBackMass"] {
        f9_print_recovery_vehicle().
        f9_print_at(
            12,
            "Separation mass: < "
                + ROUND(params["boostBackMass"], 2) + " t"
        ).
        f9_print_at(16, "Engines: waiting").
        WAIT 0.
    }
    WAIT params["boostBackDelay"].

    LOCAL boostbackEngines IS search_engine(params["boostbackEngineTag"]).
    IF boostbackEngines:LENGTH = 0 {
        f9_print_result("ERROR: no boostback engines found").
        RETURN FALSE.
    }
    LOCAL engineInfo IS get_engines_info(boostbackEngines).
    IF engineInfo["thrust"] <= 0 {
        f9_print_result("ERROR: boostback engines have no thrust").
        RETURN FALSE.
    }

    LOCAL targetGeo IS f9_refresh_target(targetContext).
    LOCAL remainingVelocity IS f9_get_boostback_vgo(targetGeo).
    f9_print_target_position(targetGeo).
    f9_print_recovery_vehicle().
    IF remainingVelocity:MAG < 0.001 {
        f9_print_at(11, "Phase: boostback - no burn required").
        f9_print_at(12, "Remaining velocity: 0.0 m/s").
        RETURN TRUE.
    }

    f9_print_at(11, "Phase: boostback - aligning").
    LOCAL steeringTarget IS f9_get_target_steering(
        remainingVelocity,
        engineInfo["TiS"],
        params["targetRoll"]
    ).
    SAS OFF.
    LOCK STEERING TO steeringTarget.
    LOCK THROTTLE TO 0.
    RCS ON.

    LOCAL alignmentError IS VANG(
        (SHIP:FACING * engineInfo["TiS"]:INVERSE):FOREVECTOR,
        remainingVelocity
    ).
    f9_print_at(
        12,
        "Remaining velocity: "
            + ROUND(remainingVelocity:MAG, 2) + " m/s"
    ).
    f9_print_at(13, "Alignment error: " + ROUND(alignmentError, 2) + " deg").
    f9_print_at(16, "Engines: armed  Throttle: 0.00").
    UNTIL alignmentError <= params["burnAlignTolerance"] {
        SET targetGeo TO f9_refresh_target(targetContext).
        SET remainingVelocity TO f9_get_boostback_vgo(targetGeo).
        SET steeringTarget TO f9_get_target_steering(
            remainingVelocity,
            engineInfo["TiS"],
            params["targetRoll"]
        ).
        SET alignmentError TO VANG(
            (SHIP:FACING * engineInfo["TiS"]:INVERSE):FOREVECTOR,
            remainingVelocity
        ).
        f9_print_target_position(targetGeo).
        f9_print_recovery_vehicle().
        f9_print_at(
            12,
            "Remaining velocity: "
                + ROUND(remainingVelocity:MAG, 2) + " m/s"
        ).
        f9_print_at(
            13,
            "Alignment error: " + ROUND(alignmentError, 2) + " deg"
        ).
        f9_print_at(
            16,
            "Engines: armed  Throttle: "
                + ROUND(SHIP:CONTROL:MAINTHROTTLE, 2)
        ).
        WAIT 0.
    }

    f9_print_at(11, "Phase: boostback - powered guidance").
    activate_engines(boostbackEngines).
    LOCAL previousMagnitude IS remainingVelocity:MAG.
    f9_print_at(16, "Engines: active").
    WAIT 0.

    UNTIL FALSE {
        SET targetGeo TO f9_refresh_target(targetContext).
        SET remainingVelocity TO f9_get_boostback_vgo(targetGeo).
        LOCAL currentMagnitude IS remainingVelocity:MAG.
        f9_print_target_position(targetGeo).
        f9_print_recovery_vehicle().
        f9_print_at(
            12,
            "Remaining velocity: "
                + ROUND(currentMagnitude, 2) + " m/s"
        ).
        f9_print_at(
            14,
            "Previous velocity error: "
                + ROUND(previousMagnitude, 2) + " m/s"
        ).
        f9_print_at(
            16,
            "Engines: active  Throttle: "
                + ROUND(SHIP:CONTROL:MAINTHROTTLE, 2)
        ).
        IF (currentMagnitude < 20 and currentMagnitude > previousMagnitude) {
            BREAK.
        }
        SET previousMagnitude TO currentMagnitude.
        IF currentMagnitude > 0.001 {
            SET steeringTarget TO f9_get_target_steering(
                remainingVelocity,
                engineInfo["TiS"],
                params["targetRoll"]
            ).
        }
        WAIT 0.
    }

    f9_print_at(11, "Phase: boostback - cutoff").
    f9_print_at(16, "Engines: cutoff  Throttle: 0.00").
    LOCK THROTTLE TO 0.
    deactivate_engines(boostbackEngines).
    UNLOCK THROTTLE.
    UNLOCK STEERING.
    RETURN TRUE.
}
