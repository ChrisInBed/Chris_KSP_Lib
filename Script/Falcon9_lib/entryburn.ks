RUNONCEPATH("0:/Falcon9_lib/params.ks").
RUNONCEPATH("0:/Falcon9_lib/f9utility.ks").

FUNCTION f9_entry_burn {
    PARAMETER params.
    PARAMETER targetContext.

    IF NOT targetContext["ok"] {
        PRINT "F9 entry error: no valid landing target".
        RETURN FALSE.
    }

    LOCAL entryEngines IS search_engine(params["entryEngineTag"]).
    IF entryEngines:LENGTH = 0 {
        PRINT "F9 entry error: no entry engines found".
        RETURN FALSE.
    }
    LOCAL engineInfo IS get_engines_info(entryEngines).
    IF engineInfo["thrust"] <= 0 {
        PRINT "F9 entry error: engines have no available thrust".
        RETURN FALSE.
    }

    PRINT "F9 entry: coasting retrograde".
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
        WAIT 0.
    }

    IF -SHIP:VERTICALSPEED <= params["entryVSpeed"] {
        PRINT "F9 entry: target descent speed already satisfied".
        UNLOCK THROTTLE.
        UNLOCK STEERING.
        RETURN TRUE.
    }

    LOCAL targetGeo IS f9_refresh_target(targetContext).
    LOCAL remainingVelocity IS f9_get_entry_vgo(
        targetGeo,
        params["entryVSpeed"]
    ).
    IF remainingVelocity:MAG < 0.001 {
        PRINT "F9 entry: no burn required".
        UNLOCK THROTTLE.
        UNLOCK STEERING.
        RETURN TRUE.
    }

    PRINT "F9 entry: aligning".
    SET steeringTarget TO f9_get_target_steering(
        remainingVelocity,
        engineInfo["TiS"],
        params["targetRoll"]
    ).
    UNTIL VANG(
        (SHIP:FACING * engineInfo["TiS"]:INVERSE):FOREVECTOR,
        remainingVelocity
    ) <= params["burnAlignTolerance"] {
        SET targetGeo TO f9_refresh_target(targetContext).
        SET remainingVelocity TO f9_get_entry_vgo(
            targetGeo,
            params["entryVSpeed"]
        ).
        SET steeringTarget TO f9_get_target_steering(
            remainingVelocity,
            engineInfo["TiS"],
            params["targetRoll"]
        ).
        WAIT 0.
    }

    PRINT "F9 entry: ignition".
    activate_engines(entryEngines).
    UNTIL SHIP:VERTICALSPEED >= -params["entryVSpeed"] {
        SET targetGeo TO f9_refresh_target(targetContext).
        SET remainingVelocity TO f9_get_entry_vgo(
            targetGeo,
            params["entryVSpeed"]
        ).
        IF remainingVelocity:MAG > 0.001 {
            SET steeringTarget TO f9_get_target_steering(
                remainingVelocity,
                engineInfo["TiS"],
                params["targetRoll"]
            ).
        }
        WAIT 0.
    }

    PRINT "F9 entry: cutoff".
    LOCK THROTTLE TO 0.
    deactivate_engines(entryEngines).
    UNLOCK THROTTLE.
    UNLOCK STEERING.
    RETURN TRUE.
}
