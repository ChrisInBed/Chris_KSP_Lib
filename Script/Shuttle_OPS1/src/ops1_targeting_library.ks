
//GLOBAL NAV VARIABLES 

GLOBAL launchpad IS SHIP:GEOPOSITION.
GLOBAL surfacestate IS  LEXICON(
								"time",0,
								"deltat", 0,
								"MET",0,
								"surfv", v(0,0,0),
								"dwnrg_dst", 0,
								"horiz_dwnrg_v", v(0,0,0),
								"az",0,
								"pitch",0,
								"alt",0,
								"vs",0,
								"hs",0,
								"vdir",0,
								"hdir",0,
								"q",0, 
								"maxq", 0,
								"eas", 0
).

GLOBAL orbitstate IS  LEXICON(
								"radius",v(0,0,0),
								"velocity",v(0,0,0)
). 


//			VARIOUS TARGETING FUNCTIONS

//for logging data in case of RTLS
//calculates the horizontal component of surface velocity 
//projected along the plane of current position and launchpad
FUNCTION current_horiz_dwnrg_speed {
	PARAMETER pos.
	PARAMETER srfvel.

	LOCAL launchvec IS pos2vec(launchpad).
	LOCAL posvec IS pos2vec(pos).
	
	LOCAL norm is VCRS(posvec, launchvec):NORMALIZED.
	LOCAL dwnrgvec IS posvec - launchvec.
	
	LOCAL horizvel IS VXCL(posvec, srfvel).
	SET horizvel TO VXCL(norm, horizvel).
	
	RETURN VDOT(dwnrgvec:NORMALIZED, horizvel).

}

// normal vector of the current instantaneous orbital plane
//it's opposite of upfg normal vector convention 
FUNCTION currentNormal{
	RETURN VCRS(orbitstate["radius"],orbitstate["velocity"]):NORMALIZED.
}

//limit off-plane component of steering
//upfg-compatible steering
function limit_yaw_steering {
	parameter steervec.
	parameter normvec.
	
	local steerproj is vxcl(normvec, steervec):normalized.
	
	local yaw_angle is signed_angle(
						steerproj,
						steervec,
						orbitstate["radius"],
						0
	).
	
	return rodrigues(
				steerproj,
				orbitstate["radius"],
				sign(yaw_angle)*min(abs(yaw_angle), ops1_parameters["yaw_steer_lim"])
	):normalized.

}


FUNCTION nominal_cutoff_params {
	PARAMETER tgt_orb.
	PARAMETER cutoff_r.
	
	//updating this every loop is NOT optional
	SET tgt_orb["normal"] TO upfg_normal(tgt_orb["inclination"], tgt_orb["LAN"]).
	
	set tgt_orb["radius"] to cutoff_r.
	
	local cut_alt is tgt_orb["radius"]:MAG.
	set tgt_orb["eta"] to orbit_alt_eta(cut_alt, tgt_orb["SMA"], tgt_orb["ecc"]).
	
	set tgt_orb["velocity"] to orbit_alt_vel(cut_alt, tgt_orb["SMA"]).
	
	set tgt_orb["fpa"] to orbit_eta_fpa(tgt_orb["eta"], tgt_orb["SMA"], tgt_orb["ecc"]).

	RETURN tgt_orb.
}

//upfg-compatible velocity vector
//expects normal vector as the left-handed product of position and velocity
function cutoff_velocity_vector {
	parameter cutoff_r.
	parameter normvec.
	parameter cutoff_vel.
	parameter cutoff_fpa.
	
	local ix_ is cutoff_r:normalized.
	local iy_ is normvec:normalized.
	local iz_ is VCRS(ix_, iy_):NORMALIZED.
	
	return rodrigues(iz_, iy_, cutoff_fpa):NORMALIZED * cutoff_vel.	

}

//givne target deltav and performance, solves for constant thrust angle and burn time 
//that solve the velocity equatinos of motion accounting for gravity
//then compares with the current budget
function estimate_excess_deltav {
	parameter r0.
	parameter v0.
	parameter tgt_deltav.
	parameter perf.
	
	local iz_ is r0:normalized.
	
	local v0h is vxcl(iz_, v0):mag.
	local r0m is r0:mag.
	
	local tgt_dvh is vxcl(iz_, tgt_deltav):mag.
	local tgt_dvv is vdot(iz_, tgt_deltav).
	
	//print geff at (0,0).

	local m0 is perf["m_initial"].
	local mdot is perf["engines"]["flow"].
	local thrust_ is perf["engines"]["thrust"]*perf["throt"].
	local vex is thrust_/mdot.
	local mbar is m0 - 0.5*mdot*perf["time"].
	
	local v0eff is v0h + vex*LN(m0/mbar).
	local geff is BODY:MU / (r0m^2) - (v0eff)^2 / r0m.
	
	local tu0 is m0 * vex * (1 - CONSTANT:E^(- tgt_dvh/vex)).
	local c_ is tgt_dvv * mbar / tu0.
	local b_ is geff / (thrust_/mbar).
	
	local y_ is 1 + c_^2 - b_^2.
	
	//print tgt_dvv at (0,1).
	//print tgt_dvh at (0,2).
	
	//print b_  at (0,3).
	//print c_  at (0,4).
	
	local dvtot is 0.
	
	if (y_ <= 0) {
		set vgrav to geff * perf["time"].
	} else {
		local x_1 is (b_ + c_ * sqrt(y_))/(1 + c_^2).
		local x_2 is (b_ - c_ * sqrt(y_))/(1 + c_^2).
		
		local x_ is 0.
		if (abs(x_1) < 1) {
			set x_ to x_1.
		} else {
			set x_ to x_2.
		}
		
		//print x_1  at (0,5).
		//print x_2  at (0,6).
		
		local dt1 is tu0/(thrust_ * sqrt(1 - x_^2) ).
		set dt1 to min(dt1, perf["time"]).
		
		//print arcsin(x_)  at (0,7).
		//print dt1  at (0,8).
		
		set vgrav to x_ * vex * ln(m0/(m0 - mdot*dt1)).
	}
	
	local dvtot is sqrt(vgrav^2 + tgt_dvh^2).
	
	local dvbias is 10.
	
	return perf["deltav"] - dvtot - dvbias.

}

//only called if hastarget=true
//propagates the current target orbital parameters forward in time 
//given a delta-t and applies secular variations
//given by j2 perturbation
FUNCTION tgt_j2_timefor {
	PARAMETER tgt_orb.
	PARAMETER deltat.
	
	LOCAL j2LNG is -1.5*1.08262668e-3*rad2deg((BODY:RADIUS/(TARGET:ORBIT:SEMIMAJORAXIS*(1 - TARGET:ORBIT:ECCENTRICITY^2)))^2*SQRT(BODY:MU/TARGET:ORBIT:SEMIMAJORAXIS^3)*COS(TARGET:ORBIT:INCLINATION)).
	
	SET tgt_orb["LAN"] TO  fixangle(TARGET:ORBIT:LAN +  j2LNG*deltat ).
	SET tgt_orb["inclination"] TO TARGET:ORBIT:INCLINATION.	
}							   

FUNCTION warp_window{
	parameter warp_dt.
	
	LOCAL launch_time IS TIME:SECONDS + warp_dt.
	addGUIMessage("TIME TO WINDOW : " + sectotime(warp_dt)).

	UNTIL FALSE {
	
		LOCAL timetolaunch IS launch_time - TIME:SECONDS.
		
		warp_controller(timetolaunch, TRUE, 2).
		
		IF (timetolaunch <=0.1) {BREAK.}
		
		Wait 0.
	}
	set warp to 0.
}

// calculate target orbital parameters 
//calculate launch azimuth and window and handle warp 
FUNCTION prepare_launch {

	clearvecdraws().

	target_orbit:ADD("direction", "nearest").
	target_orbit:ADD("sma", 0).
	target_orbit:ADD("ecc", 0).
	target_orbit:ADD("eta", 0).
	target_orbit:ADD("LAN", 0).
	target_orbit:ADD("radius", 0).
	target_orbit:ADD("velocity", 0).
	target_orbit:ADD("normal", V(0,0,0)).
	target_orbit:ADD("fpa", 0).
	target_orbit:ADD("launch_az", 0).
	target_orbit:ADD("warp_dt", 0).
	target_orbit:ADD("mode", 1).
	
	//first compute in-plane orbital parameters
	
	//check altitudes
	
	IF target_orbit["periapsis"]>target_orbit["apoapsis"] {
		local ap_ is target_orbit["apoapsis"].
		set target_orbit["apoapsis"] to target_orbit["periapsis"].
		set target_orbit["periapsis"] to ap_.
	}
	
	IF NOT target_orbit:HASKEY("cutoff alt") {
		target_orbit:ADD("cutoff alt", target_orbit["periapsis"]).
	} ELSE {
		IF (target_orbit["cutoff alt"] < target_orbit["periapsis"]) {
			SET target_orbit["cutoff alt"] TO target_orbit["periapsis"].
		} ELSE IF (target_orbit["cutoff alt"] > target_orbit["apoapsis"]) {
			SET target_orbit["cutoff alt"] TO target_orbit["apoapsis"].
		}
	}
	
	SET target_orbit["sma"] TO orbit_appe_sma(target_orbit["apoapsis"], target_orbit["periapsis"]).
	SET target_orbit["ecc"] TO orbit_appe_ecc(target_orbit["apoapsis"], target_orbit["periapsis"]).
	
	LOCAL cutoff_r IS target_orbit["cutoff alt"]*1000 + SHIP:BODY:RADIUS.
	
	//compute cutoff orbital parameters
	
	SET target_orbit["eta"] TO orbit_alt_eta(cutoff_r, target_orbit["sma"], target_orbit["ecc"]).
	set target_orbit["velocity"] to orbit_alt_vel(cutoff_r, target_orbit["sma"]).


	// now compute orbital plane

	// check inclination 
	//overridden in case of targeted launch
	//negative for southerly launches
	IF NOT target_orbit:HASKEY("inclination") {
		target_orbit:ADD("inclination", SHIP:GEOPOSITION:LAT).
	} ELSE {
		IF ABS(target_orbit["inclination"])<SHIP:GEOPOSITION:LAT {
			SET target_orbit["inclination"] TO SIGN(target_orbit["inclination"])*SHIP:GEOPOSITION:LAT.
		}
	}
	
	
	//compute lan given the various options
	
	//the second check only filters targets in earth orbit e.g. no interplanetary targets
	IF (HASTARGET = TRUE AND TARGET:BODY = SHIP:BODY) {
		SET target_orbit["LAN"] TO TARGET:ORBIT:LAN.
		SET target_orbit["inclination"] TO TARGET:ORBIT:INCLINATION.	
		
	} ELSE {
		IF target_orbit["inclination"] < 0 {
			SET target_orbit["direction"] TO "south".
			SET target_orbit["inclination"] TO ABS(target_orbit["inclination"]).	
		} ELSE {
			SET target_orbit["direction"] TO "north".
		}
		SET target_orbit["LAN"] TO LAN_orbit_overhead(target_orbit["inclination"], (target_orbit["direction"]="south"), ops1_parameters["launchTimeAdvance"] + vehicle_countdown + 1).
	}
	
	//handle nearest launch window
	//compute nearest launch direction
	IF (target_orbit["direction"]="nearest") {
			
		LOCAL shiplngvec IS VXCL(V(0,1,0), -SHIP:ORBIT:BODY:POSITION):NORMALIZED.
		
		LOCAL dlng IS get_a_bBB(SHIP:GEOPOSITION:LAT, target_orbit["inclination"]).
		
		LOCAL north_launch_vec IS rodrigues(SOLARPRIMEVECTOR, V(0,1,0), -(target_orbit["LAN"] - dlng)).
		LOCAL south_launch_vec IS rodrigues(SOLARPRIMEVECTOR, V(0,1,0), -(target_orbit["LAN"] + 180 - dlng)).

		//arrow_body(north_launch_vec, "north").
		//arrow_body(south_launch_vec, "south").
		//arrow_body(shiplngvec, "ship").
		
		LOCAL north_dlan IS signed_angle(shiplngvec, north_launch_vec, V(0,1,0), 1).
		LOCAL south_dlan IS signed_angle(shiplngvec, south_launch_vec, V(0,1,0), 1).
		
		//print " north_dlan " + north_dlan at (0,61).
		//print " south_dlan " + south_dlan at (0,62).
		
		IF (south_dlan < north_dlan) {
			SET target_orbit["direction"] TO "south". 
		} ELSE {
			SET target_orbit["direction"] TO "north". 
		}
	}
	
	//time to window
	LOCAL time2window IS orbitInterceptTime(target_orbit["inclination"], target_orbit["LAN"], (target_orbit["direction"]="south")).
	
	//if launching into plane of target account for J2 nodal precession
	IF HASTARGET = TRUE AND (TARGET:BODY = SHIP:BODY) {
		LOCAL t2w IS time2window.
		LOCAL j2LNG is -1.5*1.08262668e-3*rad2deg((BODY:RADIUS/(TARGET:ORBIT:SEMIMAJORAXIS*(1 - TARGET:ORBIT:ECCENTRICITY^2)))^2*SQRT(BODY:MU/TARGET:ORBIT:SEMIMAJORAXIS^3)*COS(TARGET:ORBIT:INCLINATION)).
		LOCAL lan_old IS target_orbit["LAN"].
		UNTIL FALSE {
			//print ltt_old AT (0,54).
			SET target_orbit["LAN"] TO  fixangle(lan_old +  j2LNG*t2w ).
			LOCAL t2w_new IS orbitInterceptTime(target_orbit["inclination"], target_orbit["LAN"], (target_orbit["direction"]="south")).
			
			//print ltt_new AT (0,55).
			
			IF ABS(t2w - t2w_new)<0.05 {
				BREAK.
			}
			SET t2w TO t2w_new.
			SET target_orbit["inclination"] TO TARGET:ORBIT:INCLINATION.	
		}
		SET time2window TO t2w.
	}
	
	SET time2window TO time2window - ops1_parameters["launchTimeAdvance"].
	
	IF (time2window < vehicle_countdown) {
		SET time2window TO time2window + SHIP:BODY:ROTATIONPERIOD.
	}
	
	set target_orbit["warp_dt"] to time2window  - vehicle_countdown.
	
	//this is for message logging
	SET vehicle["ign_t"] TO TIME:SECONDS + time2window. 
	
	set target_orbit["launch_az"] to launchAzimuth(target_orbit["inclination"], target_orbit["velocity"], (target_orbit["direction"]="south")).
	
	IF (NOT ops1_parameters["override_az_limit"]) {
		//implement range azimuth limitation
		//if the launchsite is within 50km of a known site
		//apply its range restrictions
		LOCAL site_azrange IS LEXICON(
							"KSC",LEXICON(
									"position",LATLNG(28.61938,-80.70092),
									"min_az",35,
									"max_az",120
							),
							"Vandenberg",LEXICON(
									"position",LATLNG(34.67974,-120.53102),
									"min_az",147,
									"max_az",320
							)
		
		).
		
		FOR s IN site_azrange:VALUES{
			LOCAL sitepos IS s["position"].
			
			IF downrangedist(sitepos,SHIP:GEOPOSITION) < 50 {
				SET target_orbit["launch_az"] TO CLAMP(target_orbit["launch_az"], s["min_az"], s["max_az"]).
				BREAK.
			}
		}
	}


	//print target_orbit:dump.
	//arrow_body(targetLANvec(target_orbit["LAN"]), "lan").
	//arrow_body(targetNormal(target_orbit["inclination"], target_orbit["LAN"]), "norm").
	//until false{}	
	
	initialise_abort_sites().
	
	warp_window(target_orbit["warp_dt"]).	
	
	//initialise target normal and velocity for abort calculations - in upfg coords
	
	SET target_orbit["normal"] TO upfg_normal(target_orbit["inclination"], target_orbit["LAN"]).
	local cur_r is vecYZ(SHIP:ORBIT:BODY:POSITION)*-1.
	local cutvec is VXCL(target_orbit["normal"], cur_r):NORMALIZED.
	set cutvec to rodrigues(cutvec, target_orbit["normal"], 10).
	local cutoff_r is cutvec:NORMALIZED * (target_orbit["cutoff alt"]*1000 + SHIP:BODY:RADIUS).
	SET target_orbit TO nominal_cutoff_params(target_orbit, cutoff_r).
}


function target_orbit_dump {
	IF EXISTS("0:/Shuttle_OPS1/LOGS/target_orbit_dump.txt") {
		DELETEPATH("0:/Shuttle_OPS1/LOGS/target_orbit_dump.txt").
	}
	
	log target_orbit:dump() to "0:/Shuttle_OPS1/LOGS/target_orbit_dump.txt".
}




//		NAVIGATION FUNCTIONS 



FUNCTION update_navigation {
	
	local t_prev is surfacestate["time"].
	SET surfacestate["time"] TO TIME:SECONDS.
	set surfacestate["deltat"] to surfacestate["time"] - t_prev.
	SET surfacestate["MET"] TO surfacestate["time"] - vehicle["ign_t"]. 
	
	
	//measure position and orbit parameters
	
	LOCAL progv IS v(0,0,0).
	

	
	IF (vehiclestate["major_mode"] = 101) OR (vehiclestate["major_mode"] = 102) {set progv to SHIP:SRFPROGRADE:VECTOR.}
	ELSE {set progv to SHIP:PROGRADE:VECTOR.}
	
	SET surfacestate["surfv"] TO SHIP:VELOCITY:SURFACE.
	SET surfacestate["dwnrg_dst"] TO downrangedist(launchpad,SHIP:GEOPOSITION ).
	SET surfacestate["horiz_dwnrg_v"] TO current_horiz_dwnrg_speed(SHIP:GEOPOSITION, SHIP:VELOCITY:SURFACE).
	SET surfacestate["hdir"] TO compass_for(progv,SHIP:GEOPOSITION ).
	SET surfacestate["vdir"] TO 90 - VANG(progv, SHIP:UP:VECTOR).
	SET surfacestate["pitch"] TO 90 - VANG(SHIP:FACING:VECTOR, SHIP:UP:VECTOR).	
	SET surfacestate["az"] TO compass_for(SHIP:FACING:VECTOR,SHIP:GEOPOSITION ).
	SET surfacestate["alt"] TO SHIP:ALTITUDE.
	SET surfacestate["vs"] TO SHIP:VERTICALSPEED.
	SET surfacestate["hs"] TO SHIP:VELOCITY:SURFACE:MAG.
	set surfacestate["q"] to SHIP:Q.
	
	set surfacestate["eas"] to 17.1865 * sqrt(SHIP:Q * 2116.217).
	
	SET orbitstate["velocity"] TO vecYZ(SHIP:ORBIT:VELOCITY:ORBIT).
	SET orbitstate["radius"] TO vecYZ(SHIP:ORBIT:BODY:POSITION)*-1.

}