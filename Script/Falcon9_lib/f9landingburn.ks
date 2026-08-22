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
    for _eng in decEngines {
        IF NOT _eng:tag:contains(params["landingEngineTag"]) {
            shutDownEngines:add(_eng).
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
    LOCAL targetPosition IS f9_get_aero_target_position(
        params,
        targetContext,
        vecNormal
    ).
    LOCAL bottomHeight IS f9_get_bottom_height(TiS2).
    LOCAL nextBoundsUpdate IS TIME:SECONDS + params["boundsUpdatePeriod"].
    LOCAL steeringTarget IS f9_get_aero_steering(srfPrograde).
    SAS OFF.
    LOCK STEERING TO steeringTarget.
    LOCK THROTTLE TO 0.
    RCS ON.

    f9_print_at(11, "Phase: landing - aerodynamic guidance").
    f9_print_at(16, "Ignition: armed  Engines: inactive").
    LOCAL _engineLitFlag IS FALSE.
    LOCAL _engineLitTime IS 0.
    UNTIL FALSE {
        LOCAL prediction IS f9_ltr_predict(
            params,
            targetContext,
            vecNormal,
            99999999999,
            99999999999,
            params["landingBurnAltitude"]
        ).
        SET targetPosition TO prediction["targetPosition"].
        IF TIME:SECONDS >= nextBoundsUpdate {
            SET bottomHeight TO f9_get_bottom_height(TiS2).
            SET nextBoundsUpdate TO TIME:SECONDS + params["boundsUpdatePeriod"].
        }

        LOCAL bottomAltitude IS f9_get_bottom_altitude(
            targetPosition,
            bottomHeight
        ).
        LOCAL radius IS (-SHIP:BODY:POSITION):MAG.
        LOCAL g IS SHIP:BODY:MU / radius^2.

        LOCAL spoolTime IS engineInfo1["spooluptime"].
        LOCAL futureHeight IS bottomAltitude
            + SHIP:VERTICALSPEED * spoolTime
            - 0.5 * g * spoolTime^2.

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
        IF (futureHeight <= params["landingBurnAltitude"] AND (NOT _engineLitFlag)) {
            f9_print_at(16, "Ignition condition: met").
            activate_engines(decEngines).
            SET _engineLitFlag TO TRUE.
            SET _engineLitTime TO time:seconds.
        }
        IF (_engineLitFlag AND time:seconds >= _engineLitTime + spoolUpTime1) {
            BREAK.
        }

        LOCAL desiredDirection IS srfPrograde.
        IF f9_ltr_prediction_is_valid(prediction) {
            LOCAL impactError IS prediction["finalVecR"]
                - prediction["targetBodyPosition"].
            LOCAL normalizedError IS impactError
                / MAX(1, (ship:body:position + prediction["targetBodyPosition"]):MAG)
                * 180 / constant:pi
                / (1 + ship:q * 101 / 40).  // TO deg, normalized by dynamic pressure
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
            ) + addons:ltr:GetAOACmd(ship:airspeed)["AOA"].
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

            SET desiredDirection TO srfPrograde * R(-pitchCommand, yawCommand, 0).
        } ELSE {
            f9_print_at(13, "LTR prediction: " + prediction["status"]).
            f9_print_at(14, "Aero command: surface retrograde").
        }
        f9_print_at(16, "Ignition: armed  Engines: inactive").
        SET steeringTarget TO f9_get_aero_steering(desiredDirection).
        WAIT 0.
    }

    f9_clear_guidance_display().
    f9_print_at(11, "Phase: landing - phase 1").
    f9_print_at(16, "Engines: active  Continuous ignition").

    LOCAL landingPhase IS 1.
    LOCAL bottomAltitude IS f9_get_bottom_altitude(
        targetPosition,
        bottomHeight
    ).
    LOCK maxQuadraticAOA TO (params["QuadraticAOABase"]/(1+ship:q*101/20)).
    LOCAL radius IS (-SHIP:BODY:POSITION):MAG.
    LOCAL g IS SHIP:BODY:MU / radius^2.
    LOCK refAccStart TO maxThrust1 * (0.9 + 0.1*minThrottle1) / SHIP:MASS * (-ship:verticalspeed / ship:airspeed) - g.
    LOCK refAccEnd TO max(0.5, maxThrust2 * (0.15 + 0.85*minThrottle2) / SHIP:MASS - g).
    f9_print_at(
        19,
        "AccStart = " + round(refAccStart, 1)
        + " ; AccEnd = " + round(refAccEnd, 1) + " m/s2"
    ).
    if (refAccStart <= 0) {
        f9_print_result("ERROR: invalid phase-1 acceleration").
        LOCK THROTTLE TO 0.
        deactivate_engines(decEngines).
        UNLOCK THROTTLE.
        UNLOCK STEERING.
        RETURN FALSE.
    }
    LOCAL _refAccStart TO refAccStart.
    LOCAL _refAccEnd TO refAccEnd.
    LOCAL _T to -(-ship:verticalspeed - params["touchDownSpeed"]) * 2 / (_refAccStart + _refAccEnd).
    LOCAL _accDot to (_refAccStart - _refAccEnd) / _T.
    LOCAL _getTimeToGo to {
        SET _refAccStart TO refAccStart.
        SET _refAccEnd TO refAccEnd.
        return -(-_refAccEnd+sqrt(_refAccEnd*_refAccEnd-2*_accDot*(-ship:verticalSpeed-params["touchDownSpeed"])))/_accDot.
    }.
    LOCAL timeToGo IS -_T.

    // throttle, steering and engine routine
    LOCAL done IS FALSE.
    LOCAL TiS IS TiS1.
    LOCAL _maxThrust IS maxThrust1.
    LOCAL minThrottle IS minThrottle1.
    LOCAL accTarget IS maxThrust1/SHIP:MASS * steeringTarget:forevector.
    LOCAL throttleTarget IS 1.
    LOCAL hasShutdown IS FALSE.
    LOCK THROTTLE TO throttleTarget.
    when (not done) then {
        LOCAL requestedFraction IS accTarget:mag * ship:mass / _maxThrust.
        SET throttleTarget TO f9_continuous_throttle(
            requestedFraction,
            minThrottle,
            params["minLandingThrottleCommand"]
        ).
        SET steeringTarget TO f9_get_target_steering(
            accTarget,
            TiS,
            params["targetRoll"],
            vecNormal
        ).
        return true.
    }

    UNTIL SHIP:VERTICALSPEED >= 0
        OR bottomAltitude <= params["landingCutoffHeight"] {
        f9_refresh_target(targetContext).
        SET targetPosition TO f9_get_target_position(targetContext).
        if (ship:airspeed < params["legDeploySpeed"] and (not GEAR)) GEAR ON.
        IF TIME:SECONDS >= nextBoundsUpdate {
            SET bottomHeight TO f9_get_bottom_height(TiS2).
            SET nextBoundsUpdate TO TIME:SECONDS + params["boundsUpdatePeriod"].
        }

        SET bottomAltitude TO f9_get_bottom_altitude(
            targetPosition,
            bottomHeight
        ).

        SET timeToGo TO MAX(0.02, _getTimeToGo()).
        f9_print_target_position(targetContext).
        f9_print_recovery_vehicle().
        f9_print_at(
            6,
            "Altitude: " + ROUND(SHIP:ALTITUDE, 1)
                + " m  Bottom: " + ROUND(bottomAltitude, 1) + " m"
        ).
        f9_print_at(12, "Time to go: " + ROUND(timeToGo, 2) + " s").
        IF (timeToGo <= params["landingPhase2Time"]) {
            f9_print_at(11, "Phase: landing - phase 2").
            SET landingPhase TO 2.
        }

        LOCAL upAxis IS UP:FOREVECTOR.
        LOCAL relativePosition IS -targetPosition - bottomHeight * upAxis.
        LOCAL relativeVelocity IS SHIP:VELOCITY:SURFACE.
        LOCAL quadraticTargetPosition IS V(0, 0, 0).
        LOCAL targetVelocity IS -params["touchDownSpeed"] * upAxis.
        LOCAL targetAcceleration IS refAccEnd * upAxis.
        LOCAL _maxAOA TO 0.
        IF (landingPhase = 1) SET _maxAOA TO min(maxQuadraticAOA, params["QuadraticAOADot"]*timeToGo).
        ELSE SET _maxAOA TO 0.
        LOCAL quadraticControl IS f9_quadratic_fixed_time(
            relativePosition,
            relativeVelocity,
            quadraticTargetPosition,
            targetVelocity,
            targetAcceleration,
            timeToGo,
            _maxAOA,
            upAxis,
            g
        ).
        IF landingPhase = 2 {
            // Need to add up additional vertical component to avoid divergence when approaching ground
            SET accTarget TO quadraticControl["cmdA"]:mag * (-ship:velocity:surface + 10*up:forevector):normalized.
        }
        ELSE SET accTarget TO quadraticControl["cmdA"].
        // set _drawAcc to vecDraw(V(0,0,0), accelerationShip * 5, RGB(0, 255, 0), "Acc", 1, true).

        // Shutdown decelerate engines logic: Sample N points in the trajectory to test if they are all lower than thrust cutoff
        if (NOT hasShutdown) {
            LOCAL thrustCutoff IS maxThrust2 * (0.85 + 0.15*minThrottle2).
            LOCAL timeSeq IS LIST().
            mlinspace(quadraticControl["qT"], 0, 5, timeSeq).
            LOCAL shutdownFlag TO TRUE.
            for _qT in timeSeq {
                LOCAL cmdThrust TO (targetAcceleration + quadraticControl["qJ"]*_qT + 0.5*quadraticControl["qS"]*_qT^2 + upAxis*g):mag * ship:mass.
                if (cmdThrust > thrustCutoff) {
                    SET shutdownFlag TO FALSE.
                    BREAK.
                }
            }
            if (shutdownFlag) {
                deactivate_engines(shutDownEngines).
                SET TiS TO TiS2.
                SET _maxThrust TO maxThrust2.
                SET minThrottle TO minThrottle2.
                SET hasShutdown TO TRUE.
            }
        }

        f9_print_at(
            13,
            "Position error: " + ROUND((quadraticControl["RT"]-quadraticTargetPosition):mag, 2) + " m"
        ).
        f9_print_at(
            14,
            "Command acceleration: "
                + ROUND(accTarget:MAG, 2) + " m/s2"
        ).
        f9_print_at(
            15,
            "Throttle req/cmd: " + ROUND(accTarget:MAG*ship:mass/_maxThrust, 3)
                + " / " + ROUND(throttleTarget, 3)
        ).
        f9_print_at(
            16,
            "Engines: active  Throttle: "
                + ROUND(SHIP:CONTROL:MAINTHROTTLE, 2)
        ).
        f9_print_at(
            17,
            "Local vertical speed: "
                + ROUND(ship:verticalspeed, 2) + " m/s"
        ).
        WAIT 0.
    }

    f9_print_at(11, "Phase: landing - cutoff").
    f9_print_at(16, "Engines: cutoff  Throttle: 0.00").
    deactivate_engines(decEngines).
    deactivate_engines(landingEngines).
    SET done TO TRUE.
    LOCK THROTTLE TO 0.
    LOCK steering TO lookDirUp(up:forevector, (ship:facing*TiS:inverse):topvector) * TiS.
    WAIT 5.  // 5 seconds to hold rocket upward
    UNLOCK THROTTLE.
    UNLOCK STEERING.
    RETURN TRUE.
}
