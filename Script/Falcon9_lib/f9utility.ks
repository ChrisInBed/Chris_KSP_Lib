RUNONCEPATH("0:/lib/orbit.ks").
RUNONCEPATH("0:/lib/engine_utility.ks").
RUNONCEPATH("0:/Falcon9_lib/GFOLD_defaults.ks").

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
    IF (targetContext["source"] = "none"
        AND NOT targetContext["resolved"]) {
        f9_print_at(3, "Lat/Lng: pending natural impact").
        f9_print_at(4, "Alt raw/off/final: pending").
        RETURN.
    }
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
    IF targetContext["source"] = "none" {
        f9_print_at(2, "Target source: natural impact (automatic)").
    } ELSE IF targetContext["source"] = "vessel" {
        f9_print_at(2, "Target source: vessel (moving)").
    } ELSE IF targetContext["source"] = "waypoint" {
        f9_print_at(2, "Target source: waypoint (fixed)").
    } ELSE {
        f9_print_at(2, "Target source: geoposition (fixed)").
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

// All recovery phases must start from the separated booster so engine lookup
// and FAR sampling do not use the complete launch stack. Boostback delay is
// only part of preparation when boostback will run, or when a natural-impact
// target must be selected after that delay.
FUNCTION f9_wait_for_recovery_start {
    PARAMETER params.

    f9_clear_guidance_display().
    f9_print_at(11, "Phase: recovery - waiting for separation").
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
    RETURN TRUE.
}

// Acquire the configured landing site. The recovery boot file owns the
// selector and its associated value; no active waypoint or KSP target is
// consulted implicitly.
FUNCTION f9_initialize_target {
    PARAMETER params.

    LOCAL source IS params["landingSiteUse"].
    LOCAL rawAltitude IS 0.
    LOCAL targetGeo IS 0.
    LOCAL targetObject IS 0.
    LOCAL moving IS FALSE.

    IF source = "none" {
        // This placeholder is replaced with the predicted natural impact point
        // after separation and boostBackDelay. Sea level is the first-pass
        // prediction altitude; a second pass uses the terrain at that impact.
        SET targetGeo TO SHIP:GEOPOSITION.
        SET rawAltitude TO 0.
    } ELSE IF source = "geo" {
        LOCAL geoSpec IS params["landingSiteGeo"].
        IF geoSpec:LENGTH < 2 {
            PRINT "F9 target error: landingSiteGeo needs longitude and latitude".
            RETURN LEXICON("ok", FALSE, "source", source).
        }
        LOCAL _longitude IS geoSpec[0].
        LOCAL _latitude IS geoSpec[1].
        IF (_longitude < -180 OR _longitude > 180
            OR _latitude < -90 OR _latitude > 90) {
            PRINT "F9 target error: landingSiteGeo is out of range".
            RETURN LEXICON("ok", FALSE, "source", source).
        }
        SET targetGeo TO LATLNG(_latitude, _longitude).
        SET rawAltitude TO targetGeo:TERRAINHEIGHT.
    } ELSE IF source = "waypoint" {
        LOCAL waypointName IS params["landingSiteWaypoint"].
        LOCAL waypointList IS ALLWAYPOINTS().
        FOR waypoint IN waypointList {
            IF waypoint:NAME = waypointName {
                SET targetObject TO waypoint.
                BREAK.
            }
        }
        IF targetObject = 0 {
            PRINT "F9 target error: waypoint '" + waypointName
                + "' was not found".
            RETURN LEXICON("ok", FALSE, "source", source).
        }
        SET targetGeo TO targetObject:GEOPOSITION.
        SET rawAltitude TO targetObject:ALTITUDE.
    } ELSE IF source = "vessel" {
        LOCAL vesselName IS params["landingSiteVessel"].
        SET targetObject TO VESSEL(vesselName).
        IF targetObject:ISDEAD {
            PRINT "F9 target error: vessel '" + vesselName
                + "' was not found".
            RETURN LEXICON("ok", FALSE, "source", source).
        }
        SET targetGeo TO targetObject:GEOPOSITION.
        SET rawAltitude TO targetObject:ALTITUDE.
        SET moving TO TRUE.
    } ELSE {
        PRINT "F9 target error: landingSiteUse must be none, geo, waypoint, or vessel".
        RETURN LEXICON("ok", FALSE, "source", source).
    }

    RETURN LEXICON(
        "ok", TRUE,
        "source", source,
        "resolved", source <> "none",
        "moving", moving,
        "geo", targetGeo,
        "rawAltitude", rawAltitude,
        "altitudeOffset", params["altitudeOffset"],
        "altitude", rawAltitude + params["altitudeOffset"],
        "object", targetObject
    ).
}

// Resolve landingSiteUse = "none" to the natural LTR impact point. The first
// prediction crosses sea level; the second repeats at the terrain/ocean level
// found under that impact. The final geoposition is written into targetContext
// so all later phases use the same fixed site.
FUNCTION f9_resolve_automatic_target {
    PARAMETER params.
    PARAMETER targetContext.

    IF targetContext["source"] <> "none" OR targetContext["resolved"] {
        RETURN TRUE.
    }
    IF NOT f9_initialize_ltr(params) {
        SET targetContext["ok"] TO FALSE.
        RETURN FALSE.
    }

    LOCAL vecNormal IS f9_get_surface_normal().
    FROM {
        LOCAL pass IS 0.
    } UNTIL pass >= 2 STEP {
        SET pass TO pass + 1.
    } DO {
        LOCAL prediction IS 0.
        IF params["enableEntryBurn"] {
            SET prediction TO f9_ltr_predict(
                params,
                targetContext,
                vecNormal,
                params["entryBurnAlt"],
                params["entryVSpeed"],
                params["landingBurnAltitude"]
            ).
        } ELSE {
            SET prediction TO f9_ltr_predict(
                params,
                targetContext,
                vecNormal,
                9999999999,
                9999999999,
                params["landingBurnAltitude"]
            ).
        }
        IF NOT f9_ltr_prediction_is_valid(prediction) {
            f9_print_result("ERROR: LTR automatic target prediction failed").
            SET targetContext["ok"] TO FALSE.
            RETURN FALSE.
        }

        // LTR positions are body-centred (SOI-RAW). GEOPOSITIONOF expects a
        // SHIP-RAW position, so move the origin back to the current vessel.
        LOCAL impactPosition IS prediction["finalVecR"]
            + SHIP:BODY:POSITION.
        LOCAL targetGeo IS SHIP:BODY:GEOPOSITIONOF(impactPosition).
        LOCAL rawAltitude IS targetGeo:TERRAINHEIGHT.
        IF SHIP:BODY:HASOCEAN AND rawAltitude < 0 {
            SET rawAltitude TO 0.
        }
        SET targetContext["geo"] TO targetGeo.
        SET targetContext["rawAltitude"] TO rawAltitude.
        SET targetContext["altitude"] TO rawAltitude
            + targetContext["altitudeOffset"].
    }

    SET targetContext["moving"] TO FALSE.
    SET targetContext["object"] TO 0.
    SET targetContext["resolved"] TO TRUE.
    SET targetContext["ok"] TO TRUE.
    RETURN TRUE.
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
// When the vessel hits entryAlt, the rocket burn retrograde to reduce speed to entrySpeed
// When the vessel hits burnAltitude, the predictor assumes that the rocket ignite its landing engines
// and fly a parabola trajectory down. So it calculates a simple offset to the predicted
// impact point.
FUNCTION f9_ltr_predict {
    PARAMETER params.
    PARAMETER targetContext.
    PARAMETER vecNormal.
    PARAMETER entryAlt IS 9999999999.
    PARAMETER entrySpeed IS 9999999999.
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
    SET ltr:RTarget TO targetBodyPosition.

    LOCAL initVecR TO -ship:body:position.
    LOCAL initVecV TO ship:velocity:surface.
    LOCAL vecR to initVecR.
    LOCAL vecV to initVecV.
    LOCAL tt TO 0.
    if (ship:altitude > entryAlt) {
        // Propagate to entry interface
        SET ltr:target_altitude TO entryAlt.
        LOCAL handle IS ltr:AsyncSimAtmTraj(LEXICON(
            "t", tt,
            "vecR", vecR,
            "vecV", vecV
        )).
        UNTIL ltr:CheckTask(handle) {
            1.
        }
        LOCAL result IS ltr:GetTaskResult(handle).
        SET tt TO result["t"].
        SET vecR TO result["finalVecR"].
        SET vecV TO result["finalVecV"].
        SET vecV TO vecV:normalized * min(entrySpeed, vecV:mag).
    }

    SET ltr:target_altitude TO targetContext["altitude"].
    // LOCAL state IS ltr:GetState().
    // LOCAL state IS LEXICON("vecR", -ship:body:position, "vecV", ship:velocity:surface).
    LOCAL handle IS ltr:AsyncSimAtmTraj(LEXICON(
        "t", tt,
        "vecR", vecR,
        "vecV", vecV
    )).
    UNTIL ltr:CheckTask(handle) {
        1.
    }
    LOCAL result IS ltr:GetTaskResult(handle).
    local finalVecR to result["finalVecR"].
    local finalVecV to result["finalVecV"].
    local finalFPA to min(-10, 90 - vAng(finalVecR, finalVecV)).
    local downrangeAxis to vxcl(finalVecR, finalVecV):normalized.
    set result["finalVecR"] to finalVecR + 0.33*burnAltitude/tan(finalFPA)*downrangeAxis.
    SET result["initialVecR"] TO initVecR.
    SET result["initialVecV"] TO initVecV.
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

FUNCTION f9_step_entry_vgo {
    PARAMETER params.
    PARAMETER targetContext.
    PARAMETER vecVGO.
    PARAMETER vecNormal.

    LOCAL vecR TO -body:position.
    LOCAL vecV TO ship:velocity:surface.
    LOCAL entrySpeed TO params["entryVSpeed"].
    LOCAL g0 TO ship:body:mu / ship:body:radius^2.
    LOCAL burnAltitude TO params["landingBurnAltitude"].

    f9_refresh_target(targetContext).
    LOCAL targetPosition IS f9_get_aero_target_position(
        params,
        targetContext,
        vecNormal
    ).
    LOCAL vecRT IS targetPosition - SHIP:BODY:POSITION.
    LOCAL ltr IS ADDONS:LTR.
    SET ltr:MASS TO SHIP:MASS.
    SET ltr:RTarget TO vecRT.

    // 1. normalize VGO to meet entry speed constraint
    LOCAL unitVGO TO vecVGO:normalized.
    LOCAL xx TO vDot(vecV, unitVGO).
    LOCAL _m TO xx^2 - (vecV:mag^2 - entrySpeed^2).
    IF (_m <= 0) {
        SET vecVGO TO (entrySpeed - vecV:mag) * vecV:normalized.
    }
    ELSE {
        SET VGO TO -xx - sqrt(xx^2 - (vecV:mag^2 - entrySpeed^2)).
        SET vecVGO TO VGO * unitVGO.
    }
    // 2. evaluate reaching time
    LOCAL upAxis TO vecRT:normalized.
    LOCAL vy TO vDot(vecV + vecVGO, upAxis).
    LOCAL ry TO vDot(vecR - vecRT, upAxis).
    LOCAL tt TO (vy + sqrt(vy^2 + 2*g0*ry)) / g0.
    // 3. predict impact point
    SET ltr:target_altitude TO targetContext["altitude"].
    LOCAL handle IS ltr:AsyncSimAtmTraj(LEXICON(
        "t", 0,
        "vecR", vecR,
        "vecV", vecV + vecVGO
    )).
    UNTIL ltr:CheckTask(handle) {
        1.
    }
    LOCAL result IS ltr:GetTaskResult(handle).
    IF (result["status"] <> "COMPLETED") RETURN LEXICON(
        "ok", FALSE,
        "msg", result["msg"],
        "vecVGO", vecVGO
    ).
    LOCAL vecRP TO result["finalVecR"].
    LOCAL vecVP TO result["finalVecV"].
    local finalFPA to min(-10, 90 - vAng(vecRP, vecVP)).
    local downrangeAxis to vxcl(vecRP, vecVP):normalized.
    set vecRP to vecRP + 0.33*burnAltitude/tan(finalFPA)*downrangeAxis.
    // 4. update vecVGO
    SET vecVGO TO vecVGO + (vecRT - vecRP) / tt.
    IF vAng(vecVGO, -vecV) > 30 {
        SET vecVGO TO angleAxis(30, vCrs(-vecV, vecVGO)) * (-vecV):normalized * vecVGO:mag.
    }
    return LEXICON(
        "ok", TRUE,
        "msg", result["msg"],
        "vecVGO", vecVGO
    ).
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

// Apply vessel-independent GFOLD defaults without replacing boot values.
FUNCTION f9_apply_gfold_defaults {
    PARAMETER configLex.
    FOR defaultName IN F9_GFOLD_DEFAULTS:KEYS {
        IF NOT configLex:HASKEY(defaultName) {
            SET configLex[defaultName] TO F9_GFOLD_DEFAULTS[defaultName].
        }
    }
    RETURN configLex.
}

// Build the same E-U-N axes and polar fallback used by kOS-GFOLD.
FUNCTION f9_gfold_make_basis {
    PARAMETER referenceVec.
    PARAMETER spinVec.

    LOCAL upVec IS referenceVec:NORMALIZED.
    LOCAL eastVec IS VCRS(spinVec, upVec).
    IF eastVec:MAG < 0.0000000001 {
        LOCAL seedVec IS V(0, 0, 1).
        IF (ABS(upVec:X) <= ABS(upVec:Y)
            AND ABS(upVec:X) <= ABS(upVec:Z)) {
            SET seedVec TO V(1, 0, 0).
        } ELSE IF ABS(upVec:Y) <= ABS(upVec:Z) {
            SET seedVec TO V(0, 1, 0).
        }
        SET eastVec TO VCRS(seedVec, upVec).
    }
    SET eastVec TO eastVec:NORMALIZED.
    LOCAL northVec IS VCRS(upVec, eastVec):NORMALIZED.
    RETURN LEXICON(
        "east", eastVec,
        "up", upVec,
        "north", northVec
    ).
}

// Express a vector measured in source axes using destination axes. Supplying
// current/frozen bases maps raw current coordinates into the frozen GFOLD frame;
// swapping the bases performs the inverse map.
FUNCTION f9_gfold_map_vector {
    PARAMETER inputVec.
    PARAMETER sourceBasis.
    PARAMETER destinationBasis.
    RETURN destinationBasis["east"] * VDOT(sourceBasis["east"], inputVec)
        + destinationBasis["up"] * VDOT(sourceBasis["up"], inputVec)
        + destinationBasis["north"] * VDOT(sourceBasis["north"], inputVec).
}

FUNCTION f9_gfold_target_body_position {
    PARAMETER targetContext.
    RETURN f9_get_target_position(targetContext) - SHIP:BODY:POSITION.
}

FUNCTION f9_gfold_bottom_body_position {
    PARAMETER bottomHeight.
    RETURN -SHIP:BODY:POSITION - bottomHeight * UP:FOREVECTOR.
}

// Return the virtual bottom-point state used with a target/basis frozen at
// initialization. Moving-target velocity is deliberately not subtracted.
FUNCTION f9_gfold_virtual_state {
    PARAMETER targetContext.
    PARAMETER bottomHeight.
    PARAMETER frozenTargetVec.
    PARAMETER frozenBasis.

    f9_refresh_target(targetContext).
    LOCAL currentTargetVec IS f9_gfold_target_body_position(targetContext).
    LOCAL currentBasis IS f9_gfold_make_basis(
        currentTargetVec,
        SHIP:BODY:ANGULARVEL
    ).
    LOCAL currentBottomVec IS f9_gfold_bottom_body_position(bottomHeight).
    LOCAL relativeBottomVec IS currentBottomVec - currentTargetVec.
    RETURN LEXICON(
        "position", frozenTargetVec + f9_gfold_map_vector(
            relativeBottomVec,
            currentBasis,
            frozenBasis
        ),
        "velocity", f9_gfold_map_vector(
            SHIP:VELOCITY:SURFACE,
            currentBasis,
            frozenBasis
        ),
        "currentBasis", currentBasis,
        "targetPosition", currentTargetVec,
        "bottomPosition", currentBottomVec
    ).
}

// Earliest nonnegative intercept with desiredHeight under constant vertical
// acceleration. A negative return value means no forward intercept exists.
FUNCTION f9_gfold_altitude_intercept {
    PARAMETER currentHeight.
    PARAMETER verticalRate.
    PARAMETER verticalAcceleration.
    PARAMETER desiredHeight.

    LOCAL heightOffset IS currentHeight - desiredHeight.
    IF heightOffset <= 0 {
        RETURN 0.
    }
    IF ABS(verticalAcceleration) < 0.000001 {
        IF verticalRate < -0.000001 {
            RETURN -heightOffset / verticalRate.
        }
        RETURN -1.
    }
    LOCAL discriminantValue IS verticalRate^2
        - 2 * verticalAcceleration * heightOffset.
    IF discriminantValue < 0 {
        RETURN -1.
    }
    LOCAL rootScale IS SQRT(discriminantValue).
    LOCAL firstRoot IS (-verticalRate - rootScale) / verticalAcceleration.
    LOCAL secondRoot IS (-verticalRate + rootScale) / verticalAcceleration.
    LOCAL interceptDuration IS 999999999.
    IF firstRoot >= 0 {
        SET interceptDuration TO firstRoot.
    }
    IF (secondRoot >= 0 AND secondRoot < interceptDuration) {
        SET interceptDuration TO secondRoot.
    }
    IF interceptDuration = 999999999 {
        RETURN -1.
    }
    RETURN interceptDuration.
}

FUNCTION f9_gfold_engine_limits {
    PARAMETER engineInfo.
    PARAMETER marginFraction.
    LOCAL physicalMinimum IS engineInfo["minthrottle"].
    LOCAL safeMinimum IS physicalMinimum
        + (1 - physicalMinimum) * marginFraction.
    LOCAL safeMaximum IS 1
        - (1 - physicalMinimum) * marginFraction.
    RETURN LEXICON(
        "thrustMin", engineInfo["thrust"] * safeMinimum,
        "thrustMax", engineInfo["thrust"] * safeMaximum,
        "isp", engineInfo["ISP"],
        "fractionMin", safeMinimum,
        "fractionMax", safeMaximum
    ).
}

FUNCTION f9_gfold_gain_control {
    PARAMETER gainRows.
    PARAMETER positionErrorVec.
    PARAMETER velocityErrorVec.
    LOCAL errorValues IS LIST(
        positionErrorVec:X,
        positionErrorVec:Y,
        positionErrorVec:Z,
        velocityErrorVec:X,
        velocityErrorVec:Y,
        velocityErrorVec:Z
    ).
    LOCAL correctionValues IS LIST(0, 0, 0).
    FROM {
        LOCAL gainRowIndex IS 0.
    } UNTIL gainRowIndex >= 3 STEP {
        SET gainRowIndex TO gainRowIndex + 1.
    } DO {
        LOCAL rowTotal IS 0.
        FROM {
            LOCAL gainColumnIndex IS 0.
        } UNTIL gainColumnIndex >= 6 STEP {
            SET gainColumnIndex TO gainColumnIndex + 1.
        } DO {
            SET rowTotal TO rowTotal
                + gainRows[gainRowIndex][gainColumnIndex]
                    * errorValues[gainColumnIndex].
        }
        SET correctionValues[gainRowIndex] TO rowTotal.
    }
    RETURN V(
        correctionValues[0],
        correctionValues[1],
        correctionValues[2]
    ).
}

FUNCTION f9_validate_required_keys {
    PARAMETER params.
    PARAMETER requiredKeys.
    PARAMETER context IS "configuration".

    IF NOT params:HASSUFFIX("HASKEY") {
        PRINT "F9 " + context + " config error: params must be a lexicon".
        RETURN FALSE.
    }

    LOCAL ok IS TRUE.
    FOR key IN requiredKeys {
        IF NOT params:HASKEY(key) {
            PRINT "F9 " + context + " config error: missing required key '"
                + key + "'".
            SET ok TO FALSE.
        }
    }
    RETURN ok.
}

FUNCTION f9_validate_launch_params {
    PARAMETER params.

    LOCAL requiredKeys IS LIST(
        "kOSIPU", "liftoffEngineTag", "mecoMass", "targetHeading",
        "turnSpeed", "pitchOmega", "stageSeparationDelay",
        "upperStageIgnitionDelay"
    ).
    IF NOT f9_validate_required_keys(params, requiredKeys, "launch") {
        RETURN FALSE.
    }

    LOCAL ok IS TRUE.
    IF params["mecoMass"] <= 0 {
        PRINT "F9 config error: mecoMass must be positive".
        SET ok TO FALSE.
    }
    IF (params["turnSpeed"] <= 0 OR params["pitchOmega"] <= 0) {
        PRINT "F9 config error: turnSpeed and pitchOmega must be positive".
        SET ok TO FALSE.
    }
    RETURN ok.
}

FUNCTION f9_validate_recovery_params {
    PARAMETER params.

    f9_apply_gfold_defaults(params).

    LOCAL requiredKeys IS LIST(
        "kOSIPU", "boostbackEngineTag", "entryEngineTag",
        "landingDecEngineTag", "landingEngineTag", "boostBackMass",
        "landingSiteUse", "enableBoostBack", "enableEntryBurn",
        "targetRoll", "altitudeOffset", "boostBackDelay", "entryBurnAlt",
        "entryVSpeed", "burnAlignTolerance", "ltrCtrlSpeedSamples",
        "ltrCtrlAOASamples",
        "ltrAeroSpeedSamples", "ltrAeroAltitudeSamples", "ltrCdFactor",
        "ltrClFactor", "ltrPredictMinStep", "ltrPredictMaxStep",
        "ltrPredictTMax", "aeroPitchKp", "aeroPitchKi", "aeroPitchKd",
        "aeroYawKp", "aeroYawKi", "aeroYawKd", "aeroMaxPitch",
        "aeroMaxYaw", "aeroTargetOffset", "QuadraticAOABase",
        "QuadraticAOADot", "landingBurnAltitude",
        "legDeploySpeed", "touchDownSpeed", "landingPhase2Time",
        "landingCutoffHeight", "boundsUpdatePeriod",
        "minLandingThrottleCommand", "DryMass", "gfold_engineSwitchTime",
        "gfold_pitRadius", "gfold_wallBuffer", "gfold_pitDepth",
        "gfold_planningTime",
        "gfold_thrustMargin", "gfold_accelerationSmoothing",
        "gfold_nodes", "gfold_maxSearchEvaluations", "gfold_lqrDt",
        "gfold_lqrLambda", "gfold_lqrBeta", "gfold_descentMaxSpeed",
        "gfold_descentTilt", "gfold_descentGlideSlope",
        "gfold_entryMaxSpeed", "gfold_entryTilt",
        "gfold_entryGlideSlope", "gfold_terminalTilt",
        "gfold_terminalTiltWindow", "landingPhase2Alt"
    ).
    IF NOT f9_validate_required_keys(params, requiredKeys, "recovery") {
        RETURN FALSE.
    }

    LOCAL ok IS TRUE.
    IF (params["landingSiteUse"] <> "geo"
        AND params["landingSiteUse"] <> "waypoint"
        AND params["landingSiteUse"] <> "vessel"
        AND params["landingSiteUse"] <> "none") {
        PRINT "F9 recovery config error: landingSiteUse must be none, geo, waypoint, or vessel".
        SET ok TO FALSE.
    } ELSE IF params["landingSiteUse"] = "geo" {
        IF NOT f9_validate_required_keys(
            params,
            LIST("landingSiteGeo"),
            "recovery"
        ) {
            SET ok TO FALSE.
        }
    } ELSE IF params["landingSiteUse"] = "waypoint" {
        IF NOT f9_validate_required_keys(
            params,
            LIST("landingSiteWaypoint"),
            "recovery"
        ) {
            SET ok TO FALSE.
        }
    } ELSE IF params["landingSiteUse"] = "vessel" {
        IF NOT f9_validate_required_keys(
            params,
            LIST("landingSiteVessel"),
            "recovery"
        ) {
            SET ok TO FALSE.
        }
    }
    IF params["boostBackMass"] <= 0 {
        PRINT "F9 config error: boostBackMass must be positive".
        SET ok TO FALSE.
    }

    IF params["aeroMaxPitch"] <= 0 {
        PRINT "F9 config error: aeroMaxPitch must be positive".
        SET ok TO FALSE.
    }
    IF params["aeroMaxYaw"] <= 0 {
        PRINT "F9 config error: aeroMaxYaw must be positive".
        SET ok TO FALSE.
    }
    IF (params["entryBurnAlt"] <= 0 OR params["entryVSpeed"] <= 0) {
        PRINT "F9 config error: entry burn altitude and speed must be positive".
        SET ok TO FALSE.
    }
    IF (params["ltrCtrlSpeedSamples"]:LENGTH = 0
        OR params["ltrCtrlSpeedSamples"]:LENGTH
            <> params["ltrCtrlAOASamples"]:LENGTH) {
        PRINT "F9 config error: LTR speed/AOA profiles must be nonempty and equal-length".
        SET ok TO FALSE.
    }
    IF (params["ltrAeroSpeedSamples"]:LENGTH = 0
        OR params["ltrAeroAltitudeSamples"]:LENGTH = 0) {
        PRINT "F9 config error: LTR aerodynamic sample axes must be nonempty".
        SET ok TO FALSE.
    }
    IF (params["ltrPredictMinStep"] < 0
        OR params["ltrPredictMaxStep"] <= 0
        OR params["ltrPredictMinStep"] > params["ltrPredictMaxStep"]
        OR params["ltrPredictTMax"] <= 0) {
        PRINT "F9 config error: invalid LTR predictor step/time limits".
        SET ok TO FALSE.
    }
    IF (params["touchDownSpeed"] < 0) {
        PRINT "F9 config error: invalid landing speed".
        SET ok TO FALSE.
    }
    IF params["DryMass"] <= 0 {
        PRINT "F9 config error: DryMass must be positive".
        SET ok TO FALSE.
    }
    IF (params["gfold_pitRadius"] < 0
        OR params["gfold_wallBuffer"] < 0
        OR params["gfold_pitDepth"] < 0
        OR params["gfold_wallBuffer"] > params["gfold_pitRadius"]
        OR (params["gfold_pitDepth"] > 0
            AND params["gfold_wallBuffer"] >= params["gfold_pitRadius"])) {
        PRINT "F9 config error: invalid GFOLD pit geometry".
        SET ok TO FALSE.
    }
    IF (params["gfold_planningTime"] <= 0
        OR params["gfold_engineSwitchTime"] < 0) {
        PRINT "F9 config error: invalid GFOLD planning/switch timing".
        SET ok TO FALSE.
    }
    IF (params["gfold_thrustMargin"] < 0
        OR params["gfold_thrustMargin"] >= 0.5) {
        PRINT "F9 config error: gfold_thrustMargin must be in [0, 0.5)".
        SET ok TO FALSE.
    }
    IF (params["gfold_accelerationSmoothing"] < 0
        OR params["gfold_accelerationSmoothing"] > 1) {
        PRINT "F9 config error: gfold_accelerationSmoothing must be in [0, 1]".
        SET ok TO FALSE.
    }
    IF (params["gfold_nodes"] < 4
        OR params["gfold_nodes"] > 200
        OR FLOOR(params["gfold_nodes"]) <> params["gfold_nodes"]
        OR params["gfold_maxSearchEvaluations"] < 1
        OR params["gfold_maxSearchEvaluations"] > 200
        OR FLOOR(params["gfold_maxSearchEvaluations"])
            <> params["gfold_maxSearchEvaluations"]) {
        PRINT "F9 config error: invalid GFOLD node/search count".
        SET ok TO FALSE.
    }
    IF (params["gfold_lqrDt"] <= 0
        OR params["gfold_lqrLambda"] <= 0
        OR params["gfold_lqrBeta"] < 0) {
        PRINT "F9 config error: invalid GFOLD LQR settings".
        SET ok TO FALSE.
    }
    IF (params["gfold_descentMaxSpeed"] <= 0
        OR params["gfold_entryMaxSpeed"] <= 0
        OR params["gfold_descentTilt"] < 0
        OR params["gfold_descentTilt"] > 90
        OR params["gfold_entryTilt"] < 0
        OR params["gfold_entryTilt"] > 90
        OR params["gfold_terminalTilt"] < 0
        OR params["gfold_terminalTilt"] > 90
        OR params["gfold_descentGlideSlope"] < 0
        OR params["gfold_descentGlideSlope"] >= 90
        OR params["gfold_entryGlideSlope"] < 0
        OR params["gfold_entryGlideSlope"] >= 90
        OR params["gfold_terminalTiltWindow"] < 0) {
        PRINT "F9 config error: invalid GFOLD speed/angle constraint".
        SET ok TO FALSE.
    }
    IF (params["landingBurnAltitude"] <= 0
        OR params["legDeploySpeed"] < 0
        OR params["landingCutoffHeight"] < 0
        OR params["boundsUpdatePeriod"] <= 0
        OR params["minLandingThrottleCommand"] < 0
        OR params["minLandingThrottleCommand"] > 1
        OR params["landingPhase2Time"] <= 0
        OR params["landingPhase2Alt"] <= params["landingCutoffHeight"]
        OR params["landingPhase2Alt"] >= params["landingBurnAltitude"]) {
        PRINT "F9 config error: invalid landing phase-2 threshold".
        SET ok TO FALSE.
    }
    IF (params:HASKEY("gfold_tfMin") AND params["gfold_tfMin"] <= 0) {
        PRINT "F9 config error: gfold_tfMin must be positive".
        SET ok TO FALSE.
    }
    IF (params:HASKEY("gfold_tfMax") AND params["gfold_tfMax"] <= 0) {
        PRINT "F9 config error: gfold_tfMax must be positive".
        SET ok TO FALSE.
    }
    IF (params:HASKEY("gfold_tfMin")
        AND params:HASKEY("gfold_tfMax")
        AND params["gfold_tfMin"] >= params["gfold_tfMax"]) {
        PRINT "F9 config error: gfold_tfMin must be below gfold_tfMax".
        SET ok TO FALSE.
    }
    RETURN ok.
}
