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
    parameter af.

    local v0 to ship:velocity:surface:mag.
    local vr0 to ship:verticalspeed.
    if (vr0 >= 0) return 0.  // start only in falling
    local tc to v0 / __TERMINAL_g0 / (1 - vr0 / (v0+0.001)).
    local _uc to af*tc*(1+vr0/v0)/2.
    local _T to (vrT-vr0+_uc)/(af-__TERMINAL_g0).
    local deltar to vr0*_T + (af-__TERMINAL_g0)*_T^2/2 - _uc*(_T - tc/3).

    return deltar.
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
    parameter m0.
    parameter f0.
    parameter std_throttle.
    return height + __terminal_get_deltar(vrT, std_throttle*f0/m0) < 0.
}

function terminal_step_control {
    parameter height.
    parameter vrT.
    parameter m0.
    parameter f0.
    parameter thro_min.
    parameter thro_max.
    parameter std_throttle.

    local thro_plan to std_throttle.
    local fvec_plan to v(0,0,0).
    local deltar to __terminal_get_deltar(vrT, std_throttle*f0/m0).
    if (__TERMINAL_uplock or (ship:groundspeed < 0.1 and height < 3)) {
        set __TERMINAL_uplock to true.
        set thro_plan to std_throttle * (1 + __TERMINAL_thro_PID:update(time:seconds, 1+deltar/max(height, 0.01))).
        set fvec_plan to up:forevector.
    }
    else {
        set thro_plan to std_throttle * (1 + __TERMINAL_thro_PID:update(time:seconds, 1+deltar/max(height, 0.01))).
        set fvec_plan to terminal_get_fvec().
    }
    set thro_plan to max(thro_min, min(thro_max, thro_plan)).
    return list(fvec_plan, thro_plan).
}