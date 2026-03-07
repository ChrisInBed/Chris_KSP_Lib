wait until ship:unpacked.
clearScreen.
runOncePath("0:/lib/engine_utility.ks").
function set_throttle_limit {
	parameter _engs.
	parameter _throttle.
	for e in _engs {
		set e:thrustlimit to _throttle.
	}
}
function get_total_thrust {
	parameter _engs.
	local _total to 0.
	for e in _engs {
		set _total to _total + e:thrust.
	}
	return _total.
}.

function main {
	SAS OFF.
	RCS OFF.
	print "STS launch augmentation program".
	local myengs to search_engine("core").
	wait until myengs[0]:ignition.
	print "Ignition".
	wait 38+3.5.
	print "Core engine throttle down".
	set_throttle_limit(myengs, 17).
	wait 62-38.
	print "Core engine throttle up".
	set_throttle_limit(myengs, 80).
	wait until ship:partstagged("booster"):length = 0.
	print "Core engine throttle up".
	set_throttle_limit(myengs, 100).
	wait until ship:thrust < 1e-3.
	print "Core engine cutoff, executing rolling maneuver".
	RCS ON.
	lock steering to prograde.
	wait until abs(steeringManager:angleerror) + abs(steeringManager:rollerror) < 1 and ship:angularvel:mag < 0.1 / 90.
	unlock steering.
	print "Maneuver complete, returning control".
}

main().