parameter P_NOWAIT is false.
parameter P_ALLOW_RESTART is true.
parameter P_ENGINE is "current".
clearScreen.
print "PEG landing guidance" AT(0,0).
print "============= Configuration ============" AT(0,1).
print "================ State =================" AT(0,11).
print "================ Result ================" AT(0,21).

// line 1~10: target position
// line 11~20: guidance state

runOncePath("./lib/engine_utility.ks").
function print_engines_simple_info {
    parameter elist.
    local _summary to get_engines_info(elist).
    for e in elist {
        print e:tag + " " + e:title.
    }
    print "Thrust = " + _summary:thrust AT(0,2).
    print "Isp = " + _summary:ISP AT (0,3).
    print "Minthrottle = " + _summary:minthrottle AT(0,4).
    print "Ullage = " + _summary:ullage AT(0,5).
}
set done to false.
if P_ENGINE = "auto" {
    when engine_stage_check() then {
        stage.
        set elist to get_active_engines().
        set enginfo to get_engines_info(elist).
        return (not done).
    }
    wait 0.1.  // wait for staging
    print "Engine autostaging.".
    set elist to get_active_engines().
}
else if P_ENGINE = "current" {
    set elist to get_active_engines().
}
else {
    set elist to search_engine(P_ENGINE).
}
set enginfo to get_engines_info(elist).
print_engines_simple_info(elist).

set mu to ship:body:mu.
set Rm to ship:body:radius.
set g0 to mu / ship:body:radius^2.

function exp {
    parameter x.
    return constant:e ^ x.
}

function _get_angle {
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

function _orbital_r_at_theta {
    parameter sma.
    parameter ecc.
    parameter theta.
    return sma * (1 - ecc ^ 2) / (1 + ecc * cos(theta)).
}

function _orbital_v_at_theta {
    parameter sma.
    parameter ecc.
    parameter theta.
    return sqrt(mu/(sma*(1-ecc^2)) * (1+2*ecc*cos(theta)+ecc^2)).
}

function _orbital_vr_at_theta {
    parameter sma.
    parameter ecc.
    parameter theta.
    return sqrt(mu/(sma*(1-ecc^2))) * ecc * sin(theta).
}

function _orbital_vt_at_theta {
    parameter sma.
    parameter ecc.
    parameter theta.
    return sqrt(mu/(sma*(1-ecc^2))) * (1 + ecc * cos(theta)).
}

function _get_racc {
    parameter _rr.
    parameter _vtheta.
    return mu/_rr^2 - _vtheta^2/_rr.
}

function _theta_to_time {
    parameter sma.
    parameter ecc.
    parameter thetaT.
    parameter t0.
    parameter theta0.

    set theta0 to mod(theta0+360, 360).
    set thetaT to mod(thetaT+360, 360).
    if (thetaT < theta0) {
        set thetaT to thetaT + 360.
    }
    local r0 to _orbital_r_at_theta(sma, ecc, theta0).
    local dt to 1.  // interval time
    local coef to sqrt(mu/sma/(1-ecc^2)).
    local _theta to theta0.
    local _tt to t0.
    local rr to r0.
    until (_theta >= thetaT) {
        local dtheta to dt * coef * (ecc * cos(_theta) + 1) / rr * 180 / constant:pi.
        local dr to dt * coef * ecc * sin(_theta).
        set _theta to mod(_theta + dtheta, 360).
        set rr to rr + dr.
        set _tt to _tt + dt.
        print "Integral: dt = " + round(_tt-t0) + ", theta = " + round(_theta) + ", thetaT =  " + round(thetaT) + "     " AT(0, 13).
    }
    return _tt.
}

// ship and target parameters
set m0 to ship:mass.
set f0 to enginfo:thrust.
set ve to enginfo:ISP * 9.81.
set thro_min to enginfo:minthrottle.
set std_throttle to (max(0.90, thro_min) + 1) / 2.

// when stage, update engine information
on stage:number {
    set elist to get_active_engines().
    set enginfo to get_engines_info(elist).
    set f0 to enginfo:thrust.
    set ve to enginfo:ISP * 9.81.
    set thro_min to enginfo:minthrottle.
    set std_throttle to (max(0.90, thro_min) + 1) / 2.
    print_engines_simple_info(elist).
    return true.
}

set sma to ship:orbit:semimajoraxis.
set ecc to ship:orbit:eccentricity.
set theta to ship:orbit:trueanomaly.

set __raxis to up:forevector.
set __haxis to vcrs(__raxis, ship:velocity:orbit):normalized.
set __taxis to vcrs(__haxis, __raxis):normalized.

if (not addons:tr:available) {
    print "trajectories not available".
    print 1/0.
}
if (not addons:tr:hastarget) {
    print "no target point".
    print 1/0.
}
set target_geo to addons:tr:gettarget.
set RTtrue to (target_geo:position-ship:body:position):mag.
set RT to RTtrue + 150.  // descent phase target
set VRTtrue to 0.
set VRT to VRTtrue - 3.  // descent phase target
set THETA_T to theta + _get_angle(__raxis, __haxis, __taxis, target_geo:position-ship:body:position).
print "Target position: " + target_geo AT(0,6).

// control parameters
set Ka to 5. // throttle gain

function _get_attitude {
    parameter fr.
    parameter ft.
    parameter fh.
    
    local fvec to fr * _raxis + ft * _taxis + fh * _haxis.
    local tdvect to lookDirUp(fvec, up:forevector). // facedown
    return tdvect.
}

function get_initial_params {
    // initial parameters
    local T to 0.
    local A to 0.
    local B to 0.
    local theta0 to 0.
    // initial guess
    local a0 to f0/m0 * std_throttle.
    local tau to ve/a0.
    set T to tau*(1-exp(-_orbital_v_at_theta(sma, ecc, THETA_T)/ve)).
    local _amean to a0/(1-T/tau/2).
    local _distance to 0.5 * _amean * T ^ 2.
    local dtheta to _distance / Rm * 180 / constant:pi.
    set theta0 to THETA_T - dtheta.
    local _discount to 1.
    local num_iter to 0.
    until false {
        local r0 to _orbital_r_at_theta(sma, ecc, theta0).
        local vr0 to _orbital_vr_at_theta(sma, ecc, theta0).
        local vt0 to _orbital_vt_at_theta(sma, ecc, theta0).
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
        local _fdotr_0 to A + _get_racc(r0, vt0) / a0.
        local _fdott_0 to -sqrt(1-_fdotr_0^2).
        local _a_mid to a0 / (1-T/tau/2).
        local _vt_mid to vt0 - _fdott_0 * ve * ln(1-T/tau/2).
        local _fdotr_mid to A + B*T/2 + _get_racc(r_mean, _vt_mid) / _a_mid.
        local _fdott_mid to -sqrt(1-_fdotr_mid^2).

        set dtheta to (vt0/r0*T + _fdott_mid * c0 / r_mean) * 180 / constant:pi.
        set theta0 to THETA_T - dtheta.

        local dv to -r0*vt0/r_mean / _fdott_mid.  // zero-order middle approximation
        local _deltaT to _discount * (tau * (1 - exp(-dv/ve)) - T).
        set T to T + _deltaT.
        set num_iter to num_iter + 1.
        print "Iter " + num_iter + ", T = " + round(T) + ", dv = "+ round(dv) + "     " AT(0,14).
        print "dtheta = " + round(dtheta) + ", A = " + round(A, 3) + ", B = " + round(B, 3) + "     " AT(0,15).
        if abs(_deltaT) < 0.005 {
            break.
        }
    }
    return LIST(T, A, B, theta0).
}

function step_control {
    parameter r0.
    parameter vr0.
    parameter theta0.
    parameter theta10.
    parameter m0.
    parameter tt.
    parameter T.
    parameter A.
    parameter B.
    parameter num_iter.
    
    set T to T - tt.
    local throttle_target to 0.
    if (T < 10) {
        return LIST(A+B*tt, B, T, std_throttle).
    }
    local a0 to f0/m0 * std_throttle.
    local tau to ve/a0.
    local vt0 to theta10 * r0.
    
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
    local _fdotr_0 to A + _get_racc(r0, vt0) / a0.
    local _fdott_0 to -sqrt(1-_fdotr_0^2).
    local _a_mid to a0 / (1-T/tau/2).
    local _vt_mid to vt0 - _fdott_0 * ve * ln(1-T/tau/2).
    local _fdotr_mid to A + B*T/2 + _get_racc(r_mean, _vt_mid) / _a_mid.
    local _fdott_mid to -sqrt(1-_fdotr_mid^2).
    local dv to -r0*vt0/r_mean / _fdott_mid.  // zero-order middle approximation
    set T to tau * (1 - exp(-dv/ve)).

    local dtheta to (vt0/r0*T + _fdott_mid * c0 / r_mean) * 180 / constant:pi.
    local dtheta_real to THETA_T - theta0.

    set throttle_target to max(thro_min, min(1, std_throttle * (1 + Ka*(dtheta - dtheta_real) / dtheta_real))).

    print "Iter: "+ num_iter+", T = " + round(T-tt) + ", dv = " + round(-ve*ln(1-T/tau)) + "     " AT(0,14).
    print "A = " + round(A, 3) + ", thro = " + round(throttle_target, 3) + ", E = " + round(dtheta-dtheta_real, 4) + "    " AT(0,15).

    return LIST(A, B, T, throttle_target).
}

function phase_descent {
    print "Preparing guidance...                      " AT(0,12).
    local __init_params to get_initial_params().
    local T to __init_params[0].
    local A to __init_params[1].
    local B to __init_params[2].
    local theta0 to __init_params[3].
    
    local ignition_time to time:seconds.
    if not P_NOWAIT {set ignition_time to _theta_to_time(sma, ecc, theta0, time:seconds, ship:orbit:trueanomaly).}
    print "Calculate converged, wating for ignition..." AT(0,12).
    when (true) then {
        print "Time to ignition: " + round(ignition_time - time:seconds) + ", eta = " + round(ship:orbit:trueanomaly) + "->" + round(theta0) AT(0,13).
        if (time:seconds >= ignition_time) {return false.}  // end trigger
        return true.
    }
    local _ullage_time to 0.
    if enginfo:ullage {set _ullage_time to 2.}
    
    wait until time:seconds >= ignition_time - 60.
    print "Aligning to target...                      " AT(0,12).
    lock _raxis to up:forevector.
    lock _haxis to vcrs(_raxis, ship:velocity:surface):normalized.
    lock _taxis to vcrs(_haxis, _raxis):normalized.
    lock rrr to ship:body:position:mag.
    lock vr to ship:verticalspeed.
    lock theta to THETA_T - _get_angle(_raxis, _haxis, _taxis, target_geo:position-ship:body:position).
    lock theta1 to vxcl(up:forevector, ship:velocity:surface):mag / rrr.
    lock acc to f0/ship:mass * std_throttle.
    lock frcomp to max(0, min(1, A + _get_racc(rrr, theta1*rrr)/acc)).
    local _fhcomp_pid to pidLoop(5, 0.05, 0.03, -0.1, 0.1).
    set _fhcomp_pid:setpoint to 0.
    local fhcomp to 0.
    lock ftcomp to -sqrt(1-frcomp^2-fhcomp^2).
    lock __target_attitude to _get_attitude(frcomp, ftcomp, fhcomp).
    lock steering to __target_attitude.
    RCS ON.
    wait until time:seconds >= ignition_time - _ullage_time.
    print "Braking start.                             " AT(0,12).
    activate_engines(elist).
    local _time_begin to time:seconds.
    lock tt to time:seconds - _time_begin.
    lock frcomp to max(0, min(1, A + B*tt + _get_racc(rrr, theta1*rrr)/acc)).
    local throttle_target to std_throttle.
    lock throttle to throttle_target.

    local num_iter to 0.
    local _old_ground_speed to ship:groundspeed.
    until (T - tt < 0 or rrr < RT) {
        local __new_control to step_control(rrr, vr, theta, theta1, ship:mass, tt, T, A, B, num_iter).
        set A to __new_control[0].
        set B to __new_control[1].
        set T to __new_control[2].
        set _time_begin to time:seconds.
        set fhcomp to _fhcomp_pid:update(time:seconds, -vdot(target_geo:position:normalized, _haxis)).
        set throttle_target to __new_control[3].
        set num_iter to num_iter + 1.
        if T < 10 and (ship:groundspeed / (abs(ship:verticalspeed) + 0.001) < 1.5 or (ship:groundspeed > _old_ground_speed)) {
        // if T < 10 and (ship:verticalspeed / (abs(ship:airspeed) + 0.001) > vdot(ship:facing:vector, up:vector) or (ship:groundspeed > _old_ground_speed)) {
            // low energy cutoff
            break.
        }
        set _old_ground_speed to ship:groundspeed.
    }
}

function get_max_vertical_acc {
    local _fr to vdot(steering:forevector, up:forevector).
    local _acc to std_throttle * f0 / ship:mass * _fr.
    return _acc - g0.
}

function get_target_vertical_v {
    return sqrt(2*max(0,ship:bounds:bottomaltradar)*get_max_vertical_acc()).
}

function _phase_final_get_attitude {
    // keep pitch > 30 deg
    local __tanalpha to min(0.577, 1.2 * ship:groundspeed / (abs(ship:verticalspeed) + 0.001)).
    local __horizontalvec to vxcl(up:forevector, srfRetrograde:forevector):normalized.
    return lookDirUp(__horizontalvec * __tanalpha + up:forevector, sun:position).
}

function phase_final {
    // final phase have no targeting, just reduce lateral speed and land.
    if (P_ALLOW_RESTART) {
        lock throttle to 0.
        if (enginfo:ullage) {set ship:control:fore to 0.5.}
    }
    else {lock throttle to thro_min.}
    print "Final phase.                               " AT(0,12).
    lock steering to _phase_final_get_attitude().
    // vecDraw(v(0,0,0), {return steering:forevector*20.}, RGB(0, 255, 0), "attitude", 1, true).
    local bound_box to ship:bounds.
    lock _targetV to get_target_vertical_v() * (max(thro_min, 0.7) + 1) / 2.
    wait until (-ship:verticalspeed) >= _targetV and vang(ship:facing:forevector, steering:forevector) < 40.
    local mythrott to std_throttle.
    lock throttle to mythrott.
    set ship:control:fore to 0.
    local PID_throttle to pidLoop(0.5, 0.01, 0.01, thro_min, 1).
    set done to false.
    when (bound_box:bottomaltradar < 0.1 or abs(ship:verticalspeed) < 0.1) then {
        set done to true.
        return false.
    }
    until (ship:groundspeed < 0.02 and bound_box:bottomaltradar < 3) or done {
        set mythrott to PID_throttle:update(time:seconds, ship:verticalspeed+_targetV-ship:groundspeed).
    }
    print "Touchdown..." AT(0,22).
    lock steering to lookDirUp(up:vector, sun:position).
    until done {
        set mythrott to PID_throttle:update(time:seconds, ship:verticalspeed+_targetV).
    }
    lock throttle to 0.
    wait until bound_box:bottomaltradar < 0.1.
    wait 0.2.
    unlock steering.
    unlock _targetV.
}

phase_descent().
phase_final().
print "Landing completed." AT(0,22).
print "Target distance: " + round(target_geo:position:mag, 2) + " m" AT(0,23).