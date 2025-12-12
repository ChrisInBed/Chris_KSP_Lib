parameter P_VF to 640.
parameter P_HF to 15000.
parameter P_DIST to 30000.
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

function main {
    // init_print().
    initialize_guidance().
    local predRes to entry_predictor(0, -body:position, ship:velocity:orbit,
        lexicon("bank_i", 50, "bank_f", entry_bank_f, "energy_i", entry_get_spercific_energy(body:radius+ship:altitude, ship:velocity:surface:mag), "energy_f", AFS:target_energy),
        true
    ).
    print predRes.
    if (predRes["ok"]) {
        local _vecstart to body:position + predRes["vecR_final"]:normalized * body:radius.
        local _vecend to body:position + predRes["vecR_final"].
        vecDraw(_vecstart, _vecend, RGB(0, 255, 0), "Final", 1.0, true).
    }
}

main().