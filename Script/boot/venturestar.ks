GLOBAL vehicle IS LIST(
					LEXICON(
						"name", "main",
						"massTotal", 1200000,  // Random value, program will detect vessel mass
						"massDry", 127987,
						"engines", LIST(LEXICON("isp", 455.00, "thrust", 15400001)),
						"gLim", 2.5,
						"minThrottle", 0.05,
						"staging", LEXICON(
										"jettison", FALSE,
										"ignition", FALSE
										)
					)
).
GLOBAL sequence IS LIST(
					LEXICON("time", -5, "type", "stage", "message", "Engine Start"),
					LEXICON("time", 0, "type", "stage", "message", "LIFTOFF")
					// LEXICON("time", 380, "type", "roll", "angle", 0, "message", "Roll maneuver")
).
GLOBAL controls IS LEXICON(
					"launchTimeAdvance", 120,
					"verticalAscentTime", 32,
					"pitchOverAngle", 5,
					"upfgActivation", 110,
					"initialRoll", 0,
					"disableThrustWatchdog", TRUE
).
GLOBAL mission IS LEXICON(
	"apoapsis", 300,
	"periapsis", 145,
	"inclination", 52,
	"payload", 0  // Change to your payload mass in kg
).
// set config:IPU to 2000.
// SET STEERINGMANAGER:ROLLTS TO 3.
// SET STEERINGMANAGER:YAWTS TO 3.
// SET STEERINGMANAGER:PITCHTS TO 3.
// SET usc_convergeFlags TO LIST().

SWITCH TO 0.
CLEARSCREEN.
PRINT "Loaded boot file: VentureStar!".