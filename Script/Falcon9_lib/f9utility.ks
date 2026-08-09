RUNONCEPATH("0:/lib/orbit.ks").
RUNONCEPATH("0:/lib/engine_utility.ks").

GLOBAL F9_DISPLAY_TERMINAL_WIDTH IS 50.
GLOBAL F9_DISPLAY_FIELD_WIDTH IS 48.
GLOBAL F9_GUIDANCE_FIRST_ROW IS 11.
GLOBAL F9_GUIDANCE_LAST_ROW IS 18.
GLOBAL F9_RESULT_ROW IS 21.
GLOBAL F9_LTR_INITIALIZED IS FALSE.

// Print into a fixed-width field so a shorter update erases the previous line.
FUNCTION f9_print_at {
    PARAMETER row.
    PARAMETER message.

    LOCAL lineText IS message + "".
    IF lineText:LENGTH > F9_DISPLAY_FIELD_WIDTH {
        SET lineText TO lineText:SUBSTRING(0, F9_DISPLAY_FIELD_WIDTH).
    } ELSE {
        SET lineText TO lineText:PADRIGHT(F9_DISPLAY_FIELD_WIDTH).
    }
    PRINT lineText AT(0, row).
}

FUNCTION f9_clear_display_rows {
    PARAMETER firstRow.
    PARAMETER lastRow.

    FROM {
        LOCAL row IS firstRow.
    } UNTIL row > lastRow STEP {
        SET row TO row + 1.
    } DO {
        f9_print_at(row, "").
    }
}

FUNCTION f9_clear_guidance_display {
    f9_clear_display_rows(
        F9_GUIDANCE_FIRST_ROW,
        F9_GUIDANCE_LAST_ROW
    ).
}

FUNCTION f9_print_result {
    PARAMETER message.
    f9_print_at(F9_RESULT_ROW, message).
}

FUNCTION f9_init_launch_display {
    SET TERMINAL:WIDTH TO F9_DISPLAY_TERMINAL_WIDTH.
    CLEARSCREEN.
    f9_print_at(0, "Falcon 9 Launch Guidance").
    f9_print_at(1, "--------------- VEHICLE ----------------").
    f9_print_at(9, "--------------- SEQUENCE ---------------").
    f9_print_at(20, "---------------- RESULT ----------------").
}

FUNCTION f9_print_target_position {
    PARAMETER targetContext.
    LOCAL targetGeo IS targetContext["geo"].

    f9_print_at(
        3,
        "Lat/Lng: " + ROUND(targetGeo:LAT, 4)
            + " / " + ROUND(targetGeo:LNG, 4)
    ).
    f9_print_at(
        4,
        "Alt raw/off/final: "
            + ROUND(targetContext["rawAltitude"], 1)
            + " / " + ROUND(targetContext["altitudeOffset"], 1)
            + " / " + ROUND(targetContext["altitude"], 1) + " m"
    ).
}

FUNCTION f9_init_recovery_display {
    PARAMETER targetContext.

    SET TERMINAL:WIDTH TO F9_DISPLAY_TERMINAL_WIDTH.
    CLEARSCREEN.
    f9_print_at(0, "Falcon 9 Recovery Guidance").
    f9_print_at(1, "---------------- TARGET ----------------").
    IF targetContext["moving"] {
        f9_print_at(2, "Target source: vessel (moving)").
    } ELSE {
        f9_print_at(2, "Target source: active waypoint (fixed)").
    }
    f9_print_target_position(targetContext).
    f9_print_at(5, "--------------- VEHICLE ----------------").
    f9_print_at(10, "--------------- GUIDANCE ---------------").
    f9_print_at(20, "---------------- RESULT ----------------").
}

FUNCTION f9_print_recovery_vehicle {
    f9_print_at(6, "Altitude: " + ROUND(SHIP:ALTITUDE, 1) + " m").
    f9_print_at(
        7,
        "Speed: " + ROUND(SHIP:VELOCITY:SURFACE:MAG, 1)
            + " m/s  VSpeed: " + ROUND(SHIP:VERTICALSPEED, 1)
    ).
    f9_print_at(8, "Mass: " + ROUND(SHIP:MASS, 2) + " t").
}

// Select a fixed active waypoint first. If none is selected, capture the
// current KSP target so a moving target vessel can be refreshed in flight.
FUNCTION f9_initialize_target {
    PARAMETER params.

    LOCAL activeWaypoint IS get_active_waypoint().
    LOCAL rawAltitude IS 0.
    IF activeWaypoint <> 0 {
        SET rawAltitude TO activeWaypoint:ALTITUDE.
        RETURN LEXICON(
            "ok", TRUE,
            "moving", FALSE,
            "geo", activeWaypoint:GEOPOSITION,
            "rawAltitude", rawAltitude,
            "altitudeOffset", params["altitudeOffset"],
            "altitude", rawAltitude + params["altitudeOffset"],
            "object", activeWaypoint
        ).
    }

    IF HASTARGET {
        SET rawAltitude TO TARGET:ALTITUDE.
        RETURN LEXICON(
            "ok", TRUE,
            "moving", TRUE,
            "geo", TARGET:GEOPOSITION,
            "rawAltitude", rawAltitude,
            "altitudeOffset", params["altitudeOffset"],
            "altitude", rawAltitude + params["altitudeOffset"],
            "object", TARGET
        ).
    }

    PRINT "F9 target error: select a waypoint or target vessel".
    RETURN LEXICON(
        "ok", FALSE,
        "moving", FALSE,
        "geo", SHIP:GEOPOSITION,
        "rawAltitude", SHIP:ALTITUDE,
        "altitudeOffset", params["altitudeOffset"],
        "altitude", SHIP:ALTITUDE + params["altitudeOffset"],
        "object", SHIP
    ).
}

FUNCTION f9_refresh_target {
    PARAMETER targetContext.
    IF targetContext["moving"] {
        SET targetContext["geo"] TO targetContext["object"]:GEOPOSITION.
        SET targetContext["rawAltitude"]
            TO targetContext["object"]:ALTITUDE.
        SET targetContext["altitude"]
            TO targetContext["rawAltitude"]
                + targetContext["altitudeOffset"].
    }
    RETURN targetContext["geo"].
}

FUNCTION f9_get_target_position {
    PARAMETER targetContext.
    RETURN targetContext["geo"]:ALTITUDEPOSITION(
        targetContext["altitude"]
    ).
}

FUNCTION f9_get_surface_normal {
    LOCAL unitR IS -SHIP:BODY:POSITION:NORMALIZED.
    LOCAL orbitNormal IS VCRS(unitR, SHIP:VELOCITY:SURFACE):NORMALIZED.
    IF orbitNormal:MAG < 1e-4 {
        RETURN NORTH:FORVECTOR.
    }
    RETURN orbitNormal.
}

// aeroTargetOffset is always measured along the booster's downrange axis.
// Keeping this in one helper ensures boostback, entry, and glide all aim at
// the same offset point while powered landing continues to use the raw target.
FUNCTION f9_get_aero_target_position {
    PARAMETER params.
    PARAMETER targetContext.
    PARAMETER vecNormal.

    LOCAL downrangeAxis IS VCRS(vecNormal, UP:FOREVECTOR).
    IF downrangeAxis:MAG < 0.000001 {
        SET downrangeAxis TO VXCL(
            UP:FOREVECTOR,
            SHIP:VELOCITY:SURFACE
        ).
    }
    IF downrangeAxis:MAG < 0.000001 {
        SET downrangeAxis TO NORTH:FOREVECTOR.
    } ELSE {
        SET downrangeAxis TO downrangeAxis:NORMALIZED.
    }
    RETURN f9_get_target_position(targetContext)
        + params["aeroTargetOffset"] * downrangeAxis.
}

FUNCTION f9_initialize_ltr_body {
    PARAMETER ltr.

    // Let the addon build its atmosphere interpolation tables automatically.
    // All other body parameters are assigned explicitly because the values in
    // LTR's C# constructor are only external-test fixtures. BODY:ANGULARVEL is
    // in the same raw reference frame as the body-centred prediction state.
    ltr:InitAtmModel().
    // There is something wrong with CelestialBody.angularVel API, so here we set it with kOS values
    SET ltr:bodySpin TO BODY:ANGULARVEL.
    RETURN TRUE.
}

// Initialize LTR only after stage separation so FAR samples the booster rather
// than the complete launch stack. The coefficient matrices use speed rows and
// altitude/density columns, matching kOS-AFS and kOS-LTR.
FUNCTION f9_initialize_ltr {
    PARAMETER params.
    // IF F9_LTR_INITIALIZED {
    //     RETURN TRUE.
    // }
    IF NOT ADDONS:HASADDON("LTR") {
        f9_print_result("ERROR: kOS-LTR addon is unavailable").
        RETURN FALSE.
    }

    LOCAL ltr IS ADDONS:LTR.
    IF NOT f9_initialize_ltr_body(ltr) {
        RETURN FALSE.
    }
    SET ltr:MASS TO SHIP:MASS.
    SET ltr:AREA TO ltr:REFAREA.
    SET ltr:AOAReversal TO FALSE.
    SET ltr:CtrlSpeedSamples TO params["ltrCtrlSpeedSamples"].
    SET ltr:CtrlAOASamples TO params["ltrCtrlAOASamples"].
    SET ltr:predict_min_step TO params["ltrPredictMinStep"].
    SET ltr:predict_max_step TO params["ltrPredictMaxStep"].
    SET ltr:predict_tmax TO params["ltrPredictTMax"].
    SET ltr:rotation TO R(180, 0, params["targetRoll"]).

    LOCAL cdRows IS LIST().
    LOCAL clRows IS LIST().
    FOR speed IN params["ltrAeroSpeedSamples"] {
        LOCAL cdRow IS LIST().
        LOCAL clRow IS LIST().
        LOCAL aoaCommand IS ltr:GetAOACmd(speed)["AOA"].
        FOR sampleAltitude IN params["ltrAeroAltitudeSamples"] {
            LOCAL coefficients IS ltr:GetFARAeroCoefs(LEXICON(
                "altitude", sampleAltitude,
                "speed", speed,
                "AOA", aoaCommand
            )).
            cdRow:ADD(coefficients["Cd"] * params["ltrCdFactor"]).
            clRow:ADD(coefficients["Cl"] * params["ltrClFactor"]).
        }
        cdRows:ADD(cdRow).
        clRows:ADD(clRow).
    }
    SET ltr:AeroSpeedSamples TO params["ltrAeroSpeedSamples"].
    ltr:SetAeroDsFromAlt(params["ltrAeroAltitudeSamples"]).
    SET ltr:AeroCdSamples TO cdRows.
    SET ltr:AeroClSamples TO clRows.
    SET F9_LTR_INITIALIZED TO TRUE.
    RETURN TRUE.
}

// Run one prediction from the latest state. Async execution yields the kOS CPU
// while the C# RKF45 integrator works, then returns a result and the exact target
// vector used for that prediction.
// When the vessel hits burnAltitude, the predictor assumes that the rocket ignite its landing engines
// and fly a parabola trajectory down. So it calculates a simple offset to the predicted
// impact point.
FUNCTION f9_ltr_predict {
    PARAMETER params.
    PARAMETER targetContext.
    PARAMETER vecNormal.
    PARAMETER burnAltitude IS 0.

    f9_refresh_target(targetContext).
    LOCAL targetPosition IS f9_get_aero_target_position(
        params,
        targetContext,
        vecNormal
    ).
    LOCAL targetBodyPosition IS targetPosition - SHIP:BODY:POSITION.
    LOCAL ltr IS ADDONS:LTR.
    SET ltr:MASS TO SHIP:MASS.
    SET ltr:target_altitude TO targetContext["altitude"].
    SET ltr:RTarget TO targetBodyPosition.
    // LOCAL state IS ltr:GetState().
    LOCAL state IS LEXICON("vecR", -ship:body:position, "vecV", ship:velocity:surface).
    LOCAL handle IS ltr:AsyncSimAtmTraj(LEXICON(
        "t", 0,
        "vecR", state["vecR"],
        "vecV", state["vecV"]
    )).
    UNTIL ltr:CheckTask(handle) {
        1.
    }
    LOCAL result IS ltr:GetTaskResult(handle).
    local finalVecR to result["finalVecR"].
    local finalVecV to result["finalVecV"].
    local finalFPA to min(-10, 90 - vAng(finalVecR, finalVecV)).
    local downrangeAxis to vxcl(finalVecR, finalVecV):normalized.
    set result["finalVecR"] to finalVecR + 0.5*burnAltitude/tan(finalFPA)*downrangeAxis.
    SET result["initialVecR"] TO state["vecR"].
    SET result["initialVecV"] TO state["vecV"].
    // Refresh ship-relative geometry after the asynchronous calculation. The
    // prediction state remains the captured initial state above.
    f9_refresh_target(targetContext).
    SET targetPosition TO f9_get_aero_target_position(
        params,
        targetContext,
        vecNormal
    ).
    SET result["targetPosition"] TO targetPosition.
    SET result["targetBodyPosition"] TO targetBodyPosition.
    RETURN result.
}

FUNCTION f9_ltr_prediction_is_valid {
    PARAMETER prediction.
    RETURN prediction["ok"]
        AND prediction["status"] = "COMPLETED".
}

// PEGLand-style steering: burnVector is the desired acceleration direction,
// TiS is Engine:facing:inverse * Ship:facing, and targetRoll fixes roll.
FUNCTION f9_get_target_steering {
    PARAMETER burnVector.
    PARAMETER TiS.
    PARAMETER targetRoll.
    PARAMETER vecNormal is 0.

    IF burnVector:MAG < 0.000001 {
        RETURN SHIP:FACING.
    }
    LOCAL topVector IS V(0,0,0).
    if (vecNormal <> 0)  SET topVector TO VCRS(burnVector, vecNormal).
    ELSE SET topVector TO VCRS(burnVector, f9_get_surface_normal()).
    IF topVector:MAG < 0.000001 {
        SET topVector TO NORTH:FOREVECTOR.
    }
    RETURN LOOKDIRUP(burnVector, topVector) * R(0, 0, targetRoll) * TiS.
}

// UEntry-style steering: Give desired plane-like direction then transform it into vessel direction
FUNCTION f9_get_aero_steering {
    PARAMETER desiredDirection.
    RETURN desiredDirection * ADDONS:LTR:rotation:INVERSE.
}

FUNCTION f9_get_boostback_error {
    PARAMETER prediction.
    RETURN prediction["targetBodyPosition"]
        - prediction["finalVecR"].
}

FUNCTION f9_get_entry_vgo {
    PARAMETER prediction.
    PARAMETER entrySpeed.

    // LOCAL rr IS prediction["initialVecR"].
    // LOCAL vv IS prediction["initialVecV"].
    // LOCAL rTarget IS prediction["targetBodyPosition"].
    // LOCAL impactPosition IS prediction["finalVecR"].
    // LOCAL unitR IS rr:NORMALIZED.
    // LOCAL g IS SHIP:BODY:MU / rr:MAG^2.
    // LOCAL gravity IS -g * unitR.
    // LOCAL targetRadialSpeed IS -entrySpeed.
    // LOCAL impactRadialSpeed IS VDOT(unitR, vv).
    // LOCAL height IS VDOT(unitR, rr - rTarget).
    // LOCAL targetTime IS (targetRadialSpeed
    //     + SQRT(MAX(0, targetRadialSpeed^2 + 2*g*height))) / g.
    // LOCAL impactTime IS (impactRadialSpeed
    //     + SQRT(MAX(0, impactRadialSpeed^2 + 2*g*height))) / g.
    // SET targetTime TO MAX(0.001, targetTime).
    // SET impactTime TO MAX(0.001, impactTime).

    // // This is the plan's hybrid prediction/vacuum law written relative to the
    // // current position. The relative form is algebraically frame-invariant and
    // // avoids subtracting planet-radius-sized terms divided by different times.
    // RETURN (rTarget - rr) / targetTime
    //     - (impactPosition - rr) / impactTime
    //     - 0.5 * gravity * (targetTime - impactTime).

    // Because the impact point moves a lot when the energy changes
    // So the above method is not robust, especially for ships that possess a large lift force
    // We switch to the following simple routine: just burn straight up until the vertical speed reaches entrySpeed
    local upaxis to up:forevector.
    return (-entrySpeed - ship:verticalSpeed) * upaxis.
}

FUNCTION f9_get_bottom_height {
    PARAMETER TiS.
    LOCAL thrustDown IS -(SHIP:FACING * TiS:INVERSE):FOREVECTOR.
    RETURN get_furtherst_height(SHIP:BOUNDS, thrustDown).
}

FUNCTION f9_get_bottom_altitude {
    PARAMETER targetPosition.
    PARAMETER bottomHeight.
    LOCAL bottomPosition IS SHIP:POSITION - bottomHeight * UP:FOREVECTOR.
    RETURN VDOT(bottomPosition - targetPosition, UP:FOREVECTOR).
}

FUNCTION f9_continuous_throttle {
    PARAMETER requestedFraction.
    PARAMETER minThrottle.
    PARAMETER minCommand.
    RETURN MAX(minCommand, MIN(1, simple_get_throttle(requestedFraction, minThrottle))).
}
