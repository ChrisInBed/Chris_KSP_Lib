// Falcon 9 launch and recovery parameters.
// Distances are meters, time is seconds, speed is m/s, mass is metric tons,
// and angles are degrees unless noted otherwise.

GLOBAL F9_UNSET IS -999999.

set steeringManager:maxstoppingtime to 1.
set steeringManager:pitchts to 10.
set steeringManager:yawts to 10.
set steeringManager:rollts to 40.
set steeringManager:rollpid:kd to 0.5.

local payloadMass to 16.651.

GLOBAL F9_PARAMS IS LEXICON(
    // Runtime
    "kOSIPU", 2000,

    // Engine role tags. search_engine() matches these against Engine:TAG.
    "liftoffEngineTag", "liftoff",
    "boostbackEngineTag", "boostback",
    "entryEngineTag", "entry",
    "landingEngineTag", "landing",

    // Vehicle-specific values. These must be set before flight.
    "payloadMass", payloadMass,
    "mecoMass", 180.478 + payloadMass,
    "boostBackMass", 150,
    "targetHeading", 80,
    "targetRoll", 0,

    // Launch
    "turnSpeed", 60,
    "pitchOmega", 0.4,
    "stageSeparationDelay", 1,
    "upperStageIgnitionDelay", 2,

    // Powered-burn alignment and timing
    "burnAlignTolerance", 1,
    "boostBackDelay", 2,

    // Entry burn
    "entryBurnAlt", 80000,
    // Positive magnitude. The signed target used by guidance is -entryVSpeed.
    "entryVSpeed", 900,

    // Aerodynamic guidance. These must be tuned for the vehicle before flight.
    // PID outputs are pitch/yaw correction angles in degrees.
    "aeroPitchKp", 10,
    "aeroPitchKi", 1,
    "aeroPitchKd", 1,
    "aeroYawKp", 10,
    "aeroYawKi", 1,
    "aeroYawKd", 1,
    "aeroMaxPitch", 15,
    "aeroMaxYaw", 15,

    // Landing burn
    "touchDownSpeed", 0.2,
    "landingPhase2Time", 5,
    "landingCutoffHeight", 0.2,
    "gearDeployDelay", 8,
    "boundsUpdatePeriod", 1,
    // Keep a continuously ignited RO engine above zero command until cutoff.
    "minLandingThrottleCommand", 0.01,

    "_", ""
).

FUNCTION f9_param_is_unset {
    PARAMETER value.
    RETURN value = F9_UNSET.
}

FUNCTION f9_validate_launch_params {
    PARAMETER params.
    LOCAL ok IS TRUE.

    IF f9_param_is_unset(params["mecoMass"]) {
        PRINT "F9 config error: set mecoMass in Falcon9_lib/params.ks".
        SET ok TO FALSE.
    }
    IF f9_param_is_unset(params["targetHeading"]) {
        PRINT "F9 config error: set targetHeading in Falcon9_lib/params.ks".
        SET ok TO FALSE.
    }
    IF (params["mecoMass"] <= 0
        AND NOT f9_param_is_unset(params["mecoMass"])) {
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
    LOCAL ok IS TRUE.

    IF f9_param_is_unset(params["boostBackMass"]) {
        PRINT "F9 config error: set boostBackMass in Falcon9_lib/params.ks".
        SET ok TO FALSE.
    }
    IF f9_param_is_unset(params["targetRoll"]) {
        PRINT "F9 config error: set targetRoll in Falcon9_lib/params.ks".
        SET ok TO FALSE.
    }
    IF (params["boostBackMass"] <= 0
        AND NOT f9_param_is_unset(params["boostBackMass"])) {
        PRINT "F9 config error: boostBackMass must be positive".
        SET ok TO FALSE.
    }

    LOCAL aeroKeys IS LIST(
        "aeroPitchKp", "aeroPitchKi", "aeroPitchKd",
        "aeroYawKp", "aeroYawKi", "aeroYawKd",
        "aeroMaxPitch", "aeroMaxYaw"
    ).
    FOR key IN aeroKeys {
        IF f9_param_is_unset(params[key]) {
            PRINT "F9 config error: set " + key + " in Falcon9_lib/params.ks".
            SET ok TO FALSE.
        }
    }
    IF (NOT f9_param_is_unset(params["aeroMaxPitch"])
        AND params["aeroMaxPitch"] <= 0) {
        PRINT "F9 config error: aeroMaxPitch must be positive".
        SET ok TO FALSE.
    }
    IF (NOT f9_param_is_unset(params["aeroMaxYaw"])
        AND params["aeroMaxYaw"] <= 0) {
        PRINT "F9 config error: aeroMaxYaw must be positive".
        SET ok TO FALSE.
    }
    IF (params["entryBurnAlt"] <= 0 OR params["entryVSpeed"] <= 0) {
        PRINT "F9 config error: entry burn altitude and speed must be positive".
        SET ok TO FALSE.
    }
    IF (params["touchDownSpeed"] < 0 OR params["landingPhase2Time"] <= 0) {
        PRINT "F9 config error: invalid landing speed or phase-2 time".
        SET ok TO FALSE.
    }
    RETURN ok.
}
