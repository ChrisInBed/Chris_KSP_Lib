runOncePath("0:/lib/utils.ks").
runOncePath("0:/lib/orbit.ks").
runOncePath("0:/lib/atm_utils.ks").
runOncePath("0:/lib/edllib/uentry_core.ks").
runOncePath("0:/lib/edllib/gui_utils.ks").
runOncePath("0:/lib/edllib/flightcontrol.ks").
set config:IPU to 1000.
// global varibables
declare global done to false.
declare global guidance_active to false.
declare global guidance_stage to "inactive".
declare global entry_bank_i to 20.
declare global entry_bank_f to 10.

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
    // entry_set_target(25e3, 650, 30e3, 0, get_target_geo()).
    // set _vecRtgtDraw to vecDraw(
    //     {return body:position.},
    //     {return entry_target_geo:position - body:position.},
    //     RGB(255, 0, 0), "Target", 1.0, true
    // ).
    // entry_set_AOAprofile(
    //     list(400, 2000, 6000, 8000), // speed profile in m/s
    //     list(13, 20, 32, 33) // AOA profile in degrees
    // ).
    // local aeroSpeedSamples to list().
    // mlinspace(entry_vf, 8000, 32, aeroSpeedSamples).
    // local aeroAltSamples to list().
    // mlinspace(entry_hf, body:atm:height, 32, aeroAltSamples).
    // entry_async_set_aeroprofile(
    //     aeroSpeedSamples,
    //     aeroAltSamples
    // ).

    set AFS:Qdot_max to 6e5.
    set AFS:acc_max to 25.
    set AFS:dynp_max to 10e3.
    set entry_heading_tol to 10.

    set AFS:L_min to 0.5.
    set AFS:k_QEGC to 0.5.
    set AFS:k_C to 2.
    set AFS:t_reg to 90.

    wait until entry_aeroprofile_process["idle"].
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
        print msg AT(0, 2).
        return _cd >= 0.
    } 
    wait until time:seconds - startTime > initInfo["time_entry"] - 60 or ship:altitude < body:atm:height.
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
        if (defined gui_edlmain) {
            set gui_edl_state_alt:text to "Altitude: " + round(ship:altitude*1e-3,2) + " km".
            set gui_edl_state_speed:text to "Speed: " + round(ship:velocity:surface:mag,1) + " m/s".
            set gui_edl_state_aoa:text to "AOA: " + round(AFS:AOA,1) + "(" + round(_control["AOA"],1) + ")".
            set gui_edl_state_bank:text to "Bank: " + round(get_bank(),1) + "(" + round(_control["bank"],1) + ")".
            local gamma to 90 - vAng(ship:velocity:surface, up:forevector).
            set gui_edl_state_pathangle:text to "Path Angle: " + round(gamma,2) + "°".
        }
        return true.
    }

    // Outer loop: update guidance state
    local lock ee to entry_get_spercific_energy(body:position:mag, ship:velocity:surface:mag).
    local lock ef to entry_get_spercific_energy(body:radius+entry_hf, entry_vf).
    local stepInfo to lexicon().
    // step once before entering the loop
    until (ee < ef) {
        set AFS:mass to ship:mass.
        set AFS:area to AFS:REFAREA.
        set stepInfo to entry_step_guidance(0, -body:position, ship:velocity:surface, gst).
        if (not stepInfo["ok"]) {
            print "Error: (" + stepInfo["status"] + ")" + stepInfo["msg"] AT(0, 30).
        }
        else {
            // print "bank_i = " + round(gst["bank_i"]) + " deg; " + "T = " + round(stepInfo["time_final"]) + " s    " AT(0, 13).
            // print "range error = " + round(body:radius*stepInfo["error"]/180*constant:pi) + " m    " AT(0, 14).
            // print "vf = " + round(stepInfo["vf"]) + " m/s; " + "hf = " + round(stepInfo["rf"] - body:radius) + " m    " AT(0, 15).
            // print "Max Qdot = " + round(stepInfo["maxQdot"]/1e3, 1) + " kW/m^2 @" + round(stepInfo["maxQdotTime"]) + " s    " AT(0, 17).
            // print "Max acc = " + round(stepInfo["maxAcc"]/9.81, 2) + " g @" + round(stepInfo["maxAccTime"]) + " s    " AT(0, 18).
            // print "Max dynp = " + round(stepInfo["maxDynP"]/1e3, 1) + " kPa @" + round(stepInfo["maxDynPTime"]) + " s    " AT(0, 19).
            if (defined gui_edlmain) {
                set gui_edl_state_banki:text to "Bank_i: " + round(gst["bank_i"],1):tostring + " °".
                set gui_edl_state_T:text to "T: " + round(stepInfo["time_final"]):tostring + " s".
                set gui_edl_state_rangetogo:text to "Range TOGO: " + +round(stepInfo["thetaf"]/180*constant:pi*body:radius*1e-3,2) + " km".
                set gui_edl_state_rangeerr:text to "Range Err: " + round(stepInfo["error"]/180*constant:pi*body:radius*1e-3,2) + " km".
                set gui_edl_state_vf:text to "Vf: " + round(stepInfo["vf"]):tostring + " m/s".
                set gui_edl_state_hf:text to "Hf: " + round((stepInfo["rf"] - body:radius)*1e-3):tostring + " km".
                set gui_edl_state_maxqdot:text to "M.Heatflux: " + round(stepInfo["maxQdot"]/1e3):tostring + " kW @" + round(stepInfo["maxQdotTime"]):tostring + " s".
                set gui_edl_state_maxload:text to "M.Load: " + round(stepInfo["maxAcc"]/9.81,1):tostring + " g @" + round(stepInfo["maxAccTime"]):tostring + " s".
                set gui_edl_state_maxdynp:text to "M.DynP: " + round(stepInfo["maxDynP"]/1e3,1):tostring + " kPa @" + round(stepInfo["maxDynPTime"]):tostring + " s".
                set gui_edl_state_EToGo:text to "E TOGO: " + round((ee - ef)*1e-3):tostring + " kJ".
            }
            draw_vecR_final(stepInfo["vecR_final"], entry_target_geo:position - body:position).
            if (stepInfo["time_final"] < 60) break.  // Stop updating guidance parameters
        }
        wait 1.
    }
    local _timebegin to time:seconds.
    until ee < ef {
        // print "Left Energy = " + round((ee - ef)*1e-3) + " kJ         " AT(0, 13).
        if (defined gui_edlmain) {
            set gui_edl_state_T:text to "T: " + round(stepInfo["time_final"]+_timebegin - time:seconds):tostring + " s".
            set gui_edl_state_EToGo:text to "E TOGO: " + round((ee - ef)*1e-3):tostring + " kJ".
        }
        wait 0.2.
    }
    fc_DeactiveControl().
}

function main {
    // initialize the guidance system
    init_print().
    initialize_guidance().
    edl_MakeEDLGUI().
    wait until guidance_active.
    entry_phase().
    // print result
    print "Entry guidance completed." AT(0, 21).
    print "Final position: " + ship:position AT(0, 22).
    print "Final velocity: " + ship:velocity AT(0, 23).
    wait until done.
}

main().

function draw_vecR_final {
    parameter vecRf.
    parameter vecRtgt.

    set _vecRfDraw to vecDraw(
        {return body:position.},
        {return vecRf.},
        RGB(0, 255, 0), "Final", 1.0, true
    ).
    set _vecRtgtDraw to vecDraw(
        {return body:position.},
        {return vecRtgt.},
        RGB(255, 0, 0), "Target", 1.0, true
    ).
}

function get_bank {
    // calculate current bank angle
    return arcTan2(
        -vDot(ship:facing:starvector, up:forevector),
        vDot(ship:facing:upvector, up:forevector)
    ).
}