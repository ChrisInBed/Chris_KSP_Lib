runOncePath("0:/lib/locales/utils.ks").
runOncePath("0:/lib/orbit.ks").
runOncePath("0:/lib/engine_utility.ks").

function gui_make_peglandgui {
    declare global gui_maingui is GUI(500, 700).
    set gui_maingui:style:hstretch to true.

    // title: PEG Landing Guidance
    declare global gui_title_box to gui_maingui:addhbox().
    set gui_title_box:style:height to 40.
    set gui_title_box:style:margin:top to 0.
    declare global gui_title_label to gui_title_box:addlabel("<b><size=20>" + UI_LANG["peggui.msg_summary"] + "</size></b>").
    set gui_title_label:style:align TO "center".
    declare global gui_title_exit_button to gui_title_box:addbutton("X").
    set gui_title_exit_button:style:width to 20.
    set gui_title_exit_button:style:align to "right".
    set gui_title_exit_button:onclick to {
        set done to true.
        set guidance_active to false.
        gui_maingui:hide().
    }.

    // Display region
    gui_maingui:addspacing(2).
    declare global gui_mainbox to gui_maingui:addscrollbox().
    declare global gui_display_box to gui_mainbox:addhlayout().
    declare global gui_display_box1 to gui_display_box:addvlayout().
    declare global gui_display_box2 to gui_display_box:addvlayout().
    declare global gui_display_gstatus to gui_display_box1:addlabel(UI_LANG["peggui.lbl_status"] + "inactive").
    declare global gui_display_numiters to gui_display_box1:addlabel(UI_LANG["peggui.lbl_peg_iter"] + "0").
    declare global gui_display_height to gui_display_box1:addlabel(UI_LANG["peggui.lbl_height"] + "0 m").
    declare global gui_display_distance to gui_display_box1:addlabel(UI_LANG["peggui.lbl_dist"] + "0 m").
    declare global gui_display_err to gui_display_box1:addlabel(UI_LANG["peggui.lbl_error"] + "0 m").
    declare global gui_display_vspeed to gui_display_box2:addlabel(UI_LANG["peggui.lbl_v_spd"] + "0 m/s").
    declare global gui_display_hspeed to gui_display_box2:addlabel(UI_LANG["peggui.lbl_h_spd"] + "0 m/s").
    declare global gui_display_T to gui_display_box2:addlabel(UI_LANG["peggui.lbl_time_t"] + "0 s").
    declare global gui_display_dv to gui_display_box2:addlabel(UI_LANG["peggui.lbl_peg_dv"] + "0 m/s").
    declare global gui_display_throttle to gui_display_box2:addlabel(UI_LANG["peggui.lbl_thro"] + "0").
    declare global gui_display_msg to gui_mainbox:addlabel("").

    // Orbit analysis region
    gui_mainbox:addspacing(2).
    declare global gui_orbitanalysis_box to gui_mainbox:addvlayout().
    declare global gui_orbitanalysis_button to gui_orbitanalysis_box:addbutton(UI_LANG["peggui.btn_analyze"]).
    set gui_orbitanalysis_button:style:width to 100.
    declare global gui_orbitanalysis_result1 to gui_orbitanalysis_box:addlabel("").
    declare global gui_orbitanalysis_result2 to gui_orbitanalysis_box:addlabel("").
    declare global gui_orbitanalysis_result3 to gui_orbitanalysis_box:addlabel("").
    declare global gui_orbitanalysis_result4 to gui_orbitanalysis_box:addlabel("").
    set gui_orbitanalysis_button:onclick to {
        local result to analyze_initial_orbit().
        if (not result["ok"]) {
            set gui_orbitanalysis_result1:text to result["msg"].
            return.
        }
        local distR_text to "".
        local distR_rmd_max to result["distR_rmd"] * 1.5.
        local distR_rmd_min to result["distR_rmd"] * 0.5.
        if result["distR"] > distR_rmd_max or result["distR"] < distR_rmd_min {
            set distR_text to "<color=red>"+round(result["distR"]*1e-3)+"</color>(" + round(distR_rmd_max*1e-3) + "~" + round(distR_rmd_min*1e-3) + ")".
        }
        else {
            set distR_text to round(result["distR"]*1e-3)+"(" + round(distR_rmd_min*1e-3) + "~" + round(distR_rmd_max*1e-3) + ")".
        }
        local distH_text to "".
        if result["distH"] > result["distH_rmd"] {
            set distH_text to "<color=red>"+round(result["distH"]*1e-3)+"</color>(<" + round(result["distH_rmd"]*1e-3) + ")".
        }
        else {
            set distH_text to round(result["distH"]*1e-3)+"(<" + round(result["distH_rmd"]*1e-3) + ")".
        }
        // local result_text to "T ≈ " + round(result["burntime"]) + " s;"
        //     + "Height = " + distR_text + " km;"
        //     + "Lateral distance = " + distH_text + " km".
        // set gui_orbitanalysis_result:text to result_text.
        set gui_orbitanalysis_result1:text to UI_LANG["peggui.lbl_est_burntime"] + round(result["burntime"]) + " s".
        set gui_orbitanalysis_result2:text to UI_LANG["peggui.lbl_est_distR"] + distR_text + " km".
        set gui_orbitanalysis_result3:text to UI_LANG["peggui.lbl_est_distH"] + distH_text + " km".
        set gui_orbitanalysis_result4:text to result["msg"].
    }.

    // emergency suppress
    gui_mainbox:addspacing(2).
    declare global gui_emergency_button to gui_mainbox:addcheckbox("<b><size=16>" + UI_LANG["peggui.gui_emergency"] + "</size></b>").
    set gui_emergency_button:ontoggle to {
        parameter newstate.
        set config:suppressautopilot to newstate.
    }.

    // Settings region
    declare global gui_settings_box to gui_mainbox:addvlayout().
    declare global gui_settings_gbox1 to gui_settings_box:addhlayout().
    declare global gui_settings_gbox11 to gui_settings_gbox1:addvlayout().
    declare global gui_settings_active_button to gui_settings_gbox11:addcheckbox(UI_LANG["peggui.gui_active"], false).
    set gui_settings_active_button:ontoggle to {
        parameter newstate.
        set guidance_active to newstate.
    }.
    declare global gui_settings_nowait_button to gui_settings_gbox11:addcheckbox(UI_LANG["peggui.gui_ign_now"], false).
    set gui_settings_nowait_button:ontoggle to {parameter newstate. set ignite_now to newstate.}.
    declare global gui_settings_add_approach_button to gui_settings_gbox11:addcheckbox(UI_LANG["peggui.gui_add_approach"], false).
    set gui_settings_add_approach_button:ontoggle to {
        parameter newstate. set add_approach_phase to newstate.
        if newstate {
            set desRT to 100.
            set desLT to 500.
            set desVRT to 3.
            set desVLT to 40.
        }
        else {
            set desRT to 100.
            set desLT to 0.
            set desVRT to 3.
            set desVLT to 0.
        }
        gui_update_descent_settings_display().
    }.
    declare global gui_settings_phase_box to gui_settings_gbox1:addvbox().
    declare global gui_settings_phase_box_title to gui_settings_phase_box:addlabel("<b>" + UI_LANG["peggui.gui_start_phase"] + "</b>").
    declare global gui_settings_desphase_button to gui_settings_phase_box:addradiobutton(UI_LANG["peggui.phase_descent"], true).
    set gui_settings_desphase_button:style:margin:bottom to 0.
    set gui_settings_desphase_button:ontoggle to {parameter newstate. if newstate {set start_phase to "descent".}.}.
    declare global gui_settings_appphase_button to gui_settings_phase_box:addradiobutton(UI_LANG["peggui.phase_approach"], false).
    set gui_settings_appphase_button:style:margin:bottom to 0.
    set gui_settings_appphase_button:ontoggle to {
        parameter newstate.
        if newstate {
            set start_phase to "approach".
            set gui_settings_add_approach_button:pressed to true.
        }.
    }.
    declare global gui_settings_finphase_button to gui_settings_phase_box:addradiobutton(UI_LANG["peggui.phase_final"], false).
    // set gui_settings_finphase_button:style:margin:bottom to 0.
    set gui_settings_finphase_button:ontoggle to {parameter newstate. if newstate {set start_phase to "final".}.}.
    declare global gui_settings_rotation_box to gui_settings_box:addhlayout().
    declare global gui_settings_rotation_label to gui_settings_rotation_box:addlabel(UI_LANG["peggui.lbl_roll"]).
    declare global gui_settings_rotation to gui_settings_rotation_box:addtextfield("0").
    declare global gui_settings_rotation_set to gui_settings_rotation_box:addbutton(UI_LANG["peggui.btn_set"]).
    set gui_settings_rotation_set:onclick to {set target_rotation to gui_settings_rotation:text:tonumber.}.

    declare global gui_settings_target_box to gui_settings_box:addvlayout().
    declare global gui_settings_target_title to gui_settings_target_box:addlabel("<b>" + UI_LANG["peggui.gui_tgt_settings"] + "</b>").
    declare global gui_settings_target_button_box1 to gui_settings_target_box:addhlayout().
    declare global gui_settings_target_waypoint_button to gui_settings_target_button_box1:addbutton(UI_LANG["peggui.btn_use_waypoint"]).
    set gui_settings_target_waypoint_button:onclick to {
        local _target_geo to get_target_geo().
        if (_target_geo = 0) {
            hudtext(UI_LANG["peggui.err_no_waypoint"], 4, 2, 12, hudtextcolor, false).
            return.
        }
        set gui_settings_target_lat:text to _target_geo:lat:tostring.
        set gui_settings_target_lng:text to _target_geo:lng:tostring.
        set target_geo to _target_geo.
    }.
    declare global gui_settings_target_show_button to gui_settings_target_button_box1:addcheckbox(UI_LANG["peggui.gui_show_target"], false).
    set gui_settings_target_show_button:ontoggle to {
        parameter newstate.
        if newstate {
            // draw target
            declare global gui_target_draw to vecDraw({return target_geo:position.}, {return up:forevector*3000.}, RGB(255, 0, 0), UI_LANG["peggui.vec_target"], 1, true).
        }
        else {
            // remove target draw
            if defined gui_target_draw {
                unset gui_target_draw.
            }
        }
    }.
    declare global gui_settings_target_button_box2 to gui_settings_target_box:addhlayout().
    declare global gui_settings_target_left to gui_settings_target_button_box2:addbutton("←").
    set gui_settings_target_left:onclick to {
        local new_pos to target_geo:position - gui_settings_target_step:text:tonumber * unitHtgt.
        set target_geo to body:geopositionof(new_pos).
        gui_update_target_settings_display().
    }.
    declare global gui_settings_target_right to gui_settings_target_button_box2:addbutton("→").
    set gui_settings_target_right:onclick to {
        local new_pos to target_geo:position + gui_settings_target_step:text:tonumber * unitHtgt.
        set target_geo to body:geopositionof(new_pos).
        gui_update_target_settings_display().
    }.
    declare global gui_settings_target_north to gui_settings_target_button_box2:addbutton("N").
    set gui_settings_target_north:onclick to {
        local new_pos to target_geo:position + gui_settings_target_step:text:tonumber * north:forevector.
        set target_geo to body:geopositionof(new_pos).
        gui_update_target_settings_display().
    }.
    declare global gui_settings_target_south to gui_settings_target_button_box2:addbutton("S").
    set gui_settings_target_south:onclick to {
        local new_pos to target_geo:position - gui_settings_target_step:text:tonumber * north:forevector.
        set target_geo to body:geopositionof(new_pos).
        gui_update_target_settings_display().
    }.
    declare global gui_settings_target_button_box3 to gui_settings_target_box:addhlayout().
    declare global gui_settings_target_forward to gui_settings_target_button_box3:addbutton("↑").
    set gui_settings_target_forward:onclick to {
        local new_pos to target_geo:position + gui_settings_target_step:text:tonumber * unitTtgt.
        set target_geo to body:geopositionof(new_pos).
        gui_update_target_settings_display().
    }.
    declare global gui_settings_target_backward to gui_settings_target_button_box3:addbutton("↓").
    set gui_settings_target_backward:onclick to {
        local new_pos to target_geo:position - gui_settings_target_step:text:tonumber * unitTtgt.
        set target_geo to body:geopositionof(new_pos).
        gui_update_target_settings_display().
    }.
    declare global gui_settings_target_east to gui_settings_target_button_box3:addbutton("E").
    set gui_settings_target_east:onclick to {
        local new_pos to target_geo:position + gui_settings_target_step:text:tonumber * vCrs(unitRtgt, north:forevector):normalized.
        set target_geo to body:geopositionof(new_pos).
        gui_update_target_settings_display().
    }.
    declare global gui_settings_target_west to gui_settings_target_button_box3:addbutton("W").
    set gui_settings_target_west:onclick to {
        local new_pos to target_geo:position - gui_settings_target_step:text:tonumber * vCrs(unitRtgt, north:forevector):normalized.
        set target_geo to body:geopositionof(new_pos).
        gui_update_target_settings_display().
    }.
    declare global gui_settings_target_step_box to gui_settings_target_box:addhlayout().
    declare global gui_settings_target_step_label to gui_settings_target_step_box:addlabel(UI_LANG["peggui.lbl_moving_step"]).
    declare global gui_settings_target_step to gui_settings_target_step_box:addtextfield("50").
    declare global gui_settings_target_slope_box to gui_settings_target_box:addhlayout().
    declare global gui_settings_target_slope_label to gui_settings_target_slope_box:addlabel("").
    declare global gui_settings_target_slope_sample_button to gui_settings_target_slope_box:addbutton(UI_LANG["peggui.btn_find_flat"]).
    declare global gui_settings_target_slope_sample_dist to gui_settings_target_slope_box:addtextfield("500").
    declare global gui_settings_target_slope_sample_label1 to gui_settings_target_slope_box:addlabel(UI_LANG["peggui.lbl_within"]).
    declare global gui_settings_target_slope_sample_npoints to gui_settings_target_slope_box:addtextfield("10").
    declare global gui_settings_target_slope_sample_label2 to gui_settings_target_slope_box:addlabel(UI_LANG["peggui.lbl_points"]).
    set gui_settings_target_slope_sample_button:onclick to {
        // Ramdom search for flattest spot near target
        local search_dist to gui_settings_target_slope_sample_dist:text:tonumber.
        local npoints to gui_settings_target_slope_sample_npoints:text:tonumber.
        local min_slope to get_geo_slope(target_geo).
        local best_geo to target_geo.
        from {local i to 0.} until i >= npoints step {set i to i+1.} do {
            local newgeo to get_geo_sample(target_geo, search_dist).
            local slope to get_geo_slope(newgeo).
            if slope < min_slope {
                set min_slope to slope.
                set best_geo to newgeo.
            }
        }
        set target_geo to best_geo.
        gui_update_target_settings_display().
    }.

    declare global gui_settings_target_lat_box to gui_settings_target_box:addhlayout().
    declare global gui_settings_target_lat_label to gui_settings_target_lat_box:addlabel(UI_LANG["peggui.lbl_lat"]).
    declare global gui_settings_target_lat to gui_settings_target_lat_box:addtextfield("0").
    declare global gui_settings_target_lat_set to gui_settings_target_lat_box:addbutton(UI_LANG["peggui.btn_set"]).
    set gui_settings_target_lat_set:onclick to {set target_geo to latlng(gui_settings_target_lat:text:tonumber, target_geo:lng).}.
    declare global gui_settings_target_lng_box to gui_settings_target_box:addhlayout().
    declare global gui_settings_target_lng_label to gui_settings_target_lng_box:addlabel(UI_LANG["peggui.lbl_lng"]).
    declare global gui_settings_target_lng to gui_settings_target_lng_box:addtextfield("0").
    declare global gui_settings_target_lng_set to gui_settings_target_lng_box:addbutton(UI_LANG["peggui.btn_set"]).
    set gui_settings_target_lng_set:onclick to {set target_geo to latlng(target_geo:lat, gui_settings_target_lng:text:tonumber).}.
    declare global gui_settings_target_height_box to gui_settings_target_box:addhlayout().
    declare global gui_settings_target_height_label to gui_settings_target_height_box:addlabel(UI_LANG["peggui.lbl_target_h"]).
    declare global gui_settings_target_height to gui_settings_target_height_box:addtextfield("0").
    declare global gui_settings_target_height_set to gui_settings_target_height_box:addbutton(UI_LANG["peggui.btn_set"]).
    set gui_settings_target_height_set:onclick to {set target_height to gui_settings_target_height:text:tonumber.}.

    declare global gui_settings_descent_box to gui_settings_box:addvlayout().
    declare global gui_settings_descent_title to gui_settings_descent_box:addlabel("<b>" + UI_LANG["peggui.lbl_desc_tgt"] + "</b>").
    declare global gui_settings_descent_update_button to gui_settings_descent_box:addbutton(UI_LANG["peggui.btn_upd_desc"]).
    set gui_settings_descent_update_button:onclick to {
        set desRT to gui_settings_descent_RT:text:tonumber.
        set desLT to gui_settings_descent_LT:text:tonumber.
        set desVRT to gui_settings_descent_VRT:text:tonumber.
        set desVLT to gui_settings_descent_VLT:text:tonumber.
    }.
    declare global gui_settings_descent_R_box to gui_settings_descent_box:addhlayout().
    declare global gui_settings_descent_RT_label to gui_settings_descent_R_box:addlabel(UI_LANG["peggui.lbl_rt"]).
    declare global gui_settings_descent_RT to gui_settings_descent_R_box:addtextfield("0").
    declare global gui_settings_descent_LT_label to gui_settings_descent_R_box:addlabel(UI_LANG["peggui.lbl_lt"]).
    declare global gui_settings_descent_LT to gui_settings_descent_R_box:addtextfield("0").
    declare global gui_settings_descent_V_box to gui_settings_descent_box:addhlayout().
    declare global gui_settings_descent_VRT_label to gui_settings_descent_V_box:addlabel(UI_LANG["peggui.lbl_vrt"]).
    declare global gui_settings_descent_VRT to gui_settings_descent_V_box:addtextfield("0").
    declare global gui_settings_descent_VLT_label to gui_settings_descent_V_box:addlabel(UI_LANG["peggui.lbl_vlt"]).
    declare global gui_settings_descent_VLT to gui_settings_descent_V_box:addtextfield("0").

    declare global gui_settings_engine_box to gui_settings_box:addvlayout().
    declare global gui_settings_engine_title to gui_settings_engine_box:addlabel("<b>" + UI_LANG["peggui.lbl_engine_settings"] + "</b>").
    declare global gui_settings_engine_button_box1 to gui_settings_engine_box:addhlayout().
    declare global gui_settings_engine_current_button to gui_settings_engine_button_box1:addbutton(UI_LANG["peggui.btn_current_eng"]).
    set gui_settings_engine_current_button:onclick to {
        local elist to get_active_engines().
        local enginfo to get_engines_info(elist).
        gui_set_engine_info(enginfo).
        set_engine_parameters(elist).
    }.
    declare global gui_settings_engine_search_engine to gui_settings_engine_button_box1:addbutton(UI_LANG["peggui.btn_search_eng"]).
    declare global gui_settings_engine_search_engine_text to gui_settings_engine_button_box1:addtextfield("descent").
    set gui_settings_engine_search_engine:onclick to {
        local elist to search_engine(gui_settings_engine_search_engine_text:text).
        local enginfo to get_engines_info(elist).
        gui_set_engine_info(enginfo).
        set_engine_parameters(elist).
    }.
    declare global gui_settings_engine_thrust_box to gui_settings_engine_box:addhlayout().
    declare global gui_settings_engine_thrust_label to gui_settings_engine_thrust_box:addlabel(UI_LANG["peggui.lbl_thrust_kn"]).
    declare global gui_settings_engine_thrust to gui_settings_engine_thrust_box:addtextfield("1").
    declare global gui_settings_engine_thrust_set to gui_settings_engine_thrust_box:addbutton(UI_LANG["peggui.btn_set"]).
    set gui_settings_engine_thrust_set:onclick to {
        local newvalue to gui_settings_engine_thrust:text:tonumber.
        if newvalue <= 1e-7 {
            hudtext(UI_LANG["peggui.err_thrust_zero"], 4, 2, 12, hudtextcolor, false).
            return.
        }
        set f0 to newvalue.
    }.
    declare global gui_settings_engine_isp_box to gui_settings_engine_box:addhlayout().
    declare global gui_settings_engine_isp_label to gui_settings_engine_isp_box:addlabel(UI_LANG["peggui.lbl_isp_s"]).
    declare global gui_settings_engine_isp to gui_settings_engine_isp_box:addtextfield("100").
    declare global gui_settings_engine_isp_set to gui_settings_engine_isp_box:addbutton(UI_LANG["peggui.btn_set"]).
    set gui_settings_engine_isp_set:onclick to {
        local newvalue to gui_settings_engine_isp:text:tonumber.
        if newvalue <= 0 {
            hudtext(UI_LANG["peggui.err_isp_zero"], 4, 2, 12, hudtextcolor, false).
            return.
        }
        set ve to newvalue * 9.81.
    }.
    declare global gui_settings_engine_minthrottle_box to gui_settings_engine_box:addhlayout().
    declare global gui_settings_engine_minthrottle_label to gui_settings_engine_minthrottle_box:addlabel(UI_LANG["peggui.lbl_min_throttle"]).
    declare global gui_settings_engine_minthrottle to gui_settings_engine_minthrottle_box:addtextfield("0").
    declare global gui_settings_engine_minthrottle_set to gui_settings_engine_minthrottle_box:addbutton(UI_LANG["peggui.btn_set"]).
    set gui_settings_engine_minthrottle_set:onclick to {
        local newvalue to gui_settings_engine_minthrottle:text:tonumber.
        if newvalue < 0 or newvalue > 1 {
            hudtext(UI_LANG["peggui.err_thro_range"], 4, 2, 12, hudtextcolor, false).
            return.
        }
        set thro_min to newvalue.
    }.
    declare global gui_settings_engine_spoolup_box to gui_settings_engine_box:addhlayout().
    declare global gui_settings_engine_spoolup_label to gui_settings_engine_spoolup_box:addlabel(UI_LANG["peggui.lbl_spool_up"]).
    declare global gui_settings_engine_spoolup to gui_settings_engine_spoolup_box:addtextfield("0").
    declare global gui_settings_engine_spoolup_set to gui_settings_engine_spoolup_box:addbutton(UI_LANG["peggui.btn_set"]).
    set gui_settings_engine_spoolup_set:onclick to {
        local newvalue to gui_settings_engine_spoolup:text:tonumber.
        if newvalue < 0 {
            hudtext(UI_LANG["peggui.err_spool_neg"], 4, 2, 12, hudtextcolor, false).
            return.
        }
        set spooluptime to newvalue.
    }.
    declare global gui_settings_engine_ullage_box to gui_settings_engine_box:addhlayout().
    declare global gui_settings_engine_ullage_label to gui_settings_engine_ullage_box:addlabel(UI_LANG["peggui.lbl_ullage_time"]).
    declare global gui_settings_engine_ullage to gui_settings_engine_ullage_box:addtextfield("0").
    declare global gui_settings_engine_ullage_set to gui_settings_engine_ullage_box:addbutton(UI_LANG["peggui.btn_set"]).
    set gui_settings_engine_ullage_set:onclick to {
        local newvalue to gui_settings_engine_ullage:text:tonumber.
        if newvalue < 0 {
            hudtext(UI_LANG["peggui.err_ullage_neg"], 4, 2, 12, hudtextcolor, false).
            return.
        }
        set ullage_time to newvalue.
    }.

    gui_maingui:show().
}

function gui_update_status_display {
    parameter display_status_dict.
    set gui_display_gstatus:text to UI_LANG["peggui.lbl_status"] + display_status_dict["status"].
    set gui_display_numiters:text to UI_LANG["peggui.lbl_peg_iter"] + display_status_dict["numiter"].
    set gui_display_height:text to UI_LANG["peggui.lbl_height"] + round(display_status_dict["height"], 2) + " m".
    set gui_display_distance:text to UI_LANG["peggui.lbl_dist"] + round(display_status_dict["distance"], 2) + " m".
    set gui_display_err:text to UI_LANG["peggui.lbl_error"] + round(display_status_dict["error"], 2) + " m".
    set gui_display_vspeed:text to UI_LANG["peggui.lbl_v_spd"] + round(display_status_dict["vspeed"], 2) + " m/s".
    set gui_display_hspeed:text to UI_LANG["peggui.lbl_h_spd"] + round(display_status_dict["hspeed"], 2) + " m/s".
    set gui_display_T:text to UI_LANG["peggui.lbl_time_t"] + round(display_status_dict["T"], 1) + " s".
    set gui_display_dv:text to UI_LANG["peggui.lbl_peg_dv"] + round(display_status_dict["dv"], 1) + " m/s".
    set gui_display_throttle:text to UI_LANG["peggui.lbl_thro"] + round(display_status_dict["throttle"], 3).
}

function gui_update_msg_display {
    parameter msg.
    set gui_display_msg:text to msg.
}

function gui_update_config_settings_display {
    set gui_settings_active_button:pressed to guidance_active.
    set gui_settings_nowait_button:pressed to ignite_now.
    set gui_settings_add_approach_button:pressed to add_approach_phase.
    set gui_settings_desphase_button:pressed to (start_phase = "descent").
    set gui_settings_appphase_button:pressed to (start_phase = "approach").
    set gui_settings_finphase_button:pressed to (start_phase = "final").
    set gui_settings_rotation:text to target_rotation:tostring.
}

function gui_update_target_settings_display {
    set gui_settings_target_lat:text to target_geo:lat:tostring.
    set gui_settings_target_lng:text to target_geo:lng:tostring.
    set gui_settings_target_height:text to target_height:tostring.
    set gui_settings_target_slope_label:text to UI_LANG["peggui.lbl_slope"] + round(get_geo_slope(target_geo), 2) + "°".
}

function gui_update_descent_settings_display {
    set gui_settings_descent_RT:text to desRT:tostring.
    set gui_settings_descent_LT:text to desLT:tostring.
    set gui_settings_descent_VRT:text to desVRT:tostring.
    set gui_settings_descent_VLT:text to desVLT:tostring.
}

function gui_update_engine_settings_display {
    set gui_settings_engine_thrust:text to f0:tostring.
    set gui_settings_engine_isp:text to (ve / 9.81):tostring.
    set gui_settings_engine_minthrottle:text to thro_min:tostring.
    set gui_settings_engine_spoolup:text to spooluptime:tostring.
    set gui_settings_engine_ullage:text to ullage_time:tostring.
}

on guidance_status {
    set gui_display_gstatus:text to UI_LANG["peggui.lbl_status"] + guidance_status.
    if done return false.
    return true.
}

function analyze_initial_orbit {
    if (abs(ve) < 1e-5 or abs(f0) < 1e-5) {
        return lexicon(
            "ok", false,
            "msg", "No enough thrust for landing!"
        ).
    }
    local vecRL to target_geo:position-ship:body:position.
    set vecRL to vecRL:normalized * (vecRL:mag + desRT).
    local distH to abs(vDot(vecRL, unitUy)).
    local etaL to etaref + __peg_get_angle(unitRref, vecRL, unitUy).
    local vr_etaL to get_orbit_vr_at_theta(sma, ecc, etaL, mu).
    local vt_etaL to get_orbit_vt_at_theta(sma, ecc, etaL, mu).
    local lock v_etaL to sqrt(vr_etaL^2 + vt_etaL^2).
    local r_etaL to get_orbit_r_at_theta(sma, ecc, etaL).
    local distR to r_etaL - vecRL:mag.

    local burntime to ship:mass * ve / f0 * (1 - exp(-v_etaL/ve)).
    // 1 round iteration to calibrate gravity loss
    set vr_etaL to vr_etaL + g0 * burntime.
    set burntime to ship:mass * ve / f0 * (1 - exp(-v_etaL/ve)).
    // TWR diagnosis
    local massf to ship:mass - burntime * f0 / ve.
    local TWRf to f0 / massf / g0.
    local msg to "".
    if (TWRf < 1) {
        set msg to msg + "Final TWR = " + round(TWRf, 2) + ", unable to land".
    }
    else if (TWRf < 1.4) {
        set msg to msg + "Final TWR = " + round(TWRf, 2) + ", hard to converge".
    }

    local distR_rmd to 0.125 * g0 * burntime^2.
    local distH_rmd to 0.06 * vt_etaL * burntime.

    return lexicon(
        "ok", true,
        "msg", msg,
        "burntime", burntime,
        "distR", distR,
        "distH", distH,
        "distR_rmd", distR_rmd,
        "distH_rmd", distH_rmd
    ).
}

function gui_set_engine_info {
    parameter enginfo.

    set gui_settings_engine_thrust:text to enginfo["thrust"]:tostring.
    set gui_settings_engine_isp:text to enginfo["ISP"]:tostring.
    set gui_settings_engine_minthrottle:text to enginfo["minthrottle"]:tostring.
    set gui_settings_engine_spoolup:text to enginfo["spooluptime"]:tostring.
    if enginfo["ullage"] {
        set gui_settings_engine_ullage:text to "2".
    }
    else {
        set gui_settings_engine_ullage:text to "0".
    }
}
