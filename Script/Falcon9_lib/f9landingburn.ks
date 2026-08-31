RUNONCEPATH("0:/Falcon9_lib/f9utility.ks").

// Fixed-time form of PEGLand's quadratic guidance. The public time-to-go is
// positive; PEGLand's polynomial uses a negative current time with touchdown
// at t = 0.
// Added AOA limit. This algorithm is equivalent to solve a optimization problem
// mimimize landing error, subject to AOA<AOALimit (when v_horizontal > V1 OR t > T1), and tilt<tileLimit (when v <= V1 AND t < T1), target height = end height
FUNCTION f9_quadratic_fixed_time {
    PARAMETER currentPosition.
    PARAMETER currentVelocity.
    PARAMETER targetPosition.
    PARAMETER targetVelocity.
    PARAMETER targetAcceleration.
    PARAMETER timeToGo.
    PARAMETER AOALimit.
    PARAMETER upAxis.
    PARAMETER g0.

    LOCAL qT IS -timeToGo.
    LOCAL qJ IS 24/qT^3*(currentPosition-targetPosition)
        - 6/qT^2*(currentVelocity+3*targetVelocity)
        - 6/qT*targetAcceleration.
    LOCAL qS IS -72/qT^4*(currentPosition-targetPosition)
        + 24/qT^3*(currentVelocity+2*targetVelocity)
        + 12/qT^2*targetAcceleration.
    
    LOCAL AI TO targetAcceleration + qJ*qT + 0.5*qS*qT^2.
    LOCAL CAI TO AI + g0 * upAxis.
    // // if Ttogo > T1: constrain AOA
    // if (timeToGo > 5 OR vxcl(upAxis, currentVelocity):mag > 2 AND vAng(CAI, -currentVelocity) >= AOALimit) {
    //     SET CAI TO (angleAxis(AOALimit, vcrs(-currentVelocity, CAI):normalized) * (-currentVelocity)):normalized.
    // }
    // // if Ttogo < T1, constraint tilt
    // else if (timeToGo <= 5 AND vxcl(upAxis, currentVelocity):mag <= 2 AND vAng(CAI, upAxis) >= AOALimit) {
    //     SET CAI TO (angleAxis(AOALimit, vcrs(upAxis, CAI):normalized) * (upAxis)):normalized.
    // }
    if (vAng(CAI, -currentVelocity) >= AOALimit) {
        SET CAI TO (angleAxis(AOALimit, vcrs(-currentVelocity, CAI):normalized) * (-currentVelocity)):normalized.
    }
    else {
        RETURN LEXICON(
            "withinAOA", TRUE,
            "qT", qT,
            "qJ", qJ,
            "qS", qS,
            "AI", AI,
            "cmdA", CAI,
            "RT", targetPosition
        ).
    }
    LOCAL RIz to vDot(currentPosition, upAxis).
    LOCAL RTz to vDot(targetPosition, upAxis).
    LOCAL VIz to vDot(currentVelocity, upAxis).
    LOCAL VTz to vDot(targetVelocity, upAxis).
    LOCAL ATz to vDot(targetAcceleration, upAxis).
    LOCAL qJz to 24/qT^3*(RIz-RTz) - 6/qT^2*(VIz+3*VTz) - 6/qT*ATz.
    LOCAL qSz to -72/qT^4*(RIz-RTz) + 24/qT^3*(VIz+2*VTz) + 12/qT^2*ATz.
    LOCAL CAIz TO ATz + qJz*qT + 0.5*qSz*qT^2 + g0.
    SET CAI TO CAIz * CAI / vDot(CAI, upAxis).
    SET AI TO CAI - g0 * upAxis.
    SET qJ TO 6/qT^2*(currentVelocity - targetVelocity) - 2/qT*(AI+2*targetAcceleration).
    SET qS TO -12/qT^3*(currentVelocity - targetVelocity) + 6/qT^2*(AI+targetAcceleration).
    LOCAL RT TO currentPosition - targetVelocity*qT - 0.5*targetAcceleration*qT^2 - qJ*qT^3/6 - qS*qT^4/24.
    RETURN LEXICON(
        "withinAOA", FALSE,
        "qT", qT,
        "qJ", qJ,
        "qS", qS,
        "AI", AI,
        "cmdA", CAI,
        "RT", RT
    ).
}

// Analytically propagate the polynomial used by quadratic guidance. The
// returned position is target-relative and the acceleration is specific thrust.
FUNCTION f9_quadratic_predict_state {
    PARAMETER quadraticPlan.
    PARAMETER currentPositionVec.
    PARAMETER currentVelocityVec.
    PARAMETER targetAccelerationVec.
    PARAMETER upAxisVec.
    PARAMETER gravityValue.
    PARAMETER lookaheadDuration.

    LOCAL planEpoch IS quadraticPlan["qT"].
    LOCAL planJerkVec IS quadraticPlan["qJ"].
    LOCAL planSnapVec IS quadraticPlan["qS"].
    LOCAL currentNetAccelerationVec IS quadraticPlan["AI"].
    LOCAL currentJerkVec IS planJerkVec + planSnapVec * planEpoch.
    LOCAL predictedPositionVec IS currentPositionVec
        + currentVelocityVec * lookaheadDuration
        + 0.5 * currentNetAccelerationVec * lookaheadDuration^2
        + currentJerkVec * lookaheadDuration^3 / 6
        + planSnapVec * lookaheadDuration^4 / 24.
    LOCAL predictedVelocityVec IS currentVelocityVec
        + currentNetAccelerationVec * lookaheadDuration
        + 0.5 * currentJerkVec * lookaheadDuration^2
        + planSnapVec * lookaheadDuration^3 / 6.
    LOCAL futurePlanEpoch IS planEpoch + lookaheadDuration.
    LOCAL predictedNetAccelerationVec IS targetAccelerationVec
        + planJerkVec * futurePlanEpoch
        + 0.5 * planSnapVec * futurePlanEpoch^2.
    RETURN LEXICON(
        "position", predictedPositionVec,
        "velocity", predictedVelocityVec,
        "control", predictedNetAccelerationVec
            + gravityValue * upAxisVec
    ).
}

// Approximate the rocket-equation mass change along the analytical quadratic
// control with a short trapezoidal quadrature. This runs only once per landing.
FUNCTION f9_quadratic_predict_mass {
    PARAMETER quadraticPlan.
    PARAMETER currentPositionVec.
    PARAMETER currentVelocityVec.
    PARAMETER targetAccelerationVec.
    PARAMETER upAxisVec.
    PARAMETER gravityValue.
    PARAMETER lookaheadDuration.
    PARAMETER currentMassValue.
    PARAMETER engineIspValue.

    LOCAL sampleIntervals IS 6.
    LOCAL sampleStep IS lookaheadDuration / sampleIntervals.
    LOCAL previousControlMagnitude IS quadraticPlan["cmdA"]:MAG.
    LOCAL integratedControl IS 0.
    FROM {
        LOCAL sampleIndex IS 1.
    } UNTIL sampleIndex > sampleIntervals STEP {
        SET sampleIndex TO sampleIndex + 1.
    } DO {
        LOCAL sampleDuration IS sampleStep * sampleIndex.
        LOCAL sampleState IS f9_quadratic_predict_state(
            quadraticPlan,
            currentPositionVec,
            currentVelocityVec,
            targetAccelerationVec,
            upAxisVec,
            gravityValue,
            sampleDuration
        ).
        LOCAL sampleControlMagnitude IS sampleState["control"]:MAG.
        SET integratedControl TO integratedControl
            + 0.5 * (previousControlMagnitude + sampleControlMagnitude)
                * sampleStep.
        SET previousControlMagnitude TO sampleControlMagnitude.
    }
    RETURN currentMassValue * EXP(
        -integratedControl / (engineIspValue * 9.80665)
    ).
}

FUNCTION f9_gfold_build_initialize_args {
    PARAMETER params.
    PARAMETER stateEpoch.
    PARAMETER predictedPositionVec.
    PARAMETER predictedVelocityVec.
    PARAMETER predictedMassValue.
    PARAMETER targetBodyVec.
    PARAMETER targetBasis.
    PARAMETER landingEngineLimits.

    LOCAL pitCenterVec IS targetBodyVec
        + params["gfold_pitDepth"] * targetBasis["up"].
    LOCAL initArguments IS LEXICON(
        "stateTime", stateEpoch,
        "position", predictedPositionVec,
        "velocity", predictedVelocityVec,
        "mass", predictedMassValue,
        "mu", SHIP:BODY:MU,
        "bodyRadius", SHIP:BODY:RADIUS,
        "bodySpin", SHIP:BODY:ANGULARVEL,
        "targetPosition", targetBodyVec,
        "targetVelocity", -params["touchDownSpeed"] * targetBasis["up"],
        "pitCenter", pitCenterVec,
        "fuelMass", predictedMassValue - params["DryMass"],
        "thrustMin1", landingEngineLimits["thrustMin"],
        "thrustMax1", landingEngineLimits["thrustMax"],
        "isp1", landingEngineLimits["isp"],
        "thrustMin2", landingEngineLimits["thrustMin"],
        "thrustMax2", landingEngineLimits["thrustMax"],
        "isp2", landingEngineLimits["isp"],
        "engineSwitchTime", 0,
        "descentMaxSpeed", params["gfold_descentMaxSpeed"],
        "descentTilt", params["gfold_descentTilt"],
        "descentGlideSlope", params["gfold_descentGlideSlope"],
        "entryMaxSpeed", params["gfold_entryMaxSpeed"],
        "entryTilt", params["gfold_entryTilt"],
        "entryGlideSlope", params["gfold_entryGlideSlope"],
        "terminalTilt", params["gfold_terminalTilt"],
        "terminalTiltWindow", params["gfold_terminalTiltWindow"],
        "pitRadius", params["gfold_pitRadius"],
        "wallBuffer", params["gfold_wallBuffer"],
        "pitDepth", params["gfold_pitDepth"],
        "nodes", params["gfold_nodes"],
        "maxSearchEvaluations", params["gfold_maxSearchEvaluations"],
        "lqrDt", params["gfold_lqrDt"],
        "lqrLambda", params["gfold_lqrLambda"],
        "lqrBeta", params["gfold_lqrBeta"]
    ).
    IF params:HASKEY("gfold_tfMin") {
        SET initArguments["tfMin"] TO params["gfold_tfMin"].
    }
    IF params:HASKEY("gfold_tfMax") {
        SET initArguments["tfMax"] TO params["gfold_tfMax"].
    }
    RETURN initArguments.
}

FUNCTION f9_landing_burn {
    PARAMETER params.
    PARAMETER targetContext.

    IF NOT targetContext["ok"] {
        f9_print_result("ERROR: no valid landing target").
        RETURN FALSE.
    }
    IF NOT ADDONS:HASADDON("LTR") {
        f9_print_result("ERROR: kOS-LTR addon is unavailable").
        RETURN FALSE.
    }

    f9_clear_guidance_display().
    pre_landingburn_hook().
    LOCAL landingEngines IS search_engine(params["landingEngineTag"]).
    IF landingEngines:LENGTH = 0 {
        f9_print_result("ERROR: no landing engines found").
        RETURN FALSE.
    }
    LOCAL decEngines IS search_engine(params["landingDecEngineTag"]).
    IF decEngines:LENGTH = 0 {
        SET decEngines TO landingEngines.
    }
    LOCAL shutDownEngines IS LIST().
    FOR decEngineRef IN decEngines {
        IF NOT decEngineRef:TAG:CONTAINS(params["landingEngineTag"]) {
            shutDownEngines:ADD(decEngineRef).
        }
    }
    LOCAL engineInfo1 IS get_engines_info(decEngines).
    LOCAL maxThrust1 IS engineInfo1["thrust"].
    LOCAL minThrottle1 IS engineInfo1["minthrottle"].
    LOCAL spoolUpTime1 IS engineInfo1["spooluptime"].
    LOCAL TiS1 IS engineInfo1["TiS"].
    LOCAL engineInfo2 IS get_engines_info(landingEngines).
    LOCAL maxThrust2 IS engineInfo2["thrust"].
    LOCAL minThrottle2 IS engineInfo2["minthrottle"].
    LOCAL TiS2 IS engineInfo2["TiS"].
    IF maxThrust1 <= 0 OR maxThrust2 <= 0 {
        f9_print_result("ERROR: landing engines have no thrust").
        RETURN FALSE.
    }
    IF NOT f9_initialize_ltr(params) {
        RETURN FALSE.
    }

    LOCAL gfoldAvailable IS ADDONS:HASADDON("GFOLD").
    LOCAL gfoldAddonRef IS 0.
    IF gfoldAvailable {
        SET gfoldAddonRef TO ADDONS:GFOLD.
    } ELSE {
        f9_print_result("WARNING: kOS-GFOLD unavailable; quadratic fallback armed").
    }
    LOCAL pitchPID IS PIDLOOP(
        params["aeroPitchKp"],
        params["aeroPitchKi"],
        params["aeroPitchKd"]
    ).
    LOCAL yawPID IS PIDLOOP(
        params["aeroYawKp"],
        params["aeroYawKi"],
        params["aeroYawKd"]
    ).

    f9_refresh_target(targetContext).
    LOCAL vecNormal IS f9_get_surface_normal().
    LOCAL bottomHeight IS f9_get_bottom_height(TiS2).
    LOCAL nextBoundsUpdate IS TIME:SECONDS + params["boundsUpdatePeriod"].
    LOCAL steeringTarget IS f9_get_aero_steering(SRFPROGRADE).
    LOCAL currentRadius IS (-SHIP:BODY:POSITION):MAG.
    LOCAL gravityMagnitude IS SHIP:BODY:MU / currentRadius^2.
    LOCAL filteredAccelerationVec IS -gravityMagnitude * UP:FOREVECTOR.
    LOCAL lastSurfaceVelocityVec IS SHIP:VELOCITY:SURFACE.
    LOCAL lastAccelerationEpoch IS TIME:SECONDS.

    LOCAL gfoldInitStarted IS FALSE.
    LOCAL gfoldInitRunning IS FALSE.
    LOCAL gfoldInitReady IS FALSE.
    LOCAL gfoldInitHandle IS -1.
    LOCAL gfoldReference IS 0.
    LOCAL gfoldInitEpoch IS 0.
    LOCAL gfoldInitStatus IS "WAIT AERO".
    IF NOT gfoldAvailable {
        SET gfoldInitStatus TO "UNAVAILABLE".
    }
    LOCAL frozenTargetVec IS V(0, 0, 0).
    LOCAL frozenBasis IS 0.
    LOCAL gfoldLandingMaxThrust IS maxThrust2.
    LOCAL gfoldLandingMinThrottle IS minThrottle2.
    LOCAL gfoldLandingTiS IS TiS2.

    SAS OFF.
    LOCK STEERING TO steeringTarget.
    LOCK THROTTLE TO 0.
    RCS ON.

    f9_print_at(11, "Phase: landing - aerodynamic guidance").
    f9_print_at(16, "Ignition: armed  Engines: inactive").
    LOCAL engineLitFlag IS FALSE.
    LOCAL engineLitEpoch IS 0.
    LOCAL bottomAltitude IS 999999999.
    UNTIL FALSE {
        LOCAL prediction IS f9_ltr_predict(
            params,
            targetContext,
            vecNormal,
            99999999999,
            99999999999,
            params["landingBurnAltitude"]
        ).
        f9_refresh_target(targetContext).
        LOCAL currentTargetRawVec IS f9_get_target_position(targetContext).
        IF TIME:SECONDS >= nextBoundsUpdate {
            SET bottomHeight TO f9_get_bottom_height(TiS2).
            SET nextBoundsUpdate TO TIME:SECONDS + params["boundsUpdatePeriod"].
        }
        SET bottomAltitude TO f9_get_bottom_altitude(
            currentTargetRawVec,
            bottomHeight
        ).

        LOCAL accelerationEpoch IS TIME:SECONDS.
        LOCAL accelerationDelta IS accelerationEpoch - lastAccelerationEpoch.
        IF accelerationDelta > 0.0001 {
            LOCAL measuredAccelerationVec IS
                (SHIP:VELOCITY:SURFACE - lastSurfaceVelocityVec)
                / accelerationDelta.
            LOCAL smoothingFraction IS params["gfold_accelerationSmoothing"].
            SET filteredAccelerationVec TO filteredAccelerationVec
                    * (1 - smoothingFraction)
                + measuredAccelerationVec * smoothingFraction.
            SET lastSurfaceVelocityVec TO SHIP:VELOCITY:SURFACE.
            SET lastAccelerationEpoch TO accelerationEpoch.
        }

        LOCAL currentTargetBodyVec IS currentTargetRawVec
            - SHIP:BODY:POSITION.
        LOCAL currentBasis IS f9_gfold_make_basis(
            currentTargetBodyVec,
            SHIP:BODY:ANGULARVEL
        ).
        LOCAL verticalRate IS VDOT(
            SHIP:VELOCITY:SURFACE,
            currentBasis["up"]
        ).
        LOCAL verticalAcceleration IS VDOT(
            filteredAccelerationVec,
            currentBasis["up"]
        ).
        LOCAL ignitionDuration IS f9_gfold_altitude_intercept(
            bottomAltitude,
            verticalRate,
            verticalAcceleration,
            params["landingBurnAltitude"]
        ).

        LOCAL spoolDuration IS spoolUpTime1.
        LOCAL currentBottomBodyVec IS f9_gfold_bottom_body_position(bottomHeight).
        LOCAL futureBottomBodyVec IS currentBottomBodyVec
            + SHIP:VELOCITY:SURFACE * spoolDuration
            + 0.5 * filteredAccelerationVec * spoolDuration^2.
        LOCAL futureHeight IS VDOT(
            futureBottomBodyVec - currentTargetBodyVec,
            currentBasis["up"]
        ).

        f9_print_target_position(targetContext).
        f9_print_recovery_vehicle().
        f9_print_at(
            6,
            "Altitude: " + ROUND(SHIP:ALTITUDE, 1)
                + " m  Bottom: " + ROUND(bottomAltitude, 1) + " m"
        ).
        f9_print_at(
            12,
            "Height now/future: " + ROUND(bottomAltitude, 1)
                + " / " + ROUND(futureHeight, 1) + " m"
        ).
        IF (futureHeight <= params["landingBurnAltitude"]
            AND NOT engineLitFlag) {
            f9_print_at(16, "Ignition condition: met").
            activate_engines(decEngines).
            SET engineLitFlag TO TRUE.
            SET engineLitEpoch TO TIME:SECONDS.
        }
        IF (engineLitFlag
            AND TIME:SECONDS >= engineLitEpoch + spoolUpTime1
            AND bottomAltitude <= params["landingBurnAltitude"]) {
            BREAK.
        }

        LOCAL desiredDirection IS SRFPROGRADE.
        IF f9_ltr_prediction_is_valid(prediction) {
            LOCAL impactError IS prediction["finalVecR"]
                - prediction["targetBodyPosition"].
            LOCAL normalizedError IS impactError
                / MAX(1, (SHIP:BODY:POSITION
                    + prediction["targetBodyPosition"]):MAG)
                * 180 / CONSTANT:PI
                / (1 + SHIP:Q * 101 / 40).
            LOCAL upAxis IS UP:FOREVECTOR.
            LOCAL downrangeAxis IS VXCL(
                upAxis,
                SHIP:VELOCITY:SURFACE
            ).
            IF downrangeAxis:MAG < 0.000001 {
                SET downrangeAxis TO NORTH:FOREVECTOR.
            } ELSE {
                SET downrangeAxis TO downrangeAxis:NORMALIZED.
            }
            LOCAL crossrangeAxis IS VCRS(upAxis, downrangeAxis):NORMALIZED.
            LOCAL rangeError IS VDOT(normalizedError, downrangeAxis).
            LOCAL crossError IS VDOT(normalizedError, crossrangeAxis).
            LOCAL pitchCommand IS pitchPID:UPDATE(TIME:SECONDS, rangeError).
            LOCAL yawCommand IS yawPID:UPDATE(TIME:SECONDS, crossError).
            SET pitchCommand TO MAX(
                -params["aeroMaxPitch"],
                MIN(params["aeroMaxPitch"], pitchCommand)
            ) + ADDONS:LTR:GetAOACmd(SHIP:AIRSPEED)["AOA"].
            SET yawCommand TO MAX(
                -params["aeroMaxYaw"],
                MIN(params["aeroMaxYaw"], yawCommand)
            ).
            f9_print_at(
                13,
                "Impact err D/X: " + ROUND(rangeError, 3)
                    + " / " + ROUND(crossError, 3) + " deg"
            ).
            f9_print_at(
                14,
                "Aero cmd P/Y: " + ROUND(pitchCommand, 2)
                    + " / " + ROUND(yawCommand, 2) + " deg"
            ).
            SET desiredDirection TO SRFPROGRADE
                * R(-pitchCommand, yawCommand, 0).
        } ELSE {
            f9_print_at(13, "LTR prediction: " + prediction["status"]).
            f9_print_at(14, "Aero command: surface retrograde").
        }
        IF NOT engineLitFlag {
            f9_print_at(16, "Ignition: armed  Engines: inactive").
        }
        SET steeringTarget TO f9_get_aero_steering(desiredDirection).
        WAIT 0.
    }

    LOCAL guidanceMode IS "quadratic".
    LOCAL gfoldWasActive IS FALSE.
    LOCAL gfoldReferenceEnd IS 0.
    f9_clear_guidance_display().
    f9_print_at(11, "Phase: landing - phase 1 quadratic").
    f9_print_at(16, "Engines: active  Continuous ignition").

    LOCK maxQuadraticAOA TO
        (params["QuadraticAOABase"] / (1 + SHIP:Q * 101 / 20)).
    SET currentRadius TO (-SHIP:BODY:POSITION):MAG.
    SET gravityMagnitude TO SHIP:BODY:MU / currentRadius^2.
    LOCK refAccStart TO maxThrust1 * (0.9 + 0.1 * minThrottle1)
        / SHIP:MASS * (-SHIP:VERTICALSPEED / MAX(0.01, SHIP:AIRSPEED))
        - gravityMagnitude.
    LOCK refAccEnd TO MAX(
        0.5,
        maxThrust2 * (0.15 + 0.85 * minThrottle2)
            / SHIP:MASS - gravityMagnitude
    ).
    f9_print_at(
        19,
        "AccStart = " + ROUND(refAccStart, 1)
            + " ; AccEnd = " + ROUND(refAccEnd, 1) + " m/s2"
    ).
    IF (guidanceMode = "quadratic" AND refAccStart <= 0) {
        f9_print_result("ERROR: invalid phase-1 acceleration").
        LOCK THROTTLE TO 0.
        deactivate_engines(decEngines).
        UNLOCK THROTTLE.
        UNLOCK STEERING.
        RETURN FALSE.
    }
    LOCAL refAccStartValue IS refAccStart.
    LOCAL refAccEndValue IS refAccEnd.
    LOCAL quadraticDuration IS -(
        -SHIP:VERTICALSPEED - params["touchDownSpeed"]
    ) * 2 / (refAccStartValue + refAccEndValue).
    LOCAL accelerationSlope IS
        (refAccStartValue - refAccEndValue) / quadraticDuration.
    LOCAL getQuadraticDuration IS {
        SET refAccStartValue TO refAccStart.
        SET refAccEndValue TO refAccEnd.
        RETURN -(
            -refAccEndValue
            + SQRT(
                refAccEndValue^2
                - 2 * accelerationSlope
                    * (-SHIP:VERTICALSPEED - params["touchDownSpeed"])
            )
        ) / accelerationSlope.
    }.
    LOCAL remainingDuration IS MAX(0.02, -quadraticDuration).

    // Shared throttle, steering, and engine routine.
    LOCAL done IS FALSE.
    LOCAL TiS IS TiS1.
    LOCAL activeMaxThrust IS maxThrust1.
    LOCAL activeMinThrottle IS minThrottle1.
    LOCAL accTarget IS maxThrust1 / SHIP:MASS * steeringTarget:FOREVECTOR.
    LOCAL throttleTarget IS 1.
    LOCAL hasShutdown IS FALSE.
    LOCK THROTTLE TO throttleTarget.
    WHEN (NOT done) THEN {
        LOCAL requestedFraction IS accTarget:MAG
            * SHIP:MASS / activeMaxThrust.
        SET throttleTarget TO f9_continuous_throttle(
            requestedFraction,
            activeMinThrottle,
            params["minLandingThrottleCommand"]
        ).
        SET steeringTarget TO f9_get_target_steering(
            accTarget,
            TiS,
            params["targetRoll"],
            vecNormal
        ).
        RETURN TRUE.
    }

    UNTIL SHIP:VERTICALSPEED >= 0
        OR bottomAltitude <= params["landingCutoffHeight"] {
        f9_refresh_target(targetContext).
        LOCAL landingTargetRawVec IS f9_get_target_position(targetContext).
        IF (SHIP:AIRSPEED < params["legDeploySpeed"] AND NOT GEAR) {
            GEAR ON.
        }
        IF TIME:SECONDS >= nextBoundsUpdate {
            SET bottomHeight TO f9_get_bottom_height(TiS2).
            SET nextBoundsUpdate TO TIME:SECONDS + params["boundsUpdatePeriod"].
        }
        SET bottomAltitude TO f9_get_bottom_altitude(
            landingTargetRawVec,
            bottomHeight
        ).
        SET currentRadius TO (-SHIP:BODY:POSITION):MAG.
        SET gravityMagnitude TO SHIP:BODY:MU / currentRadius^2.

        LOCAL poweredAccelerationEpoch IS TIME:SECONDS.
        LOCAL poweredAccelerationDelta IS poweredAccelerationEpoch
            - lastAccelerationEpoch.
        IF poweredAccelerationDelta > 0.0001 {
            LOCAL poweredMeasuredAccelerationVec IS
                (SHIP:VELOCITY:SURFACE - lastSurfaceVelocityVec)
                / poweredAccelerationDelta.
            LOCAL poweredSmoothingFraction IS
                params["gfold_accelerationSmoothing"].
            SET filteredAccelerationVec TO filteredAccelerationVec
                    * (1 - poweredSmoothingFraction)
                + poweredMeasuredAccelerationVec
                    * poweredSmoothingFraction.
            SET lastSurfaceVelocityVec TO SHIP:VELOCITY:SURFACE.
            SET lastAccelerationEpoch TO poweredAccelerationEpoch.
        }
        LOCAL actualThrustDirectionVec IS
            (SHIP:FACING * TiS:INVERSE):FOREVECTOR.
        LOCAL achievedThrustAccelerationVec IS actualThrustDirectionVec
            * SHIP:THRUST / MAX(0.001, SHIP:MASS).
        LOCAL modeledGravityVec IS -gravityMagnitude * UP:FOREVECTOR.
        LOCAL aerodynamicDisturbanceVec IS filteredAccelerationVec
            - modeledGravityVec - achievedThrustAccelerationVec.
        LOCAL landingAvailableAccelerationValue IS maxThrust2
            / MAX(0.001, SHIP:MASS).
        LOCAL aerodynamicDisturbanceRatio IS
            aerodynamicDisturbanceVec:MAG
            / MAX(0.001, landingAvailableAccelerationValue).

        IF (gfoldInitRunning
            AND gfoldAddonRef:CheckTask(gfoldInitHandle)) {
            SET gfoldReference TO gfoldAddonRef:GetTaskResult(gfoldInitHandle).
            SET gfoldInitRunning TO FALSE.
            IF gfoldReference["ok"] {
                SET gfoldInitReady TO TRUE.
                SET gfoldInitStatus TO "READY".
            } ELSE {
                SET gfoldInitStatus TO "FAIL " + gfoldReference["status"].
            }
        }

        IF (guidanceMode = "quadratic" AND gfoldInitReady
            AND TIME:SECONDS >= gfoldInitEpoch) {
            LOCAL preparedReferenceEnd IS gfoldReference["epoch"]
                + gfoldReference["tf"].
            LOCAL handoffGraceDuration IS MAX(
                0.25,
                2 * params["gfold_lqrDt"]
            ).
            IF (TIME:SECONDS <= preparedReferenceEnd
                AND TIME:SECONDS <= gfoldInitEpoch + handoffGraceDuration) {
                SET gfoldReferenceEnd TO preparedReferenceEnd.
                SET guidanceMode TO "gfold".
                SET gfoldWasActive TO TRUE.
                SET gfoldInitStatus TO "TRACK".
                IF NOT hasShutdown {
                    deactivate_engines(shutDownEngines).
                    activate_engines(landingEngines).
                    SET hasShutdown TO TRUE.
                }
                SET TiS TO gfoldLandingTiS.
                SET activeMaxThrust TO gfoldLandingMaxThrust.
                SET activeMinThrottle TO gfoldLandingMinThrottle.
                f9_print_at(11, "Phase: landing - phase 1 gfold").
            } ELSE {
                SET gfoldInitReady TO FALSE.
                SET gfoldInitStatus TO "FAIL LATE".
            }
        }

        LOCAL displayedPositionError IS 0.
        LOCAL gfoldTelemetryReady IS FALSE.
        LOCAL referenceAltitudeValue IS 0.
        LOCAL referenceDescentValue IS 0.
        LOCAL referenceAccelerationValue IS 0.
        LOCAL altitudeErrorValue IS 0.
        LOCAL descentErrorValue IS 0.
        IF guidanceMode = "gfold" {
            SET remainingDuration TO gfoldReferenceEnd - TIME:SECONDS.
            IF (remainingDuration <= params["landingPhase2Time"]
                OR bottomAltitude <= params["landingPhase2Alt"]
                OR TIME:SECONDS < gfoldReference["epoch"]
                OR TIME:SECONDS > gfoldReferenceEnd) {
                SET guidanceMode TO "terminal".
                f9_print_at(11, "Phase: landing - phase 2 terminal").
            }
        }

        IF (guidanceMode = "terminal" AND NOT hasShutdown) {
            deactivate_engines(shutDownEngines).
            activate_engines(landingEngines).
            SET TiS TO TiS2.
            SET activeMaxThrust TO maxThrust2.
            SET activeMinThrottle TO minThrottle2.
            SET hasShutdown TO TRUE.
        }

        IF guidanceMode = "gfold" {
            LOCAL trackedState IS f9_gfold_virtual_state(
                targetContext,
                bottomHeight,
                frozenTargetVec,
                frozenBasis
            ).
            LOCAL referenceState IS gfoldAddonRef:GetRefState(LEXICON(
                "reference", gfoldReference,
                "time", TIME:SECONDS
            )).
            LOCAL positionErrorVec IS referenceState["position"]
                - trackedState["position"].
            LOCAL velocityErrorVec IS referenceState["velocity"]
                - trackedState["velocity"].
            LOCAL correctionVec IS f9_gfold_gain_control(
                gfoldReference["K"],
                positionErrorVec,
                velocityErrorVec
            ).
            LOCAL frozenCommandVec IS referenceState["control"]
                + correctionVec.
            SET accTarget TO f9_gfold_map_vector(
                frozenCommandVec,
                frozenBasis,
                trackedState["currentBasis"]
            ).
            SET displayedPositionError TO positionErrorVec:MAG.
            SET referenceAltitudeValue TO VDOT(
                referenceState["position"] - frozenTargetVec,
                frozenBasis["up"]
            ).
            SET referenceDescentValue TO VDOT(
                referenceState["velocity"],
                frozenBasis["up"]
            ).
            SET referenceAccelerationValue TO
                referenceState["control"]:MAG.
            SET altitudeErrorValue TO VDOT(
                positionErrorVec,
                frozenBasis["up"]
            ).
            SET descentErrorValue TO VDOT(
                velocityErrorVec,
                frozenBasis["up"]
            ).
            SET gfoldTelemetryReady TO TRUE.
        } ELSE {
            IF NOT gfoldWasActive {
                SET remainingDuration TO MAX(0.02, getQuadraticDuration()).
            } ELSE {
                SET remainingDuration TO MAX(
                    0.02,
                    gfoldReferenceEnd - TIME:SECONDS
                ).
            }
            IF (guidanceMode = "quadratic"
                AND (remainingDuration <= params["landingPhase2Time"]
                    OR bottomAltitude <= params["landingPhase2Alt"])) {
                SET guidanceMode TO "terminal".
                f9_print_at(11, "Phase: landing - phase 2 terminal").
                IF NOT hasShutdown {
                    deactivate_engines(shutDownEngines).
                    activate_engines(landingEngines).
                    SET TiS TO TiS2.
                    SET activeMaxThrust TO maxThrust2.
                    SET activeMinThrottle TO minThrottle2.
                    SET hasShutdown TO TRUE.
                }
            }

            LOCAL upAxis IS UP:FOREVECTOR.
            LOCAL relativePosition IS -landingTargetRawVec
                - bottomHeight * upAxis.
            LOCAL relativeVelocity IS SHIP:VELOCITY:SURFACE.
            LOCAL quadraticTargetPosition IS V(0, 0, 0).
            LOCAL targetVelocityVec IS -params["touchDownSpeed"] * upAxis.
            LOCAL targetAccelerationVec IS refAccEnd * upAxis.
            LOCAL maxAoaValue IS 0.
            IF guidanceMode = "quadratic" {
                SET maxAoaValue TO MIN(
                    maxQuadraticAOA,
                    params["QuadraticAOADot"] * remainingDuration
                ).
            }
            LOCAL quadraticControl IS f9_quadratic_fixed_time(
                relativePosition,
                relativeVelocity,
                quadraticTargetPosition,
                targetVelocityVec,
                targetAccelerationVec,
                remainingDuration,
                maxAoaValue,
                upAxis,
                gravityMagnitude
            ).
            IF guidanceMode = "terminal" {
                // Preserve the original upward-biased retrograde terminal command.
                SET accTarget TO quadraticControl["cmdA"]:MAG
                    * (-SHIP:VELOCITY:SURFACE
                        + 10 * UP:FOREVECTOR):NORMALIZED.
            } ELSE {
                SET accTarget TO quadraticControl["cmdA"].
            }
            SET displayedPositionError TO
                (quadraticControl["RT"] - quadraticTargetPosition):MAG.

            IF (guidanceMode = "quadratic"
                AND gfoldAvailable
                AND NOT gfoldInitStarted
                AND aerodynamicDisturbanceRatio <= params["gfold_epsilon"]
                AND remainingDuration > params["gfold_planningTime"]
                    + params["landingPhase2Time"]
                AND SHIP:MASS > params["DryMass"]) {
                LOCAL handoffDuration IS params["gfold_planningTime"].
                LOCAL handoffTargetBodyVec IS landingTargetRawVec
                    - SHIP:BODY:POSITION.
                LOCAL handoffBasis IS f9_gfold_make_basis(
                    handoffTargetBodyVec,
                    SHIP:BODY:ANGULARVEL
                ).
                LOCAL predictedQuadraticState IS
                    f9_quadratic_predict_state(
                        quadraticControl,
                        relativePosition,
                        relativeVelocity,
                        targetAccelerationVec,
                        upAxis,
                        gravityMagnitude,
                        handoffDuration
                    ).
                LOCAL predictionEngineInfo IS get_engines_info(decEngines).
                IF hasShutdown {
                    SET predictionEngineInfo TO
                        get_engines_info(landingEngines).
                }
                LOCAL landingEngineInfoNow IS
                    get_engines_info(landingEngines).
                IF (predictionEngineInfo["ISP"] > 0
                    AND landingEngineInfoNow["thrust"] > 0) {
                    LOCAL predictedMassValue IS
                        f9_quadratic_predict_mass(
                            quadraticControl,
                            relativePosition,
                            relativeVelocity,
                            targetAccelerationVec,
                            upAxis,
                            gravityMagnitude,
                            handoffDuration,
                            SHIP:MASS,
                            predictionEngineInfo["ISP"]
                        ).
                    IF predictedMassValue > params["DryMass"] {
                        SET gfoldInitStarted TO TRUE.
                        SET gfoldInitRunning TO TRUE.
                        SET gfoldInitStatus TO "RUN".
                        SET gfoldInitEpoch TO TIME:SECONDS
                            + handoffDuration.
                        SET frozenTargetVec TO handoffTargetBodyVec.
                        SET frozenBasis TO handoffBasis.
                        LOCAL predictedPositionVec IS frozenTargetVec
                            + f9_gfold_map_vector(
                                predictedQuadraticState["position"],
                                handoffBasis,
                                frozenBasis
                            ).
                        LOCAL predictedVelocityVec IS f9_gfold_map_vector(
                            predictedQuadraticState["velocity"],
                            handoffBasis,
                            frozenBasis
                        ).
                        LOCAL landingEngineLimitsNow IS
                            f9_gfold_engine_limits(
                                landingEngineInfoNow,
                                params["gfold_thrustMargin"]
                            ).
                        SET gfoldLandingMaxThrust TO
                            landingEngineInfoNow["thrust"].
                        SET gfoldLandingMinThrottle TO
                            landingEngineInfoNow["minthrottle"].
                        SET gfoldLandingTiS TO landingEngineInfoNow["TiS"].
                        LOCAL initArguments IS
                            f9_gfold_build_initialize_args(
                                params,
                                gfoldInitEpoch,
                                predictedPositionVec,
                                predictedVelocityVec,
                                predictedMassValue,
                                frozenTargetVec,
                                frozenBasis,
                                landingEngineLimitsNow
                            ).
                        SET gfoldInitHandle TO
                            gfoldAddonRef:AsyncInitialize(initArguments).
                    }
                }
            }

            // Preserve the original sampled-demand engine-switch logic when
            // phase 1 is running on the quadratic fallback.
            IF (guidanceMode = "quadratic" AND NOT hasShutdown) {
                LOCAL thrustCutoff IS maxThrust2
                    * (0.85 + 0.15 * minThrottle2).
                LOCAL timeSamples IS LIST().
                mlinspace(quadraticControl["qT"], 0, 5, timeSamples).
                LOCAL shutdownFlag IS TRUE.
                FOR sampleEpochOffset IN timeSamples {
                    LOCAL commandThrust IS (
                        targetAccelerationVec
                        + quadraticControl["qJ"] * sampleEpochOffset
                        + 0.5 * quadraticControl["qS"]
                            * sampleEpochOffset^2
                        + upAxis * gravityMagnitude
                    ):MAG * SHIP:MASS.
                    IF commandThrust > thrustCutoff {
                        SET shutdownFlag TO FALSE.
                        BREAK.
                    }
                }
                IF shutdownFlag {
                    deactivate_engines(shutDownEngines).
                    activate_engines(landingEngines).
                    SET TiS TO TiS2.
                    SET activeMaxThrust TO maxThrust2.
                    SET activeMinThrottle TO minThrottle2.
                    SET hasShutdown TO TRUE.
                }
            }
        }

        f9_print_target_position(targetContext).
        f9_print_recovery_vehicle().
        f9_print_at(
            6,
            "Altitude: " + ROUND(SHIP:ALTITUDE, 1)
                + " m  Bottom: " + ROUND(bottomAltitude, 1) + " m"
        ).
        f9_print_at(12, "Time to go: " + ROUND(remainingDuration, 2) + " s").
        IF gfoldTelemetryReady {
            f9_print_at(
                13,
                "Ref H/Vz: " + ROUND(referenceAltitudeValue, 2)
                    + " / " + ROUND(referenceDescentValue, 2)
            ).
            f9_print_at(
                14,
                "A ref/cmd: " + ROUND(referenceAccelerationValue, 2)
                    + " / " + ROUND(accTarget:MAG, 2) + " m/s2"
            ).
            f9_print_at(
                15,
                "Err R-A H/Vz: " + ROUND(altitudeErrorValue, 2)
                    + " / " + ROUND(descentErrorValue, 2)
            ).
            f9_print_at(16, "GFOLD ref: hybrid handoff (fixed)").
            f9_print_at(
                17,
                "Total position error: "
                    + ROUND(displayedPositionError, 2) + " m"
            ).
            IF hasShutdown {
                f9_print_at(18, "GFOLD engine set: final").
            } ELSE {
                f9_print_at(18, "GFOLD engine set: deceleration").
            }
        } ELSE {
            f9_print_at(
                13,
                "Position error: " + ROUND(displayedPositionError, 2) + " m"
            ).
            f9_print_at(
                14,
                "Command acceleration: "
                    + ROUND(accTarget:MAG, 2) + " m/s2"
            ).
            f9_print_at(
                15,
                "Aero/GFOLD: "
                    + ROUND(aerodynamicDisturbanceRatio, 3)
                    + " / " + gfoldInitStatus
            ).
            IF hasShutdown {
                f9_print_at(16, "Engine set: final").
            } ELSE {
                f9_print_at(16, "Engine set: deceleration").
            }
            f9_print_at(
                17,
                "Guidance: " + guidanceMode + "  Vz: "
                    + ROUND(SHIP:VERTICALSPEED, 2) + " m/s"
            ).
            f9_print_at(18, "").
        }
        WAIT 0.
    }

    f9_print_at(11, "Phase: landing - cutoff").
    f9_print_at(16, "Engines: cutoff  Throttle: 0.00").
    deactivate_engines(decEngines).
    deactivate_engines(landingEngines).
    SET done TO TRUE.
    LOCK THROTTLE TO 0.
    LOCK STEERING TO LOOKDIRUP(
        UP:FOREVECTOR,
        (SHIP:FACING * TiS:INVERSE):TOPVECTOR
    ) * TiS.
    WAIT 5.
    UNLOCK THROTTLE.
    UNLOCK STEERING.
    RETURN TRUE.
}
