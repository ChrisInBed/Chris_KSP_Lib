RUNONCEPATH("0:/lib/orbit.ks").
RUNONCEPATH("0:/lib/engine_utility.ks").

GLOBAL F9_DISPLAY_TERMINAL_WIDTH IS 50.
GLOBAL F9_DISPLAY_FIELD_WIDTH IS 48.
GLOBAL F9_GUIDANCE_FIRST_ROW IS 11.
GLOBAL F9_GUIDANCE_LAST_ROW IS 18.
GLOBAL F9_RESULT_ROW IS 21.

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
    PARAMETER targetGeo.
    f9_print_at(
        3,
        "Lat/Lng: " + ROUND(targetGeo:LAT, 4)
            + " / " + ROUND(targetGeo:LNG, 4)
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
    f9_print_target_position(targetContext["geo"]).
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

FUNCTION f9_get_surface_normal {
    LOCAL unitR IS -SHIP:BODY:POSITION:NORMALIZED.
    LOCAL orbitNormal IS VCRS(SHIP:VELOCITY:ORBIT, unitR):NORMALIZED.
    IF orbitNormal:MAG < 1e-4 {
        RETURN NORTH:FORVECTOR.
    }
    RETURN orbitNormal.
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
    LOCAL topVector IS VCRS(burnVector, f9_get_surface_normal()).
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
