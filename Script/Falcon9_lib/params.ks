// Falcon 9 launch and recovery parameters.
// Distances are meters, time is seconds, speed is m/s, mass is metric tons,
// and angles are degrees unless noted otherwise.

GLOBAL F9_UNSET IS -999999.

// set steeringManager:maxstoppingtime to 5.
// set steeringManager:pitchts to 5.
// // set steeringManager:pitchpid:kd to 0.1.
// set steeringManager:yawts to 5.
// // set steeringManager:yawpid:kd to 0.1.
// set steeringManager:rollts to 5.
// // set steeringManager:rollpid:kd to 0.5.
// // set steeringManager:rollpid:epsilon to 0.1.

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
    "payloadMass", payloadMass,  // Mass of the payload, ton
    "mecoMass", 190 + payloadMass,  // When the mass is below MECO mass, trigger MECO, ton
    "boostBackMass", 150,  // After second stage seperation, the mass of first stage should be less than this, ton
    "targetHeading", 80,  // First stage ascent azimuth, deg
    "targetRoll", 0,  // Roll angle while whole process, deg
    "altitudeOffset", 0,  // Additional height added to the selected waypoint, or target COM, m

    // Launch
    "turnSpeed", 50,  // Gravity turn start speed, m/s
    "pitchOmega", 0.42,  // Programmed turn pitching speed, deg/s
    "stageSeparationDelay", 1,  // Time between MECO and 1st Stage Separation, s
    "upperStageIgnitionDelay", 2,  // Time between 1st Stage Separation and second stage ignition, s

    // Powered-burn alignment and timing
    "boostBackDelay", 4,  // Time between 1st stage separation and boostback maneuver, s
    "burnAlignTolerance", 130,  // Alignment angle error tolerance, deg

    // Entry burn
    "entryBurnAlt", 60000,  // Altitude to perform entry burn, m
    "entryVSpeed", 650,  // Target descent rate, m/s

    // kOS-LTR open-loop trajectory predictor. The speed-AOA profile is the
    // attitude assumed by the predictor; aerodynamic coefficients are sampled
    // from FAR once the booster has separated.
    "ltrCtrlSpeedSamples", LIST(300, 600, 1000),
    "ltrCtrlAOASamples", LIST(0, 8, 11),
    // "ltrCtrlAOASamples", LIST(0, 0),
    "ltrAeroSpeedSamples", LIST(100, 500, 1000, 2000, 3000),
    "ltrAeroAltitudeSamples", LIST(0, 10000, 30000, 50000, 70000),
    "ltrCdFactor", 1,
    "ltrClFactor", 1,
    "ltrPredictMinStep", 0.001,
    "ltrPredictMaxStep", 0.5,
    "ltrPredictTMax", 1200,

    // Aerodynamic guidance. These must be tuned for the vehicle before flight.
    // PID outputs are pitch/yaw correction angles in degrees.
    "aeroPitchKp", 40,
    "aeroPitchKi", 0,
    "aeroPitchKd", 0.5,
    "aeroYawKp", 40,
    "aeroYawKi", 0,
    "aeroYawKd", 0.5,
    "aeroMaxPitch", 6,
    "aeroMaxYaw", 10,
    "aeroTargetOffset", 0,  // Aerodynamic gliding phase is aiming at target + aeroTargetOffset * downRangeVector, m

    // Landing burn
    "QuadraticAOABase", 20,  // AOA limit base during quadratic guidance phase, increase this value will allow larger AOA, deg
    "QuadraticAOADot", 0.5,  // AOA limit related to Time-to-go during quadratic guidance phase, increase this value will allow larger AOA when approaching ground, deg/s
    "landingBurnAltitude", 2300,  // Ignite landing engine when altitude is below this, m
    "legDeploySpeed", 90,  // Deploy landing legs when speed is below this, m/s
    "touchDownSpeed", 0.1,  // touch down speed, m/s
    "landingPhase2Time", 0.001,  // time of untargeted landing phase 2, s
    "landingCutoffHeight", 0.2,  // cut off landing engines when height is below this, m
    "boundsUpdatePeriod", 1,  // frequency of updating bounding box, s
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
    IF (params["ltrCtrlSpeedSamples"]:LENGTH = 0
        OR params["ltrCtrlSpeedSamples"]:LENGTH
            <> params["ltrCtrlAOASamples"]:LENGTH) {
        PRINT "F9 config error: LTR speed/AOA profiles must be nonempty and equal-length".
        SET ok TO FALSE.
    }
    IF (params["ltrAeroSpeedSamples"]:LENGTH = 0
        OR params["ltrAeroAltitudeSamples"]:LENGTH = 0) {
        PRINT "F9 config error: LTR aerodynamic sample axes must be nonempty".
        SET ok TO FALSE.
    }
    IF (params["ltrPredictMinStep"] < 0
        OR params["ltrPredictMaxStep"] <= 0
        OR params["ltrPredictMinStep"] > params["ltrPredictMaxStep"]
        OR params["ltrPredictTMax"] <= 0) {
        PRINT "F9 config error: invalid LTR predictor step/time limits".
        SET ok TO FALSE.
    }
    IF (params["touchDownSpeed"] < 0 OR params["landingPhase2Time"] <= 0) {
        PRINT "F9 config error: invalid landing speed or phase-2 time".
        SET ok TO FALSE.
    }
    RETURN ok.
}
