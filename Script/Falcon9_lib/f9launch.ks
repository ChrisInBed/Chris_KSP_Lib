RUNONCEPATH("0:/Falcon9_lib/params.ks").
RUNONCEPATH("0:/Falcon9_lib/f9utility.ks").

FUNCTION f9_launch {
    PARAMETER params.

    IF NOT f9_validate_launch_params(params) {
        RETURN FALSE.
    }
    SET CONFIG:IPU TO params["kOSIPU"].
    f9_init_launch_display().

    LOCAL liftoffEngines IS search_engine(params["liftoffEngineTag"]).
    IF liftoffEngines:LENGTH = 0 {
        f9_print_result("ERROR: no liftoff engines found").
        RETURN FALSE.
    }
    LOCAL engineInfo IS get_engines_info(liftoffEngines).
    IF engineInfo["thrust"] <= 0 {
        f9_print_result("ERROR: liftoff engines have no thrust").
        RETURN FALSE.
    }

    f9_print_at(2, "State: starting main engines").
    f9_print_at(
        3,
        "Mass: " + ROUND(SHIP:MASS, 2)
            + " t  MECO: " + ROUND(params["mecoMass"], 2) + " t"
    ).
    f9_print_at(
        4,
        "Speed: " + ROUND(SHIP:VELOCITY:SURFACE:MAG, 1)
            + " m/s  Turn: " + ROUND(params["turnSpeed"], 1)
    ).
    f9_print_at(
        5,
        "Heading: " + ROUND(params["targetHeading"], 1)
            + " deg  Pitch: 90 deg"
    ).
    f9_print_at(
        6,
        "Thrust: " + ROUND(engineInfo["thrust"], 1)
            + " kN  Spool: " + ROUND(engineInfo["spooluptime"], 2) + " s"
    ).
    f9_print_at(7, "Throttle command: 1.00").
    f9_print_at(10, "Event: main engine start").
    LOCAL steeringTarget IS HEADING(params["targetHeading"], 90) * engineInfo["TiS"].
    SAS OFF.
    LOCK STEERING TO steeringTarget.
    LOCK THROTTLE TO 1.
    STAGE.
    // activate_engines(liftoffEngines).
    WAIT engineInfo["spooluptime"].

    f9_print_at(2, "State: vertical ascent").
    f9_print_at(10, "Event: liftoff").
    STAGE.
    RCS ON.
    UNTIL SHIP:VELOCITY:SURFACE:MAG >= params["turnSpeed"] {
        f9_print_at(
            3,
            "Mass: " + ROUND(SHIP:MASS, 2)
                + " t  MECO: " + ROUND(params["mecoMass"], 2) + " t"
        ).
        f9_print_at(
            4,
            "Speed: " + ROUND(SHIP:VELOCITY:SURFACE:MAG, 1)
                + " m/s  Turn: " + ROUND(params["turnSpeed"], 1)
        ).
        f9_print_at(
            5,
            "Heading: " + ROUND(params["targetHeading"], 1)
                + " deg  Pitch: 90 deg"
        ).
        f9_print_at(
            7,
            "Throttle: " + ROUND(SHIP:CONTROL:MAINTHROTTLE, 2)
        ).
        WAIT 0.
    }

    f9_print_at(2, "State: programmed turn").
    f9_print_at(10, "Event: turn started").
    LOCAL turnStart IS TIME:SECONDS.
    UNTIL SHIP:MASS <= params["mecoMass"] {
        LOCAL pitchCommand IS MAX(
            0,
            90 - params["pitchOmega"] * (TIME:SECONDS - turnStart)
        ).
        SET steeringTarget TO HEADING(params["targetHeading"], pitchCommand)
            * engineInfo["TiS"].
        f9_print_at(
            3,
            "Mass: " + ROUND(SHIP:MASS, 2)
                + " t  MECO: " + ROUND(params["mecoMass"], 2) + " t"
        ).
        f9_print_at(
            4,
            "Speed: " + ROUND(SHIP:VELOCITY:SURFACE:MAG, 1) + " m/s"
        ).
        f9_print_at(
            5,
            "Heading: " + ROUND(params["targetHeading"], 1)
                + " deg  Pitch: " + ROUND(pitchCommand, 1) + " deg"
        ).
        f9_print_at(
            7,
            "Throttle: " + ROUND(SHIP:CONTROL:MAINTHROTTLE, 2)
        ).
        WAIT 0.
    }

    f9_print_at(2, "State: MECO").
    f9_print_at(10, "Event: main engine cutoff").
    LOCK THROTTLE TO 0.
    deactivate_engines(liftoffEngines).
    f9_print_at(7, "Throttle command: 0.00").
    WAIT params["stageSeparationDelay"].

    f9_print_at(2, "State: stage separation").
    f9_print_at(10, "Event: first-stage separation").
    // Steering and throttle are locked to temporary value. In future this will be changed to PEG guidance
    SET _steering_gap TO ship:facing.
    LOCK STEERING TO _steering_gap.
    STAGE.
    SET SHIP:CONTROL:FORE TO 1.
    WAIT params["upperStageIgnitionDelay"].

    f9_print_at(2, "State: upper-stage ignition").
    f9_print_at(10, "Event: upper-stage ignition").
    LOCK THROTTLE TO 1.
    f9_print_at(7, "Throttle command: 1.00").
    STAGE.
    WAIT 0.
    SET SHIP:CONTROL:FORE TO 0.
    WAIT UNTIL AG10.
    UNLOCK STEERING.
    UNLOCK THROTTLE.
    WAIT 0.
    RETURN TRUE.
}
