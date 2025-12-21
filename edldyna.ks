parameter P_VF to 650.
parameter P_HF to 25000.
parameter P_DIST to 20000.
parameter P_BANKF to 0.

runOncePath("0:/lib/atm_utils.ks").
runOncePath("0:/lib/edllib/pc_entry.ks").
runOncePath("0:/lib/edllib/flightcontrol.ks").
runOncePath("0:/lib/orbit.ks").
set config:IPU to 1000.
// global varibables
declare global guidance_stage to "inactive".
// declare global g0 to body:mu / body:radius^2.
declare global target_geo to get_target_geo().
declare global entry_vf to P_VF.
declare global entry_hf to P_HF.
declare global entry_dist to P_DIST.
declare global entry_bank_f to P_BANKF.

// Flight controller
declare global kclcontroller to KCLController_Init().
declare global enable_pitch_torque to true.
declare global enable_yaw_torque to true.
declare global enable_roll_torque to true.

function init_print {
    // line 1~10: target position
    // line 11~20: guidance state
    clearScreen.
    print "Entry guidance" AT(0,0).
    print "============= Configuration ============" AT(0,1).
    print "================ State =================" AT(0,11).
    print "================ Result ================" AT(0,21).
}

function initialize_guidance {
    // set all state variables to initial values
    entry_initialize().
    entry_set_target(entry_hf, entry_vf, entry_dist, target_geo).
    entry_set_profile(
        list(15e3, 40e3, 70e3, 90e3), // altitude profile in meters
        list(400, 2000, 6000, 8000), // speed profile in m/s
        list(10, 25, 28, 28) // AOA profile in degrees
    ).
    print "CL profile: " + arr2str(AFS:Clsamples) AT(0,3).
    print "CD profile: " +  arr2str(AFS:Cdsamples) AT(0,4).
    set AFS:mu to body:mu.
    set AFS:R to body:radius.
    set AFS:rho0 to atm_get_sealevel_density().
    set AFS:hs to atm_get_scale_height().
    set AFS:mass to ship:mass.
    set AFS:area to FAR:REFAREA.
    set AFS:bank_max to 90.  // Maximum stable bank angle

    set AFS:Qdot_max to 6e5.
    set AFS:acc_max to 25.
    set AFS:dynp_max to 10e3.
    set entry_heading_tol to 10.

    set AFS:L_min to 0.5.
    set AFS:k_QEGC to 1.
    set AFS:k_C to 5.
    set AFS:t_reg to 90.
}

function arr2str {
    parameter arr.
    parameter rounding to 1.
    local str to "".
    from {local i to 0.} until i = arr:length() step {set i to i+1.} do {
        set str to str + round(arr[i], rounding).
        if (i < arr:length() - 1) {
            set str to str + ", ".
        }
    }
    return str.
}

function entry_phase {
    set guidance_stage to "preparation".
    // initialize guidance
    print "Preparing entry guidance.         " AT(0, 12).
    local startTime to time:seconds.
    local initInfo to entry_initialize_guidance(0, -body:position, ship:velocity:orbit, 20, entry_bank_f).
    if (not initInfo["ok"]) {
        print "Error: (" + initInfo["status"] + ")" + initInfo["msg"] AT(0, 30).
        return.
    }
    local gst to initInfo["gst"].
    // glide to entry interface
    set guidance_stage to "gliding".
    when (true) then {
        local _cd to startTime+initInfo["time_entry"]-time:seconds.
        local msg to "Time to entry = " + round(_cd) + " s.      ".
        print msg AT(0, 13).
        return _cd >= 0.
    } 
    wait until time:seconds - startTime > initInfo["time_entry"] - 60 or ship:altitude < body:atm:height.
    // wait until ship:altitude < body:atm:height.
    set guidance_stage to "entry".
    RCS ON.
    local _control to entry_get_control(-body:position, ship:velocity:surface, gst).
    // Inner loop
    when (guidance_stage = "entry") then {
        set _control to entry_get_control(-body:position, ship:velocity:surface, gst).
        local _torqueCmd to KCLController_GetControl(kclcontroller, V(_control["bank"], _control["AOA"], 0)).
        if (enable_roll_torque) set ship:control:pilotrolltrim to _torqueCmd:x.
        if (enable_pitch_torque) set ship:control:pilotpitchtrim to _torqueCmd:y.
        if (enable_yaw_torque) set ship:control:pilotyawtrim to _torqueCmd:z.
        print "Bank = " + round(_control["bank"]) + " deg; " +
                "AOA = " + round(_control["AOA"]) + " deg; " AT(0, 16).
        return true.
    }

    // Outer loop: update guidance state
    local lock ee to entry_get_spercific_energy(body:position:mag, ship:velocity:surface:mag).
    local lock ef to entry_get_spercific_energy(body:radius+entry_hf, entry_vf).
    // step once before entering the loop
    until (ee < ef) {
        local stepInfo to entry_step_guidance(0, -body:position, ship:velocity:surface, gst).
        if (not stepInfo["ok"]) {
            print "Error: (" + stepInfo["status"] + ")" + stepInfo["msg"] AT(0, 30).
        }
        else {
            print "bank_i = " + round(gst["bank_i"]) + " deg; " + "T = " + round(stepInfo["time_final"]) + " s    " AT(0, 13).
            print "range error = " + round(body:radius*stepInfo["error"]/180*constant:pi) + " m    " AT(0, 14).
            print "vf = " + round(stepInfo["vf"]) + " m/s; " + "hf = " + round(stepInfo["rf"] - body:radius) + " m    " AT(0, 15).
            print "Max Qdot = " + round(stepInfo["maxQdot"]/1e3, 1) + " kW/m^2 @" + round(stepInfo["maxQdotTime"]) + " s    " AT(0, 17).
            print "Max acc = " + round(stepInfo["maxAcc"]/9.81, 2) + " g @" + round(stepInfo["maxAccTime"]) + " s    " AT(0, 18).
            print "Max dynp = " + round(stepInfo["maxDynP"]/1e3, 1) + " kPa @" + round(stepInfo["maxDynPTime"]) + " s    " AT(0, 19).
            draw_vecR_final(stepInfo["vecR_final"], vecRtgt).
            if (stepInfo["time_final"] < 20) break.  // Stop updating guidance parameters
        }
        wait 0.2.
    }
    until ee < ef {
        print "Left Energy = " + round((ee - ef)*1e-3) + " kJ         " AT(0, 13).
        wait 0.2.
    }
    fc_deactivate().
}

function main {
    // initialize the guidance system
    init_print().
    initialize_guidance().
    gui_make_entrylandgui().
    // start entry phase
    entry_phase().
    // print result
    print "Entry guidance completed." AT(0, 21).
    print "Final position: " + ship:position AT(0, 22).
    print "Final velocity: " + ship:velocity AT(0, 23).
}

main().

function __attitude_from_AOA_Bank {
    parameter _AOA.
    parameter _Bank.
    // AOS = 0
    local target_attitude to angleAxis(-_Bank, srfprograde:forevector) * srfPrograde.
    set target_attitude to angleAxis(-_AOA, target_attitude:starvector) * target_attitude.
    return target_attitude.
}

function draw_vecR_final {
    parameter vecRf.
    parameter vecRtgt.

    set _vecRfDraw to vecDraw(
        {return body:position+vecRf:normalized*body:radius.},
        {return body:position + vecRf.},
        RGB(0, 255, 0), "Final", 1.0, true
    ).
    set _vecRtgtDraw to vecDraw(
        {return body:position + vecRtgt:normalized * body:radius.},
        {return body:position + vecRtgt.},
        RGB(255, 0, 0), "Target", 1.0, true
    ).
    // set _vecRfDraw to vecDraw(
    //     {return body:position.},
    //     {return body:position + vecRf.},
    //     RGB(0, 255, 0), "Final", 1.0, true
    // ).
    // set _vecRtgtDraw to vecDraw(
    //     {return body:position + vecRtgt:normalized * body:radius.},
    //     {return body:position + vecRtgt.},
    //     RGB(255, 0, 0), "Target", 1.0, true
    // ).
}

function get_bank {
    // calculate current bank angle
    return arcTan2(
        -vDot(ship:facing:starvector, up:forevector),
        vDot(ship:facing:upvector, up:forevector)
    ).
}

function gui_make_entrylandgui {
    declare global gui_maingui is GUI(600, 800).
    set gui_maingui:style:hstretch to true.

    // Title
    declare global gui_title_box to gui_maingui:addhbox().
    set gui_title_box:style:height to 40.
    set gui_title_box:style:margin:top to 0.
    declare global gui_title_label to gui_title_box:addlabel("<b><size=20>KCL Flight Controller</size></b>").
    set gui_title_label:style:align TO "center".
    declare global gui_title_exit_button to gui_title_box:addbutton("X").
    set gui_title_exit_button:style:width to 20.
    set gui_title_exit_button:style:align to "right".
    set gui_title_exit_button:onclick to {
        gui_maingui:hide().
        set done to true.
    }.

    gui_maingui:addspacing(10).

    // Rotation Rate Controller Parameters
    gui_maingui:addlabel("<b>Rotation Rate Controller</b>").

    declare global gui_enable_box to gui_maingui:addvbox().
    declare global gui_enable_pitch_box to gui_enable_box:addhbox().
    declare global gui_enable_pitch_button to gui_enable_pitch_box:addcheckbox("Enable Pitch Control", true).
    set gui_enable_pitch_button:ontoggle to {
        parameter newval.
        set enable_pitch_torque to newval.
        if (not newval) {
            set ship:control:pilotpitchtrim to 0.
        }
    }.
    // declare global gui_enable_pitchRCS_button to gui_enable_pitch_box:addcheckbox("Use RCS", true).
    // set gui_enable_pitchRCS_button:ontoggle to {
    //     parameter newval.
    //     set RCS:pitchenabled to newval.
    // }.
    declare global gui_enable_roll_box to gui_enable_box:addhbox().
    declare global gui_enable_yaw_button to gui_enable_roll_box:addcheckbox("Enable Yaw Control", true).
    set gui_enable_yaw_button:ontoggle to {
        parameter newval.
        set enable_yaw_torque to newval.
        if (not newval) {
            set ship:control:pilotyawtrim to 0.
        }
    }.
    // declare global gui_enable_yawRCS_button to gui_enable_roll_box:addcheckbox("Use RCS", true).
    // set gui_enable_yawRCS_button:ontoggle to {
    //     parameter newval.
    //     set RCS:yawenabled to newval.
    // }.
    declare global gui_enable_roll_box to gui_enable_box:addhbox().
    declare global gui_enable_roll_button to gui_enable_roll_box:addcheckbox("Enable Roll Control", true).
    set gui_enable_roll_button:ontoggle to {
        parameter newval.
        set enable_roll_torque to newval.
        if (not newval) {
            set ship:control:pilotrolltrim to 0.
        }
    }.
    // declare global gui_enable_rollRCS_button to gui_enable_roll_box:addcheckbox("Use RCS", true).
    // set gui_enable_rollRCS_button:ontoggle to {
    //     parameter newval.
    //     set RCS:rollenabled to newval.
    // }.
    
    // AOA rate controller
    gui_maingui:addlabel("AOA Rate").
    declare global gui_aoa_rate_box to gui_maingui:addhbox().
    declare global gui_kaoa_label to gui_aoa_rate_box:addlabel("K:").
    declare global gui_kaoa_input to gui_aoa_rate_box:addtextfield(kclcontroller["RotationRateController"]["KAOA"]:tostring).
    set gui_kaoa_input:onconfirm to {
        parameter newval.
        set kclcontroller["RotationRateController"]["KAOA"] to newval:tonumber.
    }.
    declare global gui_upperaoa_label to gui_aoa_rate_box:addlabel("Upper:").
    declare global gui_upperaoa_input to gui_aoa_rate_box:addtextfield(kclcontroller["RotationRateController"]["UpperAOA"]:tostring).
    set gui_upperaoa_input:onconfirm to {
        parameter newval.
        set kclcontroller["RotationRateController"]["UpperAOA"] to newval:tonumber.
    }.
    declare global gui_epaoa_label to gui_aoa_rate_box:addlabel("Ep:").
    declare global gui_epaoa_input to gui_aoa_rate_box:addtextfield(kclcontroller["RotationRateController"]["EpAOA"]:tostring).
    set gui_epaoa_input:onconfirm to {
        parameter newval.
        set kclcontroller["RotationRateController"]["EpAOA"] to newval:tonumber.
    }.

    // Bank rate controller
    gui_maingui:addlabel("Bank Rate").
    declare global gui_bank_rate_box to gui_maingui:addhbox().
    declare global gui_kbank_label to gui_bank_rate_box:addlabel("K:").
    declare global gui_kbank_input to gui_bank_rate_box:addtextfield(kclcontroller["RotationRateController"]["KBank"]:tostring).
    set gui_kbank_input:onconfirm to {
        parameter newval.
        set kclcontroller["RotationRateController"]["KBank"] to newval:tonumber.
    }.
    declare global gui_upperbank_label to gui_bank_rate_box:addlabel("Upper:").
    declare global gui_upperbank_input to gui_bank_rate_box:addtextfield(kclcontroller["RotationRateController"]["UpperBank"]:tostring).
    set gui_upperbank_input:onconfirm to {
        parameter newval.
        set kclcontroller["RotationRateController"]["UpperBank"] to newval:tonumber.
    }.
    declare global gui_epbank_label to gui_bank_rate_box:addlabel("Ep:").
    declare global gui_epbank_input to gui_bank_rate_box:addtextfield(kclcontroller["RotationRateController"]["EpBank"]:tostring).
    set gui_epbank_input:onconfirm to {
        parameter newval.
        set kclcontroller["RotationRateController"]["EpBank"] to newval:tonumber.
    }.

    // Sideslip rate controller
    gui_maingui:addlabel("Sideslip Rate").
    declare global gui_sideslip_rate_box to gui_maingui:addhbox().
    declare global gui_ksideslip_label to gui_sideslip_rate_box:addlabel("K:").
    declare global gui_ksideslip_input to gui_sideslip_rate_box:addtextfield(kclcontroller["RotationRateController"]["KSideslip"]:tostring).
    set gui_ksideslip_input:onconfirm to {
        parameter newval.
        set kclcontroller["RotationRateController"]["KSideslip"] to newval:tonumber.
    }.
    declare global gui_uppersideslip_label to gui_sideslip_rate_box:addlabel("Upper:").
    declare global gui_uppersideslip_input to gui_sideslip_rate_box:addtextfield(kclcontroller["RotationRateController"]["UpperSideslip"]:tostring).
    set gui_uppersideslip_input:onconfirm to {
        parameter newval.
        set kclcontroller["RotationRateController"]["UpperSideslip"] to newval:tonumber.
    }.
    declare global gui_epsideslip_label to gui_sideslip_rate_box:addlabel("Ep:").
    declare global gui_epsideslip_input to gui_sideslip_rate_box:addtextfield(kclcontroller["RotationRateController"]["EpSideslip"]:tostring).
    set gui_epsideslip_input:onconfirm to {
        parameter newval.
        set kclcontroller["RotationRateController"]["EpSideslip"] to newval:tonumber.
    }.

    gui_maingui:addspacing(10).

    // Torque Controllers
    gui_maingui:addlabel("<b>Torque Controllers</b>").

    // Roll torque controller
    gui_maingui:addlabel("Roll").
    declare global gui_roll_box to gui_maingui:addhbox().
    declare global gui_roll_kp_label to gui_roll_box:addlabel("Kp:").
    declare global gui_roll_kp_input to gui_roll_box:addtextfield(kclcontroller["RollTorqueController"]["PID"]:kp:tostring).
    set gui_roll_kp_input:onconfirm to {
        parameter newval.
        set kclcontroller["RollTorqueController"]["PID"]:kp to newval:tonumber.
    }.
    declare global gui_roll_ki_label to gui_roll_box:addlabel("Ki:").
    declare global gui_roll_ki_input to gui_roll_box:addtextfield(kclcontroller["RollTorqueController"]["PID"]:ki:tostring).
    set gui_roll_ki_input:onconfirm to {
        parameter newval.
        set kclcontroller["RollTorqueController"]["PID"]:ki to newval:tonumber.
    }.
    declare global gui_roll_kd_label to gui_roll_box:addlabel("Kd:").
    declare global gui_roll_kd_input to gui_roll_box:addtextfield(kclcontroller["RollTorqueController"]["PID"]:kd:tostring).
    set gui_roll_kd_input:onconfirm to {
        parameter newval.
        set kclcontroller["RollTorqueController"]["PID"]:kd to newval:tonumber.
    }.

    // Pitch torque controller
    gui_maingui:addlabel("Pitch").
    declare global gui_pitch_box to gui_maingui:addhbox().
    declare global gui_pitch_kp_label to gui_pitch_box:addlabel("Kp:").
    declare global gui_pitch_kp_input to gui_pitch_box:addtextfield(kclcontroller["PitchTorqueController"]["PID"]:kp:tostring).
    set gui_pitch_kp_input:onconfirm to {
        parameter newval.
        set kclcontroller["PitchTorqueController"]["PID"]:kp to newval:tonumber.
    }.
    declare global gui_pitch_ki_label to gui_pitch_box:addlabel("Ki:").
    declare global gui_pitch_ki_input to gui_pitch_box:addtextfield(kclcontroller["PitchTorqueController"]["PID"]:ki:tostring).
    set gui_pitch_ki_input:onconfirm to {
        parameter newval.
        set kclcontroller["PitchTorqueController"]["PID"]:ki to newval:tonumber.
    }.
    declare global gui_pitch_kd_label to gui_pitch_box:addlabel("Kd:").
    declare global gui_pitch_kd_input to gui_pitch_box:addtextfield(kclcontroller["PitchTorqueController"]["PID"]:kd:tostring).
    set gui_pitch_kd_input:onconfirm to {
        parameter newval.
        set kclcontroller["PitchTorqueController"]["PID"]:kd to newval:tonumber.
    }.

    // Yaw torque controller
    gui_maingui:addlabel("Yaw").
    declare global gui_yaw_box to gui_maingui:addhbox().
    declare global gui_yaw_kp_label to gui_yaw_box:addlabel("Kp:").
    declare global gui_yaw_kp_input to gui_yaw_box:addtextfield(kclcontroller["YawTorqueController"]["PID"]:kp:tostring).
    set gui_yaw_kp_input:onconfirm to {
        parameter newval.
        set kclcontroller["YawTorqueController"]["PID"]:kp to newval:tonumber.
    }.
    declare global gui_yaw_ki_label to gui_yaw_box:addlabel("Ki:").
    declare global gui_yaw_ki_input to gui_yaw_box:addtextfield(kclcontroller["YawTorqueController"]["PID"]:ki:tostring).
    set gui_yaw_ki_input:onconfirm to {
        parameter newval.
        set kclcontroller["YawTorqueController"]["PID"]:ki to newval:tonumber.
    }.
    declare global gui_yaw_kd_label to gui_yaw_box:addlabel("Kd:").
    declare global gui_yaw_kd_input to gui_yaw_box:addtextfield(kclcontroller["YawTorqueController"]["PID"]:kd:tostring).
    set gui_yaw_kd_input:onconfirm to {
        parameter newval.
        set kclcontroller["YawTorqueController"]["PID"]:kd to newval:tonumber.
    }.

    gui_maingui:show().
}