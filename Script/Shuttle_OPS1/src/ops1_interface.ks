
FUNCTION addGUIMessage {
	PARAMETER msg.
	
	LOCAL clear_ is false.
	
	local t_msg is TIME:SECONDS - vehicle["ign_t"].
	
	ascent_add_scroll_msg(
						sectotime(TIME:SECONDS - vehicle["ign_t"],"") + ": " + msg,
						clear_
	).

}

FUNCTION dataViz {
	
	log_telemetry().
	
	
	//gui update
	
	//predict 30 seconds into the future, 2 steps
	//keep roll and pitch fixed 
	LOCAL pred_simstate IS current_simstate().
	LOCAL sim_dt IS 15.
	IF (vehiclestate["major_mode"] >= 101) {
		local roll_prog is get_roll_prograde().
		local pitch_prog is get_pitch_prograde().
		
		local thrvec is vehiclestate["thr_vec"]/1000.
		
		IF (vehiclestate["major_mode"] = 102) {
			SET sim_dt TO 10.
		}
		
		FROM {local k is 1.} UNTIL k > 2 STEP {set k to k + 1.} DO { 
			SET pred_simstate TO rk3(sim_dt,pred_simstate,LIST(pitch_prog,roll_prog), thrvec).
			if (thrvec:mag > 0 and vehiclestate["isp"] > 0) {
				local eng_md is thrvec:mag / (vehiclestate["isp"] * g0).
				set pred_simstate["mass"] to pred_simstate["mass"] - sim_dt * eng_md.  
			}
		}	
	}
	
	SET pred_simstate["altitude"] TO bodyalt(pred_simstate["position"]).
	SET pred_simstate["surfvel"] TO surfacevel(pred_simstate["velocity"],pred_simstate["position"]).
	SET pred_simstate["latlong"] TO shift_pos(pred_simstate["position"],pred_simstate["simtime"]).

	LOCAL pred_vi IS pred_simstate["velocity"]:MAG.
	LOCAL pred_ve IS pred_simstate["surfvel"]:MAG.
	LOCAL pred_alt IS pred_simstate["altitude"]/1000.
	
	local tgo is upfgInternal["Tgo"].
	local vgo is upfgInternal["vgo"]:MAG.
	LOCAL converged IS (upfgInternal["s_conv"]) AND (NOT upfgInternal["s_meco"]).
	
	local gui_ref_alt is 0.
	if (ascent_traj_disp_counter = 1) {
		set gui_ref_alt to 45.
	} else {
		set gui_ref_alt to target_orbit["cutoff alt"].
	}
	
	
	LOCAL gui_data IS lexicon(
				"met", TIME:SECONDS - vehicle["ign_t"],
				"major_mode", vehiclestate["major_mode"],
				"hdot", SHIP:VERTICALSPEED,
				"r_delta", dap:steer_roll_delta,
				"p_delta", dap:steer_pitch_delta,
				"y_delta", dap:steer_yaw_delta,
				"t_delta", dap:throt_delta * 100,
				"vi", SHIP:VELOCITY:ORBIT:MAG,
				"ve", SHIP:VELOCITY:SURFACE:MAG,
				"alt", SHIP:ALTITUDE/1000,
				"pred_vi", pred_vi,
				"pred_ve", pred_ve,
				"pred_alt", pred_alt,
				"ref_alt", gui_ref_alt,
				"twr", get_TWR(),
				"ssme_thr", 100 * dap:thr_cmd_rpl * vehicle["SSME"]["thrust"] / get_rpl_thrust(),
				"et_prop", 100*get_et_prop_fraction(),
				"tgo", tgo,
				"vgo", vgo,
				"rtls_tc", 0,
				"converged", converged
	).
	
	update_abort_modes_gui().
	
	//do the rtls gui update 
	IF (vehiclestate["major_mode"] >= 600) {
	
		gui_data:ADD("dwnrg_ve", surfacestate["horiz_dwnrg_v"]).
		gui_data:ADD("dwnrg_pred_ve", current_horiz_dwnrg_speed(pred_simstate["latlong"], pred_simstate["surfvel"])).
		gui_data:ADD("rtls_cutv", target_orbit["rtls_cutv"]).
		set gui_data["rtls_tc"] to  RTLSAbort["Tc"].
		
		SET gui_data["converged"] TO (gui_data["converged"] OR ((NOT RTLSAbort["pitcharound"]["triggered"]) AND (RTLSAbort["flyback_conv"] = 1))).
		
		update_rtls_traj_disp(gui_data).
		
		//v_dwnrng", ,
		//"pred_v_dwnrg", pred_v_dwnrg,
	
	} else {
		
		gui_data:ADD("cutv", target_orbit["velocity"]).
		gui_data:ADD("droop_alt", max(0, droopInternal["rout"]/1000)).
		gui_data:ADD("droop_engaged", droopInternal["s_cdroop"]).
					
		update_ascent_traj_disp(gui_data).
	
	} 
	

}


function print_ascent_report {
		
	local orbit_str is "AP: " + ROUND(APOAPSIS/1000,1) + " km | PE: " + ROUND(PERIAPSIS/1000,1) + " km".
	
	set orbit_str to orbit_str + " | INCL:  " + ROUND(ORBIT:INCLINATION,3) + " ° | TRUE AN.: " + ROUND(ORBIT:TRUEANOMALY,2) + " °".

	addGUIMessage(orbit_str).
	
	local orbit_err_str is "Ap err: " + ROUND(abs((1 - APOAPSIS/(1 + target_orbit["Apoapsis"]*1000))*100),2) + "%".
	set orbit_err_str to orbit_err_str + " | Pe err: " + ROUND(abs((1 - PERIAPSIS/(1 + target_orbit["Periapsis"]*1000))*100),2) + "%".
	
	set orbit_err_str to orbit_err_str + " | Incl err: " + ROUND(abs((1 - ORBIT:INCLINATION/(0.001 + target_orbit["Inclination"]))*100),3) + "%".
	set orbit_err_str to orbit_err_str + " | True An err: " + ROUND(abs(ORBIT:TRUEANOMALY - target_orbit["eta"] ),2) + "° ".

	addGUIMessage(orbit_err_str).

}



FUNCTION prepare_telemetry {
	if logdata=TRUE {	
		GLOBAL loglex IS LEXICON(
										"Time",0,
										"major_mode", 0, 
										"Lat",0,
										"Lng",0,
										"Altitude",0,
										"Dwnrg Dst",0,
										"Stage",0,
										"Mass",0,
										"TWR",0,
										"Throt",0,
										"AZ(cmd)",0,
										"HAOA",0,
										"Pitch",0,
										"VAOA",0,
										"Surfvel",0,
										"Orbvel",0,
										"Vspeed",0,
										"Dwnrg surfvel",0,
										"Incl",0,
										"Ecctr",0,
										"q", 0,
										"eas", 0
		).
		log_data(loglex,"./Shuttle_OPS1/LOGS/" + vehicle["name"] + "_log", TRUE).
	}
}

FUNCTION log_telemetry {
	if logdata=TRUE {
		LOCAL stg IS get_stage().
		
		//prepare list of values to log.
		
		SET loglex["Time"] TO TIME:SECONDS - vehicle["ign_t"].
		SET loglex["major_mode"] TO vehiclestate["major_mode"].
		SET loglex["Lat"] TO SHIP:GEOPOSITION:LAT.
		SET loglex["Lng"] TO SHIP:GEOPOSITION:LNG.
		SET loglex["Altitude"] TO SHIP:ALTITUDE/1000.
		SET loglex["Dwnrg Dst"] TO surfacestate["dwnrg_dst"].	
		SET loglex["Stage"] TO vehiclestate["cur_stg"].
		SET loglex["Mass"] TO stg["m_initial"].
		SET loglex["TWR"] TO get_TWR().
		SET loglex["Throt"] TO stg["Throttle"]*100.
		SET loglex["AZ(cmd)"] TO surfacestate["hdir"].
		SET loglex["HAOA"] TO get_yaw_prograde().
		SET loglex["Pitch"] TO surfacestate["vdir"].
		SET loglex["VAOA"] TO get_pitch_prograde().
		SET loglex["Surfvel"] TO SHIP:VELOCITY:SURFACE:MAG.
		SET loglex["Orbvel"] TO SHIP:VELOCITY:ORBIT:MAG.
		SET loglex["Vspeed"] TO SHIP:VERTICALSPEED.
		SET loglex["Dwnrg surfvel"] TO current_horiz_dwnrg_speed(SHIP:GEOPOSITION, SHIP:VELOCITY:SURFACE).
		SET loglex["Incl"] TO ORBIT:INCLINATION.
		SET loglex["Ecctr"] TO ORBIT:ECCENTRICITY.
		SET loglex["q"] TO surfacestate["q"].
		SET loglex["eas"] TO surfacestate["eas"].

		log_data(loglex, "./Shuttle_OPS1/LOGS/" + vehicle["name"] + "_log").
	}
}


