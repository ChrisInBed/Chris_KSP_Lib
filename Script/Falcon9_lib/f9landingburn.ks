RUNONCEPATH("0:/Falcon9_lib/params.ks").
RUNONCEPATH("0:/Falcon9_lib/f9utility.ks").

// Fixed-time form of PEGLand's quadratic guidance. The public time-to-go is
// positive; PEGLand's polynomial uses a negative current time with touchdown
// at t = 0.
// Added AOA limit. This algorithm is equivalent to solve a optimization problem
// mimimize landing error, subject to AOA<AOALimit, target height = end height 
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
    if (vAng(CAI, -currentVelocity) < AOALimit) {
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
    SET CAI TO (angleAxis(AOALimit, vcrs(-currentVelocity, CAI):normalized) * (-currentVelocity)):normalized.
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
    LOCAL landingEngines IS search_engine(params["landingEngineTag"]).
    IF landingEngines:LENGTH = 0 {
        f9_print_result("ERROR: no landing engines found").
        RETURN FALSE.
    }
    LOCAL engineInfo IS get_engines_info(landingEngines).
    LOCAL _maxThrust IS engineInfo["thrust"].
    LOCAL minThrottle IS engineInfo["minthrottle"].
    LOCAL TiS IS engineInfo["TiS"].
    IF _maxThrust <= 0 {
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
    LOCAL bottomHeight IS f9_get_bottom_height(TiS).
    LOCAL nextBoundsUpdate IS TIME:SECONDS + params["boundsUpdatePeriod"].
    LOCAL steeringTarget IS f9_get_aero_steering(srfPrograde).
    SAS OFF.
    LOCK STEERING TO steeringTarget.
    LOCK THROTTLE TO 0.
    RCS ON.

    f9_print_at(11, "Phase: landing - aerodynamic guidance").
    f9_print_at(16, "Ignition: armed  Engines: inactive").
    UNTIL FALSE {
        LOCAL prediction IS f9_ltr_predict(
            params,
            targetContext,
            vecNormal
        ).
        SET targetPosition TO prediction["targetPosition"].
        IF TIME:SECONDS >= nextBoundsUpdate {
            SET bottomHeight TO f9_get_bottom_height(TiS).
            SET nextBoundsUpdate TO TIME:SECONDS + params["boundsUpdatePeriod"].
        }

        LOCAL bottomAltitude IS f9_get_bottom_altitude(
            targetPosition,
            bottomHeight
        ).
        LOCAL radius IS (-SHIP:BODY:POSITION):MAG.
        LOCAL g IS SHIP:BODY:MU / radius^2.
        LOCAL referenceAcceleration IS
            ((1 + minThrottle) * 0.5 * _maxThrust) / SHIP:MASS.
        IF referenceAcceleration <= g {
            f9_print_result("ERROR: reference thrust below gravity").
            UNLOCK THROTTLE.
            UNLOCK STEERING.
            RETURN FALSE.
        }

        LOCAL spoolTime IS engineInfo["spooluptime"].
        LOCAL futureVelocity IS SHIP:VELOCITY:SURFACE
            - g * spoolTime * UP:FOREVECTOR.
        LOCAL futureHeight IS bottomAltitude
            + SHIP:VERTICALSPEED * spoolTime
            - 0.5 * g * spoolTime^2.
        LOCAL futureRequiredAcceleration IS
            (futureVelocity:MAG^2 - params["touchDownSpeed"]^2)
            / (2 * MAX(0.01, futureHeight)) + g.

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
        f9_print_at(
            15,
            "Accel required/ref: "
                + ROUND(futureRequiredAcceleration, 2)
                + " / " + ROUND(referenceAcceleration, 2)
        ).
        IF (futureHeight <= params["landingBurnAltitude"]
            AND futureRequiredAcceleration >= referenceAcceleration) {
            f9_print_at(16, "Ignition condition: met").
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
    activate_engines(landingEngines).
    f9_print_at(16, "Engines: active  Continuous ignition").
    LOCAL throttleTarget IS 1.
    LOCK THROTTLE TO throttleTarget.

    // Phase 1: three-dimensional fixed-time quadratic divert.
    LOCK maxQuadraticAOA TO (params["QuadraticAOABase"]/(1+ship:q*101/10)).
    LOCAL radius IS (-SHIP:BODY:POSITION):MAG.
    LOCAL g IS SHIP:BODY:MU / radius^2.
    LOCAL refAccStart IS _maxThrust * (0.9 + 0.1*minThrottle) / SHIP:MASS - g.
    LOCAL refAccEnd IS max(0.5, _maxThrust * (0.15 + 0.85*minThrottle) / SHIP:MASS - g).
    f9_print_at(
        19,
        "AccStart = " + round(refAccStart, 1)
        + " ; AccEnd = " + round(refAccEnd, 1) + " m/s2"
    ).
    if (refAccStart <= 0) {
        f9_print_result("ERROR: invalid phase-1 acceleration").
        LOCK THROTTLE TO 0.
        deactivate_engines(landingEngines).
        UNLOCK THROTTLE.
        UNLOCK STEERING.
        RETURN FALSE.
    }
    LOCAL _T to -(SHIP:VELOCITY:SURFACE:MAG - params["touchDownSpeed"]) * 2 / (refAccStart + refAccEnd).
    LOCAL _accDot to (refAccStart - refAccEnd) / _T.
    LOCAL _getTimeToGo to { return -(-refAccEnd+sqrt(refAccEnd*refAccEnd-2*_accDot*(SHIP:velocity:surface:mag-params["touchDownSpeed"])))/_accDot. }.
    LOCAL timeToGo IS _T.
    UNTIL FALSE {
        f9_refresh_target(targetContext).
        SET targetPosition TO f9_get_target_position(targetContext).
        if (ship:airspeed < params["legDeploySpeed"] and (not GEAR)) GEAR ON.
        IF TIME:SECONDS >= nextBoundsUpdate {
            SET bottomHeight TO f9_get_bottom_height(TiS).
            SET nextBoundsUpdate TO TIME:SECONDS + params["boundsUpdatePeriod"].
        }

        LOCAL bottomAltitude IS f9_get_bottom_altitude(
            targetPosition,
            bottomHeight
        ).

        SET timeToGo TO MAX(0, _getTimeToGo()).
        f9_print_target_position(targetContext).
        f9_print_recovery_vehicle().
        f9_print_at(
            6,
            "Altitude: " + ROUND(SHIP:ALTITUDE, 1)
                + " m  Bottom: " + ROUND(bottomAltitude, 1) + " m"
        ).
        f9_print_at(12, "Time to go: " + ROUND(timeToGo, 2) + " s").
        IF (timeToGo <= params["landingPhase2Time"]
            OR bottomAltitude <= params["landingCutoffHeight"]) {
            f9_print_at(18, "Transition: landing phase 2").
            BREAK.
        }

        LOCAL upAxis IS UP:FOREVECTOR.
        LOCAL relativePosition IS -targetPosition - bottomHeight * upAxis.
        LOCAL relativeVelocity IS SHIP:VELOCITY:SURFACE.
        LOCAL quadraticTargetPosition IS V(0, 0, 0).
        LOCAL targetVelocity IS -params["touchDownSpeed"] * upAxis.
        LOCAL targetAcceleration IS refAccEnd * upAxis.
        LOCAL quadraticControl IS f9_quadratic_fixed_time(
            relativePosition,
            relativeVelocity,
            quadraticTargetPosition,
            targetVelocity,
            targetAcceleration,
            timeToGo,
            min(maxQuadraticAOA, params["QuadraticAOADot"]*timeToGo),
            upAxis,
            g
        ).
        LOCAL qT IS quadraticControl["qT"].
        LOCAL accelerationShip IS quadraticControl["cmdA"].
        // set _drawAcc to vecDraw(V(0,0,0), accelerationShip * 5, RGB(0, 255, 0), "Acc", 1, true).

        LOCAL requestedAOA IS 0.
        LOCAL commandedAOA IS 0.
        IF accelerationShip:MAG > 0.000001 {
            SET steeringTarget TO f9_get_target_steering(
                accelerationShip,
                TiS,
                params["targetRoll"],
                vecNormal
            ).
        }
        ELSE {
            SET steeringTarget TO f9_get_target_steering(
                up:forevector,
                TiS,
                params["targetRoll"],
                vecNormal
            ).
        }
        LOCAL requestedFraction IS
            SHIP:MASS * accelerationShip:MAG / _maxThrust.
        SET throttleTarget TO f9_continuous_throttle(
            requestedFraction,
            minThrottle,
            params["minLandingThrottleCommand"]
        ).
        f9_print_at(
            13,
            "Position error: " + ROUND(relativePosition:MAG, 2) + " m"
        ).
        f9_print_at(
            14,
            "Command acceleration: "
                + ROUND(accelerationShip:MAG, 2) + " m/s2"
        ).
        f9_print_at(
            15,
            "Throttle req/cmd: " + ROUND(requestedFraction, 3)
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
        f9_print_at(
            18,
            "AOA req/cmd: " + ROUND(requestedAOA, 2)
                + " / " + ROUND(commandedAOA, 2) + " deg"
        ).
        WAIT 0.
    }

    // Phase 2: vertical terminal braking. The engine remains ignited.
    f9_clear_guidance_display().
    f9_print_at(11, "Phase: landing - phase 2").
    f9_print_at(16, "Engines: active  Continuous ignition").
    LOCAL phase2Start IS TIME:SECONDS.
    SET steeringTarget TO f9_get_target_steering(
        UP:FOREVECTOR,
        TiS,
        params["targetRoll"]
    ).
    LOCAL bottomAltitude IS f9_get_bottom_altitude(
        targetPosition,
        bottomHeight
    ).

    UNTIL (SHIP:VERTICALSPEED >= 0
        OR bottomAltitude <= params["landingCutoffHeight"]) {
        f9_refresh_target(targetContext).
        SET targetPosition TO f9_get_target_position(targetContext).
        LOCAL phase2Elapsed IS TIME:SECONDS - phase2Start.

        IF TIME:SECONDS >= nextBoundsUpdate {
            SET bottomHeight TO f9_get_bottom_height(TiS).
            SET nextBoundsUpdate TO TIME:SECONDS + params["boundsUpdatePeriod"].
        }

        SET bottomAltitude TO f9_get_bottom_altitude(
            targetPosition,
            bottomHeight
        ).
        LOCAL downwardSpeed IS MAX(0, -SHIP:VERTICALSPEED).
        LOCAL requiredAcceleration IS
            (downwardSpeed^2 - params["touchDownSpeed"]^2)
            / (2 * MAX(0.01, bottomAltitude)) + g.
        SET requiredAcceleration TO MAX(0, requiredAcceleration).
        LOCAL requestedFraction IS
            SHIP:MASS * requiredAcceleration / _maxThrust.
        SET throttleTarget TO f9_continuous_throttle(
            requestedFraction,
            minThrottle,
            params["minLandingThrottleCommand"]
        ).
        if (SHIP:groundspeed > 0.5) {
            SET steeringTarget TO f9_get_target_steering(
                srfRetrograde:forevector,
                TiS,
                params["targetRoll"],
                vecNormal
            ).
        }
        else {
            SET steeringTarget TO f9_get_target_steering(
                UP:FOREVECTOR,
                TiS,
                params["targetRoll"],
                vecNormal
            ).
        }
        f9_print_target_position(targetContext).
        f9_print_recovery_vehicle().
        f9_print_at(
            6,
            "Altitude: " + ROUND(SHIP:ALTITUDE, 1)
                + " m  Bottom: " + ROUND(bottomAltitude, 1) + " m"
        ).
        f9_print_at(
            12,
            "Bottom height: " + ROUND(bottomAltitude, 2) + " m"
        ).
        f9_print_at(
            13,
            "Downward speed: " + ROUND(downwardSpeed, 2) + " m/s"
        ).
        f9_print_at(
            14,
            "Command acceleration: "
                + ROUND(requiredAcceleration, 2) + " m/s2"
        ).
        f9_print_at(
            15,
            "Throttle req/cmd: " + ROUND(requestedFraction, 3)
                + " / " + ROUND(throttleTarget, 3)
        ).
        f9_print_at(
            16,
            "Engines: active  Throttle: "
                + ROUND(SHIP:CONTROL:MAINTHROTTLE, 2)
        ).
        WAIT 0.
    }

    f9_print_at(11, "Phase: landing - cutoff").
    f9_print_at(16, "Engines: cutoff  Throttle: 0.00").
    LOCK THROTTLE TO 0.
    deactivate_engines(landingEngines).
    UNLOCK THROTTLE.
    UNLOCK STEERING.
    RETURN TRUE.
}
