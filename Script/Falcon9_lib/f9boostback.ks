RUNONCEPATH("0:/Falcon9_lib/f9utility.ks").

FUNCTION f9_boostback_getImpactErr {
    PARAMETER params.
    PARAMETER targetContext.
    PARAMETER vecNormal.

    LOCAL predTime TO time:seconds.
    LOCAL prediction IS f9_ltr_predict(
        params,
        targetContext,
        vecNormal,
        params["entryBurnAlt"],
        params["entryVSpeed"],
        params["landingBurnAltitude"]
    ).
    IF NOT f9_ltr_prediction_is_valid(prediction) {
        f9_print_result("ERROR: LTR boostback prediction failed").
        RETURN LEXICON("ok", FALSE).
    }
    LOCAL impactError IS f9_get_boostback_error(prediction).
    return LEXICON("err", impactError, "time", predTime, "ok", TRUE).
}

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

    pre_boostback_hook().
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

    // Initialize 2 predictions
    LOCAL vecNormal IS f9_get_surface_normal().
    LOCAL _predres IS f9_boostback_getImpactErr(params, targetContext, vecNormal).
    if (not _predres["ok"]) { return FALSE. }
    LOCAL lastPredTime TO _predres["time"].
    LOCAL lastPredErr TO _predres["err"].
    WAIT 0.
    SET _predres TO f9_boostback_getImpactErr(params, targetContext, vecNormal).
    if (not _predres["ok"]) { return FALSE. }
    LOCAL predTime TO _predres["time"].
    LOCAL predErr TO _predres["err"].
    LOCAL errDot TO (predErr - lastPredErr) / (predTime - lastPredTime).
    WAIT 0.
    function update_predictions {
        parameter _predErr.
        parameter _predTime.

        set lastPredTime to predTime.
        set lastPredErr to predErr.
        set predErr to _predErr.
        set predTime to _predTime.
        set errDot TO (predErr - lastPredErr) / max(0.001, predTime - lastPredTime).
    }

    f9_print_target_position(targetContext).
    f9_print_recovery_vehicle().
    IF predErr:MAG < 0.001 {
        f9_print_at(11, "Phase: boostback - no burn required").
        f9_print_at(12, "Predicted impact error: 0.0 m").
        RETURN TRUE.
    }

    f9_print_at(11, "Phase: boostback - aligning").
    SAS OFF.
    // Steering routine: lock steering to predErr
    LOCAL done to False.
    LOCAL steeringTarget TO "kill".
    when (not done) then {
        SET steeringTarget TO f9_get_target_steering(
            predErr,
            engineInfo["TiS"],
            params["targetRoll"],
            vecNormal
        ).
        return true.
    }
    LOCK STEERING TO steeringTarget.
    LOCK THROTTLE TO 0.
    RCS ON.

    LOCAL alignmentError IS VANG(
        (SHIP:FACING * engineInfo["TiS"]:INVERSE):FOREVECTOR,
        predErr
    ).
    f9_print_at(
        12,
        "Predicted impact error: "
            + ROUND(predErr:MAG, 2) + " m"
    ).
    f9_print_at(13, "Alignment error: " + ROUND(alignmentError, 2) + " deg").
    f9_print_at(16, "Engines: armed  Throttle: 0.00").
    UNTIL alignmentError <= params["burnAlignTolerance"] {
        SET _predres TO f9_boostback_getImpactErr(params, targetContext, vecNormal).
        if not _predres["ok"] { BREAK. }
        update_predictions(_predres["err"], _predres["time"]).

        SET alignmentError TO VANG(
            (SHIP:FACING * engineInfo["TiS"]:INVERSE):FOREVECTOR,
            predErr
        ).
        f9_print_target_position(targetContext).
        f9_print_recovery_vehicle().
        f9_print_at(
            12,
            "Predicted impact error: "
                + ROUND(predErr:MAG, 2) + " m"
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
    LOCK throttle TO params["boostBackThrottle"].
    LOCAL predictionFailed IS FALSE.
    f9_print_at(16, "Engines: active").
    WAIT 0.

    // Guidance with prediction latency
    // throttle and steering routine
    when (not done) then {
        // given last prediction, last time, current prediction, current time
        LOCAL currentErr TO predErr + errDot * (time:seconds - predTime).
        LOCAL errMagDot TO vDot(currentErr, errDot).
        IF (currentErr:mag <= 1000 AND errMagDot >= 0) {
            SET done TO true.
            LOCK THROTTLE TO 0.
        }
        return true.
    }
    UNTIL done {
        SET _predres TO f9_boostback_getImpactErr(params, targetContext, vecNormal).
        if not _predres["ok"] {
            SET predictionFailed TO TRUE.
            BREAK.
        }
        update_predictions(_predres["err"], _predres["time"]).

        LOCAL currentMagnitude IS predErr:MAG.
        f9_print_target_position(targetContext).
        f9_print_recovery_vehicle().
        f9_print_at(
            12,
            "Predicted impact error: "
                + ROUND(currentMagnitude, 2) + " m"
        ).
        f9_print_at(
            14,
            "errDot: "
                + ROUND(2*vDot(predErr, errDot)/max(0.01, predErr:mag), 2) + " m"
        ).
        f9_print_at(
            16,
            "Engines: active  Throttle: "
                + ROUND(SHIP:CONTROL:MAINTHROTTLE, 2)
        ).
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
