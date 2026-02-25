GLOBAL CoreThruttleTarget IS 1.
GLOBAL vehicle IS LIST(
					LEXICON(
						"name", "main stage",
						"massTotal", 849735,
						"massDry", 120732,
						"engines", LIST(LEXICON("isp", 452.30, "thrust", 7093463)),
						"gLim", 4.5,
						"minThrottle", 0.59,
						"staging", LEXICON(
										"jettison", FALSE,
										"ignition", FALSE
										)
					)
).
GLOBAL sequence IS LIST(
					LEXICON("time", -3.5, "type", "stage", "message", "Engine Start"),
					LEXICON("time", 0, "type", "stage", "message", "LIFTOFF"),
					LEXICON("time", 30, "type", "delegate", "function", "CoreThrottleDown", "message", "Core stage throttle down"),
					// LEXICON("time", 120, "type", "jettison", "massLost", 199367, "message", "booster separation"),
					LEXICON("time", 120, "type", "stage", "message", "booster separation"),
					LEXICON("time", 121, "type", "delegate", "function", "CoreThrottleUp", "message", "Core stage throttle up")
).
GLOBAL controls IS LEXICON(
					"launchTimeAdvance", 120,
					"verticalAscentTime", 10,
					"pitchOverAngle", 8,
					"upfgActivation", 123,
					"initialRoll", 180,
					"disableThrustWatchdog", TRUE
).
GLOBAL mission IS LEXICON(
	"apoapsis", 200,
	"periapsis", 150,
	"inclination", 30,
	"payload", 0  // Change to your payload mass in kg
).
set config:IPU to 2000.
SET STEERINGMANAGER:ROLLTS TO 5.
SET STEERINGMANAGER:YAWTS TO 5.
SET STEERINGMANAGER:PITCHTS TO 5.
SET usc_convergeFlags TO LIST().

SWITCH TO 0.
CLEARSCREEN.
PRINT "Loaded boot file: STS!".