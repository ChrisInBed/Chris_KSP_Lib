runOncePath("0:/lib/chrismath.ks").
runOncePath("0:/lib/orbit.ks").  // orbit prediction and calculations

set __PEG_Ka to 5. // P gain for throttle control
set __PEG_mu to ship:body:mu.

function peg_finalize {
    unset __PEG_Ka.
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
    parameter THETA_T.
    parameter VTT.
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

        local r_mean to (r0+RT) / 2.
        local _fdotr_0 to A + __peg_get_racc(r0, vt0) / a0.
        local _fdott_0 to -sqrt(1-_fdotr_0^2).
        local _a_mid to a0 / (1-T/tau/2).
        local _vt_mid to vt0 - _fdott_0 * ve * ln(1-T/tau/2).
        local _fdotr_mid to A + B*T/2 + __peg_get_racc(r_mean, _vt_mid) / _a_mid.
        local _fdott_mid to -sqrt(1-_fdotr_mid^2).

        set dtheta to (vt0/r0*T + _fdott_mid * c0 / r_mean) * 180 / constant:pi.
        set theta0 to THETA_T - dtheta.

        local dv to (RT*VTT-r0*vt0)/r_mean / _fdott_mid.  // zero-order middle approximation
        local _deltaT to _discount * (tau * (1 - exp(-dv/ve)) - T).
        set T to T + _deltaT.
        set num_iter to num_iter + 1.
        if abs(_deltaT) < 0.005 {
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
    parameter std_throttle.
    parameter ve.
    parameter T.
    parameter A.
    parameter B.
    parameter RT.
    parameter VRT.
    parameter THETA_T.
    parameter VTT.
    
    set T to T - tt.
    if (T < 10) {
        return LIST(A+B*tt, B, T, std_throttle, 0).
    }
    local a0 to f0/m0 * std_throttle.
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

    local r_mean to (r0+RT) / 2.
    local _fdotr_0 to A + __peg_get_racc(r0, vt0) / a0.
    local _fdott_0 to -sqrt(1-_fdotr_0^2).
    local _a_mid to a0 / (1-T/tau/2).
    local _vt_mid to vt0 - _fdott_0 * ve * ln(1-T/tau/2).
    local _fdotr_mid to A + B*T/2 + __peg_get_racc(r_mean, _vt_mid) / _a_mid.
    local _fdott_mid to -sqrt(1-_fdotr_mid^2).
    local dv to (RT*VTT-r0*vt0)/r_mean / _fdott_mid.  // zero-order middle approximation
    set T to tau * (1 - exp(-dv/ve)).

    local dtheta to (vt0/r0*T + _fdott_mid * c0 / r_mean) * 180 / constant:pi.
    local dtheta_real to THETA_T - theta0.
    local theta_error to dtheta - dtheta_real.

    local throttle_target to max(thro_min, min(thro_max, std_throttle * (1 + __PEG_Ka*theta_error / dtheta_real))).
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