runOncePath("0:/lib/chrismath.ks").
runOncePath("0:/lib/orbit.ks").  // orbit prediction and calculations

declare global __PEG_mu to ship:body:mu.
declare global __PEG_N_integral to 11.
declare global __PEG_thro_pid to pidLoop(5, 0.05, 0.05).

function peg_init {
    set __PEG_mu to ship:body:mu.
    set __PEG_N_integral to 11.
    set __PEG_thro_pid to pidLoop(5, 0.05, 0.05).
}

function __peg_get_angle {
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

function __peg_get_burn_time {
    parameter a0.
    parameter ve.
    parameter dv.
    return ve/a0 * (1 - exp(-dv/ve)).
}

function __peg_get_dv {
    parameter a0.
    parameter ve.
    parameter burntime.
    return -ve * ln(1 - burntime * a0 / ve).
}

function peg_get_initial_params {
    parameter tgt.
    parameter obts.
    parameter shp.
    
    // ignition point
    local etaT to __peg_get_angle(obts["unitRref"], tgt["vecRL"], obts["unitUy"]) + obts["etaref"].
    local eta0 to etaT.  // ignition point
    local t2ign to get_time_to_theta(obts["sma"], obts["ecc"], __PEG_mu, 0, obts["etaref"], eta0).
    local obtomega to get_orbit_omega_at_theta(obts["sma"], obts["ecc"], eta0, __PEG_mu).
    // build VL, RL
    local vecbodyomega to tgt["vecbodyomega"].
    local vecRLref to tgt["vecRL"].
    local vecVL_rht to tgt["vecVL_rht"].
    local vecRL to get_ground_vecR_at_time(t2ign, vecRLref, 0, vecbodyomega).
    local unitRL to vecRL:normalized.
    local unitTHL to vCrs(unitRL, obts["unitUy"]):normalized.
    local unitHL to vCrs(unitRL, unitTHL).
    local vecVL to vCrs(vecRL, vecbodyomega) + vecVL_rht:x * unitRL + vecVL_rht:y * unitHL + vecVL_rht:z * unitTHL.
    // ship parameters
    local ve to shp["ve"].
    local a0 to shp["thrust"]*shp["throttle"] / shp["mass"].
    local tau to ve/a0.
    // initialize control
    local _vecVandvecR to get_orbit_vecVR_at_theta(obts["sma"], obts["ecc"], obts["unitUy"], eta0, obts["unitRref"], obts["etaref"], __PEG_mu).
    local vecV0 to _vecVandvecR[0].
    local vecR0 to _vecVandvecR[1].
    local deltav to (vecVL - vecV0):mag.
    local T to __peg_get_burn_time(a0, ve, deltav).
    local vecGAV1 to -__PEG_mu*vecR0/vecR0:mag^3.
    local vecGAV2 to vecGAV1.
    local vecVGO to vecVL - vecV0 - vecGAV1*T.
    local unituK to vecVGO:normalized.
    local deruK to vCrs(unituK, obts["unitUy"]) / T / 10.
    local omega to deruK:mag.
    // integrals
    function _make_integrals {
        local _tseq to list().
        mlinspace(0, T, __PEG_N_integral, _tseq).
        local _aseq to list().
        mzeros(__PEG_N_integral, _aseq).
        marropt({parameter tt. return a0/(1-tt/tau).}, list(_tseq), _aseq).
        local _sinseq to list().
        mzeros(__PEG_N_integral, _sinseq).
        marropt({parameter tt. return sin(omega*tt *180/constant:pi).}, list(_tseq), _sinseq).
        marrmul(_sinseq, _aseq).
        local _cosseq to list().
        mzeros(__PEG_N_integral, _cosseq).
        marropt({parameter tt. return cos(omega*tt *180/constant:pi).}, list(_tseq), _cosseq).
        marrmul(_cosseq, _aseq).
        local _interval to T/(__PEG_N_integral-1).
        local Bvs to mintegral(_sinseq, _interval).
        local Bvc to mintegral(_cosseq, _interval).
        local K to arcTan(Bvs/Bvc) /180*constant:pi / omega.
        // use _sinseq list for remaining integrals
        marropt({parameter tt. return cos(omega*(tt-K) *180/constant:pi).}, list(_tseq), _sinseq).
        marrmul(_sinseq, _aseq).
        local Av to mintegral(_sinseq, _interval).
        marropt({parameter tt. return (T-tt)*cos(omega*(tt-K) *180/constant:pi).}, list(_tseq), _sinseq).
        marrmul(_sinseq, _aseq).
        local Ar to mintegral(_sinseq, _interval).
        marropt({parameter tt. return (T-tt)*sin(omega*(tt-K) *180/constant:pi).}, list(_tseq), _sinseq).
        marrmul(_sinseq, _aseq).
        local Br to mintegral(_sinseq, _interval).
        return lexicon("Av", Av, "Bvs", Bvs, "Bvc", Bvc, "Ar", Ar, "Br", Br, "K", K).
    }
    local _integrals to _make_integrals().
    set vecVGO to _integrals["Av"] * unituK.
    local vecRGO to _integrals["Ar"] * unituK + _integrals["Br"] * deruK / omega.
    local vecVF to V(0,0,0).
    local vecRF to V(0,0,0).

    local numiter to 0.
    until false {
        // predictor
        local _last_vecRF to V(0,0,0).
        until false {
            set vecVF to vecV0 + vecVGO + vecGAV1*T.
            set vecRF to vecR0 + vecV0*T + vecRGO + 0.5*vecGAV2*T^2.
            if (vecRF - _last_vecRF):mag < 1 {
                break.
            }
            set _last_vecRF to vecRF.
            local _magR0 to vecR0:mag.
            local _vecG0 to -__PEG_mu*vecR0/_magR0^3.
            local _derG0 to -__PEG_mu/_magR0^3 * (vecV0 - 3*vDot(vecV0, vecR0)/_magR0^2 * vecR0).
            local _magRF to vecRF:mag.
            local _vecGF to -__PEG_mu*vecRF/_magRF^3.
            local _derGF to -__PEG_mu/_magRF^3 * (vecVF - 3*vDot(vecVF, vecRF)/_magRF^2 * vecRF).
            set vecGAV1 to (_vecGF + _vecG0)/2 - (_derGF - _derG0)*T/12.
            set vecGAV2 to (3*_vecGF + 7*_vecG0)/10 - (_derGF - 1.5*_derG0)*T/15.
        }
        // corrector
        // t2ign + T -> etaT: VL, RL_new = R(T_new-T)*(VL, RL); etaT = etaT + angle(RL, RL_new)
        // etaT -> eta0_new
        // eta0_new -> t2ign: t2ign = t2ign + (eta0_new - eta0)/omega
        set vecRL to get_ground_vecR_at_time(t2ign + T, vecRLref, 0, vecbodyomega).
        set unitRL to vecRL:normalized.
        set unitTHL to vCrs(unitRL, obts["unitUy"]):normalized.
        set unitHL to vCrs(unitRL, unitTHL).
        set vecVL to vCrs(vecRL, vecbodyomega) + vecVL_rht:x * unitRL + vecVL_rht:y * unitHL + vecVL_rht:z * unitTHL.
        set etaT to __peg_get_angle(obts["unitRref"], vecRL, obts["unitUy"]) + obts["etaref"].
        set eta0_new to etaT - __peg_get_angle(vecR0, vecRF, obts["unitUy"]).
        set t2ign to t2ign + (eta0_new - eta0)/180*constant:pi/obtomega.
        set _vecVandvecR to get_orbit_vecVR_at_theta(obts["sma"], obts["ecc"], obts["unitUy"], eta0_new, obts["unitRref"], obts["etaref"], __PEG_mu).
        set vecV0 to _vecVandvecR[0].
        set vecR0 to _vecVandvecR[1].
        // solver
        set vecVGO to vecVL - vecV0 - vecGAV1*T.
        set unituK to vecVGO:normalized.
        set T to T + (vecVGO:mag - _integrals["Av"]) / (a0/(1-T/tau)*cos(omega*(T-_integrals["K"]) *180/constant:pi)).
        if (abs(T) < 1e-6 or abs(T) > 1e6) {
            print "PEG initialization iteration diverged, check your landing orbit parameters" AT(0, 16).
            return 0.  // 
        }
        set _integrals to _make_integrals().
        set vecVGO to _integrals["Av"] * unituK.
        set vecRGO to vecRL - vecR0 - vecV0*T - 0.5*vecGAV2*T^2.
        set vecRGO to _integrals["Ar"] * unituK + vecRGO - unituK * vDot(vecRGO, unituK).
        local vecRGOV to vecRGO - _integrals["Ar"] * unituK.
        set omega to omega * vecRGOV:mag / msafedivision(_integrals["Br"], 1e-7).
        set deruK to vecRGOV:normalized * omega.
        if abs(eta0_new - eta0) < 0.001 {
            break.
        }
        set eta0 to eta0_new.
        set numiter to numiter + 1.
        print "Iter " + numiter + ", T = " + round(T) + ", Av = "+ round(_integrals["Av"]) + "     " AT(0,14).
        print "dpitch = " + round(omega*T*180/constant:pi) + ", K = " + round(_integrals["K"]) + "   " AT(0,15).
    }
    local gst to lexicon(
        "eta0", eta0, "T", T, "K", _integrals["K"], "unituK", unituK, "deruK", deruK, "throttle", shp["throttle"],
        "vecV0", vecV0, "vecR0", vecR0, "vecVF", vecVF, "vecRF", vecRF, "Av", _integrals["Av"],
        "vecGAV1", vecGAV1, "vecGAV2", vecGAV2,
        "unitHref", -obts["unitUy"], "vecErr", vecRF - vecRL, "numiter", numiter
    ).
    // // log column names
    // log "ve%m0%f0%throttle%a0%vecVL_rht%vecbodyomega%sma%ecc%unitUy%unitRref%etaref
    // %vecV0%vecR0%vecVF%vecRF%vecVL%vecRL%vecGAV1%vecGAV2%unituK%deruK%K%T%t2ign
    // %eta0%etaT%vecVGO%vecRGO%Av%Bvs%Bvc%Ar%Br" to "0:/peg_init.log".
    // // log values
    // log ve+"%"+shp["mass"]+"%"+shp["thrust"]+"%"+shp["throttle"]+"%"+a0+"%"+vecVL_rht+"%"+vecbodyomega+"%"+
    //     obts["sma"]+"%"+obts["ecc"]+"%"+obts["unitUy"]+"%"+obts["unitRref"]+"%"+obts["etaref"]+"%"+
    //     vecV0+"%"+vecR0+"%"+vecVF+"%"+vecRF+"%"+vecVL+"%"+vecRL+"%"+vecGAV1+"%"+vecGAV2+"%"+
    //     unituK+"%"+deruK+"%"+_integrals["K"]+"%"+T+"%"+t2ign+"%"+eta0+"%"+etaT+
    //     "%"+vecVGO+"%"+vecRGO+"%"+_integrals["Av"]+"%"+_integrals["Bvs"]+
    //     "%"+_integrals["Bvc"]+"%"+_integrals["Ar"]+"%"+_integrals["Br"] to "0:/peg_init.log".
    return gst.
}

function peg_step_control {
    parameter tgt.
    parameter shp.
    parameter gst.

    if gst["T"] < 5 {
        // stop update control
        return gst.
    }
    // build VL, RL
    local vecbodyomega to tgt["vecbodyomega"].
    local vecRLref to tgt["vecRL"].
    local vecVL_rht to tgt["vecVL_rht"].
    local vecRL to get_ground_vecR_at_time(gst["T"], vecRLref, 0, vecbodyomega).
    local unitRL to vecRL:normalized.
    local unitTHL to vCrs(gst["unitHref"], unitRL):normalized.
    local unitHL to vCrs(unitRL, unitTHL).
    // ship parameters
    local ve to shp["ve"].
    local a0 to shp["thrust"]*gst["throttle"] / shp["mass"].
    local tau to ve/a0.
    // corrector
    local vecV0 to gst["vecV0"].
    local vecR0 to gst["vecR0"].
    local vecVF to gst["vecVF"].
    local vecRF to gst["vecRF"].
    local unitRD to vxcl(unitHL, vecRF):normalized.
    local vecRD to unitRD * vecRL:mag.
    local unitTHD to vCrs(unitHL, unitRD).
    set unitTHD to unitTHD:normalized.
    local unitHD to vCrs(unitRD, unitTHD).
    local vecVD to vCrs(vecRD, vecbodyomega) + vecVL_rht:x * unitRD + vecVL_rht:y * unitHD + vecVL_rht:z * unitTHD.
    // solver
    local omega to gst["deruK"]:mag.
    local T to gst["T"].
    local vecGAV1 to gst["vecGAV1"].
    local vecGAV2 to gst["vecGAV2"].
    local vecVGO to vecVD - vecV0 - vecGAV1*T.
    local unituK to vecVGO:normalized.
    set T to T + (vecVGO:mag - gst["Av"]) / (a0/(1-T/tau)*cos(omega*(T-gst["K"]) *180/constant:pi)).
    // integrals
    function _make_integrals {
        local _tseq to list().
        mlinspace(0, T, __PEG_N_integral, _tseq).
        local _aseq to list().
        mzeros(__PEG_N_integral, _aseq).
        marropt({parameter tt. return a0/(1-tt/tau).}, list(_tseq), _aseq).
        local _sinseq to list().
        mzeros(__PEG_N_integral, _sinseq).
        marropt({parameter tt. return sin(omega*tt *180/constant:pi).}, list(_tseq), _sinseq).
        marrmul(_sinseq, _aseq).
        local _cosseq to list().
        mzeros(__PEG_N_integral, _cosseq).
        marropt({parameter tt. return cos(omega*tt *180/constant:pi).}, list(_tseq), _cosseq).
        marrmul(_cosseq, _aseq).
        local _interval to T/(__PEG_N_integral-1).
        local Bvs to mintegral(_sinseq, _interval).
        local Bvc to mintegral(_cosseq, _interval).
        local K to arcTan(Bvs/Bvc) /180*constant:pi / omega.
        // use _sinseq list for remaining integrals
        marropt({parameter tt. return cos(omega*(tt-K) *180/constant:pi).}, list(_tseq), _sinseq).
        marrmul(_sinseq, _aseq).
        local Av to mintegral(_sinseq, _interval).
        marropt({parameter tt. return (T-tt)*cos(omega*(tt-K) *180/constant:pi).}, list(_tseq), _sinseq).
        marrmul(_sinseq, _aseq).
        local Ar to mintegral(_sinseq, _interval).
        marropt({parameter tt. return (T-tt)*sin(omega*(tt-K) *180/constant:pi).}, list(_tseq), _sinseq).
        marrmul(_sinseq, _aseq).
        local Br to mintegral(_sinseq, _interval).
        return lexicon("Av", Av, "Bvs", Bvs, "Bvc", Bvc, "Ar", Ar, "Br", Br, "K", K).
    }
    local _integrals to _make_integrals().
    set vecVGO to _integrals["Av"] * unituK.
    local vecRGO to vecRD - vecR0 - vecV0*T - 0.5*vecGAV2*T^2.
    set vecRGO to _integrals["Ar"] * unituK + vecRGO - unituK * vDot(vecRGO, unituK).
    local vecRGOV to vecRGO - _integrals["Ar"] * unituK.
    set omega to omega * vecRGOV:mag / msafedivision(_integrals["Br"], 1e-7).
    local deruK to vecRGOV:normalized * omega.
    // predictor
    set vecRF to vecRD.
    until false {
        local _last_vecRF to vecRF.
        local _magR0 to vecR0:mag.
        local _vecG0 to -__PEG_mu*vecR0/_magR0^3.
        local _derG0 to -__PEG_mu/_magR0^3 * (vecV0 - 3*vDot(vecV0, vecR0)/_magR0^2 * vecR0).
        local _magRF to vecRF:mag.
        local _vecGF to -__PEG_mu*vecRF/_magRF^3.
        local _derGF to -__PEG_mu/_magRF^3 * (vecVF - 3*vDot(vecVF, vecRF)/_magRF^2 * vecRF).
        set vecGAV1 to (_vecGF + _vecG0)/2 - (_derGF - _derG0)*T/12.
        set vecGAV2 to (3*_vecGF + 7*_vecG0)/10 - (_derGF - 1.5*_derG0)*T/15.
        set vecVF to vecV0 + vecVGO + vecGAV1*T.
        set vecRF to vecR0 + vecV0*T + vecRGO + 0.5*vecGAV2*T^2.
        if (vecRF - _last_vecRF):mag < 1 {
            break.
        }
    }
    // throttle routine
    local alpha to 1/(1-T/2/tau).
    // local throt to gst["throttle"] * (1 + vDot(unitTHL, vecRF-vecRL)/vDot(unitTHL, vecVF*T-alpha*vecRGO)).
    local throt to gst["throttle"] * (1+__PEG_thro_pid:update(time:seconds, -vDot(unitTHL, vecRF-vecRL)/vDot(unitTHL, vecVF*T-alpha*vecRGO))).
    set throt to min(max(throt, shp["thro_min"]), shp["thro_max"]).
    set gst["T"] to T.
    set gst["K"] to _integrals["K"].
    set gst["unituK"] to unituK.
    set gst["deruK"] to deruK.
    set gst["throttle"] to throt.
    set gst["Av"] to _integrals["Av"].
    set gst["vecVF"] to vecVF.
    set gst["vecRF"] to vecRF.
    set gst["vecGAV1"] to vecGAV1.
    set gst["vecGAV2"] to vecGAV2.
    set gst["vecErr"] to vecRF - vecRL.
    // if not (defined __PEG_log_head) {
    //     // log column names
    //     log "t%ve%m0%f0%throttle%a0%vecVL_rht%vecbodyomega%unitHref
    //     %vecV0%vecR0%vecVD%vecRD%vecVF%vecRF%vecRL%vecGAV1%vecGAV2%unituK%deruK%K%T
    //     %vecVGO%vecRGO%Av%Bvs%Bvc%Ar%Br" to "0:/peg_control.log".
    //     local __PEG_log_head to false.
    // }
    // // log values
    // log time:seconds+"%"+ve+"%"+shp["mass"]+"%"+shp["thrust"]+"%"+gst["throttle"]+"%"+a0+"%"+vecVL_rht+"%"+vecbodyomega+"%"+
    //     gst["unitHref"]+"%"+vecV0+"%"+vecR0+"%"+vecVD+"%"+vecRD+"%"+vecVF+"%"+vecRF+"%"+
    //     vecRL+"%"+vecGAV1+"%"+vecGAV2+"%"+unituK+"%"+deruK+"%"+gst["K"]+"%"+T+
    //     "%"+vecVGO+"%"+vecRGO+"%"+_integrals["Av"]+"%"+_integrals["Bvs"]+
    //     "%"+_integrals["Bvc"]+"%"+_integrals["Ar"]+"%"+_integrals["Br"] to "0:/peg_control.log".
    return gst.
}

function peg_get_burnvec {
    parameter tt.
    parameter gst.

    local omega to gst["deruK"]:mag.
    return gst["unituK"] * cos(omega*(tt-gst["K"]) *180/constant:pi) + gst["deruK"]/omega * sin(omega*(tt-gst["K"]) *180/constant:pi).
}