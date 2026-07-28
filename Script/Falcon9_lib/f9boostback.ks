RUNONCEPATH("0:/Falcon9_lib/params.ks").
RUNONCEPATH("0:/Falcon9_lib/f9utility.ks").

FUNCTION f9_boostback {
    PARAMETER params.
    PARAMETER targetContext.

    IF NOT targetContext["ok"] {
        PRINT "F9 boostback error: no valid landing target".
        RETURN FALSE.
    }

    PRINT "F9 booster: waiting for stage separation".
    WAIT UNTIL SHIP:MASS < params["boostBackMass"].
    WAIT params["boostBackDelay"].

    LOCAL boostbackEngines IS search_engine(params["boostbackEngineTag"]).
    IF boostbackEngines:LENGTH = 0 {
        PRINT "F9 boostback error: no boostback engines found".
        RETURN FALSE.
    }
    LOCAL engineInfo IS get_engines_info(boostbackEngines).
    IF engineInfo["thrust"] <= 0 {
        PRINT "F9 boostback error: engines have no available thrust".
        RETURN FALSE.
    }

    LOCAL targetGeo IS f9_refresh_target(targetContext).
    LOCAL remainingVelocity IS f9_get_boostback_vgo(targetGeo).
    IF remainingVelocity:MAG < 0.001 {
        PRINT "F9 boostback: no burn required".
        RETURN TRUE.
    }

    PRINT "F9 boostback: aligning".
    LOCAL steeringTarget IS f9_get_target_steering(
        remainingVelocity,
        engineInfo["TiS"],
        params["targetRoll"]
    ).
    SAS OFF.
    LOCK STEERING TO steeringTarget.
    LOCK THROTTLE TO 0.
    RCS ON.

    UNTIL VANG(
        (SHIP:FACING * engineInfo["TiS"]:INVERSE):FOREVECTOR,
        remainingVelocity
    ) <= params["burnAlignTolerance"] {
        SET targetGeo TO f9_refresh_target(targetContext).
        SET remainingVelocity TO f9_get_boostback_vgo(targetGeo).
        SET steeringTarget TO f9_get_target_steering(
            remainingVelocity,
            engineInfo["TiS"],
            params["targetRoll"]
        ).
        WAIT 0.
    }

    PRINT "F9 boostback: ignition".
    activate_engines(boostbackEngines).
    LOCAL previousMagnitude IS remainingVelocity:MAG.
    WAIT 0.

    UNTIL FALSE {
        SET targetGeo TO f9_refresh_target(targetContext).
        SET remainingVelocity TO f9_get_boostback_vgo(targetGeo).
        LOCAL currentMagnitude IS remainingVelocity:MAG.
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

    PRINT "F9 boostback: cutoff".
    LOCK THROTTLE TO 0.
    deactivate_engines(boostbackEngines).
    UNLOCK THROTTLE.
    UNLOCK STEERING.
    RETURN TRUE.
}
