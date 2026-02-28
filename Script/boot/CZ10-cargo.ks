GLOBAL fairingMass to 202 * 2.
GLOBAL towerMass to 0.
GLOBAL BoosterInfo to lexicon(
	"massWet", 1230115,
	"massDry", 99231,
	"thrust", 19977100,
	"isp", 338.20
).
GLOBAL CoreInfo to lexicon(
	"massWet", 873490 + fairingMass + towerMass,
	"massDry", 308048 + fairingMass + towerMass,
	"thrust", 9988550,
	"isp", 338.20,
	"throttleMinLevel", 0.637,
	"throttleDownTime", 60,
	"throttleDownLevel", 0.64
).
GLOBAL CoreThrottleTarget to 100 * (CoreInfo:throttleDownLevel - CoreInfo:throttleMinLevel) / (1 - CoreInfo:throttleMinLevel).

local _initialStateConfig to make_throttle_stage_config(BoosterInfo, CoreInfo).

GLOBAL vehicle IS LIST(
					// upfg stage start after core stage throttle down
					// _initialStateConfig["fullStage"],
					_initialStateConfig["throttleDownStage"],  // guidance activate at throttle down stage
					_initialStateConfig["throttleUpStage"],
					LEXICON(
						"name", "stage2",
						"massTotal", 258064,
						"massDry", 82498,
						"engines", LIST(LEXICON("isp", 352.30, "thrust", 2900e3)),
						"spoolup", 3.14,
						"staging", LEXICON(
										"jettison", TRUE,
										"waitBeforeJettison", 3,
										"ignition", TRUE,
										"waitBeforeIgnition", 1.5,
										"ullage", "none"
										)
					),
					LEXICON(
						"name", "stage3",
						"massTotal", 67000,
						"massDry", 7701,
						"engines", LIST(LEXICON("isp", 451, "thrust", 276324)),
						"spoolup", 1.60,
						"staging", LEXICON(
										"jettison", TRUE,
										"waitBeforeJettison", 5,
										"ignition", TRUE,
										"waitBeforeIgnition", 0.5,
										"ullage", "rcs",
										"ullageBurnDuration", 3,
										"postUllageBurn", 2
										)
					)
).
GLOBAL sequence IS LIST(
					LEXICON("time", -3, "type", "stage", "message", "Engine Start"),
					LEXICON("time", 0, "type", "stage", "message", "LIFTOFF"),
					LEXICON("time", _initialStateConfig["ts"], "type", "delegate", "function", "CoreThrottleDown", "message", "Core stage throttle down"),
					LEXICON("time", _initialStateConfig["te"] + 1, "type", "jettison", "massLost", _initialStateConfig["jettisonMass"], "message", "booster separation"),
					LEXICON("time", _initialStateConfig["te"] + 1.5, "type", "delegate", "function", "CoreThrottleUp", "message", "Core stage throttle up"),
					LEXICON("time", _initialStateConfig["te"] + 20, "type", "jettison", "massLost", fairingMass + towerMass, "message", "jettison fairing and tower")
).
GLOBAL controls IS LEXICON(
					"launchTimeAdvance", 120,
					"verticalAscentTime", 20,
					"pitchOverAngle", 4,
					"upfgActivation", 125,
					"initialRoll", 90,
					"disableThrustWatchdog", TRUE
).
GLOBAL mission IS LEXICON(
	"apoapsis", 200,
	"periapsis", 200,
	"payload", 18146  // Change to your payload mass in kg
).
set config:IPU to 2000.
SET STEERINGMANAGER:ROLLTS TO 10.
SET usc_convergeFlags TO LIST().

SWITCH TO 0.
CLEARSCREEN.
PRINT "Loaded boot file: CZ-10!".

function make_throttle_stage_config {
	parameter boosterInfo.
	parameter coreInfo.

	local mdotB to boosterInfo:thrust / (boosterInfo:isp * constant:g0).
	local mdotC to coreInfo:thrust / (coreInfo:isp * constant:g0).
	local ts to coreInfo:throttleDownTime.
	local te to (boosterInfo:massWet - boosterInfo:massDry) / mdotB.

	local mbs to boosterInfo:massWet - mdotB * ts.
	local mcs to coreInfo:massWet - mdotC * ts.
	local mbe to boosterInfo:massDry.
	local mce to mcs - coreInfo:throttleDownLevel * mdotC * (te - ts).

	local tj to te + (mce - coreInfo:massDry) / mdotC.

	local fullStageConfig to lexicon(
		"name", "full thrust",
		"massTotal", boosterInfo:massWet + coreInfo:massWet,
		"massDry", mbs + mcs,
		"engines", list(
			lexicon("isp", boosterInfo:isp, "thrust", boosterInfo:thrust),
			lexicon("isp", coreInfo:isp, "thrust", coreInfo:thrust)
		),
		"staging", lexicon(
			"jettison", false,
			"ignition", false
		)
	).
	local throttleDownStageConfig to lexicon(
		"name", "throttle down",
		"massTotal", fullStageConfig["massDry"],
		"massDry", mbe + mce,
		"engines", list(
			lexicon("isp", coreInfo:isp, "thrust", coreInfo:thrust * coreInfo:throttleMinLevel),
			lexicon("isp", boosterInfo:isp, "thrust", boosterInfo:thrust)
		),
		"staging", lexicon(
			"jettison", false,
			"ignition", false
		)
	).
	local throttleUpStageConfig to lexicon(
		"name", "throttle up",
		"massTotal", mce,
		"massDry", coreInfo:massDry,
		"engines", list(
			lexicon("isp", coreInfo:isp, "thrust", coreInfo:thrust)
		),
		"staging", lexicon(
			"jettison", false,
			"ignition", false
		)
	).

	return lexicon(
		"fullStage", fullStageConfig,
		"throttleDownStage", throttleDownStageConfig,
		"throttleUpStage", throttleUpStageConfig,
		"jettisonMass", boosterInfo:massDry,
		"ts", ts,
		"te", te,
		"tj", tj
	).
}