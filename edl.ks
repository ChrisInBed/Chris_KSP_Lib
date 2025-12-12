parameter P_VF to 640.
parameter P_HF to 15000.
parameter P_DIST to 30000.
parameter P_BANKF to 10.

runOncePath("./lib/atm_utils.ks").
runOncePath("./lib/edllib/pc_entry.ks").
runOncePath("./lib/orbit.ks").
set config:IPU to 200.
// global varibables
declare global guidance_stage to "inactive".
// declare global g0 to body:mu / body:radius^2.
declare global target_geo to get_target_geo().
declare global entry_vf to P_VF.
declare global entry_hf to P_HF.
declare global entry_dist to P_DIST.
declare global entry_bank_f to P_BANKF.
// declare global Qdotmax to 3000e3. // maximum heat flux in W/m^2
// declare global accmax to 2 * g0. // maximum acceleration in m/s^2
// declare global qmax to 15e3. // maximum dynamic pressure in Pa
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
    when (guidance_stage = "entry") then {
        set _control to entry_get_control(-body:position, ship:velocity:surface, gst).
        set target_attitude to __attitude_from_AOA_Bank(_control["AOA"], _control["bank"]).
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
            if (stepInfo["time_final"] < 20) break.  // Stop updating guidance parameters
        }
        wait 2.
    }
    wait until ee < ef.
    unlock steering.
}

function main {
    // initialize the guidance system
    init_print().
    initialize_guidance().
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