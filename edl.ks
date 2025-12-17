parameter P_VF to 650.
parameter P_HF to 25000.
parameter P_DIST to 20000.
parameter P_BANKF to 10.

runOncePath("./lib/atm_utils.ks").
runOncePath("./lib/edllib/pc_entry.ks").
runOncePath("./lib/orbit.ks").
set config:IPU to 1000.
// global varibables
declare global guidance_stage to "inactive".
// declare global g0 to body:mu / body:radius^2.
declare global target_geo to get_target_geo().
declare global entry_vf to P_VF.
declare global entry_hf to P_HF.
declare global entry_dist to P_DIST.
declare global entry_bank_f to P_BANKF.
declare global entry_bank_rate to 10.  // deg/s
// declare global pitch_pid to pidLoop(0.1, 0.01, 0.01, -1, 1).
// declare global bank_pid to pidLoop(0.1, 0.01, 0.01, -1, 1).
// declare global yaw_pid to pidLoop(0.1, 0.01, 0.01, -1, 1).

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
    set AFS:Qdot_max to 1e6.
    set AFS:acc_max to 25.
    set AFS:dynp_max to 10e3.
    set entry_heading_tol to 5.
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
    local initInfo to entry_initialize_guidance(0, -body:position, ship:velocity:orbit, 50, entry_bank_f).
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
    // align ship attitude
    set guidance_stage to "align attitude".
    print "Aligning attitude for entry.      " AT(0, 12).
    RCS ON.
    local _control to entry_get_control(-body:position, ship:velocity:surface, gst).
    local target_attitude to __attitude_from_AOA_Bank(_control["AOA"], _control["bank"]).
    lock steering to target_attitude.
    wait until ship:altitude < body:atm:height.
    set guidance_stage to "entry".

    // Inner loop
    local ast to init_attitude_control().
    activate_aero_control().
    when (guidance_stage = "entry") then {
        set _control to entry_get_control(-body:position, ship:velocity:surface, gst).
        set _control to get_attitude_control(_control["AOA"], _control["bank"], ast).
        set target_attitude to __attitude_from_AOA_Bank(_control["AOA"], _control["Bank"]).
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
    unlock steering.
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

function init_attitude_control {
    local ast to lexicon(
        "last_bank", get_bank(),
        "last_time", time:seconds
    ).
    return ast.
}

function get_attitude_control {
    parameter _AOA, _Bank.
    parameter ast.
    print "Command AOA = " + round(_AOA) + " deg; Bank = " + round(_Bank) + " deg; " AT(0, 1).
    // calculate bank
    local bank_current to get_bank().
    local time_current to time:seconds.
    if (abs(bank_current - _Bank) < entry_bank_rate) {
        // close enough, jump to the target directly
        set ast["last_bank"] to bank_current.
        set ast["last_time"] to time_current.
        return lexicon("AOA", _AOA, "Bank", _Bank).
    }
    local dt to time:seconds - ast["last_time"].
    local bank_error to ast["last_bank"] - _Bank.
    if (bank_error > 0) {
        set _Bank to ast["last_bank"] - min(entry_bank_rate * dt, bank_error).
    }
    else {
        set _Bank to ast["last_bank"] + min(entry_bank_rate * dt, -bank_error).
    }
    // print "Adjusted Bank = " + round(_Bank) + " deg; " AT(0, 2).
    // print "Last bank = " + round(ast["last_bank"]) + " deg; dt = " + round(dt, 3) + " s; " AT(0, 3).
    // print "Bank error = " + round(bank_error) + " deg; " AT(0, 4).
    return lexicon("AOA", _AOA, "Bank", _Bank).
}

function activate_aero_control {
    STEERINGMANAGER:RESETPIDS().
    STEERINGMANAGER:RESETTODEFAULT().
    // SET STEERINGMANAGER:SHOWFACINGVECTORS TO TRUE.

    SET STEERINGMANAGER:PITCHTS TO 8.0.
    SET STEERINGMANAGER:YAWTS TO 2.
    SET STEERINGMANAGER:ROLLTS TO 5.

    SET STEERINGMANAGER:PITCHPID:KD TO 1.5.
    SET STEERINGMANAGER:YAWPID:KD TO 1.5.
    SET STEERINGMANAGER:ROLLPID:KD TO 1.5.

    // IF (STEERINGMANAGER:PITCHPID:HASSUFFIX("epsilon")) {
    //     SET STEERINGMANAGER:PITCHPID:EPSILON TO 0.5.
    //     SET STEERINGMANAGER:YAWPID:EPSILON TO 0.2.
    //     SET STEERINGMANAGER:ROLLPID:EPSILON TO 0.6.
    // }

    // IF (STEERINGMANAGER:PITCHPID:HASSUFFIX("TORQUEEPSILONMAX")) {
    //     set STEERINGMANAGER:TORQUEEPSILONMAX TO 0.002.
    // }
}

function deactivate_aero_control {
    STEERINGMANAGER:RESETPIDS().
    STEERINGMANAGER:RESETTODEFAULT().
}

function gui_make_entrylandgui {
    declare global gui_maingui is GUI(500, 700).
    set gui_maingui:style:hstretch to true.

    // title: PEG Landing Guidance
    declare global gui_title_box to gui_maingui:addhbox().
    set gui_title_box:style:height to 40.
    set gui_title_box:style:margin:top to 0.
    declare global gui_title_label to gui_title_box:addlabel("<b><size=20>Entry Guidance</size></b>").
    set gui_title_label:style:align TO "center".
    declare global gui_title_exit_button to gui_title_box:addbutton("X").
    set gui_title_exit_button:style:width to 20.
    set gui_title_exit_button:style:align to "right".
    set gui_title_exit_button:onclick to {
        set done to true.
        set guidance_active to false.
        gui_maingui:hide().
    }.

    // Pitch control
    declare global gui_pitch_label to gui_maingui:addlabel("Pitch").
    declare global gui_pitch_box to gui_maingui:addhbox().
    declare global gui_pitch_ts_label to gui_pitch_box:addlabel("TS"). 
    declare global gui_pitch_ts to gui_pitch_box:addtextfield("8.0").
    set gui_pitch_ts:onconfirm to {
        parameter newval.
        set STEERINGMANAGER:PITCHTS to newval:tonumber.
    }.
    declare global gui_pitch_kd_label to gui_pitch_box:addlabel("KD").
    declare global gui_pitch_kd to gui_pitch_box:addtextfield("1.5").
    set gui_pitch_kd:onconfirm to {
        parameter newval.
        set STEERINGMANAGER:PITCHPID:KD to newval:tonumber.
    }.
    declare global gui_pitch_epsilon_label to gui_pitch_box:addlabel("Ep").
    declare global gui_pitch_epsilon to gui_pitch_box:addtextfield("0.5").
    set gui_pitch_epsilon:onconfirm to {
        parameter newval.
        set STEERINGMANAGER:PITCHPID:EPSILON to newval:tonumber.
    }.

    // Yaw control
    declare global gui_yaw_label to gui_maingui:addlabel("Yaw").
    declare global gui_yaw_box to gui_maingui:addhbox().
    declare global gui_yaw_ts_label to gui_yaw_box:addlabel("TS").
    declare global gui_yaw_ts to gui_yaw_box:addtextfield("2.0").
    set gui_yaw_ts:onconfirm to {
        parameter newval.
        set STEERINGMANAGER:YAWTS to newval:tonumber.
    }.
    declare global gui_yaw_kd_label to gui_yaw_box:addlabel("KD").
    declare global gui_yaw_kd to gui_yaw_box:addtextfield("1.5").
    set gui_yaw_kd:onconfirm to {
        parameter newval.
        set STEERINGMANAGER:YAWPID:KD to newval:tonumber.
    }.
    declare global gui_yaw_epsilon_label to gui_yaw_box:addlabel("Ep").
    declare global gui_yaw_epsilon to gui_yaw_box:addtextfield("0.2").
    set gui_yaw_epsilon:onconfirm to {
        parameter newval.
        set STEERINGMANAGER:YAWPID:EPSILON to newval:tonumber.
    }.

    // Roll control
    declare global gui_roll_label to gui_maingui:addlabel("Roll").
    declare global gui_roll_box to gui_maingui:addhbox().
    declare global gui_roll_ts_label to gui_roll_box:addlabel("TS").
    declare global gui_roll_ts to gui_roll_box:addtextfield("5.0").
    set gui_roll_ts:onconfirm to {
        parameter newval.
        set STEERINGMANAGER:ROLLTS to newval:tonumber.
    }.
    declare global gui_roll_kd_label to gui_roll_box:addlabel("KD").
    declare global gui_roll_kd to gui_roll_box:addtextfield("1.5").
    set gui_roll_kd:onconfirm to {
        parameter newval.
        set STEERINGMANAGER:ROLLPID:KD to newval:tonumber.
    }.
    declare global gui_roll_epsilon_label to gui_roll_box:addlabel("Ep").
    declare global gui_roll_epsilon to gui_roll_box:addtextfield("0.6").
    set gui_roll_epsilon:onconfirm to {
        parameter newval.
        set STEERINGMANAGER:ROLLPID:EPSILON to newval:tonumber.
    }.

    // TORQUEEPSILONMAX and TORQUEEPSILONMIN
    declare global gui_torque_epsilonmax_box to gui_maingui:addhbox().
    declare global gui_torque_epsilonmax_label to gui_torque_epsilonmax_box:addlabel("Torque Ep Max").
    declare global gui_torque_epsilonmax to gui_torque_epsilonmax_box:addtextfield("0.002").
    set gui_torque_epsilonmax:onconfirm to {
        parameter newval.
        set STEERINGMANAGER:TORQUEEPSILONMAX to newval:tonumber.
    }.

    // Reset all button
    declare global gui_reset_button to gui_maingui:addbutton("Reset All to Default").
    set gui_reset_button:onclick to {
        STEERINGMANAGER:RESETPIDS().
        STEERINGMANAGER:RESETTODEFAULT().
        // update GUI values
        set gui_pitch_ts:text to round(STEERINGMANAGER:PITCHTS, 2).
        set gui_pitch_kd:text to round(STEERINGMANAGER:PITCHPID:KD, 3).
        set gui_pitch_epsilon:text to round(STEERINGMANAGER:PITCHPID:EPSILON, 3).
        set gui_yaw_ts:text to round(STEERINGMANAGER:YAWTS, 2).
        set gui_yaw_kd:text to round(STEERINGMANAGER:YAWPID:KD, 3).
        set gui_yaw_epsilon:text to round(STEERINGMANAGER:YAWPID:EPSILON, 3).
        set gui_roll_ts:text to round(STEERINGMANAGER:ROLLTS, 2).
        set gui_roll_kd:text to round(STEERINGMANAGER:ROLLPID:KD, 3).
        set gui_roll_epsilon:text to round(STEERINGMANAGER:ROLLPID:EPSILON, 3).
        set gui_torque_epsilonmax:text to round(STEERINGMANAGER:TORQUEEPSILONMAX, 4).
    }.

    gui_maingui:show().
}