set __TERMINAL_g0 to ship:body:mu / ship:body:radius^2.
set __TERMINAL_PID_throttle to pidLoop(0.5, 0.01, 0.01).

function terminal_finalize {
    unset __TERMINAL_g0.
    unset __TERMINAL_PID_throttle.
}

function __terminal_max_vertical_acc {
    parameter fvec.
    parameter facc.
    local _fr to vdot(fvec, up:forevector).
    return facc * _fr - __TERMINAL_g0.
}

function __terminal_target_vertical_v {
    parameter height.
    parameter fvec.
    parameter facc.
    return -sqrt(2*max(0, height)*__terminal_max_vertical_acc(fvec, facc)).
}

function terminal_get_fvec {
    // keep pitch > 30 deg
    local __tanalpha to min(0.577, 1.0 * ship:groundspeed / (abs(ship:verticalspeed) + 0.001)).
    local __horizontalvec to vxcl(up:forevector, srfRetrograde:forevector):normalized.
    return __horizontalvec * __tanalpha + up:forevector.
}

function terminal_time_to_fire {
    parameter height.
    parameter fvec.
    parameter m0.
    parameter f0.
    parameter std_throttle.
    return ship:verticalspeed <= __terminal_target_vertical_v(height, fvec, f0/m0*std_throttle).
}

function terminal_step_control {
    parameter height.
    parameter fvec.
    parameter m0.
    parameter f0.
    parameter thro_min.
    parameter thro_max.
    parameter std_throttle.

    local thro_plan to 0.
    local fvec_plan to v(0,0,0).
    local _targetV to __terminal_target_vertical_v(height, fvec, f0/m0*std_throttle).
    if (ship:groundspeed < 0.02 and height < 3) {
        set thro_plan to __TERMINAL_PID_throttle:update(time:seconds, ship:verticalspeed-_targetV).
        set fvec_plan to up:forevector.
    }
    else {
        set thro_plan to __TERMINAL_PID_throttle:update(time:seconds, ship:verticalspeed-_targetV-ship:groundspeed*0.3).
        set fvec_plan to terminal_get_fvec().
    }
    set thro_plan to max(thro_min, min(thro_max, thro_plan)).
    return list(fvec_plan, thro_plan).
}