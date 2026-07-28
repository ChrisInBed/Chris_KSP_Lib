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
        PRINT "F9 landing error: no valid landing target".
        RETURN FALSE.
    }
    IF NOT ADDONS:TR:AVAILABLE {
        PRINT "F9 landing error: Trajectories is unavailable".
        RETURN FALSE.
    }

    LOCAL landingEngines IS search_engine(params["landingEngineTag"]).
    IF landingEngines:LENGTH = 0 {
        PRINT "F9 landing error: no landing engines found".
        RETURN FALSE.
    }
    LOCAL engineInfo IS get_engines_info(landingEngines).
    LOCAL _maxThrust IS engineInfo["thrust"].
    LOCAL minThrottle IS engineInfo["minthrottle"].
    LOCAL TiS IS engineInfo["TiS"].
    IF _maxThrust <= 0 {
        PRINT "F9 landing error: engines have no available thrust".
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

    PRINT "F9 landing: aerodynamic guidance".
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
            PRINT "F9 landing error: reference thrust cannot overcome gravity".
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

        IF (futureHeight <= 0
            OR futureRequiredAcceleration >= referenceAcceleration) {
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

            SET desiredVector TO ANGLEAXIS(
                pitchCommand,
                crossrangeAxis
            ) * desiredVector.
            SET desiredVector TO ANGLEAXIS(
                yawCommand,
                upAxis
            ) * desiredVector.
        }
        SET steeringTarget TO f9_get_target_steering(
            desiredVector,
            TiS,
            params["targetRoll"]
        ).
        WAIT 0.
    }

    PRINT "F9 landing: ignition".
    activate_engines(landingEngines).
    LOCAL throttleTarget IS 1.
    LOCK THROTTLE TO throttleTarget.

    // Phase 1: three-dimensional fixed-time quadratic divert.
    PRINT "F9 landing: phase 1".
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
            PRINT "F9 landing error: phase-1 reference acceleration is invalid".
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
        IF (timeToGo <= params["landingPhase2Time"]
            OR bottomAltitude <= params["landingCutoffHeight"]) {
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
        LOCAL targetAcceleration IS V(0, 0, 0).
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
        WAIT 0.
    }

    // Phase 2: vertical terminal braking. The engine remains ignited.
    PRINT "F9 landing: phase 2".
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

        IF (NOT gearDeployed
            AND TIME:SECONDS - phase2Start >= params["gearDeployDelay"]) {
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
        WAIT 0.
    }

    PRINT "F9 landing: cutoff".
    LOCK THROTTLE TO 0.
    deactivate_engines(landingEngines).
    UNLOCK THROTTLE.
    UNLOCK STEERING.
    RETURN TRUE.
}
