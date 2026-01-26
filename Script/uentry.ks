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

function entry_phase {
    set guidance_stage to "preparation".
    // initialize guidance
    print "Preparing entry guidance.         " AT(0, 12).
    local startTime to time:seconds.
    set AFS:mass to ship:mass.
    set AFS:area to AFS:REFAREA.
    AFS:InitAtmModel().
    local initInfo to entry_initialize_guidance(0, -body:position, ship:velocity:orbit, entry_bank_i, entry_bank_f).
    if (not initInfo["ok"]) {
        print "Error: (" + initInfo["status"] + ")" + initInfo["msg"] AT(0, 30).
        return.
    }
    local gst to initInfo["gst"].
    // glide to entry interface
    set guidance_stage to "gliding".
    when ((not done) and guidance_active) then {
        local _cd to startTime+initInfo["time_entry"]-time:seconds.
        if (defined gui_edlmain) {
            local msg to "Time to entry = " + round(_cd) + " s.".
            set gui_edl_state_msg:text to msg.
        }
        return _cd >= 0.
    } 
    wait until time:seconds - startTime > initInfo["time_entry"] - 60 or ship:altitude < body:atm:height or done or (not guidance_active).
    if (done or (not guidance_active)) return.
    set guidance_stage to "entry".
    RCS ON.
    local _control to entry_get_control(-body:position, ship:velocity:surface, gst).
    // Inner loop
    when (guidance_stage = "entry" and (not done) and guidance_active) then {
        set _control to entry_get_control(-body:position, ship:velocity:surface, gst).
        local _AOACmd to _control["AOA"].
        if (AFS:AOAReversal) {set _AOACmd to -_AOACmd.}
        local _targetAttitude to AeroFrameCmd2Attitude(_AOACmd, 0, _control["bank"]).
        KCLController_ApplyControl(kclcontroller, ship:facing * AFS:rotation, _targetAttitude).
        if (defined gui_edlmain) {
            set gui_edl_state_alt:text to "Altitude: " + round(ship:altitude*1e-3,2) + " km".
            set gui_edl_state_speed:text to "Speed: " + round(ship:velocity:surface:mag,1) + " m/s".
            set gui_edl_state_aoa:text to "AOA: " + round(AFS:AOA,1) + "(" + round(_control["AOA"],1) + ")".
            set gui_edl_state_bank:text to "Bank: " + round(AFS:BANK,1) + "(" + round(_control["bank"],1) + ")".
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
    until (ee < ef or done or (not guidance_active)) {
        set AFS:mass to ship:mass.
        set AFS:area to AFS:REFAREA.
        AFS:InitAtmModel().
        set stepInfo to entry_step_guidance(0, -body:position, ship:velocity:surface, gst).
        if (not stepInfo["ok"]) {
            print "Error: (" + stepInfo["status"] + ")" + stepInfo["msg"] AT(0, 30).
            if (defined gui_edlmain) {
                set gui_edl_state_msg:text to "Error: (" + stepInfo["status"] + ")" + stepInfo["msg"].
            }
        }
        else {
            // debug
            print "FAR CD = " + round(AFS:CD, 2) + ", CL = " + round(AFS:CL, 2) + "          " AT(0, 13).
            // local calculated_cdl to AFS:GetFARAeroCoefs(lexicon("altitude", ship:altitude, "speed", ship:velocity:surface:mag, "AOA", AFS:AOA)).
            local AOACmd to AFS:GetAOACmd(lexicon("vecR", V(0,0,0), "vecV", ship:velocity:surface))["AOA"].
            local calculated_cdl to AFS:GetFARAeroCoefs(lexicon("altitude", ship:altitude, "speed", ship:velocity:surface:mag, "AOA", AOACmd)).
            local estimated_cdl to AFS:GetFARAeroCoefsEst(lexicon("altitude", ship:altitude, "speed", ship:velocity:surface:mag)).
            print "Estimated CD = " + round(estimated_cdl["CD"], 2) + ", CL = " + round(estimated_cdl["CL"], 2) + "          " AT(0, 14).
            print "Calculated CD = " + round(calculated_cdl["CD"], 2) + ", CL = " + round(calculated_cdl["CL"], 2) + "          " AT(0, 15).
            print "Current Air Density = " + AFS:Density + " kg/m^3          " AT(0,16).
            print "Estimated Air Density = " + AFS:GetDensityEst(ship:altitude) + " kg/m^3          " AT(0,17).
            if (defined gui_edlmain) {
                set gui_edl_state_banki:text to "Bank_i: " + round(gst["bank_i"],1):tostring + " °".
                set gui_edl_state_T:text to "T: " + round(stepInfo["time_final"]):tostring + " s".
                set gui_edl_state_EToGo:text to "E TOGO: " + round((ee - ef)*1e-3):tostring + " kJ".
                local vecR to -body:position.
                local vecV to ship:velocity:surface.
                local thetaf to entry_angle_to_target(vecR, vecV, stepInfo["vecR_final"]).
                set gui_edl_state_rangetogo:text to "Range TOGO: " + +round(thetaf/180*constant:pi*body:radius*1e-3,2) + " km".
                set gui_edl_state_rangeerr:text to "Range Err: " + round(stepInfo["error"]/180*constant:pi*body:radius*1e-3,2) + " km".
                set gui_edl_state_vf:text to "Vf: " + round(stepInfo["vecV_final"]:mag):tostring + " m/s".
                set gui_edl_state_hf:text to "Hf: " + round((stepInfo["vecR_final"]:mag - body:radius)*1e-3):tostring + " km".

                set gui_edl_state_qdot:text to "Heatflux: " + round(AFS:HeatFlux*1e-3):tostring + " kW".
                set gui_edl_state_maxqdot:text to "M.Heatflux: " + round(stepInfo["maxQdot"]*1e-3):tostring + " kW @" + round(stepInfo["maxQdotTime"]):tostring + " s".
                set gui_edl_state_load:text to "Load: " + round(AFS:GeeForce,1):tostring + " g".
                set gui_edl_state_maxload:text to "M.Load: " + round(stepInfo["maxAcc"]/9.81,1):tostring + " g @" + round(stepInfo["maxAccTime"]):tostring + " s".
                set gui_edl_state_dynp:text to "DynP: " + round(AFS:DynamicPressure*1e-3,1):tostring + " kPa".
                set gui_edl_state_maxdynp:text to "M.DynP: " + round(stepInfo["maxDynP"]*1e-3,1):tostring + " kPa @" + round(stepInfo["maxDynPTime"]):tostring + " s".
            }
            if (stepInfo["time_final"] < 60) break.  // Stop updating guidance parameters
        }
        wait 0.5.
    }
    local _timebegin to time:seconds.
    until ee < ef or done or (not guidance_active) {
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
    entry_initialize().
    edl_MakeEDLGUI().
    until done {
        wait until guidance_active or done.
        if (not done) {entry_phase().}
        // print result
        print "Entry guidance completed." AT(0, 21).
        print "Final position: " + ship:position AT(0, 22).
        print "Final velocity: " + ship:velocity AT(0, 23).
        set guidance_stage to "inactive".
        set guidance_active to false.
    }
    wait until done.
}

main().