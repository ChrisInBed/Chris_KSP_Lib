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
declare global target_geo to get_target_geo().
declare global entry_vf to 650.
declare global entry_hf to 25000.
declare global entry_dist to 20000.
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
    set AFS:t_reg to 100.
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
        set AFS:mass to ship:mass.
        set AFS:area to FAR:REFAREA.
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
            // draw_vecR_final(stepInfo["vecR_final"], vecRtgt).
            if (stepInfo["time_final"] < 60) break.  // Stop updating guidance parameters
        }
        wait 0.2.
    }
    until ee < ef {
        print "Left Energy = " + round((ee - ef)*1e-3) + " kJ         " AT(0, 13).
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

// function get_bank {
//     // calculate current bank angle
//     return arcTan2(
//         -vDot(ship:facing:starvector, up:forevector),
//         vDot(ship:facing:upvector, up:forevector)
//     ).
// }