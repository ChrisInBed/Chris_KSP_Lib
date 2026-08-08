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
    IF NOT f9_initialize_ltr(params) {
        RETURN FALSE.
    }

    LOCAL vecNormal IS f9_get_surface_normal().
    LOCAL prediction IS f9_ltr_predict(
        params,
        targetContext,
        vecNormal
    ).
    IF NOT f9_ltr_prediction_is_valid(prediction) {
        f9_print_result("ERROR: LTR boostback prediction failed").
        RETURN FALSE.
    }
    LOCAL impactError IS f9_get_boostback_error(prediction).
    f9_print_target_position(targetContext).
    f9_print_recovery_vehicle().
    IF impactError:MAG < 0.001 {
        f9_print_at(11, "Phase: boostback - no burn required").
        f9_print_at(12, "Predicted impact error: 0.0 m").
        RETURN TRUE.
    }

    f9_print_at(11, "Phase: boostback - aligning").
    LOCAL steeringTarget IS f9_get_target_steering(
        impactError,
        engineInfo["TiS"],
        params["targetRoll"]
    ).
    SAS OFF.
    LOCK STEERING TO steeringTarget.
    LOCK THROTTLE TO 0.
    RCS ON.

    LOCAL alignmentError IS VANG(
        (SHIP:FACING * engineInfo["TiS"]:INVERSE):FOREVECTOR,
        impactError
    ).
    f9_print_at(
        12,
        "Predicted impact error: "
            + ROUND(impactError:MAG, 2) + " m"
    ).
    f9_print_at(13, "Alignment error: " + ROUND(alignmentError, 2) + " deg").
    f9_print_at(16, "Engines: armed  Throttle: 0.00").
    UNTIL alignmentError <= params["burnAlignTolerance"] {
        SET prediction TO f9_ltr_predict(
            params,
            targetContext,
            vecNormal
        ).
        IF NOT f9_ltr_prediction_is_valid(prediction) {
            f9_print_result("ERROR: LTR boostback prediction failed").
            UNLOCK THROTTLE.
            UNLOCK STEERING.
            RETURN FALSE.
        }
        SET impactError TO f9_get_boostback_error(prediction).
        SET steeringTarget TO f9_get_target_steering(
            impactError,
            engineInfo["TiS"],
            params["targetRoll"],
            vecNormal
        ).
        SET alignmentError TO VANG(
            (SHIP:FACING * engineInfo["TiS"]:INVERSE):FOREVECTOR,
            impactError
        ).
        f9_print_target_position(targetContext).
        f9_print_recovery_vehicle().
        f9_print_at(
            12,
            "Predicted impact error: "
                + ROUND(impactError:MAG, 2) + " m"
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
    LOCAL previousMagnitude IS impactError:MAG.
    LOCAL predictionFailed IS FALSE.
    f9_print_at(16, "Engines: active").
    WAIT 0.

    UNTIL FALSE {
        SET prediction TO f9_ltr_predict(
            params,
            targetContext,
            vecNormal
        ).
        IF NOT f9_ltr_prediction_is_valid(prediction) {
            SET predictionFailed TO TRUE.
            BREAK.
        }
        SET impactError TO f9_get_boostback_error(prediction).
        LOCAL currentMagnitude IS impactError:MAG.
        f9_print_target_position(targetContext).
        f9_print_recovery_vehicle().
        f9_print_at(
            12,
            "Predicted impact error: "
                + ROUND(currentMagnitude, 2) + " m"
        ).
        f9_print_at(
            14,
            "Previous impact error: "
                + ROUND(previousMagnitude, 2) + " m"
        ).
        f9_print_at(
            16,
            "Engines: active  Throttle: "
                + ROUND(SHIP:CONTROL:MAINTHROTTLE, 2)
        ).
        IF currentMagnitude <= 10000 AND currentMagnitude >= previousMagnitude {
            BREAK.
        }
        SET previousMagnitude TO currentMagnitude.
        IF currentMagnitude > 0.001 {
            SET steeringTarget TO f9_get_target_steering(
                impactError,
                engineInfo["TiS"],
                params["targetRoll"],
                vecNormal
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
    IF predictionFailed {
        f9_print_result("ERROR: LTR boostback prediction failed").
        RETURN FALSE.
    }
    RETURN TRUE.
}
