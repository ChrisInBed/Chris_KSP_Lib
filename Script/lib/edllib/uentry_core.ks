runOncePath("0:/lib/chrismath.ks").
runOncePath("0:/lib/orbit.ks").
runOncePath("0:/lib/atm_utils.ks").

declare global AFS to addons:AFS.
declare global entry_step_guidance_err_pid to pidLoop(1, 0.01, 0, -5, 5).
declare global entry_aeroprofile_process to lexicon(
    "idle", true,
    "speedSamples", list(), "altSamples", list(),
    "batchsize", 20, "curIndex", 0,
    "Cdlist", list(), "Cllist", list()
).
function entry_async_set_aeroprofile {
    parameter speedSamples.
    parameter altSamples.
    parameter batchsize is 20.

    set entry_aeroprofile_process["idle"] to false.
    set entry_aeroprofile_process["speedSamples"] to speedSamples.
    set entry_aeroprofile_process["altSamples"] to altSamples.
    set entry_aeroprofile_process["batchsize"] to batchsize.
    set entry_aeroprofile_process["Cdlist"] to list().
    set entry_aeroprofile_process["Cllist"] to list().
    set entry_aeroprofile_process["curIndex"] to 0.
    when (true) then {
        local speedSamples to entry_aeroprofile_process["speedSamples"].
        local altSamples to entry_aeroprofile_process["altSamples"].
        local batchsize to entry_aeroprofile_process["batchsize"].
        local nV to speedSamples:length.
        local nH to altSamples:length.
        local curIndex to entry_aeroprofile_process["curIndex"].
        local curEnd to min(curIndex + batchsize, nV * nH).
        from {local i to curIndex.} until i = curEnd step {set i to i+1.} do {
            local iv to floor(i/nH+1e-3).
            local ih to mod(i, nH).
            if (ih = 0) {
                entry_aeroprofile_process["Cdlist"]:add(list()).
                entry_aeroprofile_process["Cllist"]:add(list()).
            }
            local AOAcmd to AFS:GetAOACmd(lexicon("y4", list(10e3, 0, speedSamples[iv], 0)))["AOA"].
            local CLD to atm_get_CLD_at(AOAcmd, speedSamples[iv], altSamples[ih]).
            entry_aeroprofile_process["Cdlist"][iv]:add(CLD["Cd"]).
            entry_aeroprofile_process["Cllist"][iv]:add(CLD["Cl"]).
        }
        if (curEnd = nV * nH) {
            set AFS:AeroSpeedSamples to speedSamples.
            set AFS:AeroAltSamples to altSamples.
            set AFS:AeroCdSamples to entry_aeroprofile_process["Cdlist"].
            set AFS:AeroClSamples to entry_aeroprofile_process["Cllist"].
            set entry_aeroprofile_process["idle"] to true.
            return false.
        }
        set entry_aeroprofile_process["curIndex"] to curEnd.
        return true.
    }
}

function entry_initialize {
    if (not addons:hasaddon("AFS")) {
        print "AFS addon is not installed. Please install the AFS addon to use this script.".
        print 1/0.
    }

    // Initialize atmosphere density model
    // Note that in FAR model, geoposition and time are counted in temperature and pressure calculation
    // But here we assume density only depends on altitude, this lead to ~5% error on Earth
    // This will be improved in future versions
    AFS:InitAtmModel().
    // set AFS:mu to body:mu.
    // set AFS:R to body:radius.
    // set AFS:molar_mass to body:atm:molarmass.
    // set AFS:atm_height to body:atm:height.
    // set basic ship parameters
    set AFS:mass to ship:mass.
    set AFS:area to AFS:REFAREA.
    set AFS:bank_max to 70.  // Maximum stable bank angle
    local CtrlSpeedSamples to list(400, 2000, 6000, 8000).
    entry_set_AOAprofile(
        CtrlSpeedSamples,
        list(10, 25, 28, 28)
    ).
    set AFS:AeroSpeedSamples to list(5000).
    set AFS:AeroAltSamples to list(0).
    set AFS:AeroCdSamples to list(list(1.5)).
    set AFS:AeroClSamples to list(list(0.3)).
    // target geo and path contraints
    declare global entry_hf to 25000.
    declare global entry_vf to 650.
    declare global entry_target_geo to body:geopositionlatlng(0, 0).
    set AFS:target_energy to entry_get_spercific_energy(body:radius+entry_hf, entry_vf).
    declare global entry_heading_tol to 10.
    declare global entry_bank_reversal to false.
    // path constraints
    set AFS:Qdot_max to 6e5.
    set AFS:acc_max to 25.
    set AFS:dynp_max to 10e3.
    set entry_heading_tol to 10.
    // prediction parameters
    set AFS:predict_min_step to 0.
    set AFS:predict_max_step to 0.5.
    set AFS:predict_tmax to 3600.
    // control parameters
    set AFS:L_min to 0.5.
    set AFS:k_QEGC to 0.5.
    set AFS:k_C to 2.
    set AFS:t_reg to 90.

    // Trajectory sampling parameters
    set AFS:predict_traj_dSqrtE to 300.
    set AFS:predict_traj_dH to 10e3.
}

function entry_set_target {
    parameter new_hf, new_vf, new_df, new_headingf.
    parameter new_target_geo.

    set entry_hf to new_hf.
    set entry_vf to new_vf.
    set AFS:target_energy to entry_get_spercific_energy(body:radius+entry_hf, entry_vf).

    local dlat to new_df * cos(new_headingf) / body:radius /constant:pi*180.
    local dlon to new_df / cos(new_target_geo:lat) * sin(new_headingf) / body:radius /constant:pi*180.
    set entry_target_geo to body:geopositionlatlng(new_target_geo:lat + dlat, new_target_geo:lng + dlon).
}

function entry_set_AOAprofile {
    parameter speedSamples.
    parameter AOASamples.

    set AFS:CtrlSpeedSamples to speedSamples.
    set AFS:CtrlAOASamples to AOASamples.
}

function entry_get_control {
    parameter vecR.
    parameter vecV.
    parameter gst.
    
    local unitR to vecR:normalized.
    local unitRtgt to (entry_target_geo:position - body:position):normalized.
    local rr to vecR:mag.
    local theta to -vAng(unitR, unitRtgt).
    local vv to vecV:mag.
    local gamma to 90 - vAng(vecR, vecV).
    local unitH to vCrs(unitRtgt, unitR):normalized.
    local psi to entry_get_angle(vCrs(unitR, unitH), vecV, unitR).

    // unsigned bank command
    local y4 to list(rr, theta, vv, gamma).
    local bank_cmd to AFS:GetBankCmd(lexicon(
        "y4", y4,
        "bank_i", gst["bank_i"], "bank_f", gst["bank_f"],
        "energy_i", gst["energy_i"], "energy_f", gst["energy_f"]
    ))["Bank"].

    // bank reversal
    if (abs(psi) > entry_heading_tol or abs(bank_cmd) < 0.1) set entry_bank_reversal to (psi < 0).
    if (entry_bank_reversal) set bank_cmd to -bank_cmd.

    // linear interpolation for AOA command
    local AOA_cmd to AFS:GetAOACmd(lexicon("y4", y4))["AOA"].

    return lexicon("bank", bank_cmd, "AOA", AOA_cmd).
}

function entry_initialize_guidance { 
    parameter tt.
    parameter vecR.
    parameter vecV.  // orbital velocity
    parameter bank_i, bank_f.

    local vecRtgt to entry_target_geo:position - body:position.

    // propagate to entry interface
    local entryInfo to entry_propagate_to_entry(tt, vecR, vecV).
    if (not entryInfo["ok"]) return lexicon(
        "ok", false, "status", entryInfo["status"],
        "msg", entryInfo["msg"]
    ).
    set tt to entryInfo["time_entry"].
    set vecR to entryInfo["vecR"].
    set vecV to entryInfo["vecV"].
    // print "Time to entry interface: " + round(tt) + " s." AT(0, 13).
    // print "Entry height = " + round(vecR:mag - body:radius) + " m."
    //     + ", speed = " + round(vecV:mag) + " m/s." AT(0, 14).
    // convert to body-fixed frame
    local _toBodyFixed to angleAxis(-body:angularvel:mag*180/constant:pi*tt, body:angularvel).
    set vecR to _toBodyFixed * vecR.
    set vecV to _toBodyFixed * vecV - vCrs(body:angularvel, vecR).

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
        ), true).
        if (not result1["ok"]) {
            print "Entry predictor error: (" + result1["status"] + ") "
                + result1["msg"] AT(0, 15).
            if (result1["status"] = "TIMEOUT" and bank_i <= AFS:bank_max - 0.1) {
                // This case arise when simulation time is too short
                // or trajectory is too shallo.
                // Here we increase bank_i and try again
                set bank_i to AFS:bank_max.
            }
            else return lexicon("ok", false, "status", result1["status"], "msg", result1["msg"]).
        }
        else {
            local result2 to entry_predictor(tt, vecR, vecV, lexicon(
                "bank_i", bank_i + 0.1,
                "bank_f", bank_f,
                "energy_i", energy_i,
                "energy_f", energy_f
            ), true).
            if (not result2["ok"]) return lexicon("ok", false, "status", result2["status"], "msg", result2["msg"]).
            set thetaErr to result1["thetaf"] - theta_target.
            local thetaErrDBank to (result2["thetaf"] - result1["thetaf"]) / 0.1.
            local bank_i_old to bank_i.
            set bank_i to bank_i - max(-5, min(5, thetaErr / msafedivision(thetaErrDBank))).
            set bank_i to max(0, min(AFS:bank_max, bank_i)).
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
        "re", result1["re"], "thetae", result1["thetae"], "ve", result1["ve"], "gammae", result1["gammae"],
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

    // local rangeFactor to 1.
    // local rhoReal to AFS:Density.
    // if (rhoReal * ship:airspeed^2 * 0.5 > 10) {
    //     local rhoEst to AFS:GetDensityEst(ship:altitude).
    //     set rangeFactor to min(1.3, max(0.7, rhoEst / rhoReal)).
    // }

    // re-align guidance start point
    local energy_now to entry_get_spercific_energy(vecR:mag, vecV:mag).
    local bank_now to gst["bank_i"]
        + (gst["bank_f"] - gst["bank_i"]) * (energy_now - gst["energy_i"]) / (gst["energy_f"] - gst["energy_i"]).
    // prediction and get derivatives
    local vecRtgt to entry_target_geo:position - body:position.
    local theta_target to vAng(vecR, vecRtgt).
    local result1 to entry_predictor(tt, vecR, vecV, lexicon(
        "bank_i", bank_now,
        "bank_f", gst["bank_f"],
        "energy_i", energy_now,
        "energy_f", gst["energy_f"]
    ), false).
    if (not result1["ok"]) return lexicon("ok", false, "status", result1["status"], "msg", result1["msg"]).
    // set result1["thetaf"] to result1["thetaf"] * rangeFactor.  // adjust for density error
    local result2 to entry_predictor(tt, vecR, vecV, lexicon(
        "bank_i", bank_now + 0.1,
        "bank_f", gst["bank_f"],
        "energy_i", energy_now,
        "energy_f", gst["energy_f"]
    ), false).
    if (not result2["ok"]) return lexicon("ok", false, "status", result2["status"], "msg", result2["msg"]).
    // set result2["thetaf"] to result2["thetaf"] * rangeFactor.  // adjust for density error
    local thetaErr to result1["thetaf"] - theta_target.
    local thetaErrDBank to (result2["thetaf"] - result1["thetaf"]) / 0.1.
    // update gst
    set bank_now to bank_now - max(-5, min(5, thetaErr / msafedivision(thetaErrDBank))).
    // set bank_now to bank_now + entry_step_guidance_err_pid:Update(time:seconds, thetaErr/msafedivision(thetaErrDBank)).
    set bank_now to max(0, min(AFS:bank_max, bank_now)).
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
    parameter PlanMode is true.

    if (PlanMode) {
        // In plan mode, vecV is orbital velocity
        // And the program will propagate to entry interface first
        // propagate to entry interface
        local entryInfo to entry_propagate_to_entry(tt, vecR, vecV).
        if (not entryInfo["ok"]) return lexicon(
            "ok", false,
            "status", entryInfo["status"],
            "msg", entryInfo["msg"]
        ).
        set tt to entryInfo["time_entry"].
        set vecR to entryInfo["vecR"].
        set vecV to entryInfo["vecV"].

        // convert to body-fixed frame
        local _toBodyFixed to angleAxis(-body:angularvel:mag*180/constant:pi*tt, body:angularvel).
        set vecR to _toBodyFixed * vecR.
        set vecV to _toBodyFixed * vecV - vCrs(body:angularvel, vecR).
    }

    // Convert to y4 state
    local rr to vecR:mag.
    local theta to 0.
    local vv to vecV:mag.
    local gamma to 90 - vAng(vecR, vecV).
    local y4_entry to list(rr, theta, vv, gamma).
    local unitUy to vCrs(vecV, vecR):normalized.
    local unitRref to vecR:normalized.
    // Propagate to final state
    local _jobid to AFS:AsyncSimAtmTraj(lexicon(
        "t", tt, "y4", y4_entry,
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
    set yf[1] to yf[1] * sin(entry_heading_tol) / (entry_heading_tol/180*constant:pi + 1e-6).  // correction for crossrange
    local unitRf to angleAxis(yf[1], -unitUy) * unitRref.
    local vecRf to unitRf * yf[0].
    local vrf to yf[2] * sin(yf[3]).
    local vtf to yf[2] * cos(yf[3]).
    local vecVf to vrf * unitRf + vtf * vCrs(unitRf, unitUy).
    return lexicon(
        "ok", true, "status", "COMPLETED",
        "time_entry", tt, "vecR_entry", vecR, "vecV_entry", vecV,
        "re", y4_entry[0], "thetae", y4_entry[1], "ve", y4_entry[2], "gammae", y4_entry[3],
        "time_final", predRes["t"], "vecR_final", vecRf, "vecV_final", vecVf,
        "rf", yf[0], "thetaf", yf[1], "vf", yf[2], "gammaf", yf[3],
        "trajE", predRes["trajE"],
        "trajR", predRes["trajR"], "trajTheta", predRes["trajTheta"],
        "trajV", predRes["trajV"], "trajGamma", predRes["trajGamma"],
        "trajBank", predRes["trajBank"], "trajAOA", predRes["trajAOA"],
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

    if (vecR:mag <= body:radius + body:atm:height) {
        // local _toBodyFixed to angleAxis(-body:angularvel:mag*180/constant:pi*tt, body:angularvel).
        // set vecR to _toBodyFixed * vecR.
        // set vecV to _toBodyFixed * vecV.
        return lexicon(
            "ok", true, "status", "COMPLETED",
            "time_entry", tt,
            "vecR", vecR,
            "vecV", vecV
        ).
    }

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
    // local _toBodyFixed to angleAxis(-body:angularvel:mag*180/constant:pi*t_e, body:angularvel).
    // set vecR_e to _toBodyFixed * vecR_e.
    // set vecV_e to _toBodyFixed * vecV_e.
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