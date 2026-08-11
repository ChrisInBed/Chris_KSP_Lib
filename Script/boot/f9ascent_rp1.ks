// Falcon 9 second stage boot file.
// Provides very simple open-loop ascent guidance
// If you want more capable rocket ascent guidance, please use PEGAS
// Distances are meters, time is seconds, speed is m/s, mass is metric tons,
// and angles are degrees unless noted otherwise.

local payloadMass to 14.573.
GLOBAL F9_ASCENT_PARAMS IS LEXICON(
    // Runtime
    "kOSIPU", 2000,
    "liftoffEngineTag", "liftoff",

    // Vehicle-specific values. These must be set before flight.
    "payloadMass", payloadMass,  // Mass of the payload, ton
    "mecoMass", 185 + payloadMass,  // When the mass is below MECO mass, trigger MECO, ton
    "targetHeading", 80,  // First stage ascent azimuth, deg
    "targetRoll", 0,  // Roll angle while whole process, deg

    // Launch
    "turnSpeed", 50,  // Gravity turn start speed, m/s
    "pitchOmega", 0.42,  // Programmed turn pitching speed, deg/s
    "stageSeparationDelay", 1,  // Time between MECO and 1st Stage Separation, s
    "upperStageIgnitionDelay", 2  // Time between 1st Stage Separation and second stage ignition, s
).

if (ship:status = "PRELAUNCH") {
    print "Activate AG10 to enable launch.".
    wait until ag10.
    runPath("0:/Falcon9_lib/gof9u.ks").
}
