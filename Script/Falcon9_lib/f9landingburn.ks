RUNONCEPATH("0:/Falcon9_lib/params.ks").
RUNONCEPATH("0:/Falcon9_lib/f9utility.ks").

// Fixed-time form of PEGLand's quadratic guidance. The public time-to-go is
// positive; PEGLand's polynomial uses a negative current time with touchdown
// at t = 0.
FUNCTION f9_quadratic_fixed_time {
    PARAMETER currentPosition.
    PARAMETER currentVelocity.
    PARAMETER targetPosition.
    PARAMETER targetVelocity.
    PARAMETER targetAcceleration.
    PARAMETER timeToGo.

    LOCAL qT IS -MAX(0.05, timeToGo).
    LOCAL qJ IS 24/qT^3*(currentPosition-targetPosition)
        - 6/qT^2*(currentVelocity+3*targetVelocity)
        - 6/qT*targetAcceleration.
    LOCAL qS IS -72/qT^4*(currentPosition-targetPosition)
        + 24/qT^3*(currentVelocity+2*targetVelocity)
        + 12/qT^2*targetAcceleration.
    RETURN LIST(qT, qJ, qS).
}

FUNCTION f9_landing_burn {
    PARAMETER params.
    PARAMETER targetContext.

    IF NOT targetContext["ok"] {
        f9_print_result("ERROR: no valid landing target").
        RETURN FALSE.
    }
    IF NOT ADDONS:TR:AVAILABLE {
        f9_print_result("ERROR: Trajectories is unavailable").
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

    LOCAL targetGeo IS f9_refresh_target(targetContext).
    LOCAL bottomHeight IS f9_get_bottom_height(TiS).
    LOCAL nextBoundsUpdate IS TIME:SECONDS + params["boundsUpdatePeriod"].
    LOCAL steeringTarget IS f9_get_target_steering(
        SRFRETROGRADE:FOREVECTOR,
        TiS,
        params["targetRoll"]
    ).
    SAS OFF.
    LOCK STEERING TO steeringTarget.
    LOCK THROTTLE TO 0.
    RCS ON.

    f9_print_at(11, "Phase: landing - aerodynamic guidance").
    f9_print_at(16, "Ignition: armed  Engines: inactive").
    UNTIL FALSE {
        SET targetGeo TO f9_refresh_target(targetContext).
        IF TIME:SECONDS >= nextBoundsUpdate {
            SET bottomHeight TO f9_get_bottom_height(TiS).
            SET nextBoundsUpdate TO TIME:SECONDS + params["boundsUpdatePeriod"].
        }

        LOCAL bottomAltitude IS f9_get_bottom_altitude(targetGeo, bottomHeight).
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

        f9_print_target_position(targetGeo).
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
        IF (ship:altitude < 25000 and (futureHeight <= 0
            OR futureRequiredAcceleration >= referenceAcceleration)) {
            f9_print_at(16, "Ignition condition: met").
            BREAK.
        }

        LOCAL desiredVector IS SRFRETROGRADE:FOREVECTOR.
        IF ADDONS:TR:HASIMPACT {
            LOCAL impactError IS ADDONS:TR:IMPACTPOS:POSITION
                - targetGeo:POSITION.
            LOCAL normalizedError IS impactError
                / MAX(1, targetGeo:POSITION:MAG) * 180 / constant:pi.  // TO deg
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

            LOCAL pitchError IS VDOT(normalizedError, downrangeAxis).
            LOCAL yawError IS VDOT(normalizedError, crossrangeAxis).
            LOCAL pitchCommand IS pitchPID:UPDATE(TIME:SECONDS, pitchError).
            LOCAL yawCommand IS yawPID:UPDATE(TIME:SECONDS, yawError).
            SET pitchCommand TO MAX(
                -params["aeroMaxPitch"],
                MIN(params["aeroMaxPitch"], pitchCommand)
            ).
            SET yawCommand TO MAX(
                -params["aeroMaxYaw"],
                MIN(params["aeroMaxYaw"], yawCommand)
            ).
            f9_print_at(
                13,
                "Impact err D/X: " + ROUND(pitchError, 3)
                    + " / " + ROUND(yawError, 3) + " deg"
            ).
            f9_print_at(
                14,
                "Aero cmd P/Y: " + ROUND(pitchCommand, 2)
                    + " / " + ROUND(yawCommand, 2) + " deg"
            ).

            SET desiredVector TO ANGLEAXIS(
                -pitchCommand,
                crossrangeAxis
            ) * desiredVector.
            SET desiredVector TO ANGLEAXIS(
                yawCommand,
                upAxis
            ) * desiredVector.
        } ELSE {
            f9_print_at(13, "Impact prediction: unavailable").
            f9_print_at(14, "Aero command: surface retrograde").
        }
        f9_print_at(16, "Ignition: armed  Engines: inactive").
        SET steeringTarget TO f9_get_target_steering(
            desiredVector,
            TiS,
            params["targetRoll"]
        ).
        WAIT 0.
    }

    f9_clear_guidance_display().
    f9_print_at(11, "Phase: landing - phase 1").
    activate_engines(landingEngines).
    f9_print_at(16, "Engines: active  Continuous ignition").
    LOCAL throttleTarget IS 1.
    LOCK THROTTLE TO throttleTarget.

    // Phase 1: three-dimensional fixed-time quadratic divert.
    LOCAL timeToGo IS params["landingPhase2Time"] + 1.
    UNTIL FALSE {
        SET targetGeo TO f9_refresh_target(targetContext).
        IF TIME:SECONDS >= nextBoundsUpdate {
            SET bottomHeight TO f9_get_bottom_height(TiS).
            SET nextBoundsUpdate TO TIME:SECONDS + params["boundsUpdatePeriod"].
        }

        LOCAL bottomAltitude IS f9_get_bottom_altitude(targetGeo, bottomHeight).
        LOCAL radius IS (-SHIP:BODY:POSITION):MAG.
        LOCAL g IS SHIP:BODY:MU / radius^2.
        LOCAL referenceAcceleration IS
            ((1 + minThrottle) * 0.5 * _maxThrust) / SHIP:MASS.
        LOCAL netReferenceAcceleration IS referenceAcceleration - g.
        IF netReferenceAcceleration <= 0 {
            f9_print_result("ERROR: invalid phase-1 acceleration").
            LOCK THROTTLE TO 0.
            deactivate_engines(landingEngines).
            UNLOCK THROTTLE.
            UNLOCK STEERING.
            RETURN FALSE.
        }

        SET timeToGo TO MAX(
            0,
            (SHIP:VELOCITY:SURFACE:MAG - params["touchDownSpeed"])
            / netReferenceAcceleration
        ).
        f9_print_target_position(targetGeo).
        f9_print_recovery_vehicle().
        f9_print_at(
            6,
            "Altitude: " + ROUND(SHIP:ALTITUDE, 1)
                + " m  Bottom: " + ROUND(bottomAltitude, 1) + " m"
        ).
        f9_print_at(12, "Time to go: " + ROUND(timeToGo, 2) + " s").
        f9_print_at(
            15,
            "Reference acceleration: "
                + ROUND(referenceAcceleration, 2) + " m/s2"
        ).
        IF (timeToGo <= params["landingPhase2Time"]
            OR bottomAltitude <= params["landingCutoffHeight"]) {
            f9_print_at(18, "Transition: landing phase 2").
            BREAK.
        }

        LOCAL upAxis IS UP:FOREVECTOR.
        LOCAL horizontalAxis IS VCRS(
            upAxis,
            SHIP:VELOCITY:SURFACE
        ).
        IF horizontalAxis:MAG < 0.000001 {
            SET horizontalAxis TO VCRS(upAxis, NORTH:FOREVECTOR).
        }
        IF horizontalAxis:MAG < 0.000001 {
            SET horizontalAxis TO SHIP:FACING:STARVECTOR.
        }
        SET horizontalAxis TO horizontalAxis:NORMALIZED.
        LOCAL downrangeAxis IS VCRS(horizontalAxis, upAxis):NORMALIZED.

        LOCAL bottomPosition IS SHIP:POSITION
            - bottomHeight * upAxis
            - targetGeo:POSITION.
        LOCAL vecV IS SHIP:VELOCITY:SURFACE.
        LOCAL relativePosition IS V(
            VDOT(bottomPosition, downrangeAxis),
            VDOT(bottomPosition, horizontalAxis),
            VDOT(bottomPosition, upAxis)
        ).
        LOCAL relativeVelocity IS V(
            VDOT(vecV, downrangeAxis),
            VDOT(vecV, horizontalAxis),
            VDOT(vecV, upAxis)
        ).
        LOCAL targetPosition IS V(0, 0, 0).
        LOCAL targetVelocity IS V(0, 0, -params["touchDownSpeed"]).
        LOCAL targetAcceleration IS V(0, 0, netReferenceAcceleration).
        LOCAL quadraticControl IS f9_quadratic_fixed_time(
            relativePosition,
            relativeVelocity,
            targetPosition,
            targetVelocity,
            targetAcceleration,
            timeToGo
        ).
        LOCAL qT IS quadraticControl[0].
        LOCAL qJ IS quadraticControl[1].
        LOCAL qS IS quadraticControl[2].
        LOCAL accelerationLocal IS targetAcceleration
            + qJ*qT + 0.5*qS*qT^2 + V(0, 0, g).
        LOCAL accelerationWorld IS accelerationLocal:X * downrangeAxis
            + accelerationLocal:Y * horizontalAxis
            + accelerationLocal:Z * upAxis.

        IF accelerationWorld:MAG > 0.000001 {
            SET steeringTarget TO f9_get_target_steering(
                accelerationWorld,
                TiS,
                params["targetRoll"]
            ).
        }
        LOCAL requestedFraction IS
            SHIP:MASS * accelerationWorld:MAG / _maxThrust.
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
                + ROUND(accelerationWorld:MAG, 2) + " m/s2"
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
                + ROUND(relativeVelocity:Z, 2) + " m/s"
        ).
        WAIT 0.
    }

    // Phase 2: vertical terminal braking. The engine remains ignited.
    f9_clear_guidance_display().
    f9_print_at(11, "Phase: landing - phase 2").
    f9_print_at(16, "Engines: active  Continuous ignition").
    LOCAL phase2Start IS TIME:SECONDS.
    LOCAL gearDeployed IS FALSE.
    SET steeringTarget TO f9_get_target_steering(
        UP:FOREVECTOR,
        TiS,
        params["targetRoll"]
    ).
    LOCAL bottomAltitude IS f9_get_bottom_altitude(targetGeo, bottomHeight).

    UNTIL (SHIP:VERTICALSPEED >= 0
        OR bottomAltitude <= params["landingCutoffHeight"]) {
        SET targetGeo TO f9_refresh_target(targetContext).
        LOCAL phase2Elapsed IS TIME:SECONDS - phase2Start.

        IF (NOT gearDeployed
            AND phase2Elapsed >= params["gearDeployDelay"]) {
            GEAR ON.
            SET gearDeployed TO TRUE.
            SET bottomHeight TO f9_get_bottom_height(TiS).
            SET nextBoundsUpdate TO TIME:SECONDS + params["boundsUpdatePeriod"].
        } ELSE IF TIME:SECONDS >= nextBoundsUpdate {
            SET bottomHeight TO f9_get_bottom_height(TiS).
            SET nextBoundsUpdate TO TIME:SECONDS + params["boundsUpdatePeriod"].
        }

        SET bottomAltitude TO f9_get_bottom_altitude(targetGeo, bottomHeight).
        LOCAL radius IS (-SHIP:BODY:POSITION):MAG.
        LOCAL g IS SHIP:BODY:MU / radius^2.
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
        SET steeringTarget TO f9_get_target_steering(
            UP:FOREVECTOR,
            TiS,
            params["targetRoll"]
        ).
        f9_print_target_position(targetGeo).
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
        IF gearDeployed {
            f9_print_at(
                17,
                "Gear: deployed  Phase time: "
                    + ROUND(phase2Elapsed, 2) + " s"
            ).
        } ELSE {
            f9_print_at(
                17,
                "Gear: waiting  Phase time: "
                    + ROUND(phase2Elapsed, 2) + " s"
            ).
        }
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
