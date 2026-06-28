@lazyGlobal off.

WAIT UNTIL SHIP:UNPACKED.
CORE:PART:GETMODULE("kOSProcessor"):DOEVENT("Open Terminal").
clearScreen.
print "Automatic engine control script loaded".

local adjustmentStep is 0.5.
local allEngines is Lexicon().
for engine in ship:engines
{
	if engine:HasModule("ModuleEnginesAJERamjet")
	{
		local module is engine:GetModule("ModuleEnginesAJERamjet").
		allEngines:Add(module, Lexicon(
			"delegate", HandleRamjetEngine@,
			"maxEngineTemperature", module:GetHiddenField("maxEngineTemp") - 2,
			"thrustLimit", 100
		)).
	}
	
	if engine:HasModule("ModuleEnginesAJEJet")
	{
		local module is engine:GetModule("ModuleEnginesAJEJet").
		allEngines:Add(module, Lexicon(
			"delegate", HandleJetEngine@,
			"maxEngineTemperature", module:GetHiddenField("maxEngineTemp") - 2,
			"thrustLimit", 80
		)).
	}
}

if allEngines:length > 0
{
	print "managing engines".
	
	until false
	{
		for engine in allEngines:keys
		{
			allEngines[engine]["delegate"]:call(engine, allEngines[engine]).
		}

		wait 0.
	}
}
else
{
	print "No engines detected, stopping script".
}

local function HandleJetEngine
{
	local parameter engine, engineData is Lexicon().

	if engine:GetField("eng. internal temp") >= engineData["maxEngineTemperature"]
	{
		set engineData["thrustLimit"] to max(0, engineData["thrustLimit"] - adjustmentStep).

		if engine:GetField("thrust") < 1
		{
			if engine:HasEvent("shutdown engine")
			{
				engine:DoEvent("shutdown engine").
				set engineData["thrustLimit"] to 80.
			}
		}

		engine:SetField("thrust limiter", engineData["thrustLimit"]).
	}
}

local function HandleRamjetEngine
{
	local parameter engine, engineData is Lexicon().

	if engineData["thrustLimit"] <> engine:GetField("thrust limiter")
	{
		set engineData["thrustLimit"] to engine:GetField("thrust limiter").
	}

	if engine:GetField("eng. internal temp") >= engineData["maxEngineTemperature"]
	{
		set engineData["thrustLimit"] to max(0, engineData["thrustLimit"] - adjustmentStep).
		engine:SetField("thrust limiter", engineData["thrustLimit"]).
	}
}