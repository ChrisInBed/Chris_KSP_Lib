runOncePath("0:/lib/chrismath.ks").
runOncePath("0:/lib/orbit.ks").  // orbit prediction and calculations

// set __PEG_Ka to 1.
set __PEG_thro_pid to pidLoop(3, 0.1, 0.05).
set __PEG_mu to ship:body:mu.

function peg_finalize {
    // unset __PEG_Ka.
    unset __PEG_thro_pid.
    unset __PEG_mu.
}

function __peg_get_angle {
    parameter _r0axis.
    parameter _h0axis.
    parameter _t0axis.
    parameter _pos.
    local _ang to vang(vxcl(_h0axis, _pos), _r0axis).
    if (vdot(vxcl(_h0axis, _pos), _t0axis) < 0) {
        set _ang to -_ang.
    }
    return _ang.
}

function __peg_get_racc {
    parameter _rr.
    parameter _vtheta.
    return __PEG_mu/_rr^2 - _vtheta^2/_rr.
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
    parameter sma.
    parameter ecc.
    parameter mu.
    parameter a0.
    parameter ve.
    parameter RT.
    parameter VRT.
    parameter VTT.
    parameter THETA_T.
    // initial parameters
    local T to 0.
    local A to 0.
    local B to 0.
    local theta0 to 0.
    // initial guess
    local tau to ve/a0.
    local _tgt_v to sqrt(VTT^2 + VRT^2).
    set T to tau*(1-exp(-abs(get_orbit_v_at_theta(sma, ecc, THETA_T, mu) - _tgt_v)/ve)).
    local _amean to a0/(1-T/tau/2).
    local _distance to VTT * T + 0.5 * _amean * T ^ 2.
    local dtheta to _distance / RT * 180 / constant:pi.
    set theta0 to THETA_T - dtheta.
    local _discount to 1.
    local num_iter to 0.
    until num_iter > 2000 {
        local r0 to get_orbit_r_at_theta(sma, ecc, theta0).
        local vr0 to get_orbit_vr_at_theta(sma, ecc, theta0, mu).
        local vt0 to get_orbit_vt_at_theta(sma, ecc, theta0, mu).
        // integral coefficients
        local b0 to -ve*ln(1-T/tau).
        local b1 to b0*tau - ve*T.
        // local b2 to b1*tau - ve*T^2/2.
        local c0 to b0*T - b1.
        local c1 to c0*tau - ve*T^2/2.
        // local c2 to c1*tau - ve*T^3/6.

        local error_r to RT - (r0 + vr0*T).
        local error_vr to VRT - vr0.
        set A to (error_vr/b1 - error_r/c1) / (b0/b1 - c0/c1).
        set B to (error_vr - A*b0) / b1.

        // first-order approximation
        // local r_mean to (r0+RT) / 2.
        // local _fdotr_0 to max(-1, min(1, A + __peg_get_racc(r0, vt0) / a0)).
        // local _ft0 to -sqrt(1-_fdotr_0^2).
        // local _accT to a0 / (1-T/tau).
        // local _fdotr_T to max(-1, min(1, A + B*T + __peg_get_racc(RT, VTT) / _accT)).
        // local _fdott_T to -sqrt(1-_fdotr_T^2).
        // local _ft1 to (_fdott_T-_ft0)/T.
        // set dtheta to (vt0/r0*T + (_ft0*c0+_ft1*c1) / r_mean) * 180 / constant:pi.
        // local dv to ((VTT/RT-vt0/r0)*r_mean + _ft1*ve*T)/(_ft0+_ft1*tau).

        // zero-order midpoint approximation
        local r_mean to (r0+RT) / 2.
        local _fdotr_0 to max(-1, min(1, A + __peg_get_racc(r0, vt0) / a0)).
        local _fdott_0 to -sqrt(1-_fdotr_0^2).
        local _a_mid to a0 / (1-T/tau/2).
        local _vt_mid to vt0 - _fdott_0 * ve * ln(1-T/tau/2).
        local _fdotr_mid to max(-1, min(1, A + B*T/2 + __peg_get_racc(r_mean, _vt_mid) / _a_mid)).
        local _fdott_mid to -sqrt(1-_fdotr_mid^2).
        set dtheta to (vt0/r0*T + _fdott_mid * c0 / r_mean) * 180 / constant:pi.
        local dv to (RT*VTT-r0*vt0)/r_mean / _fdott_mid.

        set theta0 to THETA_T - dtheta.
        local _deltaT to _discount * (tau * (1 - exp(-dv/ve)) - T).
        set T to T + _deltaT.
        set num_iter to num_iter + 1.
        if abs(_deltaT) < 0.001 {
            break.
        }
    }
    return LIST(T, A, B, theta0, num_iter).
}

function peg_step_control{
    parameter tt.
    parameter r0.
    parameter vr0.
    parameter theta0.
    parameter vt0.
    parameter m0.
    parameter f0.
    parameter thro_min.
    parameter thro_max.
    parameter throttle_target.
    parameter ve.
    parameter T.
    parameter A.
    parameter B.
    parameter RT.
    parameter VRT.
    parameter VTT.
    parameter THETA_T.
    
    set T to T - tt.
    if (T < 10) {
        return LIST(A+B*tt, B, T, throttle_target, 0).
    }
    local a0 to f0/m0 * throttle_target.
    local tau to ve/a0.
    
    local b0 to -ve*ln(1-T/tau).
    local b1 to b0*tau - ve*T.
    // local b2 to b1*tau - ve*T^2/2.
    local c0 to b0*T - b1.
    local c1 to c0*tau - ve*T^2/2.
    // local c2 to c1*tau - ve*T^3/6.

    local error_r to RT - (r0 + vr0*T).
    local error_vr to VRT - vr0.
    set A to (error_vr/b1 - error_r/c1) / (b0/b1 - c0/c1).
    set B to (error_vr - A*b0) / b1.

    // first-order approximation
    // local r_mean to (r0+RT) / 2.
    // local _fdotr_0 to max(-1, min(1, A + __peg_get_racc(r0, vt0) / a0)).
    // local _ft0 to -sqrt(1-_fdotr_0^2).
    // local _accT to a0 / (1-T/tau).
    // local _fdotr_T to max(-1, min(1, A + B*T + __peg_get_racc(RT, VTT) / _accT)).
    // local _fdott_T to -sqrt(1-_fdotr_T^2).
    // local _ft1 to (_fdott_T-_ft0)/T.
    // local dtheta to (vt0/r0*T + (_ft0*c0+_ft1*c1) / r_mean) * 180 / constant:pi.
    // local dv to ((VTT/RT-vt0/r0)*r_mean + _ft1*ve*T)/(_ft0+_ft1*tau).

    // zero-order midpoint approximation
    local r_mean to (r0+RT) / 2.
    local _fdotr_0 to max(-1, min(1, A + __peg_get_racc(r0, vt0) / a0)).
    local _fdott_0 to -sqrt(1-_fdotr_0^2).
    local _a_mid to a0 / (1-T/tau/2).
    local _vt_mid to vt0 - _fdott_0 * ve * ln(1-T/tau/2).
    local _fdotr_mid to max(-1, min(1, A + B*T/2 + __peg_get_racc(r_mean, _vt_mid) / _a_mid)).
    local _fdott_mid to -sqrt(1-_fdotr_mid^2).
    local dtheta to (vt0/r0*T + _fdott_mid * c0 / r_mean) * 180 / constant:pi.
    local dv to (RT*VTT-r0*vt0)/r_mean / _fdott_mid.

    set T to tau * (1 - exp(-dv/ve)).
    local dtheta_real to THETA_T - theta0.
    local theta_error to dtheta - dtheta_real.

    // // full iteration including throttle
    // if (dtheta_real < 0) {
    //     // If the target is behind, use max throttle.
    //     set throttle_target to thro_max.
    // }
    // else {
    //     // First-order approximation
    //     // set c0 to (r_mean*(dtheta_real/180*constant:pi-vt0/r0*T) + 0.5*_ft1*ve*T^2) / (_ft0+_ft1*tau).
    //     // set tau to T + (ve*T - c0) / b0.
    //     // set throttle_target to max(thro_min, min(thro_max, m0*ve/f0/tau)).

    //     // zero-order midpoint approximation
    //     set c0 to r_mean*(dtheta_real/180*constant:pi-vt0/r0*T) / _fdott_mid.
    //     set tau to T + (ve*T - c0) / b0.
    //     set throttle_target to max(thro_min, min(thro_max, m0*ve/f0/tau)).
    // }
    
    // simple P control
    // set throttle_target to max(thro_min, min(thro_max, throttle_target * (1 + __PEG_Ka*(dtheta - dtheta_real) / dtheta_real))).

    // PID control
    set throttle_target to max(thro_min, min(thro_max, throttle_target + __PEG_thro_pid:update(time:seconds, (dtheta_real-dtheta)/dtheta_real))).

    return LIST(A, B, T, throttle_target, theta_error).
}

function peg_get_frcomp {
    parameter tt.
    parameter rr.
    parameter vtheta.
    parameter acc.
    parameter A.
    parameter B.

    return max(0, min(1, A + B*tt + __peg_get_racc(rr, vtheta)/acc)).
}