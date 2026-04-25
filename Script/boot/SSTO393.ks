GLOBAL vehicle IS LIST(
					LEXICON(
						"name", "SL",
						"massTotal", 3088674,
						"massDry", 921468 + 30e3,  // Add 30 ton to support hot staging
						"engines", LIST(LEXICON("isp", 341.50, "thrust", 45492216)),
						"staging", LEXICON(
										"jettison", FALSE,
										"ignition", FALSE
										)
					),
					LEXICON(
						"name", "VAC",
						"massTotal", 921468,
						"massDry", 276960,
						"engines", LIST(LEXICON("isp", 433.17, "thrust", 7985705)),
						"spoolup", 2.81,
						"staging", LEXICON(
										"jettison", FALSE,
										"ignition", TRUE,
										"waitBeforeIgnition", 0,
										"ullage", "none"
										)
					)
).
GLOBAL sequence IS LIST(
					LEXICON("time", -3.10, "type", "stage", "message", "Engine Start"),
					LEXICON("time", 0, "type", "stage", "message", "LIFTOFF")
					// LEXICON("time", 380, "type", "roll", "angle", 0, "message", "Roll maneuver")
).
GLOBAL controls IS LEXICON(
					"launchTimeAdvance", 120,
					"verticalAscentTime", 15,
					"pitchOverAngle", 5.7,
					"upfgActivation", 110,
					"initialRoll", 0,
					"disableThrustWatchdog", TRUE
).
GLOBAL mission IS LEXICON(
	"apoapsis", 300,
	"periapsis", 145,
	"inclination", 35,
	"payload", 0  // Change to your payload mass in kg
).
// set config:IPU to 2000.
// SET STEERINGMANAGER:ROLLTS TO 3.
// SET STEERINGMANAGER:YAWTS TO 3.
// SET STEERINGMANAGER:PITCHTS TO 3.
// SET usc_convergeFlags TO LIST().

SWITCH TO 0.
CLEARSCREEN.
PRINT "Loaded boot file: SSTO-39.3!".