GLOBAL g0 IS 9.80665. 
GLOBAL vehicle_countdown IS 10.

GLOBAL vehiclestate IS LEXICON(
	"major_mode",0,
	"cur_stg", 1,
	"staging_time", 0,
	"staging_in_progress", FALSE,
	"srb_sep",LEXICON(
							"v",0,
							"alt",0
							),
	"m_burn_left", 0,
	"thr_vec", v(0,0,0),
	"isp", 0,
	"avg_thr", average_value_factory(3),
	"q", 0
).



GLOBAL events IS LIST().


//VEHICLE INITIALISATION FUNCTION 

function initialise_shuttle {

	//RUNPATH("0:/Libraries/resources_library").	

	
	FUNCTION add_resource {
		parameter lexx.
		parameter reslist.
		
		
		for res in reslist {
			IF NOT lexx:HASKEY(res) {lexx:ADD(res,0).}
		}
		RETURN lexx.
	}

	//this must be changed if the RO config for the SRBs ever changes
	LOCAL srb_time IS 119.

	
	//hard-coded initialisation of shuttle vehicle
	
	
	//prepare the main struct 
	
	GLOBAL vehicle IS LEXICON(
						"name",SHIP:NAME,
						"ign_t", 0,
						"trajectory_scale",0,
						"roll",180,
						"1st_stg_tgt_pch", 90,
						"srb_sep_flag", FALSE,
						"roll_heads_up_flag", FALSE,
						"et_sep_flag", FALSE,
						"meco_flag", FALSE,
						"qbucket", FALSE,
						"max_q_reached", FALSE,
						"yaw_steering", FALSE,
						"glim", 3,
						"low_level", FALSE,
						"terminal_flag", FALSE,
						"pitchdown_flag", FALSE,
						"maxThrottle",0,	
						"minThrottle",0,	
						"nominalThrottle",0,	
						"qbucketThrottle",0,	
						"SSME_prop_0", 0,
						"SSME_prop", 0,
						"OMS_prop_0", 0,
						"OMS_prop", 0,
						"SSME",0,
						"OMS",0,
						"stack_full_mass", 0,
						"stack_empty_mass", 0,
						"stages",LIST(),
						"ssme_out_detected", FALSE,
						"rtls_mbod", 0,
						"ssme_cant_angle", 13
	).
	
	SET vehicle["SSME"] TO parse_ssme().
	SET vehicle["OMS"] TO parse_oms().
	
	//measure initial propellants 
	SET vehicle["SSME_prop"] TO get_ssme_prop().
	SET vehicle["SSME_prop_0"] TO vehicle["SSME_prop"].
	
	SET vehicle["OMS_prop"] TO get_oms_prop().
	SET vehicle["OMS_prop_0"] TO vehicle["OMS_prop"].
	
	//now reset number of engines to default : 3 active SSME, 0 active OMS
	SET vehicle["SSME"]["active"] TO 3.
	SET vehicle["OMS"]["active"] TO 0.
	
	//add the ssme type to the vessel name 
	
	SET vehicle["name"] TO vehicle["name"] + " " + vehicle["SSME"]["type"].
	
	//limit upper throttle in nominal case
	SET vehicle["maxThrottle"] TO vehicle["SSME"]["maxThrottle"].
	SET vehicle["minThrottle"] TO vehicle["SSME"]["minThrottle"].
	SET vehicle["nominalThrottle"] TO min(1, convert_ssme_throt_rpl(1.045)).
	SET vehicle["qbucketThrottle"] TO convert_ssme_throt_rpl(0.75).
	
	//measure total mass less the SRBs and clamps
	SET vehicle["stack_full_mass"] TO getShuttleStackMass().
	
	//nominally we just burn SSME propellant
	LOCAL total_prop_mass IS vehicle["SSME_prop"].
	
	SET vehicle["stack_empty_mass"] TO vehicle["stack_full_mass"] - total_prop_mass.	
	
	
	//prepare stages list
	
	LOCAL engines_lex IS build_engines_lex().
	
	//zeroth stage 
	vehicle["stages"]:ADD(0).
	
	//stage1 - SRB
	
	LOCAL new_stg_1 IS empty_stg_template().
	
	set new_stg_1["m_initial"] to vehicle["stack_full_mass"].
	set new_stg_1["glim"] to vehicle["glim"].
	set new_stg_1["Throttle"] to vehicle["nominalThrottle"].
	set new_stg_1["Tstage"] to srb_time.
	set new_stg_1["engines"] to engines_lex.
	set new_stg_1["mode"] to 1.
	SET new_stg_1["staging"]["type"] TO "time".
	
	LOCAL stage1_final_mass IS const_f_dt_mfinal(new_stg_1).
	
	SET new_stg_1["m_burn"] TO vehicle["stack_full_mass"] - stage1_final_mass.
	SET new_stg_1["m_final"] TO stage1_final_mass. 

	vehicle["stages"]:ADD(new_stg_1).
	
	setup_shuttle_stages(
						new_stg_1["m_final"],
						vehicle["stack_empty_mass"],
						engines_lex,
						vehicle["nominalThrottle"]
	).
	
	SET vehicle["traj_steepness"] TO vehicle_traj_steepness().
	
	//debug_vehicle().
	
	if (ops1_parameters["debug_mode"]) {
		dump_vehicle().
	}
	
	//prepare launch triggers 
	activate_fuel_cells().
	
}


FUNCTION debug_vehicle {
	
	dump_vehicle().
	
	until false{
		print "vehicle debug, press crtl-c to quit" at (0,2).
		wait 0.1.
	}
}

FUNCTION dump_vehicle {
	
	IF EXISTS("0:/Shuttle_OPS1/LOGS/vehicledump.txt") {
			DELETEPATH("0:/Shuttle_OPS1/LOGS/vehicledump.txt").
	}
	log vehicle:dump() to "0:/Shuttle_OPS1/LOGS/vehicledump.txt".
}





									//CONTROL FUNCTIONS			

//default trajectory steepness factor 
//bias given deltas of cutoff altitude and engine thrust with respect to reference
//engine thrust with reference to 104% rpl
FUNCTION vehicle_traj_steepness {

	//reference thrust is rs-25D
	LOCAL ssme_thr_fac IS (1.045*get_rpl_thrust())/(vehicle["SSME"]["thrust"]*vehicle["SSME"]["maxThrottle"]).
	
	//reference alt is 112 km.
	LOCAL cut_alt_fac IS target_orbit["cutoff alt"]/112.
	
	//base + alt correction + thrust correction
	LOCAL steep_ IS 1 + 0.14*cut_alt_fac + 0.05*ssme_thr_fac.
	
	RETURN steep_.
}

fUNCTION nominal_pitch_profile {
	PARAMETER rel_v.
	PARAMETER steep_fac.
	
	LOCAL p1 IS -0.0088.
	LOCAL p2 IS 30.5.
	LOCAL p3 IS 28000.
	LOCAL q1 IS 3.923.
	
	LOCAL x IS rel_v + 400.

	LOCAL out IS CLAMP((p1*x^2 + p2*x + p3)/(x + q1), 0, 90).
	
	return out + (steep_fac - 1)*(90 - out)^0.7.

}

//bias first-stage trajectory scale for lofting
FUNCTION first_stage_engout_lofting_bias {
	
	//modification, do not bias higher than 1ee
	//contingencies do not need lofting
	
	local engines_out is get_engines_out().
	local abort_t is 1000.
	
	local engout_fac is 0.
	
	if (engines_out > 0) {
		set abort_t to abort_modes["ssmes_out"][0]["time"].
		set engout_fac to 1 + 2^(engines_out - 1).
	}
	
	RETURN max(engout_fac * 0.33*(1 - abort_t/122), 0).
	
}

//open-loop pitch profile for first stage ascent
FUNCTION open_loop_pitch {
	PARAMETER curv.	 
	
	LOCAL vrel IS curv - ops1_parameters["pitch_v0"].
	
	LOCAL steep_fac IS vehicle["traj_steepness"].
	
	//bias trajectory in case of first-stage rtls
	SET steep_fac TO steep_fac + first_stage_engout_lofting_bias().
	
	local prograde_bias is FALSE.
	
	local engines_out is get_engines_out().
	
	if (engines_out < 3) {
		IF (curv<=ops1_parameters["pitch_v0"]) {
			SET vehicle["1st_stg_tgt_pch"] TO 90.
		} ELSE IF (curv<=ops1_parameters["pitch_vmatch"]) {
			//quadratic matching to the pitch profile
			LOCAL vrel_match IS ops1_parameters["pitch_vmatch"] - ops1_parameters["pitch_v0"].
			
			LOCAL prof_match IS nominal_pitch_profile(vrel_match, steep_fac).
			
			LOCAL dv IS 2.
			LOCAL dp_dv IS (nominal_pitch_profile(vrel_match + dv, steep_fac) - prof_match) / dv.
			
			local c_ is (2*(prof_match - 90) - dp_dv * vrel_match) / vrel_match^3.
			local b_ is (-dp_dv/vrel_match - 3*c_*vrel_match)/2.
			
			SET vehicle["1st_stg_tgt_pch"] TO 90 - (b_ + c_ * vrel) * vrel^2.
		} ELSE {
			SET vehicle["1st_stg_tgt_pch"] TO nominal_pitch_profile(vrel, steep_fac).
			SET prograde_bias to TRUE.
		}
	} else {
		SET vehicle["1st_stg_tgt_pch"] TO ops1_parameters["pitch_abort_ss_lim"] + MAX(0, 0.99*(vehicle["1st_stg_tgt_pch"] - ops1_parameters["pitch_abort_ss_lim"]) ).
		SET prograde_bias to TRUE.
	}
	
	LOCAL cmd_pch IS vehicle["1st_stg_tgt_pch"].
	
	if (prograde_bias) {
		local prog_p is get_surf_fpa().
		
		LOCAL bias IS vehicle["1st_stg_tgt_pch"] - prog_p.
	
		LOCAL bias_gain IS CLAMP((curv - vrel)/ 200, 0, 0.5).
		
		LOCAL prof_corr IS ABS(bias_gain * bias).
		
		//don't deviate too much from prograde
		LOCAL max_prograde_dev IS 12.
		LOCAL max_prof_dev IS MAX(max_prograde_dev - ABS((bias_gain + 1) * bias), 0).
		
		set cmd_pch to cmd_pch + SIGN(bias) * MIN(max_prof_dev, prof_corr).
	}

	
	
	RETURN CLAMP(cmd_pch, 0, 90).
}

function first_stage_guidance {

	local az_err is target_orbit["launch_az"] - surfacestate["hdir"].
	
	local az_corr is target_orbit["launch_az"] + clamp(az_err, -2, 2).

	local pitch_ is open_loop_pitch(surfacestate["surfv"]:MAG).

	return HEADING(az_corr, pitch_):forevector.
} 



function ascent_dap_factory {

	SET STEERINGMANAGER:ROLLCONTROLANGLERANGE TO 180.

	LOCAL this IS lexicon().
	
	this:add("steer_freeze", false).
	
	this:add("steer_mode", "").
	this:add("thr_mode", "").		//ksp 0-1 throttle value
	
	this:add("thr_cmd", 1).
	this:add("thr_cmd_rpl", 1).
	
	this:add("last_time", TIME:SECONDS).
	
	this:add("iteration_dt", 0).
	
	this:add("update_time",{
		LOCAL old_t IS this:last_time.
		SET this:last_time TO TIME:SECONDS.
		SET this:iteration_dt TO this:last_time - old_t.
	}).
	
	this:add("thrust_corr", TRUE).
	
	this:add("cur_dir", SHIP:FACINg).
	this:add("cur_thrvec", v(0,0,0)).
	
	this:add("cur_steer_pitch", 0).
	this:add("cur_steer_az", 0).
	this:add("cur_steer_roll", 0).
	
	this:add("steer_pitch_delta", 0).
	this:add("steer_yaw_delta", 0).
	this:add("steer_roll_delta", 0).
	this:add("throt_delta", 0).
	this:add("ship_roll_delta", 0).
	
	this:add("steer_dir", SHIP:FACINg).
	
	this:add("roll_rate", 0).
	this:add("pitch_rate", 0).
	this:add("yaw_rate", 0).
	
	this:add("steer_check_delta", 5).
	this:add("steering_null_err", false).
	this:add("roll_null_err", false).
	
	this:add("measure_refv_roll", {
		LOCAL refv IS VXCL(this:steer_thrvec, this:steer_refv):NORMALIZED.
		LOCAL topv IS VXCL(this:steer_thrvec, this:cur_dir:TOPVECTOR):NORMALIZED.
		
		
		set this:cur_steer_roll to signed_angle(refv, topv, this:steer_thrvec, 1).
	}).
	
	this:add("measure_cur_state", {
		this:update_time().
		
		set this:cur_dir to ship:facing.
		set this:cur_thrvec to thrust_vec().
		
		set this:cur_steer_az to get_az_lvlh(this:steer_dir).
		set this:cur_steer_pitch to get_pitch_lvlh(this:steer_dir).
		
		this:measure_refv_roll().
		
		local tgtv_h is vxcl(this:steer_dir:topvector, this:steer_tgtdir:forevector):normalized.
		local tgtv_v is vxcl(this:steer_dir:starvector, this:steer_tgtdir:forevector):normalized.
		local tgttv_p is vxcl(this:steer_dir:forevector, this:steer_tgtdir:topvector):normalized.
		
		local shptv_p is vxcl(this:steer_dir:forevector, this:cur_dir:topvector):normalized.
		
		
		set this:steer_pitch_delta to signed_angle(tgtv_v, this:steer_dir:forevector, this:steer_dir:starvector, 0).
		set this:steer_yaw_delta to -signed_angle(tgtv_h, this:steer_dir:forevector, this:steer_dir:topvector, 0).
		set this:steer_roll_delta to signed_angle(tgttv_p, this:steer_dir:topvector, this:steer_dir:forevector, 0).
		
		set this:throt_delta to this:thr_rpl_tgt - this:thr_cmd_rpl.
		
		//set this:ship_roll_delta to signed_angle(this:steer_dir:topvector, shptv_p, this:steer_dir:forevector, 0).
		set this:ship_roll_delta to unfixangle(this:steer_roll - this:cur_steer_roll).
		
		local angv_ is SHIP:ANGULARVEL * constant:RadToDeg.
		
		set this:roll_rate to VDOT(this:cur_dir:FOREVECTOR, angv_).
		set this:yaw_rate to VDOT(this:cur_dir:TOPVECTOR, angv_).
		set this:pitch_rate to VDOT(this:cur_dir:STARVECTOR, angv_).
		
		set this:steering_null_err to (abs(this:steer_pitch_delta)  < this:steer_check_delta) 
			and (abs(this:steer_yaw_delta) < this:steer_check_delta) 
			and (abs(this:yaw_rate) < 0.5)
			and (abs(this:pitch_rate) < 0.5).
			
		set this:roll_null_err to (ABS(this:ship_roll_delta) < this:steer_check_delta) 
			and (abs(this:roll_rate) < 0.5).
		
		this:update_steer_tgtdir().
	}).
	
	
	
	this:add("max_steervec_corr", 5).
	this:add("steer_refv", SHIP:FACINg:topvector).
	this:add("steer_thrvec", SHIP:FACINg:forevector).
	this:add("steer_roll", 0).
	this:add("steer_cmd_roll", 0).
	
	this:add("steer_tgtdir", SHIP:FACINg).

	
	this:add("set_steer_tgt", {
		parameter new_thrvec.
		
		set this:steer_thrvec to new_thrvec.
	}).
	
	this:add("update_steer_tgtdir", {
	
		if (this:steer_freeze) {
			return.
		}
	
		//required for continuous pilot input across several funcion calls
		LOCAL time_gain IS ABS(this:iteration_dt/0.2).
		
		local max_roll_corr is 13 * time_gain * STEERINGMANAGER:MAXSTOPPINGTIME.
		
		local roll_delta is unfixangle(this:cur_steer_roll - this:steer_roll).
		set roll_delta to sign(roll_delta) * min(abs(roll_delta) ,max_roll_corr).
		
		set this:steer_cmd_roll to this:cur_steer_roll - roll_delta.
		
		if (this:thrust_corr) {
			set this:steer_tgtdir to aimAndRoll(this:steer_thrvec, this:steer_refv, this:steer_cmd_roll).
		} else {
			set this:steer_tgtdir to aimAndRollDirect(this:steer_thrvec, this:steer_refv, this:steer_cmd_roll).
		}
	}).
	
	this:add("steer_auto_thrvec", {
		set this:steer_mode to "auto_thrvec".
		
		this:update_strmgr().
		
		this:measure_cur_state().
	
		local steer_err_tol is 0.5.
	
		local max_roll_corr is 20.
		
		local cur_steervec is this:cur_dir:forevector.
		local tgt_steervec is this:steer_tgtdir:forevector.
		
		local steer_err is vang(cur_steervec, tgt_steervec).
		
		if (steer_err > steer_err_tol) {
			local steerv_norm is vcrs(cur_steervec, tgt_steervec).
			local steerv_corr is min(this:max_steervec_corr, steer_err).
			
			set tgt_steervec to rodrigues(cur_steervec, steerv_norm, steerv_corr).
		} else {
			set tgt_steervec to tgt_steervec.
		}
		
		local cur_topvec is vxcl(tgt_steervec, this:cur_dir:topvector).
		local tgt_topvec is vxcl(tgt_steervec, this:steer_tgtdir:topvector).
		
		//local roll_err is signed_angle(tgt_topvec, cur_topvec, tgt_steervec, 0).
		//local roll_corr is sign(roll_err) * min(abs(roll_err) ,max_roll_corr).
		//
		//print "roll_corr " + roll_corr + " " at (0,20).
		//
		//set tgt_topvec to rodrigues(cur_topvec, tgt_steervec, -roll_corr).
	
		set this:steer_dir to LOOKDIRUP(tgt_steervec, tgt_topvec ).
		
		this:update_serc().
	}).


	this:add("steer_css", {
		set this:steer_mode to "css".
		
		this:update_strmgr().
		
		this:measure_cur_state().
	
		//required for continuous pilot input across several funcion calls
		LOCAL time_gain IS ABS(this:iteration_dt/0.2).
		
		//gains suitable for manoeivrable steerign in atmosphere
		LOCAL pitchgain IS 0.7.
		LOCAL rollgain IS 1.
		LOCAL yawgain IS 0.7.
		
		LOCAL steer_tol IS 0.1.
		
		local input_pitch is SHIP:CONTROL:PILOTPITCH.
		local input_roll is SHIP:CONTROL:PILOTROLL.
		local input_yaw is SHIP:CONTROL:PILOTYAW.
		
		if (abs(input_pitch) < steer_tol) {
			set input_pitch to 0. 
		}
		if (abs(input_roll) < steer_tol) {
			set input_roll to 0. 
		}
		if (abs(input_yaw) < steer_tol) {
			set input_yaw to 0. 
		}

		//measure input minus the trim settings
		LOCAL deltaroll IS time_gain * rollgain * input_roll.
		LOCAL deltapitch IS time_gain * pitchgain * input_pitch.
		LOCAL deltayaw IS time_gain * yawgain * input_yaw.
		
		print input_pitch + "  " at (0,20).
		print input_roll + "  " at (0,21).
		print input_yaw + "  " at (0,22).
		
		local steer_fore is this:steer_dir:forevector.
		local steer_top is this:steer_dir:topvector.
		local steer_star is this:steer_dir:starvector.
		
		local new_steerfore is rodrigues(steer_fore, steer_top, deltayaw).
		set new_steerfore to rodrigues(new_steerfore, steer_star, - deltapitch).
		
		local cur_fore is this:cur_dir:forevector.
		
		local cur_new_norm is vcrs(cur_fore, new_steerfore).
		
		LOCAL ang_dev IS MIN(this:max_steervec_corr, vang(cur_fore, new_steerfore) ).
		
		set new_steerfore to rodrigues(cur_fore, cur_new_norm, ang_dev).
		
		local new_steertop is vxcl(new_steerfore, steer_top).   
		
		set new_steertop to rodrigues(new_steertop, new_steerfore, - deltaroll).
		
		set this:steer_dir to LOOKDIRUP(new_steerfore, new_steertop ).
		
		this:update_serc().
	}).
	
	
	this:add("thr_rpl_tgt", 0).
	this:add("thr_cmd_tgt", 0).
	this:add("thr_max", 1).	
	this:add("thr_min", 0).	
	
	this:add("update_thr_cmd", {
		local new_thr_rpl is CLAMP(this:thr_rpl_tgt, this:thr_min, this:thr_max).
		set this:thr_cmd_tgt to throtteValueConverter(new_thr_rpl, this:thr_min).
	}).
	
	this:add("thr_control_auto", {
		set this:thr_mode to "thr_auto".
	
		this:update_thr_cmd().
		
		set this:thr_cmd to this:thr_cmd_tgt.
		set this:thr_cmd_rpl to throtteValueConverter(this:thr_cmd, this:thr_min, TRUE).
	}).
	
	
	this:add("thr_control_css", {
		set this:thr_mode to "thr_css".
		
		this:update_thr_cmd().
	
		local thr_input is  SHIP:CONTROL:PILOTMAINTHROTTLE.
		set this:thr_cmd to thr_input.
		set this:thr_cmd_rpl to throtteValueConverter(this:thr_cmd, this:thr_min, TRUE).
	}).
	
	//serc stuff 
	
	this:add("serc_enabled", FALSE).
	this:add("serc_tgt_roll_rate", 0).
	this:add("serc_yaw_pid", PIDLOOP(0.4,0,0.8)).
	SET this:serc_yaw_pid:SETPOINT TO 0.
	
	this:add("toggle_serc", {
		parameter enabled_.
		set this:serc_enabled to enabled_.
	}).
	
	this:add("update_serc", {
	
		if (NOT this:serc_enabled) {
			SET SHIP:CONTROL:STARBOARD TO 0.
			return.
		}
		
		set this:serc_tgt_roll_rate to sign(this:ship_roll_delta) * MIN(0.5 * abs(this:ship_roll_delta), 5).
		
		SET SHIP:CONTROL:STARBOARD TO  this:serc_yaw_pid:UPDATE(this:last_time, this:serc_tgt_roll_rate - this:roll_rate ).
	
	}).
	
	
	this:add("print_debug",{
		PARAMETER line.
		
		print "steer_mode : " + this:steer_mode + "    " at (0,line).
		print "thr_mode : " + this:thr_mode + "    " at (0,line + 1).
		
		print "loop dt : " + round(this:iteration_dt(),3) + "    " at (0,line + 3).
		
		print "steering manager : " + STEERINGMANAGER:MAXSTOPPINGTIME + "    " at (0,line + 4).
		
		print "cur_steer_pitch : " + round(this:cur_steer_pitch,3) + "    " at (0,line + 5).
		print "cur_steer_roll : " + round(this:cur_steer_roll,3) + "    " at (0,line + 6).
		print "steer_cmd_roll : " + round(this:steer_cmd_roll,3) + "    " at (0,line + 7).
		print "thr_rpl_tgt : " + round(this:thr_rpl_tgt,3) + "    " at (0,line + 8).
		print "thr_cmd_tgt : " + round(this:thr_cmd_tgt,3) + "    " at (0,line + 9).
		
		print "steer_pitch_delta : " + round(this:steer_pitch_delta,3) + "    " at (0,line + 11).
		print "steer_roll_delta : " + round(this:steer_roll_delta,3) + "    " at (0,line + 12).
		print "steer_yaw_delta : " + round(this:steer_yaw_delta,3) + "    " at (0,line + 13).
		print "throt_delta : " + round(this:throt_delta,3) + "    " at (0,line + 14).
		
		print "ship_roll_delta : " + round(this:ship_roll_delta,3) + "    " at (0,line + 16).
		
		print "pitch rate: " + round(this:pitch_rate,1) + "			" at (0,line + 18).
		print "roll rate: " + round(this:roll_rate,1) + "			" at (0,line + 19).
		print "yaw rate: " + round(this:yaw_rate,1) + "			" at (0,line + 20).
		
		print "steering nulled: " + this:steering_null_err + "			" at (0,line + 22).
		print "roll nulled: " + this:roll_null_err + "			" at (0,line + 23).
		
	}).
	
	this:add("update_strmgr", {
		local strmgr is STEERINGMANAGER:MAXSTOPPINGTIME.
		
		if (this:steer_mode = "css") {
			set strmgr to 0.6.
		} else {
		
			if (vehiclestate["major_mode"] <= 101) {
				set strmgr to 0.001.
			} else if (vehiclestate["major_mode"] = 102) {
				set strmgr to min(1.2, strmgr + 0.75 * sqrt(strmgr) * this:iteration_dt).
			} else if (vehiclestate["major_mode"] >= 103) {
				set strmgr to 0.1.
				
				if (not this:roll_null_err) {
					set strmgr to midval(abs(this:ship_roll_delta) * 0.08, strmgr, 0.5).
					
				}
				
				if (not this:steering_null_err) {
					set strmgr to midval(strmgr + abs(this:steer_pitch_delta) * 0.075 - 0.013, strmgr, 1.5).
				}
				
				if (this:serc_enabled) {
					set strmgr to 0.15.
				}
				
				if (vehicle["pitchdown_flag"]) {
					set strmgr to max(strmgr, 0.7).
				}
			}
		}
		
		if (vehicle["meco_flag"]) {
			set strmgr to 4.
		}
		
		SET STEERINGMANAGER:MAXSTOPPINGTIME TO strmgr.
	}).
	
	this:add("set_rcs", {
		PARAMETER on_.
		
		if (on_) {
			RCS ON.
		} else {
			RCS OFF.
		}
	}).
	
	
	
	this:measure_cur_state().

	return this.

}


									//VEHICLE PERFORMANCE & STAGING FUNCTIONS
									

// LEGACY , no longer used
//simple function to check if vehicle is past maxq
FUNCTION measure_q {
	PARAMETER newq.
	
	
	
	
	IF (surfacestate["q"] >=  surfacestate["maxq"] ) {
		SET surfacestate["q"] TO newq.
	} ELSE if (NOT vehicle["max_q_reached"]) {
		addGUIMessage("VEHICLE HAS REACHED MAX-Q").
		
		set vehicle["max_q_reached"] to TRUE.
		
		WHEN (SHIP:Q < 0.95*newq) THEN {
			IF (vehicle["stages"][1]["Throttle"] < 1) {
				addGUIMessage("GO AT THROTTLE-UP").
				SET vehicle["stages"][1]["Throttle"] TO 1.
			}
		}
	}

}


FUNCTION get_stage {
	RETURN vehicle["stages"][vehiclestate["cur_stg"]].
}


FUNCTION add_action_event{
	PARAMETER tt.
	PARAMETER callable.
	
	
	events:ADD(
		LEXICON(
				"time",tt,
				"type", "action",
				"action",callable
		)
	).
}


FUNCTION events_handler {

	local x IS events:LENGTH.
	
	local rem_list IS LIST().

	//FROM {LOCAL k IS 0.} UNTIL k >= x STEP { SET k TO k+1.} DO{
	
	LOCAL k IS 0.
	FOR evt IN events {
		
		IF surfacestate["MET"]>evt["time"]  {
			IF evt["type"]="jettison" {
				TOGGLE AG8.
				IF evt:HASKEY("mass") {
					FROM { LOCAL i IS vehiclestate["cur_stg"]. } UNTIL i > (vehicle["stages"]:LENGTH - 1)  STEP { SET i TO i+1. } DO {
						SET vehicle["stages"][i]["m_initial"] TO vehicle["stages"][i]["m_initial"] - evt["mass"].
						SET vehicle["stages"][i]["m_final"] TO vehicle["stages"][i]["m_final"] - evt["mass"].
					}
				}
				rem_list:ADD(k).
			}
			ELSE IF evt["type"]="action" { 
				IF evt:HASKEY("action") {
					evt["action"]:call().
				}
				rem_list:ADD(k).
			}
				
			
			
		}
		SET k TO k+1.
	}
	
	LOCAL items_removed IS 0.
	FOR e IN rem_list {
		events:REMOVE(e - items_removed).
		SET items_removed TO items_removed + 1.
	}
}



//compute the total mass of all the parts composing orbiter, payload and ET excluding SRBs and clamps
function getShuttleStackMass {

	function removeChildrenPartsRecursively {
		parameter partslist.
		parameter part.
		
		local partchildren is part:children:copy.
		
		if partchildren:length > 0 {
			for p in partchildren {
			
				removeChildrenPartsRecursively(
					partslist,
					p 
				).
			
			}
		}
		
		partslist:remove(partslist:find(part)).
		return.

	}
	
	LOCAL et_part IS get_ext_tank_part().

	local shuttleParts is ship:parts:copy.

	removeChildrenPartsRecursively(
		shuttleParts,
		et_part
	).

	shuttleParts:add(et_part).
	
	LOCAL stackmass IS 0.
	FOR p IN shuttleParts {
		set stackmass to stackmass + p:mass*1000.
	}
	
	RETURN stackmass.
}

FUNCTION get_TWR {
	RETURN vehiclestate["avg_thr"]["latest_value"]/(1000*SHIP:MASS*g0).
}

//needed for aborts 
//given specified engines and throttle value, calculate deltav and time to burn 
function veh_perf_estimator {
	parameter engines_lex.
	parameter throtset.
	
	local prop_left is vehiclestate["m_burn_left"].
	
	local m_initial is vehicle["stack_empty_mass"] + prop_left.
	
	LOCAL ve_ IS engines_lex["isp"] * g0.
	
	local deltav_ is ve_*ln(m_initial/(m_initial - prop_left)).
	
	local burnt is ((m_initial * ve_) / (engines_lex["thrust"] * throtset)) * (1 - CONSTANT:E^(- deltav_/ve_)).
	
	
	return lexicon(
					"m_initial", m_initial,
					"time", burnt,
					"deltav", deltav_,
					"engines", engines_lex,
					"throt", throtset
	
	).

}


//measures everything about the current state of the vehicle, including instantaneous thrust
//thrust only averaged over if staging is not in progress
FUNCTION getState {
	
	update_navigation().
	
	IF DEFINED events {	events_handler().}
	
	//measure and compute vehicle performance parameters
	
	LOCAL cur_stg IS get_stage().
	
	LOCAL engines_ IS get_current_thrust_isp().
	
	SET vehiclestate["thr_vec"] TO engines_["thrvec"].
	SET vehiclestate["isp"] TO engines_["isp"].
	
	vehiclestate["avg_thr"]:update(vehiclestate["thr_vec"]:MAG).
	
	LOCAL avg_thrust is vehiclestate["avg_thr"]:average().

	IF NOT (vehiclestate["staging_in_progress"] OR vehicle["meco_flag"]) {
		
		LOCAL current_m IS SHIP:MASS*1000.
		
		local res_left IS get_shuttle_res_left().
		
		SET vehiclestate["m_burn_left"] to res_left.
		
		IF (vehiclestate["cur_stg"]=1) {
		
			SET cur_stg["Tstage"] TO cur_stg["Tstage"] - surfacestate["deltat"].
			
		} ELSE {
			IF (vehiclestate["cur_stg"]=2) {
			
				update_stage2(current_m, res_left).
		
			} ELSE IF (vehiclestate["cur_stg"]=3) {
				
				update_stage3(current_m, res_left).
			
			} ELSE IF (vehiclestate["cur_stg"]=4) {
				
				update_stage4(current_m, res_left).
			}
			
			ssme_staging(vehiclestate["cur_stg"]).
			ssme_low_level().
			ssme_flameout().
		}
	
	}
	
	//moved this here bc we must update oms propellant once before checking if it's time to stop
	stop_oms_dump().
	
	
	if (ops1_parameters["debug_mode"]) {
		dump_vehicle().
	}
}

FUNCTION update_stage2 {
	PARAMETER m_initial.
	PARAMETER res_left.
	PARAMETER stg2 IS vehicle["stages"][2].

	SET stg2["m_initial"] TO m_initial.
	SET stg2["m_burn"] TO res_left.
	SET stg2["m_final"] TO m_initial - res_left.
	
	IF (stg2["staging"]["type"]="depletion") {
		
		SET stg2["Tstage"] TO const_f_t(stg2).	
		
	} ELSE IF (stg2["staging"]["type"]="glim") {
		
		LOCAL x IS glim_t_m(stg2).
		
		LOCAL stg3_m_initial IS 0.
		
		IF (x[0] >= 0) {
			SET stg2["Tstage"] TO x[0]. 
			SET stg2["m_final"] TO x[1]. 
			SET stg2["m_burn"] TO m_initial - x[1].
			set stg3_m_initial to x[1].
		} ELSE {
			//will never violate the limit
			SET stg2["Tstage"] TO 0. 
			SET stg2["m_burn"] TO m_initial - stg2["m_final"].
			set stg3_m_initial to stg2["m_final"].
		}
		
		
		LOCAL stg3_m_burn IS res_left - stg2["m_burn"].
		
		update_stage3(stg3_m_initial, stg3_m_burn).
	} ELSE IF (stg2["staging"]["type"]="time") {
		//only ever entered during aborts 
		
		SET stg2["m_final"] TO const_f_dt_mfinal(stg2).
		SET stg2["m_burn"] TO stg2["m_initial"] - stg2["m_final"].
		
		IF (vehicle["stages"]:LENGTH > 3) {
			LOCAL stg3_m_initial IS stg2["m_final"].
			LOCAL stg3_m_burn IS MAX(0, res_left - stg2["m_burn"]).
			
			update_stage3(stg3_m_initial, stg3_m_burn).
		}
	}

}



FUNCTION update_stage3 {
	PARAMETER m_initial.
	PARAMETER res_left.
	PARAMETER stg3 IS vehicle["stages"][3].
	
	SET stg3["m_initial"] TO m_initial.
	SET stg3["m_burn"] TO res_left.
	SET stg3["m_final"] TO m_initial - res_left.
	
	IF stg3["mode"]=1 {
		//constant thrust depletion stage, only used for aborts
		
		SET stg3["Tstage"] TO const_f_t(stg3).	
	
	} ELSE IF stg3["mode"]=2 {
	
		LOCAL x IS const_G_t_m(stg3).
		
		SET stg3["Tstage"] TO x[0].

		IF (stg3["staging"]["type"]="minthrot") {
			//there is a fourth stage, assume there will be a violation of minimum throttle 
			
			SET stg3["m_final"] TO x[1].
			LOCAL stg4_m_initial IS x[1].
			
			SET stg3["m_burn"] TO m_initial - x[1].
			LOCAL stg4_m_burn IS res_left - stg3["m_burn"].

			update_stage4(stg4_m_initial, stg4_m_burn).
			
		}
	}
}


FUNCTION update_stage4 {
	PARAMETER m_initial.
	PARAMETER res_left.
	PARAMETER stg4 IS vehicle["stages"][4].
	
	//assume it's a depletion stage
	
	
	SET stg4["m_initial"] TO m_initial.
	SET stg4["m_burn"] TO res_left.
	SET stg4["m_final"] TO m_initial - res_left.
	
	SET stg4["Tstage"] TO const_f_t(stg4).	
	
}



FUNCTION increment_stage {
	
	SET vehiclestate["staging_time"] TO surfacestate["time"].
	
	LOCAL j IS vehiclestate["cur_stg"].
	
	SET vehiclestate["cur_stg"] TO j + 1.
	
	SET vehicle["stages"][j+1]["ign_t"] TO vehiclestate["staging_time"].
	
	vehiclestate["avg_thr"]:reset().
	
	WHEN (surfacestate["time"] > vehiclestate["staging_time"] + 0.5) THEN {
		addGUIMessage("STAGING SEQUENCE COMPLETE").
		SET vehiclestate["staging_in_progress"] TO FALSE.
	}

}

//to be called after stage setup when an engine fails 
//reset back to stage 2 
FUNCTION reset_stage {
	set vehiclestate["cur_stg"] to min(vehiclestate["cur_stg"], 2).
}

FUNCTION ssme_staging {
	parameter cur_stg.
	
	IF vehiclestate["staging_in_progress"] {RETURN.}
	
	if (vehicle["stages"][cur_stg]["Tstage"] <= 0.5) {
		if (cur_stg < (vehicle["stages"]:LENGTH - 1)) {
			SET vehiclestate["staging_in_progress"] TO TRUE.
			increment_stage().
		}
	}
}


//returns true when we're close to depletion at minimum throttle on three engines
FUNCTION ssme_low_level {
	
	local three_eng_lex is build_engines_lex(3, 0).

	local prop_left is vehicle["SSME_prop"].
	
	local low_level_prop is three_eng_lex["flow"] * three_eng_lex["minThrottle"] * ops1_parameters["low_level_burnt"].
	
	set vehicle["low_level"] to (prop_left <= low_level_prop).
}









//		SHUTTLE-SPECIFIC FUNCTIONS 


function setup_shuttle_stages {
	parameter initial_mass.
	parameter stack_empty_mass.
	parameter engines_lex.
	parameter max_throtval.
	
	local stg_1 is vehicle["stages"][1].
	
	// ssme constant F stage
	
	local new_stg_2 is empty_stg_template().
	
	set new_stg_2["m_initial"] to initial_mass.
	set new_stg_2["m_final"] to stack_empty_mass.
	set new_stg_2["m_burn"] to initial_mass - stack_empty_mass.
	set new_stg_2["glim"] to vehicle["glim"].
	set new_stg_2["Throttle"] to max_throtval.
	set new_stg_2["engines"] to engines_lex.
	set new_stg_2["mode"] to 1.
	
	LOCAL stage3InitialMass IS 0.
	LOCAL stage3mode IS 0.
	
	LOCAL gl_out IS glim_t_m(new_stg_2).
	
	If (gl_out[0] < 0) {
		// won't violate the glim
		SET new_stg_2["Tstage"] TO const_f_t(new_stg_2).
		SET new_stg_2["staging"]["type"] TO "depletion".
		
		if (new_stg_2["Tstage"] = 0) {
			set new_stg_2["m_final"] to new_stg_2["m_initial"].
			set new_stg_2["m_burn"] to 0.
		}
		
		set stage3InitialMass to new_stg_2["m_final"].
		set stage3mode to 1.
		
	} else {
		// will violate the glim 
		
		set new_stg_2["m_final"] to MIN(gl_out[1], new_stg_2["m_initial"]).
		SET new_stg_2["m_burn"] TO new_stg_2["m_initial"] - new_stg_2["m_final"].
		SET new_stg_2["Tstage"] TO MAX(gl_out[0], 0).
		SET new_stg_2["staging"]["type"] TO "glim".
		
		set stage3InitialMass to new_stg_2["m_final"].
		set stage3mode to 2.
	}
	
	local new_stg_3 is empty_stg_template().
	
	set new_stg_3["m_initial"] to stage3InitialMass.
	set new_stg_3["m_final"] to stack_empty_mass.
	set new_stg_3["m_burn"] to stage3InitialMass - stack_empty_mass.
	set new_stg_3["glim"] to vehicle["glim"].
	set new_stg_3["Throttle"] to max_throtval.
	set new_stg_3["engines"] to engines_lex.
	set new_stg_3["mode"] to stage3mode.
	
	LOCAL stage4InitialMass IS 0.
	
	if (stage3mode = 1) {
		// only if we never reach the glim 
		
		set stage4InitialMass to new_stg_3["m_final"].
		
		SET new_stg_3["Tstage"] TO const_f_t(new_stg_3).
		SET new_stg_3["staging"]["type"] TO "depletion".
		
	} else if (stage3mode = 2) {
		LOCAL gtm_out IS const_G_t_m(new_stg_3).
		
		set stage4InitialMass to gtm_out[1].
		SET new_stg_3["m_final"] TO gtm_out[1].
		SET new_stg_3["m_burn"] TO new_stg_3["m_initial"] - new_stg_3["m_final"].
		SET new_stg_3["Tstage"] TO gtm_out[0].
		
		
		
		if (stage4InitialMass > stack_empty_mass) {
			SET new_stg_3["staging"]["type"] TO "minthrot".
		} else {
			SET new_stg_3["staging"]["type"] TO "depletion".
		}
		
	}	
	
	
	local new_stg_4 is empty_stg_template().
	
	set new_stg_4["m_initial"] to stage4InitialMass.
	set new_stg_4["m_final"] to stack_empty_mass.
	set new_stg_4["m_burn"] to stage4InitialMass - stack_empty_mass.
	set new_stg_4["glim"] to vehicle["glim"].
	set new_stg_4["Throttle"] to vehicle["minThrottle"].
	set new_stg_4["engines"] to engines_lex.
	set new_stg_4["mode"] to 1.
	set new_stg_4["staging"]["type"] TO "depletion".
	SET new_stg_4["Tstage"] TO const_f_t(new_stg_4).
	
	set vehicle["stages"] to list(
									0,
									stg_1,
									new_stg_2,
									new_stg_3,
									new_stg_4
	).

}

function empty_stg_template {

	return LEXICON(
		"m_initial", 0,
		"m_final", 0,
		"m_burn", 0,
		"staging", LEXICON (
					"type","",
					"ignition",	FALSE
		),
		"glim", 0,
		"ign_t", 0,
		"Throttle", 0,
		"Tstage",0,
		"engines", 0,
		"mode", 0
	).

}


FUNCTION get_srb_thrust {

	local srb_l is get_srb_parts().
	
	if (srb_l:length = 0) {
		return 0.
	}
	
	return srb_l[0]:thrust.
}

//return thrust thresh for separation as a function of engines out 
function srb_sep_thrust {
	
	local engines_out is get_engines_out().
	
	if (engines_out = 3) {
		return 550.
	}
	
	return 350/(1 + engines_out).
	
}

//shutdown a number of engines
//if just one, avoid shautting down the centre engine
FUNCTION trigger_engine_failure {
	parameter n.

	local engines_out is get_engines_out().
	
	LOCAL running_eng IS get_running_ssmes().
	
	
	if (n = 1) {
		if (engines_out = 0) {
			LOCAL zpos IS 0.
			LOCAL ze_ IS 0.
			FROM {local e_ is 0.} UNTIL e_ >= running_eng:LENGTH STEP {set e_ to e_+1.} DO { 
				
				LOCAL eng IS running_eng[e_].
				LOCAL z_ IS VDOT(VXCL(SHIP:FACING:STARVECTOR, eng:POSITION), SHIP:FACING:TOPVECTOR).
				IF (z_ > zpos) {
					set zpos to z_.
					set ze_ to e_.
				}
			}
			running_eng:REMOVe(ze_).
		}
		
		select_rand(running_eng):SHUTDOWN.
		
	} else if (n > 1) {
		
		if (n = 2)  and (engines_out = 0) {
			local safe_eng_idx is random_int_range(running_eng:length).
		
			running_eng:remove(safe_eng_idx).
		}
		
		for e_ in running_eng {
			e_:shutdown.
		}
	
	}
}


//measure both ssme and oms fuel 
FUNCTION get_shuttle_res_left {

	SET vehicle["SSME_prop"] TO get_ssme_prop().
	SET vehicle["OMS_prop"] TO get_oms_prop().

	//default and to prevent divisions by zero
	LOCAL total_prop IS vehicle["SSME_prop"].
	//IF (vehicle["SSME"]["active"] > 0) {
	//	SET total_prop TO total_prop + vehicle["SSME_prop"].
	//}
	
	IF (vehicle["OMS"]["active"] > 0) {
		SET total_prop TO total_prop + vehicle["OMS_prop"].
	}
		
	return total_prop.
}

function get_ssme_parts {

	local expected_ssme is 3.

	local sss_eng is SHIP:PARTSDUBBEDPATTERN(".*ssme.*").
	
	if (sss_eng:length = expected_ssme) {
		return sss_eng.
	}
	
	local ro_eng is SHIP:PARTSDUBBEDPATTERN(".*rs25.*").
	
	if (ro_eng:length = expected_ssme) {
		return ro_eng.
	}

	return list().
}

function get_running_ssmes {
	local running_ssme is list().

	FOR ssme IN get_ssme_parts() {
		IF (ssme:IGNITION) and (NOT ssme:FLAMEOUT) {
			running_ssme:add(ssme).
		}
	}
	
	return running_ssme.
}

function get_srb_parts {
	return ship:partsdubbed("ShuttleRocketBooster").
}

//return the ET part to read fuel quantities
//designed to crash if there is no part with this name
FUNCTION get_ext_tank_part {
	RETURN SHIP:PARTSDUBBED("ShuttleExtTank")[0].
}

//get propellants for SSMEs
FUNCTION get_ssme_prop {
	return get_prop_mass(
		LEXICON(
			"resources",vehicle["SSME"]["resources"],
			"tankparts",LIST(get_ext_tank_part())
		)
	).
}

//return the ET propellant fraction left
function get_et_prop_fraction {
	return vehicle["SSME_prop"] / vehicle["SSME_prop_0"].
}

function get_oms_parts {

	local expected_oms is 2.

	local sss_eng is SHIP:PARTSDUBBEDPATTERN(".*engineoms.*").
	
	if (sss_eng:length = expected_oms) {
		return sss_eng.
	}
	
	local ro_eng is SHIP:PARTSDUBBEDPATTERN(".*aj10.*").
	
	if (ro_eng:length = expected_oms) {
		return ro_eng.
	}

	return list().
}

//return a list ocntaining parts with OMS fuel (i.e. oms pods)
//designed to crash if there are less than two matching parts
FUNCTION get_oms_tanks_parts {
	LOCAL partslist IS ship:PARTSNAMEDPATTERN("ShuttleOMSPod*").
	RETURN LIST(partslist[0], partslist[1]).
}

//get propellants for OMSs
FUNCTION get_oms_prop {
	return get_prop_mass(
		LEXICON(
			"resources",vehicle["OMS"]["resources"],
			"tankparts",get_oms_tanks_parts()
		)
	).
}

//return the ET propellant fraction left
function get_oms_prop_fraction {
	return vehicle["OMS_prop"] / vehicle["OMS_prop_0"].
}


FUNCTION activate_fuel_cells {

	LOCAL partslist IS LIST().
	for p in SHIP:PARTSDUBBEDPATTERN("ShuttleOrbiter.*") {
		partslist:ADD(p).
	}
	for p in SHIP:PARTSDUBBED("ShuttleEngMount") {
		partslist:ADD(p).
	}
	
	for p in partslist {
		for m in p:MODULESNAMED("ModuleResourceConverter") {
			for an in m:ALLACTIONNAMES {
				IF an:CONTAINS("start fuel cell") {
					m:DOACTION(an, true).
				}
			}
		}
	}
}

function et_sep {
	local et_part is get_ext_tank_part().
	
	local dm is et_part:getmodule("ModuleDecouple").
	dm:doaction("Decouple", true).
}


//close umbilical doors
FUNCTION close_umbilical {

	LOCAL partslist IS LIST().
	for p in SHIP:PARTSDUBBEDPATTERN("ShuttleOrbiter.*") {
		partslist:ADD(p).
	}
	for p in SHIP:PARTSDUBBED("ShuttleEngMount") {
		partslist:ADD(p).
	}
	
	for p in partslist {
		for m in p:MODULESNAMED("ModuleAnimateGeneric") {
			if m:hasaction("toggle et door") {
				m:doaction("toggle et door", true).
			}
		}
	}
}




FUNCTION start_oms_dump {
	parameter fast_dump is false.

	
	if (abort_modes["oms_dump_complete"]) {
		return.
	}
	
	if (fast_dump) {
		dap:set_rcs(TRUE).
		SET SHIP:CONTROL:FORE TO 1.
		SET SHIP:CONTROL:TOP TO 1.
	}
	toggle_oms(true).
	
	if (NOT abort_modes["oms_dump"]) {
		addGUIMessage("OMS DUMP STARTED").
		SET abort_modes["oms_dump"] TO TRUE.
	}
}

FUNCTION stop_oms_dump {
	PARAMETER force IS FALSE.
	
	IF (NOT abort_modes["oms_dump"]) {
		RETURN.
	}
	
	local prop_frac_flag is (get_oms_prop_fraction() <= ops1_parameters["OMS_prop_dump_frac"]).

	IF prop_frac_flag OR (force) {
		SET SHIP:CONTROL:NEUTRALIZE TO TRUE.
		toggle_oms(false).
		addGUIMessage("OMS DUMP STOPPED").
		SET abort_modes["oms_dump"] TO FALSE.
		SET abort_modes["oms_dump_complete"] TO prop_frac_flag.
	}
}

function toggle_oms {
	parameter turn_on.
	
	FOR oms IN get_oms_parts() {
		if (turn_on) {
			oms:ACTIVATE.
		} else {
			oms:SHUTDOWN.
		}
	}
}

//check that the three ssme are present and the same type, calculate all the parameters needed
FUNCTION parse_ssme {
	
	LOCAL ssmelex IS LEXICON(
		"type","",
		"active",0,
		"isp",0,
		"thrust",0,
		"flow",0,
		"minThrottle",0,
		"maxThrottle",1,
		"resources",0
	).
	
	//count SSMEs, not necessary per se but a useful check to see if we're flying a DECQ shuttle
	LOCAL ssme_count IS 0. 
	SET ssmelex["type"] TO get_ssme_parts()[0]:CONFIG.
	
	LOCAL ssme_reslex IS LEXICON().
	
	FOR ssme IN get_ssme_parts() {
		IF ssme:ISTYPE("engine") {
			SET ssme_count TO ssme_count + 1.
			
			IF (ssme:CONFIG <> ssmelex["type"]) {
				PRINT ("ERROR! THE VEHICLE SEEMS TO HAVE MISMATCHED SSME TYPES") AT (1,5).
				LOCAL X IS 1/0.
			}
			
			LOCAL ssme_thr IS ssme:POSSIBLETHRUSTAT(0.0).
			LOCAL ssme_isp IS ssme:VACUUMISP.
			LOCAL ssme_flow IS ssme:MAXMASSFLOW*1000.
			LOCAL ssme_minthr IS ssme:MINTHROTTLE.
			LOCAL ssme_res IS ssme:consumedresources:VALUES.
	
			SET ssmelex["thrust"] TO ssmelex["thrust"] + ssme_thr.
			SET ssmelex["isp"] TO ssmelex["isp"] + ssme_isp*ssme_thr.
			SET ssmelex["flow"] TO ssmelex["flow"] + ssme_flow.
			SET ssmelex["minThrottle"] TO ssmelex["minThrottle"] + ssme_minthr*ssme_thr.
			
			FOR res IN ssme_res {
				IF NOT ssme_reslex:HASKEY(res:name) {
					ssme_reslex:ADD(res:name, res).
				}
			}
		}
	}
	
	IF (ssme_count <> 3 ) {
		PRINT ("ERROR! THE VEHICLE SEEMS TO HAVE THE WRONG NUMBER OF SSMEs") AT (1,5).
		LOCAL X IS 1/0.
	}
	
	SET ssmelex["active"] TO ssme_count.
	
	SET ssmelex["isp"] TO ssmelex["isp"]/ssmelex["thrust"].
	SET ssmelex["minThrottle"] TO ssmelex["minThrottle"]/ssmelex["thrust"].
	
	SET ssmelex["thrust"] TO ssmelex["thrust"]/ssme_count.
	SET ssmelex["flow"] TO ssmelex["flow"]/ssme_count.
	
	SET ssmelex["resources"] TO ssme_reslex.
	
	RETURN ssmelex.
	
}


//check that the two oms are present and the same type, calculate all the parameters needed
FUNCTION parse_oms {
	
	LOCAL omslex IS LEXICON(
		"type","",
		"active",0,
		"isp",0,
		"thrust",0,
		"flow",0,
		"minThrottle",0,
		"maxThrottle",0,
		"resources",0
	).
	
	//count OMS, not necessary per se but a useful check to see if we're flying a DECQ shuttle
	LOCAL oms_count IS 0. 
	
	SET omslex["type"] TO get_oms_parts()[0]:CONFIG.
	
	LOCAL oms_reslex IS LEXICON().
	
	FOR oms IN get_oms_parts() {
		IF oms:ISTYPE("engine") {
			SET oms_count TO oms_count + 1.
			
			IF (oms:CONFIG <> omslex["type"]) {
				PRINT ("ERROR! THE VEHICLE SEEMS TO HAVE MISMATCHED OMS TYPES") AT (1,5).
				LOCAL X IS 1/0.
			}
			
			LOCAL oms_thr IS oms:POSSIBLETHRUSTAT(0.0).
			LOCAL oms_isp IS oms:VACUUMISP.
			LOCAL oms_flow IS oms:MAXMASSFLOW*1000.
			LOCAL oms_minthr IS oms:MINTHROTTLE.
			LOCAL oms_res IS oms:consumedresources:VALUES.
	
			SET omslex["thrust"] TO omslex["thrust"] + oms_thr.
			SET omslex["isp"] TO omslex["isp"] + oms_isp*oms_thr.
			SET omslex["flow"] TO omslex["flow"] + oms_flow.
			SET omslex["minThrottle"] TO omslex["minThrottle"] + oms_minthr*oms_thr.
			
			FOR res IN oms_res {
				IF NOT oms_reslex:HASKEY(res:name) {
					oms_reslex:ADD(res:name, res).
				}
			}
		}
	}
	
	IF (oms_count <> 2 ) {
		PRINT ("ERROR! THE VEHICLE SEEMS TO HAVE THE WRONG NUMBER OF OMSs") AT (1,5).
		LOCAL X IS 1/0.
	}
	
	SET omslex["active"] TO oms_count.
	
	SET omslex["isp"] TO omslex["isp"]/omslex["thrust"].
	SET omslex["minThrottle"] TO omslex["minThrottle"]/omslex["thrust"].
	
	SET omslex["thrust"] TO omslex["thrust"]/oms_count.
	SET omslex["flow"] TO omslex["flow"]/oms_count.

	SET omslex["maxThrottle"] TO 1.
	
	SET omslex["resources"] TO oms_reslex.
	
	RETURN omslex.
	
}

FUNCTION build_engines_lex {
	parameter ssme_active is vehicle["SSME"]["active"].
	parameter oms_active is vehicle["OMS"]["active"].

	LOCAL tot_ssme_thrust IS ssme_active*vehicle["SSME"]["thrust"].
	LOCAL tot_oms_thrust IS oms_active*vehicle["OMS"]["thrust"].
	LOCAL tot_thrust IS tot_ssme_thrust + tot_oms_thrust.

	LOCAL ssme_flow IS ssme_active*vehicle["SSME"]["flow"].
	LOCAL oms_flow IS oms_active*vehicle["OMS"]["flow"].
	LOCAL tot_flow IS ssme_flow + oms_flow.
	
	LOCAL tot_isp IS 0.
	
	IF (tot_flow > 0) {
		SET tot_isp TO (vehicle["SSME"]["isp"] * ssme_flow + vehicle["OMS"]["isp"] * oms_flow) / tot_flow.
	}
	
	
	LOCAL tot_minThrot IS vehicle["SSME"]["minThrottle"].
	IF (tot_thrust > 0) {
		SET tot_minThrot TO (tot_ssme_thrust * vehicle["SSME"]["minThrottle"] + tot_oms_thrust * vehicle["OMS"]["minThrottle"]) / tot_thrust.
	}
	
	RETURN LEXICON(
				"thrust", tot_thrust*1000, 
				"isp", tot_isp, 
				"flow",tot_flow,
				"minThrottle", tot_minThrot
	).
}

//100 percent rated power level in kn in vacuum (1ssme)
function get_rpl_thrust {
	return 2090.
}

//given a throttle value as a percentage of rpl, converts it into absolute percentage
FUNCTION convert_ssme_throt_rpl {
	parameter rpl_throt.
	
	//first work out the rpl level of the engines' max thrust 
	
	local max_rpl_thr is vehicle["SSME"]["thrust"]/get_rpl_thrust().
	
	//then do the proportion with 100% commanded throttle 
	
	return rpl_throt/max_rpl_thr.

}

//measure running engines of both kinds and rebuild the engines LEXICON
FUNCTION measure_update_engines {

	if (vehiclestate["staging_in_progress"]) {
		return.
	}
	
	LOCAL SSMEcount_prev IS vehicle["SSME"]["active"].
	
	//measure engines 
	LOCAL SSMEcount IS get_running_ssmes():length.
	
	local ssmes_out is (SSMEcount_prev - SSMEcount).
	local ssme_out_detected_flag is (ssmes_out > 0).
	
	if (ssme_out_detected_flag) {
		addGUIMessage("ENGINE OUT DETECTED").
		ssme_out_safing().
		if (SSMEcount = 1) {
			addGUIMessage("SINGLE ENGINE ROLL CONTROL").
			single_engine_roll_control().
		}
		
		FROM {local k is 0.} UNTIL k = ssmes_out STEP {set k to k+1.} DO {
			local engout_vi is orbitstate["velocity"]:mag.
			
			ascent_traj_add_engout(engout_vi).
			abort_modes["ssmes_out"]:add(
										lexicon(
												"time", surfacestate["MET"],
												"vi", engout_vi,
												"ve", surfacestate["surfv"]:mag
										)
			).
			
		} 
		
		//force upfg unconverged 
		set upfgInternal["s_conv"] to false.
		
	}
	//latch flag until reset by the abort initialiser
	set vehicle["ssme_out_detected"] to (vehicle["ssme_out_detected"] OR ssme_out_detected_flag).
	
	SET vehicle["SSME"]["active"] TO SSMEcount.
	
	LOCAL OMScount IS 0.
	FOR e IN get_oms_parts() {
		IF e:IGNITION {
			SET OMScount TO OMScount + 1.
		}
	}
	
	SET vehicle["OMS"]["active"] TO OMScount.
	
	LOCAL cur_stg IS get_stage().
	SET cur_stg["engines"] TO build_engines_lex().
	
	if (ssme_out_detected_flag) {
		LOCAL current_m IS SHIP:MASS*1000.
		local res_left IS get_shuttle_res_left().
		
		setup_shuttle_stages(
							current_m,
							current_m - res_left,
							cur_stg["engines"],
							vehicle["maxThrottle"]
		).
		reset_stage().
	}
	
		
}

function get_engines_out {
	return 3 - vehicle["SSME"]["active"].
}

//this should now return true if no engines are running
FUNCTION ssme_flameout {
	SET vehicle["meco_flag"] TO (get_engines_out() = 3).
}


FUNCTION shutdown_ssmes {
	if (vehicle["meco_flag"]) {
		return.
	}
	
	FOR e IN get_ssme_parts() {
		e:shutdown.
	}	
}

function ssme_out_safing {
	FOR ssme IN get_ssme_parts() {
		if (ssme:FLAMEOUT) {
			ssme:shutdown.
			wait 0.
		}
		
		IF (NOT ssme:IGNITION) {
			ssme:GIMBAL:DOACTION("lock gimbal", TRUE).
		}
	}
}

function single_engine_roll_control {

	dap:set_rcs(TRUE).
	
	dap:toggle_serc(true).
	
	FOR ssme IN get_ssme_parts() {
		set ssme:GIMBAL:roll to false.
	}
	
	FOR oms IN get_oms_parts() {
		set oms:GIMBAL:roll to false.
	}

}

function switch_att_rcs {
	parameter pitch_rcs is true.
	parameter yaw_rcs is true.
	parameter roll_rcs is true.
	
	LIST RCS IN rcslist.
	
	local rcsmoduleslist is list().
	
	for rcs_ in rcslist {
		for rcsm_ in rcs_:modulesnamed("ModuleRCSFX") {
			if (rcsm_:hasevent("show actuation toggles")) {
				rcsm_:doevent("show actuation toggles").
				wait 0.
			}
			
			rcsm_:SETFIELD("pitch",pitch_rcs).
			rcsm_:SETFIELD("yaw",yaw_rcs).
			rcsm_:SETFIELD("roll",roll_rcs).
		}
	}

}