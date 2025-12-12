runOncePath("0:/lib/orbit.ks").
runOncePath("0:/lib/atm_utils.ks").

function entry_initialize {
    if (not addons:hasaddon("AFS")) {
        print "AFS addon is not installed. Please install the AFS addon to use this script.".
        print 1/0.
    }
    if (not addons:hasaddon("FAR")) {
        print "FAR addon is not installed. Please install the FAR addon to use this script.".
        print 1/0.
    }
    declare global AFS to addons:AFS.
    declare global FAR to addons:FAR.
    // set basic ship parameters
    set AFS:mu to body:mu.
    set AFS:R to body:radius.
    set AFS:rho0 to atm_get_sealevel_density().
    set AFS:hs to atm_get_scale_height().
    set AFS:mass to ship:mass.
    set AFS:area to FAR:REFAREA.
    // AOA profile and Cl, Cd profiles
    set AFS:speedsamples to list(200, 1000, 5000, 7000).
    declare global AOAProfile to list(160, 160, 160, 160).
    declare global HProfile to list(5e3, 25e3, 50e3, 80e3).
    entry_set_profile(
        HProfile,
        AFS:speedsamples,
        AOAProfile
    ).
    // target geo and path contraints
    declare global vecRtgt to V(0, 0, 0).
    set AFS:Qdot_max to 5e6.
    set AFS:acc_max to 30.
    set AFS:dynp_max to 15e3.
    set AFS:target_energy to entry_get_spercific_energy(body:radius+HProfile[0], AFS:speedsamples[0]).
    declare global entry_heading_tol to 5.
    declare global entry_bank_reversal to false.
    // prediction parameters
    set AFS:predict_min_step to 0.
    set AFS:predict_max_step to 0.5.
    set AFS:predict_tmax to 3600.
    // control parameters
    set AFS:L_min to 0.5.
    // set AFS:k_QEGC to 1.
    // set AFS:k_C to 1.
    // set AFS:t_reg to 60.
}

function entry_set_target {
    parameter hf, vf, df.
    parameter new_target_geo.

    local unitRtarget to (new_target_geo:position - body:position):normalized.
    local unitRref to -body:position:normalized.
    local unitH to -vCrs(unitRref, unitRtarget):normalized.
    local dtheta to df / body:radius /constant:pi*180.
    local unitRtgt to angleAxis(-dtheta, -unitH) * unitRtarget.
    set vecRtgt to unitRtgt * (body:radius + hf).
    set AFS:target_energy to entry_get_spercific_energy(body:radius+hf, vf).
}

function entry_set_profile {
    parameter newHProfile.
    parameter newSpeedsamples.
    parameter newAOAProfile.

    set AFS:speedsamples to newSpeedsamples.
    set AOAProfile to newAOAProfile.
    set HProfile to newHProfile.
    local ClProfile to list().
    local CdProfile to list().
    from {local i to 0.} until i = AOAProfile:length step {set i to i+1.} do {
        local CLD to atm_get_CLD_at(AOAProfile[i], AFS:speedsamples[i], HProfile[i]).
        ClProfile:add(CLD[0]).
        CdProfile:add(CLD[1]).
    }
    set AFS:Clsamples to ClProfile.
    set AFS:Cdsamples to CdProfile.
}

function entry_get_control {
    parameter vecR.
    parameter vecV.
    parameter gst.
    
    local unitR to vecR:normalized.
    local unitRtgt to vecRtgt:normalized.
    local rr to vecR:mag.
    local theta to -vAng(unitR, unitRtgt).
    local vv to vecV:mag.
    local gamma to 90 - vAng(vecR, vecV).
    local unitH to vCrs(unitRtgt, unitR):normalized.
    local psi to entry_get_angle(vCrs(unitR, unitH), vecV, unitR).

    // unsigned bank command
    local bank_cmd to AFS:GetBankCmd(lexicon(
        "y4", list(rr, theta, vv, gamma),
        "bank_i", gst["bank_i"], "bank_f", gst["bank_f"],
        "energy_i", gst["energy_i"], "energy_f", gst["energy_f"]
    )).

    // bank reversal
    if (abs(psi) > entry_heading_tol) set entry_bank_reversal to (psi < 0).
    if (entry_bank_reversal) set bank_cmd to -bank_cmd.

    // linear interpolation for AOA command
    local AOA_cmd to mlinearInterpolation(AFS:speedsamples, AOAProfile, vv).

    return lexicon("bank", bank_cmd, "AOA", AOA_cmd).
}

function entry_initialize_guidance { 
    parameter tt.
    parameter vecR.
    parameter vecV.  // orbital velocity
    parameter bank_i, bank_f.

    if (vecR:mag > body:radius + body:atm:height) {
        // propagate to entry interface
        local _result to entry_propagate_to_entry(tt, vecR, vecV).
        if (not _result["ok"]) return lexicon(
            "ok", false, "status", _result["status"],
            "msg", _result["msg"]
        ).
        set tt to _result["time_entry"].
        set vecR to _result["vecR"].
        set vecV to _result["vecV"].
        print "Time to entry interface: " + round(tt) + " s." AT(0, 13).
        print "Entry height = " + round(vecR:mag - body:radius) + " m."
            + ", speed = " + round(vecV:mag) + " m/s." AT(0, 14).
    }
    // Convert orbital velocity to surface velocity
    set vecV to vecV - vCrs(body:angularvel, vecR).

    local energy_i to entry_get_spercific_energy(vecR:mag, vecV:mag).
    local energy_f to AFS:target_energy.

    local theta_target to vAng(vecR, vecRtgt).
    local bank_tol to 0.3.
    local numiter to 0.
    local result1 to lexicon().
    local thetaErr to 1e6.
    until (numiter > 40) {
        set result1 to entry_predictor(tt, vecR, vecV, lexicon(
            "bank_i", bank_i,
            "bank_f", bank_f,
            "energy_i", energy_i,
            "energy_f", energy_f
        )).
        if (not result1["ok"]) {
            print "Entry predictor error: (" + result1["status"] + ") "
                + result1["msg"] AT(0, 15).
            if (result1["status"] = "TIMEOUT" and bank_i <= 89.9) {
                // This case arise when simulation time is too short
                // or trajectory is too shallo.
                // Here we increase bank_i and try again
                set bank_i to 90.
            }
            else return lexicon("ok", false, "status", result1["status"], "msg", result1["msg"]).
        }
        else {
            local result2 to entry_predictor(tt, vecR, vecV, lexicon(
                "bank_i", bank_i + 0.1,
                "bank_f", bank_f,
                "energy_i", energy_i,
                "energy_f", energy_f
            )).
            if (not result2["ok"]) return lexicon("ok", false, "status", result2["status"], "msg", result2["msg"]).
            set thetaErr to result1["thetaf"] - theta_target.
            local thetaErrDBank to (result2["thetaf"] - result1["thetaf"]) / 0.1.
            local bank_i_old to bank_i.
            set bank_i to bank_i - thetaErr / (thetaErrDBank+1e-6).
            set bank_i to max(0, min(90, bank_i)).
            print "Iteration " + (numiter+1) + ": bank_i = "
                + round(bank_i, 2) + " deg; theta error = "
                + round(thetaErr, 4) + " deg." AT(0, 15).
            if (abs(bank_i - bank_i_old) < bank_tol) {
                break.
            }
        }
        set numiter to numiter + 1.
    }

    local gst to lexicon(
        "bank_i", bank_i,
        "bank_f", bank_f,
        "energy_i", energy_i,
        "energy_f", energy_f
    ).

    return lexicon(
        "ok", true, "status", "COMPLETED", "gst", gst,
        "time_entry", tt, "vecR_entry", vecR, "vecV_entry", vecV,
        "time_final", result1["time_final"], "vecR_final", result1["vecR_final"], "vecV_final", result1["vecV_final"],
        "rf", result1["rf"], "thetaf", result1["thetaf"], "vf", result1["vf"], "gammaf", result1["gammaf"],
        "maxQdot", result1["maxQdot"], "maxQdotTime", result1["maxQdotTime"],
        "maxAcc", result1["maxAcc"], "maxAccTime", result1["maxAccTime"],
        "maxDynP", result1["maxDynP"], "maxDynPTime", result1["maxDynPTime"],
        "error", thetaErr
    ).
}

function entry_step_guidance {
    parameter tt.
    parameter vecR.
    parameter vecV.  // surface velocity
    parameter gst.

    // re-align guidance start point
    local energy_now to entry_get_spercific_energy(vecR:mag, vecV:mag).
    local bank_now to gst["bank_i"]
        + (gst["bank_f"] - gst["bank_i"]) * (energy_now - gst["energy_i"]) / (gst["energy_f"] - gst["energy_i"]).
    // prediction and get derivatives
    local theta_target to vAng(vecR, vecRtgt).
    local result1 to entry_predictor(tt, vecR, vecV, lexicon(
        "bank_i", bank_now,
        "bank_f", gst["bank_f"],
        "energy_i", energy_now,
        "energy_f", gst["energy_f"]
    )).
    if (not result1["ok"]) return lexicon("ok", false, "status", result1["status"], "msg", result1["msg"]).
    local result2 to entry_predictor(tt, vecR, vecV, lexicon(
        "bank_i", bank_now + 0.1,
        "bank_f", gst["bank_f"],
        "energy_i", energy_now,
        "energy_f", gst["energy_f"]
    )).
    if (not result2["ok"]) return lexicon("ok", false, "status", result2["status"], "msg", result2["msg"]).
    local thetaErr to result1["thetaf"] - theta_target.
    local thetaErrDBank to (result2["thetaf"] - result1["thetaf"]) / 0.1.
    // update gst
    set bank_now to bank_now - thetaErr / (thetaErrDBank+1e-6).
    set bank_now to max(0, min(90, bank_now)).
    set gst["bank_i"] to bank_now.
    set gst["energy_i"] to energy_now.

    return lexicon(
        "ok", true, "status", "COMPLETED",
        "time_final", result1["time_final"], "vecR_final", result1["vecR_final"], "vecV_final", result1["vecV_final"],
        "rf", result1["rf"], "thetaf", result1["thetaf"], "vf", result1["vf"], "gammaf", result1["gammaf"],
        "maxQdot", result1["maxQdot"], "maxQdotTime", result1["maxQdotTime"],
        "maxAcc", result1["maxAcc"], "maxAccTime", result1["maxAccTime"],
        "maxDynP", result1["maxDynP"], "maxDynPTime", result1["maxDynPTime"],
        "error", thetaErr
    ).
}

function entry_predictor {
    parameter tt.
    parameter vecR.
    parameter vecV.  // orbital or surface velocity
    parameter gst.
    parameter inOrbit is false.  // true if vecV is orbital velocity

    if (vecR:mag > body:radius + body:atm:height) {
        // propagate to entry interface
        local _result to entry_propagate_to_entry(tt, vecR, vecV).
        if (not _result["ok"]) return lexicon(
            "ok", false,
            "status", _result["status"],
            "msg", _result["msg"]
        ).
        set tt to _result["time_entry"].
        set vecR to _result["vecR"].
        set vecV to _result["vecV"].
    }

    if (inOrbit) {
        // Convert orbital velocity to surface velocity
        set vecV to vecV - vCrs(body:angularvel, vecR).
    }

    // Convert to y4 state
    local rr to vecR:mag.
    local theta to 0.
    local vv to vecV:mag.
    local gamma to 90 - vAng(vecR, vecV).
    local unitUy to vCrs(vecV, vecR):normalized.
    local unitRref to vecR:normalized.
    // Propagate to final state
    local _jobid to AFS:AsyncSimAtmTraj(lexicon(
        "t", tt, "y4", list(rr, theta, vv, gamma),
        "bank_i", gst["bank_i"], "bank_f", gst["bank_f"],
        "energy_i", gst["energy_i"], "energy_f", gst["energy_f"]
    )).
    print "jobid: " + _jobid AT(0, 20).
    // until (AFS:CheckTask(_jobid)) {local i to 1.}
    wait until AFS:CheckTask(_jobid).  // slower but less burden for CPU
    print "jobid: " + _jobid + " completed." AT(0, 20).
    local predRes to AFS:GetTaskResult(_jobid).
    if (not predRes["ok"]) return lexicon(
        "ok", false,
        "status", "ERROR",
        "msg", predRes["msg"]
    ).
    if (predRes["status"] <> "COMPLETED") return lexicon(
        "ok", false,
        "status", predRes["status"],
        "msg", "Prediction did not end at terminal condition, status: " + predRes["status"]
    ).
    local yf to predRes["finalState"].
    local unitRf to angleAxis(yf[1], -unitUy) * unitRref.
    local vecRf to unitRf * yf[0].
    local vrf to yf[2] * sin(yf[3]).
    local vtf to yf[2] * cos(yf[3]).
    local vecVf to vrf * unitRf + vtf * vCrs(unitRf, unitUy).
    return lexicon(
        "ok", true, "status", "COMPLETED",
        "time_entry", tt, "vecR_entry", vecR, "vecV_entry", vecV,
        "time_final", predRes["t"], "vecR_final", vecRf, "vecV_final", vecVf,
        "rf", yf[0], "thetaf", yf[1], "vf", yf[2], "gammaf", yf[3],
        "nsteps", predRes["nsteps"],
        "maxQdot", predRes["maxQdot"], "maxQdotTime", predRes["maxQdotTime"],
        "maxAcc", predRes["maxAcc"], "maxAccTime", predRes["maxAccTime"],
        "maxDynP", predRes["maxDynP"], "maxDynPTime", predRes["maxDynPTime"]
    ).
}

function entry_propagate_to_entry {
    parameter tt.
    parameter vecR.
    parameter vecV.

    // Get orbit elements
    local obts to get_orbit_element_from_VR(vecR, vecV, body:mu).
    local unitUy to vCrs(vecV, vecR):normalized.

    local r_e to body:atm:height + body:radius - 1.
    local r_min to get_orbit_r_at_theta(obts["sma"], obts["ecc"], 0).
    if (r_e <= r_min) return lexicon(
        "ok", false, "status", "HIGH_PERIGEE",
        "msg", "Perigee is higher than atomosphere"
    ).
    if (obts["ecc"] >= 1 and obts["TA"] < 180 and obts["TA"] > 0) return lexicon(
        "ok", false, "status", "ESCAPING",
        "msg", "Escaping, will not enter atmosphere"
    ).
    local theta_e to 360-arcCos((get_orbit_latus_rectum(obts["sma"], obts["ecc"])/r_e-1)/obts["ecc"]).
    local unitR_e to angleAxis(theta_e-obts["TA"], -unitUy) * vecR:normalized.
    local vecR_e to unitR_e * r_e.
    local _vfactor to sqrt(body:mu/(obts["sma"]*(1-obts["ecc"]^2))).
    local vr_e to _vfactor * obts["ecc"] * sin(theta_e).
    local vt_e to _vfactor * (1 + obts["ecc"] * cos(theta_e)).
    local vecV_e to vr_e * unitR_e + vt_e * vCrs(unitR_e, unitUy).
    local t_e to get_time_to_theta(obts["sma"], obts["ecc"], body:mu, tt, obts["TA"], theta_e).
    print "TA = " + round(obts["TA"]) + " ; TA_entry = " + round(theta_e) + "   " AT(0, 17).
    // to body-fixed reference frame
    local _toBodyFixed to angleAxis(-body:angularvel:mag*180/constant:pi*(t_e-tt), body:angularvel).
    set vecR_e to _toBodyFixed * vecR_e.
    set vecV_e to _toBodyFixed * vecV_e.
    return lexicon(
        "ok", true, "status", "COMPLETED",
        "time_entry", t_e,
        "vecR", vecR_e,
        "vecV", vecV_e
    ).
}

function entry_get_angle {
    parameter vec1.
    parameter vec2.
    parameter unitH.
    
    set vec1 to vxcl(unitH, vec1).
    set vec2 to vxcl(unitH, vec2).
    local theta to vang(vec1, vec2).
    if vDot(vCrs(vec2, vec1), unitH) < 0 {
        set theta to -theta.
    }
    return theta.
}

function entry_get_spercific_energy {
    parameter rr.
    parameter vv.
    return -body:mu/rr + 0.5*vv*vv.
}