@LAZYGLOBAL OFF.
CLEARSCREEN.
SET CONFIG:IPU TO 1200.	
GLOBAL quit_program IS FALSE.

RUNPATH("0:/Shuttle_OPS1/parameters").

//	Load libraries
RUNPATH("0:/Shuttle_OPS3/landing_sites").
RUNPATH("0:/Libraries/misc_library").	
RUNPATH("0:/Libraries/maths_library").	
RUNPATH("0:/Libraries/navigation_library").	
RUNPATH("0:/Libraries/vehicle_library").	
RUNPATH("0:/Libraries/aerosim_library").	


RUNPATH("0:/Shuttle_OPS1/src/ops1_interface").
RUNPATH("0:/Shuttle_OPS1/src/ops1_vehicle_library").
RUNPATH("0:/Shuttle_OPS1/src/ops1_targeting_library").
RUNPATH("0:/Shuttle_OPS1/src/ops1_upfg_library").
RUNPATH("0:/Shuttle_OPS1/src/ops1_abort_library").
RUNPATH("0:/Shuttle_OPS1/src/ops1_gui_library.ks").

function ops1_main_exec {

	close_all_GUIs().
	
	make_main_ascent_gui().
	make_ascent_traj1_disp().
	
	wait until ship:unpacked and ship:loaded.
	
	initialise_shuttle().
	prepare_launch().	
	
	
	//need to have initalised the vehicle first for the vessel name
	prepare_telemetry().
	
	GLOBAL dap IS ascent_dap_factory().
	
	GLOBAL dap_gui_executor IS loop_executor_factory(
												ops1_parameters["control_loop_dt"],
												{
													//protection
													if (SAS) {
														SAS OFF.
													}
													
													if (is_dap_auto()) {
														dap:steer_auto_thrvec().
														dap:thr_control_auto().
													} else if (is_dap_css()) {
														dap:steer_css().
														dap:thr_control_css().
													}
													
													set get_stage()["Throttle"] to dap:thr_rpl_tgt.
													
													if (ops1_parameters["dap_debug"]) {
														//clearscreen.
														clearvecdraws().
														
														dap:print_debug(2).
														
														arrow_ship(3 * dap:steer_thrvec,"steer_thrvec").
														arrow_ship(2 * dap:steer_dir:forevector,"forevec").
														arrow_ship(2 * dap:steer_dir:topvector,"topvec").
													
													}
													
													dataViz().
												}
	).
	
	IF (NOT ops1_countdown()) {
		if (NOT quit_program) {
			WAIT 5.
		}
		clean_up_ops1().
		RETURN.
	}
	
	ops1_first_stage().
	
	if (quit_program) {
		clean_up_ops1().
		RETURN.
	}
	
	setupUPFG().
	
	//so we skip directly to rtls or contingency in case of a first stage abort 
	abort_handler().
	getState().
	
	// check for abort modes, proceed to nominal, rtls or contingency
	if NOT (abort_modes["cont_2eo_active"] or abort_modes["cont_3eo_active"] or abort_modes["rtls_active"]) {
		ops1_second_stage_nominal().
	}
	
	if (quit_program) {
		clean_up_ops1().
		RETURN.
	}
	
	//handle sequence for rtls and contingency 
	
	if (abort_modes["rtls_active"]) {
		ops1_second_stage_rtls().
	}
	
	if (quit_program) {
		clean_up_ops1().
		RETURN.
	}
	
	if (abort_modes["cont_2eo_active"]) {		//probably won't handle 3eo in this block
		ops1_second_stage_contingency().
	}
	
	if (quit_program) {
		clean_up_ops1().
		RETURN.
	}
	
	ops1_et_sep().
	
	ops1_termination().
}




function ops1_countdown{

	//needed to update the dap at least once
	wait 0.

	SAS OFF.
	switch_att_rcs(false, false, false).
	
	//this sets the pilot throttle command to some value so that it's not zero if the program is aborted
	LOCK THROTTLE to dap:thr_cmd.
	
	//precaution
	SET vehicle["ign_t"] TO TIME:SECONDS + vehicle_countdown.
	
	addGUIMessage(" T MINUS 10").
	
	set vehiclestate["major_mode"] TO 100.
	
	set dap:thr_max to vehicle["maxThrottle"].
	set dap:thr_min to vehicle["minThrottle"].
	SET dap:thr_rpl_tgt TO convert_ssme_throt_rpl(1).
	set dap:steer_refv to HEADING(target_orbit["launch_az"] + 180, 0):VECTOR.	
	set dap:steer_roll to vehicle["roll"].
	dap:set_steer_tgt(dap:cur_dir:forevector).
	set dap:thrust_corr to FALSE.
	
	local TT IS TIME:SECONDS + 10 - ops1_parameters["preburn"].
	LOCAL monitor_rsls IS FALSE.
	WHEN  TIME:SECONDS>=TT  THEN {
			addGUIMessage("GO FOR MAIN ENGINES START").
			SET monitor_rsls TO TRUE.
			stage.
			WAIT 0.
		}
	local break_loop is false.
	UNTIL (	TIME:SECONDS >= vehicle["ign_t"] ) {
		SET SHIP:CONTROL:PILOTMAINTHROTTLE TO dap:thr_cmd.
	
		if (quit_program) {
			set break_loop to true.
			break.
		}
		IF (monitor_rsls) {
			setup_engine_failure().
			measure_update_engines().
	
			IF (vehicle["ssme_out_detected"]) {
				set break_loop to true.
				break.
			}
		}
	}
	
	if (break_loop) {
		addGUIMessage("RSLS ABORT.").
		shutdown_all_engines().
		LOCK THROTTLE to 0.
		SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.
		UNLOCK STEERING.
		RETURN FALSE.
	}
	
	
	LOCK STEERING TO dap:steer_dir.
	set dap:steer_freeze to true.
	
	addGUIMessage("BOOSTER IGNITION").
	stage.
	SET surfacestate["time"] TO TIME:SECONDS. 
	SET vehicle["ign_t"] TO TIME:SECONDS. 
	
	//vertical speed greater than 1 three times in a row
	local liftoff_sample_c is 0.
	until false {
		if (liftoff_sample_c >= 3) {
			break.
		}
		if (SHIP:VERTICALSPEED > 1) {
			set liftoff_sample_c to liftoff_sample_c + 1.
		}
		wait 0.1.
	}
	
	addGUIMessage("LIFT-OFF CONFIRMED").
	getState().
	set vehiclestate["major_mode"] TO 101.
	
	RETURN TRUE.
	
}



function ops1_first_stage {
		
	local steer_flag IS false.
	local throt_flag IS false.
	local roll_program_flag IS false.																	 
	
	WHEN (surfacestate["vs"] >= ops1_parameters["roll_v0"]) THEN {
		addGUIMessage("ROLL PROGRAM").	
		set vehiclestate["major_mode"] TO 102.
		SET steer_flag TO true.
		SET throt_flag TO true.
		set dap:steer_freeze to false.
		set dap:thrust_corr to TRUE.
		
		//reset throttle to maximum
		SET dap:thr_rpl_tgt TO vehicle["nominalThrottle"].
	}
	
	//main ascent loop
	UNTIL FALSE {	
		if (quit_program) {
			RETURN.
		}
		
		if (ops1_parameters["debug_mode"]) {
			clearvecdraws().
		}
	
		abort_handler().
		getState().
		
		IF (vehicle["stages"][vehiclestate["cur_stg"]]["Tstage"] <= 4 ) {
			BREAK.
		}
		
		if vehiclestate["staging_in_progress"] {
			SET steer_flag TO FALSE.
		}
		
		IF steer_flag {		
			dap:set_steer_tgt(
						first_stage_guidance()
			).
		}
		
		set dap:thr_max to vehicle["maxThrottle"].
		set dap:thr_min to vehicle["minThrottle"].
		
		// q bucket and throttling logic
		//modification - meaure max-Q separately from throttling so it's done for aborts as well 
		if (NOT vehicle["max_q_reached"]) AND (surfacestate["vs"] > 100) {
			IF (surfacestate["q"] >=  surfacestate["maxq"] ) {
				SET surfacestate["maxq"] TO surfacestate["q"].
				set vehicle["max_q_reached"] to FALSE.
			} else {
				addGUIMessage("VEHICLE HAS REACHED MAX-Q").
				set vehicle["max_q_reached"] to TRUE.
			}
		}
		
		if (get_engines_out() > 0) {
			set dap:thr_rpl_tgt to vehicle["maxThrottle"].
			set throt_flag to false.
		} else {
			if (throt_flag) {
				if (vehicle["qbucket"]) {
					if (vehicle["max_q_reached"]) AND (surfacestate["q"] < 0.95*surfacestate["maxq"]) {
						addGUIMessage("GO AT THROTTLE-UP").
						set vehicle["qbucket"] to FALSE.
					}
					set dap:thr_rpl_tgt to vehicle["qbucketThrottle"].
				} else {
					if (NOT vehicle["max_q_reached"]) AND (surfacestate["q"] > ops1_parameters["qbucketval"]) {
						set vehicle["qbucket"] to TRUE.
						addGUIMessage("THROTTLING DOWN").
					}
				
					set dap:thr_rpl_tgt to vehicle["nominalThrottle"].
				}
			
			}
		}
	}
	
	
	//separation loop
	//central block to handle nominal srb sep and 3eo contingency breakout to the et sep block
	
	SET vehiclestate["staging_in_progress"] TO TRUE.
	
	//save the 3eo flag so we don't mess things up if 3eo happens during the srb sep loop
	local _3eo_et_sep is abort_modes["cont_3eo_active"].
	local staging_met is surfacestate["MET"] + 100000.
	
	local srb_tailoff_thr is srb_sep_thrust().
	
	if (_3eo_et_sep) {
		addGUIMessage("EMERGENCY ET SEP").
		dap:set_rcs(TRUE).
		local srb_sep_pitch_up_steer is rodrigues(surfacestate["surfv"]:NORMALIZED, -dap:cur_dir:starvector, 10).
		dap:set_steer_tgt(srb_sep_pitch_up_steer).
		set dap:thrust_corr to FALSE.
		set dap:steer_freeze to false.
	} else {
		addGUIMessage("STAND-BY FOR SRB SEP").
		set dap:steer_freeze to true.
	}
	
	local break_sep_loop is false.
	local rcs_translation_sep is _3eo_et_sep.
	
	UNTIL FALSE {	
		if (quit_program) {
			RETURN.
		}
		
		if (break_sep_loop) {
			break.
		}
		
		if (ops1_parameters["debug_mode"]) {
			clearvecdraws().
		}
		
		abort_handler().
		getState().
		
		local srb_tailoff is (get_srb_thrust()<srb_tailoff_thr).
		
		local stg_elapsed is (surfacestate["MET"] - staging_met).
		
		if (_3eo_et_sep) {
	
			set break_sep_loop to srb_tailoff.
		} else  {
		
			set break_sep_loop to (stg_elapsed >= 5).
		
			//at tailoff, trigger srb sep
			if (NOT vehicle["srb_sep_flag"]) and (srb_tailoff) {
				wait until stage:ready.
				STAGE.
				
				//measure and save conditions at staging 
				LOCAL ve_stg IS surfacestate["surfv"]:MAG.

				SET vehiclestate["srb_sep"]["time"] TO surfacestate["MET"].
				SET vehiclestate["srb_sep"]["ve"] TO ve_stg.
				SET vehiclestate["srb_sep"]["alt"] TO surfacestate["alt"].
				
				increment_stage().
				
				set staging_met to (vehiclestate["staging_time"] - vehicle["ign_t"]).
				
				set vehicle["srb_sep_flag"] to true.
			}
		}
	}
	
	if (NOT _3eo_et_sep) {
		//need this here so 2eo before srb sep works correctly
		SET vehiclestate["major_mode"] TO 103.
	}
}


function ops1_second_stage_nominal {

	freeze_abort_gui(false).
	
	SET target_orbit["normal"] TO upfg_normal(target_orbit["inclination"], target_orbit["LAN"]).
	
	local steer_flag is false.
	
	//upfg loop
	UNTIL FALSE{
		if (quit_program) {
			RETURN.
		}
		
		set dap:steer_refv to -SHIP:ORBIT:BODY:POSITION:NORMALIZED.
		
		//roll to heads-up 
		if (not vehicle["roll_heads_up_flag"]) and ((orbitstate["velocity"]:mag >= ops1_parameters["roll_headsup_vi"]) or dap:serc_enabled) {
			if (vehicle["roll"] <> 0) {
				addGUIMessage("ROLL TO HEADS-UP ATTITUDE").
				set vehicle["roll"] to 0.
				set dap:steer_roll to 0.
				
				wait 0.3.
			} else {
				if (dap:roll_null_err) {
					set vehicle["roll_heads_up_flag"] to true.
				}
			}
		}
		
		if (cont_2eo_immediate_sep()) {
			//if below the contingency altitude, force 3eo abort
			shutdown_ssmes().
		}	

		abort_handler().
		getState().
		
		if (abort_modes["cont_2eo_active"]) or (abort_modes["cont_3eo_active"]) or (abort_modes["rtls_active"]) {
			return.
		}
		
		if (vehicle["low_level"]) {
			addGUIMessage("LOW LEVEL").
			BREAK.
		}
		
		if (upfgInternal["s_meco"]) {
			addGUIMessage("TERMINAL GUIDANCE").
			BREAK.
		}	
		
		if (vehicle["meco_flag"]) {
			break.
		}
		
		IF HASTARGET = TRUE AND (TARGET:BODY = SHIP:BODY) {
			tgt_j2_timefor(target_orbit, upfgInternal["tgo"]).
		}
		
		upfg_sense_current_state(upfgInternal).
		
		upfg(
			vehicle["stages"]:SUBLIST(vehiclestate["cur_stg"],vehicle:LENGTH-vehiclestate["cur_stg"]),
			target_orbit,
			upfgInternal
		).
		
		droop_control().
		
		if (not steer_flag) and upfgInternal["s_conv"] {
			set steer_flag to true.
			set dap:steer_freeze to false.
		}
		
		if (NOT vehiclestate["staging_in_progress"]) {
			if (droopInternal["s_cdroop"]) {
				local steer_yawlim is limit_yaw_steering(droopInternal["steering"], target_orbit["normal"]).
				dap:set_steer_tgt(vecYZ(steer_yawlim)).
				 set dap:thr_rpl_tgt to dap:thr_max.
			} else if (upfgInternal["s_conv"]) {
				local steer_yawlim is limit_yaw_steering(upfgInternal["steering"], target_orbit["normal"]).
				dap:set_steer_tgt(vecYZ(steer_yawlim)).
				set dap:thr_rpl_tgt to upfgInternal["throtset"].	
			}
		}
		
		if (ops1_parameters["debug_mode"]) {
			clearvecdraws().
			arrow_ship(vecyz(upfgInternal["steering"]),"steer").
			arrow_ship(vecyz(upfgInternal["ix"]),"ix").
			arrow_ship(vecyz(upfgInternal["iy"]),"iy").
			arrow_ship(vecyz(upfgInternal["iz"]),"iz").
			
			if (droopInternal["s_cdroop"]) {
				arrow_ship(vecyz(droopInternal["steering"]*2),"droop").
			}
			
			arrow_body(vecyz(vxcl(upfgInternal["iy"], upfgInternal["r_cur"])),"r_proj").
			arrow_body(vecyz(upfgInternal["rd"]),"rd").
			arrow_body(vecyz(target_orbit["normal"]),"rd").
		}
	}
	
	//terminal loop 
	SET upfgInternal["s_meco"] to TRUE.
	SET vehicle["terminal_flag"] TO TRUE.
	
	set dap:thr_rpl_tgt to dap:thr_min.
	
	addGUIMessage("WAITING FOR MECO").
	
	UNTIL FALSE {
		if (quit_program) {
			RETURN.
		}
	
		abort_handler().
		getState().
		
		IF (orbitstate["velocity"]:MAG >= target_orbit["velocity"]) OR vehicle["meco_flag"] {
			BREAK.
		}
	}
	
	//stop oms dump for intact aborts
	LOCK THROTTLE to 0.
	SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.
	shutdown_ssmes().
	stop_oms_dump(TRUE).
	
	SET vehiclestate["major_mode"] TO 104.
}


function ops1_second_stage_rtls {

	SET vehiclestate["major_mode"] TO 601.
	
	set dap:steer_freeze to false.
	
	set dap:steer_refv to -SHIP:ORBIT:BODY:POSITION:NORMALIZED.

	until false {
		if (quit_program) {
			RETURN.
		}

		abort_handler().
		getState().
		
		if (abort_modes["cont_2eo_active"]) or (abort_modes["cont_3eo_active"]) {
			return.
		}
		
		if (vehicle["low_level"]) {
			addGUIMessage("LOW LEVEL").
			BREAK.
		}
		
		if (upfgInternal["s_meco"] or RTLS_rvline_terminal_check(TRUE)) {
			addGUIMessage("TERMINAL GUIDANCE").
			BREAK.
		}
		
		if (vehicle["meco_flag"]) {
			break.
		}
		
		upfg_sense_current_state(upfgInternal).
		
		IF (NOT RTLSAbort["flyback_flag"]) {
		
			LOCAL stg IS get_stage().
		
			//extrapolate state to the end of ppa
			SET upfgInternal["t_cur"] TO upfgInternal["t_cur"] - RTLSAbort["pitcharound"]["dt"].
			SET upfgInternal["r_cur"] TO upfgInternal["r_cur"] + upfgInternal["v_cur"] * RTLSAbort["pitcharound"]["dt"].
			SET upfgInternal["m_cur"] TO upfgInternal["m_cur"] - stg["engines"]["flow"] * RTLSAbort["pitcharound"]["dt"].
			SET upfgInternal["tb_cur"] TO upfgInternal["tb_cur"] - RTLSAbort["pitcharound"]["dt"].
		
		}
		
		upfg(
			vehicle["stages"]:SUBLIST(vehiclestate["cur_stg"],vehicle:LENGTH-vehiclestate["cur_stg"]),
			target_orbit,
			upfgInternal
		).
		
		LOCAL PEG_Tc IS (upfgInternal["mbo_T"] - upfgInternal["tgo"]).
		
		IF (NOT (RTLSAbort["flyback_flag"] AND RTLSAbort["pitcharound"]["complete"] )) {

			//force unconverged until flyback
			SET upfgInternal["s_conv"] TO FALSE.
			SET upfgInternal["iter_conv"] TO 0.
			SET upfgInternal["itercount"] TO 0.
		
			LOCAL RTLS_steering IS V(0,0,0).
			
			IF ( NOT RTLSAbort["pitcharound"]["triggered"] ) {
				//dissipation 
				SET RTLSAbort["C1"] TO RTLS_C1(RTLSAbort["theta_C1"]).
				SET RTLS_steering TO RTLSAbort["C1"]:NORMALIZED.
				
				//range lockout bc lose to the site guidance is unreliable 
				LOCAL range_now IS greatcircledist(RTLS_tgt_site_vector(), orbitstate["radius"]).
				
				IF (PEG_Tc > RTLSAbort["Tc"]) OR (range_now < RTLSAbort["flyback_range_lockout"]) {
					SET RTLSAbort["flyback_conv"] TO RTLSAbort["flyback_iter"].
				} ELSE {
					SET RTLSAbort["flyback_conv"] TO MIN( 1, RTLSAbort["flyback_conv"] + 1).
				}
				
				IF (RTLSAbort["flyback_conv"] = 1) {
					LOCAL pitchover_bias IS 0.5 * RTLSAbort["pitcharound"]["dt"].
					
					IF (PEG_Tc <= (1 + pitchover_bias)) {
						addGUIMessage("POWERED PITCH-AROUND").
						SET RTLSAbort["pitcharound"]["triggered"] TO TRUE.
						SET RTLSAbort["pitcharound"]["complete"] TO FALSE.
						//precaution for convergence display
						SET RTLSAbort["flyback_conv"] TO RTLSAbort["flyback_iter"].
					} 
				}
				
			} ELSE {
				//powered pitcharound					
				//get the current thrust vector, project in the plane containing the peg vector (flyback guidance command) and C1,
				//rotate ahead by a few degrees
				
				set vehicle["roll"] to 0.
				set dap:steer_roll to 0.
				set dap:max_steervec_corr to 8.
				
				LOCAL thrust_facing IS VXCL(RTLSAbort["pitcharound"]["refvec"],vecYZ(thrust_vec()):NORMALIZED).
				
				local rtls_ppa_angle is min(45, VANG(thrust_facing, RTLSAbort["pitcharound"]["target"])).
				
				IF (rtls_ppa_angle < 5) {
					SET RTLSAbort["pitcharound"]["complete"] TO TRUE.
					SET RTLSAbort["flyback_flag"] TO TRUE.
					SET upfgInternal["s_flyback"] TO TRUE.
					SET upfgInternal["s_throt"] TO TRUE.
					set dap:steer_refv to -SHIP:ORBIT:BODY:POSITION:NORMALIZED.
					SET RTLS_steering TO RTLSAbort["pitcharound"]["target"].
				} else {
					set dap:steer_refv to VXCL(vecYZ(RTLSAbort["pitcharound"]["refvec"]),SHIP:FACING:TOPVECTOR).
					SET RTLS_steering TO rodrigues(thrust_facing, RTLSAbort["pitcharound"]["refvec"], rtls_ppa_angle). 
				}
			
			}
			
			dap:set_steer_tgt(vecYZ(RTLS_steering)).
			
		} else {
			set dap:steer_refv to -SHIP:ORBIT:BODY:POSITION:NORMALIZED.
		
			IF (upfgInternal["s_conv"] AND NOT vehiclestate["staging_in_progress"]) {
				local steer_yawlim is limit_yaw_steering(upfgInternal["steering"], target_orbit["normal"]).
				dap:set_steer_tgt(vecYZ(steer_yawlim)).
				set dap:thr_rpl_tgt to upfgInternal["throtset"].	
			}
		}
	
		SET RTLSAbort["Tc"] TO PEG_Tc.
		
		if (ops1_parameters["debug_mode"]) {
			clearvecdraws().
			arrow_ship(vecyz(upfgInternal["steering"]),"steer").
			arrow_ship(vecyz(upfgInternal["ix"]),"ix").
			arrow_ship(vecyz(upfgInternal["iy"]),"iy").
			arrow_ship(vecyz(upfgInternal["iz"]),"iz").
			
			arrow_body(vecyz(vxcl(upfgInternal["iy"], upfgInternal["r_cur"])),"r_proj").
			arrow_body(vecyz(upfgInternal["rd"]),"rd").
			arrow_body(vecyz(target_orbit["normal"]),"rd").
		}
		
	}
	
	//powered pitchdown
	SET upfgInternal["s_meco"] to TRUE.
	SET vehicle["terminal_flag"] TO TRUE.
	set vehicle["pitchdown_flag"] to true.
	
	addGUIMessage("POWERED PITCH-DOWN").
	
	set dap:thrust_corr to FALSE.
	set dap:thr_rpl_tgt to dap:thr_min.
	set dap:steer_refv to -SHIP:ORBIT:BODY:POSITION:NORMALIZED.
	
	UNTIL FALSE{
		if (quit_program) {
			RETURN.
		}
	
		abort_handler().
		getState().
		
		LOCAL steervec IS surfacestate["surfv"]:NORMALIZED.
		LOCAL upvec IS -SHIP:ORBIT:BODY:POSITION:NORMALIZED.
		
		dap:set_steer_tgt(steervec).

		IF (RTLS_rvline_terminal_check() OR vehicle["meco_flag"]) {
			BREAK.
		}
	}
	
	//stop oms dump for intact aborts
	LOCK THROTTLE to 0.
	SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.
	shutdown_ssmes().
	stop_oms_dump(TRUE).
	
	SET vehiclestate["major_mode"] TO 602.		//?????
}


function ops1_second_stage_contingency {
	
	//preserve the major mode from wherever we came from
	//for correct gui
	//re-initialise 2eo, required for 2eo during first-stage
	setup_2eo_contingency().
	
	set dap:steer_freeze to false.
	dap:set_steer_tgt(dap:cur_dir:forevector).	
	set dap:thrust_corr to FALSE.
	set dap:thr_rpl_tgt to dap:thr_max.
	
	//for correct displaying
	set upfgInternal["s_conv"] to false.
	set droopInternal["s_cdroop"] to false.
	
	//flags for pre-meco attitude control
	local active_steer_flag is false.
	local pitchdown_mode_flag is false.
	local rate_sep_flag is false.
	
	if (abort_modes["ecal_tgt_site"] <> "") and 
		(abort_modes["2eo_cont_mode"] = "GREEN" or (abort_modes["2eo_cont_mode"] = "RTLS YELLOW" and (NOT RTLSAbort["pitcharound"]["triggered"]))) {
		set vehicle["yaw_steering"] to true.
		addGUIMessage("ECAL YAW STEERING TO " + abort_modes["ecal_tgt_site"]["site"]).
	}
	
	if (abort_modes["2eo_cont_mode"] = "BLUE" or abort_modes["2eo_cont_mode"] = "GREEN" or abort_modes["2eo_cont_mode"] = "RTLS BLUE" or abort_modes["2eo_cont_mode"] = "RTLS YELLOW" or abort_modes["2eo_cont_mode"] = "RTLS RED") {
		set active_steer_flag to true.
	}

	
	if (abort_modes["2eo_cont_mode"] = "RTLS GREEN" or abort_modes["2eo_cont_mode"] = "RTLS RED") {
		set pitchdown_mode_flag to true.
	}
	
	if (abort_modes["2eo_cont_mode"] = "BLUE" or abort_modes["2eo_cont_mode"] = "GREEN" or abort_modes["2eo_cont_mode"] = "RTLS BLUE" or abort_modes["2eo_cont_mode"] = "RTLS YELLOW" or abort_modes["2eo_cont_mode"] = "RTLS ORANGE") {
		set rate_sep_flag to true.
	}
	
	//sequencing flags
	local roll_headsup_trg is false.
	local immediate_et_sep is false.
	local quit_guid_loop is false.
	
	SET target_orbit["normal"] TO currentNormal().
	
	wait 0.3.
	
	until false {
		if (quit_program) {
			RETURN.
		}
		
		set dap:steer_refv to -SHIP:ORBIT:BODY:POSITION:NORMALIZED.
		
		abort_handler().
		getState().
		
		if (vehicle["low_level"]) {
			addGUIMessage("LOW LEVEL").
			BREAK.
		}
		
		if (cont_2eo_immediate_sep()) or vehicle["meco_flag"] {
			set immediate_et_sep to true.
			break.
		}
		
		if (abort_modes["cont_3eo_active"]) {
			break.
		}
		
		if (not roll_headsup_trg) and (dap:steering_null_err) {
			set roll_headsup_trg to true.
			set vehicle["roll"] to 0.
			set dap:steer_roll to 0.
			set dap:thrust_corr to FALSE.
			wait 0.3.
		}
		
		if roll_headsup_trg and (not vehicle["roll_heads_up_flag"]) and (dap:roll_null_err) {
			set vehicle["roll_heads_up_flag"] to true.
		}
		
		if (roll_headsup_trg and vehicle["roll_heads_up_flag"] and cont_2eo_terminal_condition() and dap:steering_null_err) {
			break.
		}
		
		if (vehicle["yaw_steering"]) and (cont_2eo_yawsteer_off()) {
			set vehicle["yaw_steering"] to false.
		}
		
		local steer_v is cont_2eo_steering().

		if (active_steer_flag) {
			if vehicle["yaw_steering"] {
				set steer_v to limit_yaw_steering(steer_v, target_orbit["normal"]).
			}
			dap:set_steer_tgt(vecYZ(steer_v)).
		}
		
		if (ops1_parameters["debug_mode"]) {
			clearvecdraws().
			arrow_ship(vecYZ(steer_v),"steer").
			arrow_ship(vecyz(target_orbit["normal"]),"iy").
		}
	}
	
	local bypass_pitchdown is false.
	
	if (immediate_et_sep) {
		addGUIMessage("IMMEDIATE ET SEP").
		set bypass_pitchdown to true.
	}
	
	if (abort_modes["cont_3eo_active"]) {
		set bypass_pitchdown to true.
	}
	
	set dap:thr_rpl_tgt to dap:thr_min.
	
	if (not bypass_pitchdown) {
		
		addGUIMessage("CONTINGENCY PITCH-DOWN").
		
		set vehicle["pitchdown_flag"] to true.
		
		set dap:thrust_corr to FALSE.
		
		local quit_pchdn_loop is false.
		
		local rate_sep_pitch_rate is 2.
		
		//wait 3 seconds to allow the dap time to update the flags
		LOCAL sequence_trigger_t IS surfacestate["time"].
		local seq_end_t is 3.
		
		until false {
			if (quit_program) {
				RETURN.
			}
			
			abort_handler().
			getState().
			
			if (quit_pchdn_loop) or (abort_modes["cont_3eo_active"]) {
				break.
			}
			
			if (cont_2eo_immediate_sep()) or vehicle["meco_flag"] {
				set immediate_et_sep to true.
				break.
			}
			
			local t_loop_flag is (surfacestate["time"] > sequence_trigger_t + seq_end_t).
			
			if (rate_sep_flag) {
				local rate_sep_steer_tgt is rodrigues(dap:cur_dir:forevector, -dap:cur_dir:starvector, -45).
				dap:set_steer_tgt(rate_sep_steer_tgt).
				
				//separate when pitch rate is high enough for long enough or when we pitch below the horizon
				set quit_pchdn_loop to (t_loop_flag) and ((dap:pitch_rate >= rate_sep_pitch_rate) or (dap:cur_steer_pitch <= -vehicle["ssme_cant_angle"])).
			} else if (pitchdown_mode_flag) {
				dap:set_steer_tgt(surfacestate["surfv"]:NORMALIZED).
				
				set quit_pchdn_loop to dap:steering_null_err and t_loop_flag.
			}
		
		}
	}
	
	shutdown_ssmes().
	
	//works for 103 and 601
	SET vehiclestate["major_mode"] TO vehiclestate["major_mode"] + 1.
}

function ops1_et_sep {

	if (vehicle["et_sep_flag"]) {return.}
	
	set dap:steer_refv to -SHIP:ORBIT:BODY:POSITION:NORMALIZED.
	
	set dap:thrust_corr to FALSE.
	dap:set_rcs(TRUE).
	switch_att_rcs().
	set dap:steer_freeze to false.
	dap:set_steer_tgt(dap:cur_dir:forevector).
	
	shutdown_ssmes().	//for good measure
	SET vehicle["meco_flag"] TO TRUE.
	ssme_out_safing().
	
	SET vehiclestate["staging_in_progress"] TO TRUE.	//so that vehicle perf calculations are skipped in getState
	
	//if oms dump is in progress save state but stop it for et sep
	local trigger_oms_dump is abort_modes["oms_dump"].
	local post_meco_dump is false.
	stop_oms_dump(TRUE).

	addGUIMessage("STAND-BY FOR ET SEP").
	
	//3 modes: nominal, immediate, rate-sep 
	et_sep_mode_determinator().
	
	//one last lex dump 
	abort_handler().
	
	local pre_sequence_t is 0.
	local pre_sep_t is 0.
	local translation_t is 0.
	local rate_sep_pitch_rate is 2.
	local rate_sep_wait_t is 8.
	local et_sep_oms_t is 5.
	
	
	if (abort_modes["et_sep_mode"] = "nominal") {
		set pre_sequence_t to 2.
		set pre_sep_t to 1.
		set translation_t to 13.
	} else if (abort_modes["et_sep_mode"] = "immediate") {
		set pre_sequence_t to 1.
		set pre_sep_t to 0.3.
		set translation_t to 10.
	} else if (abort_modes["et_sep_mode"] = "rate") {
		set pre_sequence_t to 1.
		set pre_sep_t to 1.
		set translation_t to 10.
		set vehicle["pitchdown_flag"] to true.
	}
	
	LOCAL sequence_start is false.
	LOCAL sequence_end is false.
	local pitch_rate_flag is false.
	LOCAL sequence_trigger_t IS surfacestate["time"].
	LOCAL et_sep_t IS surfacestate["time"] + 100.	//bias in the future
	
	//calculate a pitch-up steering direction for contingencies
	local post_sep_pitch_up_steer is dap:cur_dir:forevector.
	local rate_sep_steer_tgt is dap:cur_dir:forevector.
	
	UNTIL FALSE{
		getState().
		
		IF (sequence_end) {
			BREAK.
		}
		
		if (not vehicle["et_sep_flag"]) {
		
			//rate sep is different
			if (abort_modes["et_sep_mode"] = "rate") {
				
				set vehicle["roll"] to 0.
				set dap:steer_roll to 0.
				set dap:max_steervec_corr to 8.
				set dap:steer_refv to dap:cur_dir:topvector.
			
				if (NOT sequence_start) {
					//set steering target to induce a pitch-down 
					set rate_sep_steer_tgt to rodrigues(dap:cur_dir:forevector, -dap:cur_dir:starvector, -45).
					dap:set_steer_tgt(rate_sep_steer_tgt).
					
					//separate when pitch rate is high enough for long enough
					//or when the wait timr is out, or when we pitch below the horizon
					if (not pitch_rate_flag) and (
							(dap:pitch_rate >= rate_sep_pitch_rate)
							or (surfacestate["time"] > sequence_trigger_t + rate_sep_wait_t)
							or (dap:cur_steer_pitch <= -vehicle["ssme_cant_angle"])
					) {
						set pitch_rate_flag to true.
						set sequence_trigger_t to surfacestate["time"].
					}
				
					if (pitch_rate_flag) and (surfacestate["time"] > sequence_trigger_t + pre_sequence_t)  {
						set sequence_start to true.
						set sequence_trigger_t to surfacestate["time"].
						
						SET SHIP:CONTROL:TOP TO 1.
						SET SHIP:CONTROL:FORE TO 1.
					}
					
				} else {
					if (surfacestate["time"] > sequence_trigger_t + pre_sep_t) {
						set vehicle["et_sep_flag"] to true.
						set sequence_trigger_t to surfacestate["time"].
						set et_sep_t to surfacestate["time"].
						
						et_sep().
						
						set post_sep_pitch_up_steer to rodrigues(dap:cur_dir:forevector, -dap:cur_dir:starvector, 5).
						
						dap:set_steer_tgt(post_sep_pitch_up_steer).
					}
				}
				
			} else {
				//nominal and immediate sep work the same except with different timings
				
				if (NOT sequence_start)  {
					if (surfacestate["time"] > sequence_trigger_t + pre_sequence_t) {
						set sequence_start to true.
						set sequence_trigger_t to surfacestate["time"].
						
						SET SHIP:CONTROL:TOP TO 1.
						SET SHIP:CONTROL:FORE TO 1.
					}
				} else {
					if (surfacestate["time"] > sequence_trigger_t + pre_sep_t) {
						set vehicle["et_sep_flag"] to true.
						set sequence_trigger_t to surfacestate["time"].
						set et_sep_t to surfacestate["time"].
						
						et_sep().
						
						if (abort_modes["et_sep_mode"] <> "nominal") {
							
							set post_sep_pitch_up_steer to rodrigues(dap:cur_dir:forevector, -dap:cur_dir:starvector, 5).
							dap:set_steer_tgt(post_sep_pitch_up_steer).
						}
					}
				}
			}
		
		} else {
		
			if (trigger_oms_dump) and (surfacestate["time"] > et_sep_t + et_sep_oms_t) {
				set trigger_oms_dump to false.
				set post_meco_dump to true.
				start_oms_dump().
			}
		
			if (surfacestate["time"] > sequence_trigger_t + translation_t) {
				set sequence_end to true.
				set sequence_trigger_t to surfacestate["time"].
				
				SET SHIP:CONTROL:NEUTRALIZE TO TRUE.
			}
		}
		
		if (ops1_parameters["debug_mode"]) {
			clearvecdraws().
			arrow_ship(post_sep_pitch_up_steer,"steer").
		}
	}
	
	//zero throttle unless a dump should be continued
	if (not post_meco_dump) {
		LOCK THROTTLE to 0.
		SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.
		toggle_oms(true).
	}
	
	//for good measure 
	set dap:steer_refv to -SHIP:ORBIT:BODY:POSITION:NORMALIZED.
	
	//need to wait for the dap to update the relative roll
	wait 0.3.
	
	//after et sep set toggle serc off in the dap
	dap:toggle_serc(false).
	
	//skip in case of 3eo first stage, stay heads-down
	if (vehiclestate["major_mode"] <> 102) {
		local forward_steerv is dap:cur_dir:forevector.
		if (abort_modes["et_sep_mode"] <> "nominal") {
			//do a re-orientation after et-sep since we might be in a weird attitude
			//take component of steering along velocity, if negative, flip to the other side 
			
			local surfv_proj IS VXCL(dap:steer_refv, surfacestate["surfv"]):NORMALIZED.
			local normv_ is VCRS(dap:steer_refv, surfv_proj):normalized.
			set forward_steerv to vxcl(normv_, forward_steerv).
			
			local steer_prog is vdot(forward_steerv, surfv_proj).
			
			if (steer_prog < 0) {
				set forward_steerv to (forward_steerv + 2*abs(steer_prog) * surfv_proj):normalized.
			}
			
			dap:set_steer_tgt(forward_steerv).
			
			if (ops1_parameters["debug_mode"]) {
				clearvecdraws().
				arrow_ship(forward_steerv,"steer").
			}
		}
	
		set vehicle["roll"] to 0.
		set dap:steer_roll to 0.
	}
	
	wait 0.3.
	
	until false {
		getState().
		
		if (dap:steering_null_err and dap:roll_null_err) {
			BREAK.
		}
	}

}

//figure out what to do based on mode and abort modes 
function ops1_termination {

	close_umbilical().

	local nominal_termination_flag is (not abort_triggered()) or abort_modes["ato_active"].

	if nominal_termination_flag {
		print_ascent_report().
		WAIT 5.
	}
	
	clean_up_ops1().
	
	if nominal_termination_flag {
		return.
	} else if (abort_modes["tal_active"]) {
		RUN "0:/ops3"("tal", abort_modes["tal_tgt_site"]["site"]).
	} else if (abort_modes["rtls_active"]) {
		RUN "0:/ops3"("grtls", abort_modes["rtls_tgt_site"]["site"]).
	} else if (abort_modes["cont_2eo_active"] OR abort_modes["cont_3eo_active"]) {
	
		if (abort_modes["2eo_cont_mode"] = "RTLS RED") {
			RUN "0:/ops3"("grtls", abort_modes["rtls_tgt_site"]["site"]).
		} else if (abort_modes["ecal_tgt_site"] <> "") {
			RUN "0:/ops3"("ecal", abort_modes["ecal_tgt_site"]["site"]).
		} else {
			RUN "0:/ops3"("cont", abort_modes["rtls_tgt_site"]["site"]).
		}
	} 

}

function clean_up_ops1 {
	CLEARSCREEN.
	clearvecdraws().
	dap_gui_executor["stop_execution"]().
	close_all_GUIs().

	UNLOCK THROTTLE.
	UNLOCK STEERING.
	SAS ON.	//for good measure
}

ops1_main_exec().
