parameter P_ENGINE is "current".
parameter P_guidance is true.
parameter P_burntime is -1.

print "Execute pulse maneuver node with high accuracy".
print "Usage: run exe_pulse_node([Mode], [Engine], [burntime])".
print "[Engine]:".
print "  A name tag of the target engine. The script will automatically activate this engine while flying.
If 'auto', the currently activated engine will be used, and the vessel will be automatically staged if the 
current stage is out
If 'current', the program will use currently activated engines".
print "[guidance]:".
print "  If true, the program will align ship to node direction before executing the node".
print "  Else, the program will execute the node directly".
print "[burntime]:".
print "  The burn time of the maneuver, only usable when executing a pulse maneuver node.".
print "  If not set, the program will calculate the burn time automatically.".

runOncePath("./lib/engine_utility.ks").

set done to false.
if P_ENGINE = "auto" {
	when engine_stage_check() then {
		stage.
		set elist to get_active_engines().
		return (not done).
	}
	wait 0.1.  // wait for staging
	print "Engine autostaging.".
	set elist to get_active_engines().
}
else if P_ENGINE = "current" {
	set elist to get_active_engines().
}
else {
	set elist to search_engine(P_ENGINE).
}
print_engines_info(elist).
set enginfo to get_engines_info(elist).
if enginfo:thrust < 1e-4 {
	print "Cannot aquire engine infomation".
}
set mymaxthrust to enginfo:thrust.
set Isp to enginfo:ISP.
set minthrottle to enginfo:minthrottle.
set ullage to enginfo:ullage.
set TiS to enginfo:TiS.

if ullage {
	set ullage_time to 1.
}
else {
	set ullage_time to 0.
}

set nd to nextNode.
set _targetVI to nd:deltav:mag.
print "deltaV = " + _targetVI.
if P_burntime > 0 {
	set burntime to P_burntime.
}
else {
	set burntime to get_burn_time(ship:mass, mymaxthrust, Isp, _targetVI).
}
if burntime < 0 {
	set burntime to P_burntime.
	if burntime < 0 {
		print "failed to calculate burn time, aborting...".
		set _1 to 1 / 0.
	}
}

print "Executing maneuver:".
print nd.
print "deltaV = " + _targetVI.
print "acceleration time = " + burntime.

function get_target_attitude {
	parameter vecT.
	return lookDirUp(vecT, vXcl(vecT, prograde:upvector)+vCrs(vecT, prograde:starvector)) * TiS.
}

if P_guidance {
	wait until nd:eta <= 40 + burntime/2 + ullage_time.
	SAS OFF.
	RCS ON.
	print "Aligning pose".
	lock steering to get_target_attitude(nd:deltav).
	wait until vAng(nd:deltav, (ship:facing * TiS:inverse):forevector) < 0.5.
	print "Pose aligned".
}
wait until nd:eta <= burntime/2 + ullage_time.
// prepare for velocity integral
set _IntFlag to true.
set _VI to 0.
set _maxacc to 0.
lock _r to ship:body:position.
lock _bodyacc to ship:body:mu / (_r:mag)^3 * _r.
set _v0 to ship:velocity:orbit.
set _v1 to ship:velocity:orbit.
set _t0 to time:seconds.
set _t1 to time:seconds.
when true then {
	set _t1 to time:seconds.
	set _v1 to ship:velocity:orbit.
	set _VI to _VI + (_v1 - _v0 - _bodyacc * (_t1 - _t0)):mag.
	set _maxacc to max(_maxacc, ((_v1 - _v0)/(_t1 - _t0) - _bodyacc):mag).
	set _t0 to _t1.
	set _v0 to _v1.
	return _IntFlag.
}
print "Fire".
activate_engines(elist, ullage_time).
wait until _VI >= _targetVI - _maxacc * 0.1.
// a mini P-loop
set _VI0 to _VI.
if _VI0 < _targetVI {
	lock throttle to max(0.01, min(1,  (_targetVI - _VI) / (_targetVI - _VI0))).
	wait until _VI >= _targetVI.
}
lock throttle to 0.
set _IntFlag to false. // end integral
wait 0.2.

print "Maneuver finished.".
unset mymaxthrust.
unset minthrottle.
unset ullage.
unset Isp.
unset elist.
unset ullage_time.
unset nd.
unset _targetVI.
unset _IntFlag.
unset _VI.
unset _VI0.
unset _maxacc.
unlock _r.
unlock _bodyacc.
unset _v0.
unset _v1.
unset _t0.
unset _t1.
unlock steering.
unlock throttle.
set done to true.
