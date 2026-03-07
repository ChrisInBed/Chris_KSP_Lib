GLOBAL CoreThrottleTarget IS 17.
GLOBAL vehicle IS LIST(
					LEXICON(
						"name", "main stage",
						"massTotal", 849735,
						"massDry", 124606,
						"engines", LIST(LEXICON("isp", 452.30, "thrust", 7093463)),
						"gLim", 3.5,
						"minThrottle", 0.59,
						"staging", LEXICON(
										"jettison", FALSE,
										"ignition", FALSE
										)
					)
).
local boosterSepTime to 118.
GLOBAL sequence IS LIST(
					LEXICON("time", -3.5, "type", "stage", "message", "Engine Start"),
					LEXICON("time", 0, "type", "stage", "message", "LIFTOFF"),
					LEXICON("time", 38, "type", "delegate", "function", "CoreThrottleDown", "message", "Core stage throttle down"),
					LEXICON("time", 70, "type", "delegate", "function", "CoreThrottleUp", "message", "Core stage throttle up"),
					LEXICON("time", boosterSepTime, "type", "stage", "message", "booster separation")
					// LEXICON("time", 380, "type", "roll", "angle", 0, "message", "Roll maneuver")
).
GLOBAL controls IS LEXICON(
					"launchTimeAdvance", 120,
					"verticalAscentTime", 10,
					"pitchOverAngle", 8,
					"upfgActivation", boosterSepTime + 6,
					"initialRoll", 180,
					"disableThrustWatchdog", TRUE
).
GLOBAL mission IS LEXICON(
	"apoapsis", 200,
	"periapsis", 120,
	"inclination", 52,
	"payload", 200+976+20861  // Change to your payload mass in kg
).
// set config:IPU to 2000.
SET STEERINGMANAGER:ROLLTS TO 3.
SET STEERINGMANAGER:YAWTS TO 3.
SET STEERINGMANAGER:PITCHTS TO 3.
// SET usc_convergeFlags TO LIST().

SWITCH TO 0.
CLEARSCREEN.
PRINT "Loaded boot file: STS_SSS!".