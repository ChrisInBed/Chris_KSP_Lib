set __TERMINAL_g0 to ship:body:mu / ship:body:radius^2.
set __TERMINAL_uplock to false.
set __TERMINAL_thro_PID to pidLoop(1, 0.01, 0).

function terminal_init {
    set __TERMINAL_g0 to ship:body:mu / ship:body:radius^2.
    set __TERMINAL_uplock to false.
    set __TERMINAL_thro_PID to pidLoop(1, 0.01, 0).
}

function __terminal_get_deltar {
    parameter vrT.
    parameter af1, af2, T2.

    set af1 to af1 - __TERMINAL_g0.
    set af2 to af2 - __TERMINAL_g0.
    local v0 to ship:velocity:surface:mag.
    local vr0 to ship:verticalspeed.
    if (vr0 >= 0) return list(0, 0).  // start only in falling
    local deltar to 0.
    local _stage to 0.
    // judge stage 1 or stage 2
    if (vr0 + af2*T2) >= vrT {
        set _stage to 2.
        set deltar to (vrT*vrT - vr0*vr0) * 0.5 / af2.
    }
    else {
        set _stage to 1.
        local _deltar2 to vrT*T2 - 0.5*af2*T2*T2.
        set vrT to vrT - af2*T2.
        local tc to v0 / __TERMINAL_g0 / (1 - vr0 / (v0+0.001)).
        local _uc to af1*tc*(1+vr0/v0)/2.
        local _T to (vrT-vr0+_uc)/af1.
        set deltar to vr0*_T + af1*_T^2/2 - _uc*(_T - tc/3) + _deltar2.
    }
    // print "deltar=" + round(deltar, 3) + " stage=" + _stage AT(0, 13).

    return list(_stage, deltar).
}

function terminal_get_fvec {
    // keep pitch > 45 deg
    local __tanalpha to 1.0.
    if (ship:verticalspeed < 0) {
        set __tanalpha to min(1.0, 1.0 * ship:groundspeed / (abs(ship:verticalspeed) + 0.001)).
    }
    local __horizontalvec to vxcl(up:forevector, srfRetrograde:forevector):normalized.
    return __horizontalvec * __tanalpha + up:forevector.
}

function terminal_time_to_fire {
    parameter height.
    parameter vrT.
    parameter af1, af2, T2.
    if (ship:verticalspeed >= 0) return false.  // start only in falling
    return height + __terminal_get_deltar(vrT, af1, af2, T2)[1] < 0.
}

function terminal_step_control {
    parameter height.
    parameter vrT.
    parameter m0.
    parameter f0.
    parameter thro_min.
    parameter thro_max.
    parameter std_throttle.
    parameter final_throttle, T2.

    local thro_plan to std_throttle.
    local fvec_plan to v(0,0,0).
    local _fullacc to f0 / m0.
    local _res to __terminal_get_deltar(vrT, std_throttle*_fullacc, final_throttle*_fullacc, T2).
    local _throttle_target to final_throttle.
    if _res[0] = 1 {set _throttle_target to std_throttle.}
    local deltar to _res[1].
    if (__TERMINAL_uplock or (ship:groundspeed < 0.1 and height < 3)) {
        set __TERMINAL_uplock to true.
        set thro_plan to _throttle_target * (1 + __TERMINAL_thro_PID:update(time:seconds, 1+deltar/max(height, 0.01))).
        set fvec_plan to up:forevector.
    }
    else {
        set thro_plan to _throttle_target * (1 + __TERMINAL_thro_PID:update(time:seconds, 1+deltar/max(height, 0.01))).
        set fvec_plan to terminal_get_fvec().
    }
    set thro_plan to max(thro_min, min(thro_max, thro_plan)).
    return list(fvec_plan, thro_plan).
}