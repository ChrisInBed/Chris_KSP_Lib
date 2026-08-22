// Falcon 9 recovery stage boot file.
// Distances are meters, time is seconds, speed is m/s, mass is metric tons,
// and angles are degrees unless noted otherwise.

GLOBAL F9_PARAMS IS LEXICON(
    // Runtime
    "kOSIPU", 2000,

    "landingSiteUse", "waypoint",  // Options: "geo", "waypoint", "vessel", "none". "none" selects the predicted natural impact after separation and boostBackDelay
    "landingSiteGeo", list(0, 0),  // longitude and latitude, use terrain height as altitude
    "landingSiteWaypoint", "ASDS-Falcon9RP1-Cape",  // name of waypoint, use waypoint altitude as altitude
    "landingSiteVessel", "drone",  // name of target vessel, use vessel altitude as altitude, the vessel can move slowly

    "boostbackEngineTag", "boostback_",
    "entryEngineTag", "entry_",
    "landingDecEngineTag", "landing1_",
    "landingEngineTag", "landing2_",

    // Vehicle-specific values. These must be set before flight.
    "boostBackMass", 150,  // After second stage seperation, the mass of first stage should be less than this, ton
    "targetRoll", 0,  // Roll angle while whole process, deg
    "altitudeOffset", 4619.1+2,  // Additional height added to the selected waypoint, or target COM, m

    // Powered-burn alignment and timing
    "enableBoostBack", FALSE,  // Set FALSE to skip the boostback phase
    "boostBackDelay", 5,  // Time between 1st stage separation and boostback maneuver, s
    "burnAlignTolerance", 130,  // Alignment angle error tolerance, deg
    "boostBackThrottle", 1,  // throttle (0~1) during boost back maneuver

    // Entry burn
    "enableEntryBurn", TRUE,  // Set FALSE to skip only the powered entry burn; aerodynamic gliding remains enabled
    "entryBurnAlt", 60000,  // Altitude to perform entry burn, m
    "entryVSpeed", 900,  // Target descent rate, m/s
    "entryThrottle", 1,  // throttle (0~1) during entry burn

    // kOS-LTR open-loop trajectory predictor. The speed-AOA profile is the
    // attitude assumed by the predictor; aerodynamic coefficients are sampled
    // from FAR once the booster has separated.
    "ltrCtrlSpeedSamples", LIST(300, 600, 1000),
    "ltrCtrlAOASamples", LIST(0, 8, 11),
    "ltrAeroSpeedSamples", LIST(100, 500, 1000, 2000, 3000),
    "ltrAeroAltitudeSamples", LIST(0, 10000, 30000, 50000, 70000),
    "ltrCdFactor", 1,
    "ltrClFactor", 1,
    "ltrPredictMinStep", 0.001,
    "ltrPredictMaxStep", 0.5,
    "ltrPredictTMax", 1200,

    // Aerodynamic guidance. These must be tuned for the vehicle before flight.
    // PID outputs are pitch/yaw correction angles in degrees.
    "aeroPitchKp", 10,
    "aeroPitchKi", 0,
    "aeroPitchKd", 0,
    "aeroYawKp", 10,
    "aeroYawKi", 0,
    "aeroYawKd", 0,
    "aeroMaxPitch", 6,
    "aeroMaxYaw", 10,
    "aeroTargetOffset", 200,  // Aerodynamic gliding phase is aiming at target + aeroTargetOffset * downRangeVector, m

    // Landing burn
    "QuadraticAOABase", 30,  // AOA limit base during quadratic guidance phase, increase this value will allow larger AOA, deg
    "QuadraticAOADot", 1,  // AOA limit related to Time-to-go during quadratic guidance phase, increase this value will allow larger AOA when approaching ground, deg/s
    "landingBurnAltitude", 2300,  // Ignite decelerating engines (or landing fallback) below this, m
    "legDeploySpeed", 90,  // Deploy landing legs when speed is below this, m/s
    "touchDownSpeed", 1,  // touch down speed, m/s
    "landingPhase2Time", 5,  // time of untargeted landing phase 2, s
    "landingCutoffHeight", 0.2,  // cut off landing engines when height is below this, m
    "boundsUpdatePeriod", 1,  // frequency of updating bounding box, s
    // Keep a continuously ignited RO engine above zero command until cutoff.
    "minLandingThrottleCommand", 0.01
).

// these code will be fired soon after second stage seperation
FUNCTION pre_boostback_hook {
    // set steeringManager:maxstoppingtime to 1.
    // set steeringManager:pitchts to 8.
    set steeringManager:pitchpid:kd to 0.5.
    // set steeringManager:yawts to 8.
    set steeringManager:yawpid:kd to 0.5.
    // set steeringManager:rollts to 1.
    set steeringManager:rollpid:kd to 0.5.
    // set steeringManager:rollpid:epsilon to 0.1.
}

// these code will be fired soon after boostback maneuver is finished
FUNCTION pre_entryburn_hook {
    1.
}

// these code will be fired soon after entryburn is finished
FUNCTION pre_landingburn_hook {
    1.
}

if (ship:status = "PRELAUNCH" OR ship:status = "FLYING" OR ship:status = "SUB_ORBITAL") {
    runPath("0:/Falcon9_lib/gof9d.ks").
}
