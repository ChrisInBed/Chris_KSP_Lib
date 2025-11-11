runOncePath("0:/lib/orbit.ks").
runOncePath("0:/lib/engine_utility.ks").

function gui_make_peglandgui {
    declare global gui_maingui is GUI(500, 500).
    set gui_maingui:style:hstretch to true.

    // title: PEG Landing Guidance
    declare global gui_title_box to gui_maingui:addhbox().
    set gui_title_box:style:height to 40.
    set gui_title_box:style:margin:top to 0.
    declare global gui_title_label to gui_title_box:addlabel("<b><size=20>PEG Landing Guidance v0.8</size></b>").
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
    declare global gui_display_gstatus to gui_display_box1:addlabel("Status: inactive").
    declare global gui_display_numiters to gui_display_box1:addlabel("Iteration: 0").
    declare global gui_display_height to gui_display_box1:addlabel("Height = 0 m").
    declare global gui_display_distance to gui_display_box1:addlabel("Distance = 0 m").
    declare global gui_display_err to gui_display_box1:addlabel("Error = 0 m").
    declare global gui_display_vspeed to gui_display_box2:addlabel("Vertical speed = 0 m/s").
    declare global gui_display_hspeed to gui_display_box2:addlabel("Horizontal speed = 0 m/s").
    declare global gui_display_T to gui_display_box2:addlabel("T = 0 s").
    declare global gui_display_dv to gui_display_box2:addlabel("Δv = 0 m/s").
    declare global gui_display_throttle to gui_display_box2:addlabel("throttle = 0").
    declare global gui_display_msg to gui_mainbox:addlabel("").

    // Orbit analysis region
    gui_mainbox:addspacing(2).
    declare global gui_orbitanalysis_box to gui_mainbox:addvlayout().
    declare global gui_orbitanalysis_button to gui_orbitanalysis_box:addbutton("Analyze Orbit").
    set gui_orbitanalysis_button:style:width to 100.
    declare global gui_orbitanalysis_result1 to gui_orbitanalysis_box:addlabel("").
    declare global gui_orbitanalysis_result2 to gui_orbitanalysis_box:addlabel("").
    declare global gui_orbitanalysis_result3 to gui_orbitanalysis_box:addlabel("").
    set gui_orbitanalysis_button:onclick to {
        local result to analyze_initial_orbit().
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
        set gui_orbitanalysis_result1:text to "Estimated burn time ≈ " + round(result["burntime"]) + " s".
        set gui_orbitanalysis_result2:text to "Estimated descent distance = " + distR_text + " km".
        set gui_orbitanalysis_result3:text to "Estimated lateral distance = " + distH_text + " km".
    }.

    // emergency suppress
    gui_mainbox:addspacing(2).
    declare global gui_emergency_button to gui_mainbox:addcheckbox("<b><size=16>EMERGENCY SUPPRESS</size></b>").
    set gui_emergency_button:ontoggle to {
        parameter newstate.
        set config:suppressautopilot to newstate.
    }.

    // Settings region
    declare global gui_settings_box to gui_mainbox:addvlayout().
    declare global gui_settings_gbox1 to gui_settings_box:addhlayout().
    declare global gui_settings_gbox11 to gui_settings_gbox1:addvlayout().
    declare global gui_settings_active_button to gui_settings_gbox11:addcheckbox("Active", false).
    set gui_settings_active_button:ontoggle to {
        parameter newstate.
        set guidance_active to newstate.
    }.
    declare global gui_settings_nowait_button to gui_settings_gbox11:addcheckbox("Ignite Now", false).
    set gui_settings_nowait_button:ontoggle to {parameter newstate. set ignite_now to newstate.}.
    declare global gui_settings_add_approach_button to gui_settings_gbox11:addcheckbox("Add Approach Phase", false).
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
    declare global gui_settings_desphase_button to gui_settings_phase_box:addradiobutton("descent phase", true).
    set gui_settings_desphase_button:ontoggle to {parameter newstate. if newstate {set start_phase to "descent".}.}.
    declare global gui_settings_appphase_button to gui_settings_phase_box:addradiobutton("approach phase", false).
    set gui_settings_appphase_button:ontoggle to {
        parameter newstate.
        if newstate {
            set start_phase to "approach".
            set gui_settings_add_approach_button:pressed to true.
        }.
    }.
    declare global gui_settings_finphase_button to gui_settings_phase_box:addradiobutton("final phase", false).
    set gui_settings_finphase_button:ontoggle to {parameter newstate. if newstate {set start_phase to "final".}.}.
    declare global gui_settings_rotation_box to gui_settings_box:addhlayout().
    declare global gui_settings_rotation_label to gui_settings_rotation_box:addlabel("Roll").
    declare global gui_settings_rotation to gui_settings_rotation_box:addtextfield("0").
    set gui_settings_rotation:onconfirm to {parameter newvalue. set target_rotation to newvalue:tonumber.}.

    declare global gui_settings_target_box to gui_settings_box:addvlayout().
    declare global gui_settings_target_title to gui_settings_target_box:addlabel("<b>Target settings</b>").
    declare global gui_settings_target_button_box1 to gui_settings_target_box:addhlayout().
    declare global gui_settings_target_waypoint_button to gui_settings_target_button_box1:addbutton("current waypoint").
    set gui_settings_target_waypoint_button:onclick to {
        local target_geo to get_target_geo().
        if (target_geo = 0) {
            hudtext("No active waypoint found!", 4, 2, 12, hudtextcolor, false).
            return.
        }
        set gui_settings_target_lat:text to target_geo:lat:tostring.
        set gui_settings_target_lng:text to target_geo:lng:tostring.
    }.
    declare global gui_settings_target_show_button to gui_settings_target_button_box1:addcheckbox("show target", false).
    set gui_settings_target_show_button:ontoggle to {
        parameter newstate.
        if newstate {
            // draw target
            declare global gui_target_draw to vecDraw({return target_geo:position.}, {return up:forevector*3000.}, RGB(255, 0, 0), "Target", 1, true).
        }
        else {
            // remove target draw
            if defined gui_target_draw {
                unset gui_target_draw.
            }
        }
    }.
    declare global gui_settings_target_update_button to gui_settings_target_button_box1:addbutton("update target").
    set gui_settings_target_update_button:onclick to {
        set target_geo to latlng(gui_settings_target_lat:text:tonumber, gui_settings_target_lng:text:tonumber).
        set target_height to gui_settings_target_height:text:tonumber.
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
    declare global gui_settings_target_step_label to gui_settings_target_step_box:addlabel("Moving step (m) ").
    declare global gui_settings_target_step to gui_settings_target_step_box:addtextfield("50").
    declare global gui_settings_target_lat_box to gui_settings_target_box:addhlayout().
    declare global gui_settings_target_lat_label to gui_settings_target_lat_box:addlabel("Latitude ").
    declare global gui_settings_target_lat to gui_settings_target_lat_box:addtextfield("0").
    declare global gui_settings_target_lng_box to gui_settings_target_box:addhlayout().
    declare global gui_settings_target_lng_label to gui_settings_target_lng_box:addlabel("Longitude ").
    declare global gui_settings_target_lng to gui_settings_target_lng_box:addtextfield("0").
    declare global gui_settings_target_height_box to gui_settings_target_box:addhlayout().
    declare global gui_settings_target_height_label to gui_settings_target_height_box:addlabel("Height (m) ").
    declare global gui_settings_target_height to gui_settings_target_height_box:addtextfield("0").

    declare global gui_settings_descent_box to gui_settings_box:addvlayout().
    declare global gui_settings_descent_title to gui_settings_descent_box:addlabel("<b>Descent target</b>").
    declare global gui_settings_descent_update_button to gui_settings_descent_box:addbutton("update descent").
    set gui_settings_descent_update_button:onclick to {
        set desRT to gui_settings_descent_RT:text:tonumber.
        set desLT to gui_settings_descent_LT:text:tonumber.
        set desVRT to gui_settings_descent_VRT:text:tonumber.
        set desVLT to gui_settings_descent_VLT:text:tonumber.
    }.
    declare global gui_settings_descent_R_box to gui_settings_descent_box:addhlayout().
    declare global gui_settings_descent_RT_label to gui_settings_descent_R_box:addlabel("RT (m) ").
    declare global gui_settings_descent_RT to gui_settings_descent_R_box:addtextfield("0").
    declare global gui_settings_descent_LT_label to gui_settings_descent_R_box:addlabel("LT (m) ").
    declare global gui_settings_descent_LT to gui_settings_descent_R_box:addtextfield("0").
    declare global gui_settings_descent_V_box to gui_settings_descent_box:addhlayout().
    declare global gui_settings_descent_VRT_label to gui_settings_descent_V_box:addlabel("VRT (m/s) ").
    declare global gui_settings_descent_VRT to gui_settings_descent_V_box:addtextfield("0").
    declare global gui_settings_descent_VLT_label to gui_settings_descent_V_box:addlabel("VLT (m/s) ").
    declare global gui_settings_descent_VLT to gui_settings_descent_V_box:addtextfield("0").

    declare global gui_settings_engine_box to gui_settings_box:addvlayout().
    declare global gui_settings_engine_title to gui_settings_engine_box:addlabel("<b>Engine settings</b>").
    declare global gui_settings_engine_button_box1 to gui_settings_engine_box:addhlayout().
    declare global gui_settings_engine_current_button to gui_settings_engine_button_box1:addbutton("current engine").
    set gui_settings_engine_current_button:onclick to {
        local elist to get_active_engines().
        local enginfo to get_engines_info(elist).
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
    }.
    declare global gui_settings_engine_update_button to gui_settings_engine_button_box1:addbutton("update engine").
    set gui_settings_engine_update_button:onclick to {
        set f0 to gui_settings_engine_thrust:text:tonumber.
        set ve to gui_settings_engine_isp:text:tonumber * 9.81.
        set thro_min to gui_settings_engine_minthrottle:text:tonumber.
        set spooluptime to gui_settings_engine_spoolup:text:tonumber.
        set ullage_time to gui_settings_engine_ullage:text:tonumber.
    }.
    declare global gui_settings_engine_thrust_box to gui_settings_engine_box:addhlayout().
    declare global gui_settings_engine_thrust_label to gui_settings_engine_thrust_box:addlabel("Thrust (kN) ").
    declare global gui_settings_engine_thrust to gui_settings_engine_thrust_box:addtextfield("1").
    set gui_settings_engine_thrust:onconfirm to {
        parameter newvalue.
        if newvalue:tonumber <= 1e-7 {
            hudtext("Thrust must be larger than 0", 4, 2, 12, hudtextcolor, false).
        }
        set gui_settings_engine_thrust:text to "1".
    }.
    declare global gui_settings_engine_isp_box to gui_settings_engine_box:addhlayout().
    declare global gui_settings_engine_isp_label to gui_settings_engine_isp_box:addlabel("ISP (s) ").
    declare global gui_settings_engine_isp to gui_settings_engine_isp_box:addtextfield("100").
    set gui_settings_engine_isp:onconfirm to {
        parameter newvalue.
        if newvalue:tonumber <= 0 {
            hudtext("ISP must be larger than 0", 4, 2, 12, hudtextcolor, false).
            set gui_settings_engine_isp:text to "100".
        }
    }.
    declare global gui_settings_engine_minthrottle_box to gui_settings_engine_box:addhlayout().
    declare global gui_settings_engine_minthrottle_label to gui_settings_engine_minthrottle_box:addlabel("Min throttle ").
    declare global gui_settings_engine_minthrottle to gui_settings_engine_minthrottle_box:addtextfield("0").
    declare global gui_settings_engine_spoolup_box to gui_settings_engine_box:addhlayout().
    declare global gui_settings_engine_spoolup_label to gui_settings_engine_spoolup_box:addlabel("Spool-up time (s) ").
    declare global gui_settings_engine_spoolup to gui_settings_engine_spoolup_box:addtextfield("0").
    declare global gui_settings_engine_ullage_box to gui_settings_engine_box:addhlayout().
    declare global gui_settings_engine_ullage_label to gui_settings_engine_ullage_box:addlabel("Ullage time (s) ").
    declare global gui_settings_engine_ullage to gui_settings_engine_ullage_box:addtextfield("0").

    gui_maingui:show().
}

function gui_update_status_display {
    parameter display_status_dict.
    set gui_display_gstatus:text to "Status: " + display_status_dict["status"].
    set gui_display_numiters:text to "Iteration: " + display_status_dict["numiter"].
    set gui_display_height:text to "Height = " + round(display_status_dict["height"], 2) + " m".
    set gui_display_distance:text to "Distance = " + round(display_status_dict["distance"], 2) + " m".
    set gui_display_err:text to "Error = " + round(display_status_dict["error"], 2) + " m".
    set gui_display_vspeed:text to "Vertical speed = " + round(display_status_dict["vspeed"], 2) + " m/s".
    set gui_display_hspeed:text to "Horizontal speed = " + round(display_status_dict["hspeed"], 2) + " m/s".
    set gui_display_T:text to "T = " + round(display_status_dict["T"], 1) + " s".
    set gui_display_dv:text to "Δv = " + round(display_status_dict["dv"], 1) + " m/s".
    set gui_display_throttle:text to "throttle = " + round(display_status_dict["throttle"], 3).
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
    set gui_display_gstatus:text to "Status: " + guidance_status.
    if done return false.
    return true.
}

function analyze_initial_orbit {
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

    local distR_rmd to 0.125 * g0 * burntime^2.
    local distH_rmd to 0.06 * vt_etaL * burntime.

    return lexicon(
        "burntime", burntime,
        "distR", distR,
        "distH", distH,
        "distR_rmd", distR_rmd,
        "distH_rmd", distH_rmd
    ).
}