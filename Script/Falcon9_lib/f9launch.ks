RUNONCEPATH("0:/Falcon9_lib/params.ks").
RUNONCEPATH("0:/Falcon9_lib/f9utility.ks").

FUNCTION f9_launch {
    PARAMETER params.

    IF NOT f9_validate_launch_params(params) {
        RETURN FALSE.
    }
    SET CONFIG:IPU TO params["kOSIPU"].

    LOCAL liftoffEngines IS search_engine(params["liftoffEngineTag"]).
    IF liftoffEngines:LENGTH = 0 {
        PRINT "F9 launch error: no liftoff engines found".
        RETURN FALSE.
    }
    LOCAL engineInfo IS get_engines_info(liftoffEngines).
    IF engineInfo["thrust"] <= 0 {
        PRINT "F9 launch error: liftoff engines have no available thrust".
        RETURN FALSE.
    }

    PRINT "F9 launch: starting main engines".
    LOCAL steeringTarget IS HEADING(params["targetHeading"], 90) * engineInfo["TiS"].
    SAS OFF.
    LOCK STEERING TO steeringTarget.
    LOCK THROTTLE TO 1.
    RCS ON.
    STAGE.
    // activate_engines(liftoffEngines).
    WAIT engineInfo["spooluptime"].

    PRINT "F9 launch: liftoff".
    STAGE.
    WAIT UNTIL SHIP:VELOCITY:SURFACE:MAG >= params["turnSpeed"].

    PRINT "F9 launch: programmed turn".
    LOCAL turnStart IS TIME:SECONDS.
    UNTIL SHIP:MASS <= params["mecoMass"] {
        LOCAL pitchCommand IS MAX(
            0,
            90 - params["pitchOmega"] * (TIME:SECONDS - turnStart)
        ).
        SET steeringTarget TO HEADING(params["targetHeading"], pitchCommand)
            * engineInfo["TiS"].
        WAIT 0.
    }

    PRINT "F9 launch: MECO".
    LOCK THROTTLE TO 0.
    deactivate_engines(liftoffEngines).
    WAIT params["stageSeparationDelay"].

    PRINT "F9 launch: first-stage separation".
    STAGE.
    SET SHIP:CONTROL:FORE TO 1.
    WAIT params["upperStageIgnitionDelay"].

    PRINT "F9 launch: upper-stage ignition".
    LOCK THROTTLE TO 1.
    STAGE.
    UNLOCK STEERING.
    SAS ON.
    WAIT 0.
    SET SHIP:CONTROL:FORE TO 0.
    UNLOCK THROTTLE.
    RETURN TRUE.
}
