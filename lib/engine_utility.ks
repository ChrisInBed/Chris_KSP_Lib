function get_engines_info {
	parameter elist.
	// calculate thrust and ISP and minimal throttle
	local _thrustvec to v(0, 0, 0).
	local _Isp to 0.0.
	local _minthrottle to 0.0.
	local _ullage to false.
	local _number to 0.
	local _spooluptime to 0.
	for e in elist {
		set _number to _number + 1.
		set _thrustvec to _thrustvec + e:possiblethrust * e:facing:vector.
		set _Isp to _Isp + (e:possiblethrust/max(100, e:visp)).
		set _minthrottle to max(_minthrottle, e:minthrottle).
		if e:ullage { set _ullage to true. }
		// RealFuel information: spool up time
		if e:hasmodule("ModuleEnginesRF") {
			local _rfmod to e:getmodule("ModuleEnginesRF").
			if _rfmod:hasfield("effective spool-up time") {
				set _spooluptime to max(_spooluptime, _rfmod:getfield("effective spool-up time")).
			}
		}
	}
	local _thrust to _thrustvec:mag.
	if _thrust < 1e-4 return lexicon("thrust", _thrust, "ISP", _Isp, "minthrottle", _minthrottle, "ullage", false, "spooluptime", 0.0).
	set _Isp to _thrust / _Isp.
	return lexicon("number", _number, "thrust", _thrust, "ISP", _Isp, "minthrottle", _minthrottle, "ullage", _ullage, "spooluptime", _spooluptime).
}

function need_ullage {
	parameter elist.
	for e in elist {
		if e:ullage { return true. }
	}
	return false.
}

function engine_stability {
	parameter elist.
	local _stability to 1.
	for e in elist {
		set _stability to min(_stability, e:fuelstability).
	}
	return _stability.
}

function print_engines_info {
	parameter elist.
	local _summary to get_engines_info(elist).
	for e in elist {
		print e:tag + " " + e:title.
	}
	print "Thrust = " + _summary:thrust.
	print "Isp = " + _summary:ISP.
	print "Minthrottle = " + _summary:minthrottle.
	print "Ullage = " + _summary:ullage.
}

function activate_engines {
	parameter _engs.
	if need_ullage(_engs) {
		RCS ON.
		set ship:control:fore to 1.
		wait until engine_stability(_engs) > 0.999.
	}
	lock throttle to 1.
	for e in _engs {
		e:activate().
	}
	set ship:control:fore to 0.
}

function deactivate_engines {
	parameter _engs.
	for e in _engs {
		e:shutdown().
	}
}

function search_engine {
	// return the engine list that contains the target name tag
	parameter P_ENGINE_TAG.
	list engines in elist.
	local matched_engines to list().
	for e in elist {
		if e:tag:contains(P_ENGINE_TAG) { matched_engines:add(e). }
	}
	return matched_engines.
}

function get_active_engines {
	list engines in elist.
	local matched_engines to list().
	for e in elist {
		if (e:ignition) {
			matched_engines:add(e).
		}
	}
	return matched_engines.
}

function get_burn_time {
	parameter P_MASS0.
	parameter P_THRUST.
	parameter P_ISP.
	parameter P_DV.
	if P_ISP < 1 or P_THRUST < 0.0001 { return -1. }
	local _isp to P_ISP * constant:g0.
	local mt to P_MASS0 * (constant:e ^ (-P_DV / _isp)).
	local bt to (P_MASS0 - mt) / (P_THRUST / _isp).
	return bt.
}

function engine_stage_check {
	if not stage:ready { return false. }
	list engines in elist.
	if elist:length = 0 { return false. }
	for e in elist {
		if e:stage = stage:number { set hasCurStageEngine to true. }
		if e:flameout { return true. }
	}
	if not (defined hasCurStageEngine) { return true. }
	else { unset hasCurStageEngine. }
	return false.
}

function engine_work_time {
	parameter P_ENGINE.
	local _worktime to 9999999999.
	for resource in P_ENGINE:consumedresources:values {
		set _worktime to min(_worktime, resource:amount / (resource:maxfuelflow+1e-8)).
	}
	return _worktime.
}

function get_curthrust {
	local elist to get_active_engines().
	local thrustvec to v(0, 0, 0).
	for e in elist {
		set thrustvec to thrustvec + e:thrust * e:facing:vector.
	}
	return thrustvec:mag.
}

function initialize_throttle_control {
	parameter f0.
	parameter thro_min.
	parameter thrust_target.
	return lexicon(
		"maxthrust", f0,
		"minthrottle", thro_min,
		"throttle", 0,
		"thrust", 0,
		"thrust_target", thrust_target,
		"pid", pidLoop(1, 0.01, 0)
	).
}

function update_throttle_control {
	parameter control_state.
	if control_state["minthrottle"] > 0.999 {
		return 1.
	}
	local throttle_target to (control_state["thrust_target"]/control_state["maxthrust"]).
	set throttle_target to simple_get_throttle(throttle_target, control_state["minthrottle"]).
	// local throttle_target to control_state["throttle"].
	set throttle_target to throttle_target
		+ control_state["pid"]:update(time:seconds,
		(control_state["thrust"]-control_state["thrust_target"])/(control_state["maxthrust"]*(1-control_state["minthrottle"]))).
	set throttle_target to min(max(throttle_target, 0.01), 1).
	set control_state["throttle"] to throttle_target.
	return throttle_target.
}

function simple_get_throttle {
	parameter real_thro.
	parameter min_thro.
	if (min_thro > 0.999) {return 1.}
	return max(0.01, min(1, (real_thro - min_thro) / (1 - min_thro))).
}