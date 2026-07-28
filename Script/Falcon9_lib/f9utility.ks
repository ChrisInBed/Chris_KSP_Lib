RUNONCEPATH("0:/lib/orbit.ks").
RUNONCEPATH("0:/lib/engine_utility.ks").

// Select a fixed active waypoint first. If none is selected, capture the
// current KSP target so a moving target vessel can be refreshed in flight.
FUNCTION f9_initialize_target {
    LOCAL activeWaypoint IS get_active_waypoint().
    IF activeWaypoint <> 0 {
        RETURN LEXICON(
            "ok", TRUE,
            "moving", FALSE,
            "geo", activeWaypoint:GEOPOSITION,
            "object", activeWaypoint
        ).
    }

    IF HASTARGET {
        RETURN LEXICON(
            "ok", TRUE,
            "moving", TRUE,
            "geo", TARGET:GEOPOSITION,
            "object", TARGET
        ).
    }

    PRINT "F9 target error: select a waypoint or target vessel".
    RETURN LEXICON(
        "ok", FALSE,
        "moving", FALSE,
        "geo", SHIP:GEOPOSITION,
        "object", SHIP
    ).
}

FUNCTION f9_refresh_target {
    PARAMETER targetContext.
    IF targetContext["moving"] {
        SET targetContext["geo"] TO targetContext["object"]:GEOPOSITION.
    }
    RETURN targetContext["geo"].
}

FUNCTION f9_get_orbit_normal {
    LOCAL unitR IS -SHIP:BODY:POSITION:NORMALIZED.
    LOCAL orbitNormal IS VCRS(SHIP:VELOCITY:ORBIT, unitR).
    IF orbitNormal:MAG < 0.000001 {
        RETURN NORTH:FOREVECTOR.
    }
    RETURN orbitNormal:NORMALIZED.
}

// PEGLand-style steering: burnVector is the desired acceleration direction,
// TiS is Engine:facing:inverse * Ship:facing, and targetRoll fixes roll.
FUNCTION f9_get_target_steering {
    PARAMETER burnVector.
    PARAMETER TiS.
    PARAMETER targetRoll.

    IF burnVector:MAG < 0.000001 {
        RETURN SHIP:FACING.
    }
    LOCAL topVector IS VCRS(burnVector, f9_get_orbit_normal()).
    IF topVector:MAG < 0.000001 {
        SET topVector TO NORTH:FOREVECTOR.
    }
    SET topVector TO ANGLEAXIS(targetRoll, burnVector) * topVector.
    RETURN LOOKDIRUP(burnVector, topVector) * TiS.
}

FUNCTION f9_get_boostback_vgo {
    PARAMETER targetGeo.

    LOCAL rr IS -SHIP:BODY:POSITION.
    LOCAL vv IS SHIP:VELOCITY:SURFACE.
    LOCAL rTarget IS targetGeo:POSITION - SHIP:BODY:POSITION.
    LOCAL unitR IS rr:NORMALIZED.
    LOCAL g IS SHIP:BODY:MU / rr:MAG^2.
    LOCAL gravity IS -g * unitR.
    LOCAL radialSpeed IS VDOT(unitR, vv).
    LOCAL height IS VDOT(unitR, rr - rTarget).
    LOCAL timeToGo IS (radialSpeed + SQRT(MAX(0, radialSpeed^2 + 2*g*height))) / g.
    SET timeToGo TO MAX(0.001, timeToGo).

    RETURN (rTarget - rr - 0.5*gravity*timeToGo^2) / timeToGo - vv.
}

FUNCTION f9_get_entry_vgo {
    PARAMETER targetGeo.
    PARAMETER entrySpeed.

    LOCAL rr IS -SHIP:BODY:POSITION.
    LOCAL vv IS SHIP:VELOCITY:SURFACE.
    LOCAL rTarget IS targetGeo:POSITION - SHIP:BODY:POSITION.
    LOCAL unitR IS rr:NORMALIZED.
    LOCAL g IS SHIP:BODY:MU / rr:MAG^2.
    LOCAL gravity IS -g * unitR.
    LOCAL postBurnVerticalSpeed IS -entrySpeed.
    LOCAL height IS VDOT(unitR, rr - rTarget).
    LOCAL timeToGo IS (postBurnVerticalSpeed
        + SQRT(MAX(0, postBurnVerticalSpeed^2 + 2*g*height))) / g.
    SET timeToGo TO MAX(0.001, timeToGo).

    RETURN (rTarget - rr - 0.5*gravity*timeToGo^2) / timeToGo - vv.
}

FUNCTION f9_get_bottom_height {
    PARAMETER TiS.
    LOCAL thrustDown IS -(SHIP:FACING * TiS:INVERSE):FOREVECTOR.
    RETURN get_furtherst_height(SHIP:BOUNDS, thrustDown).
}

FUNCTION f9_get_bottom_altitude {
    PARAMETER targetGeo.
    PARAMETER bottomHeight.
    LOCAL bottomPosition IS SHIP:POSITION - bottomHeight * UP:FOREVECTOR.
    RETURN VDOT(bottomPosition - targetGeo:POSITION, UP:FOREVECTOR).
}

FUNCTION f9_continuous_throttle {
    PARAMETER requestedFraction.
    PARAMETER minThrottle.
    PARAMETER minCommand.
    RETURN MAX(minCommand, MIN(1, simple_get_throttle(requestedFraction, minThrottle))).
}
