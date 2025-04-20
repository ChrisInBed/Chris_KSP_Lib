parameter P_NOWAIT is false.
parameter P_ENGINE is "current".
clearScreen.
print "PEG landing guidance" AT(0,0).
print "============= Configuration ============" AT(0,1).
print "================ State =================" AT(0,11).
print "================ Result ================" AT(0,21).

// line 1~10: target position
// line 11~20: guidance state

runOncePath("0:/lib/landlib/peg.ks").
runOncePath("0:/lib/landlib/quadratic.ks").
runOncePath("0:/lib/landlib/terminal.ks").
runOncePath("0:/lib/engine_utility.ks").

set __gap_throttle to 0.  // between phases, throttle will be locked to this value

function print_engines_simple_info {
    parameter elist.
    local _summary to get_engines_info(elist).
    print "Thrust = " + round(_summary:thrust, 2) + "kN       " AT(0,2).
    print "Isp = " + round(_summary:ISP, 1) + "s       " AT (0,3).
    print "Minthrottle = " + round(_summary:minthrottle, 2) + "       " AT(0,4).
    print "Ullage = " + _summary:ullage + "   " AT(0,5).
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

function set_engine_parameters {
    parameter elist.
    set enginfo to get_engines_info(elist).
    set f0 to enginfo:thrust.
    set ve to enginfo:ISP * 9.81.
    set thro_min to enginfo:minthrottle.
    set std_throttle to (max(0.90, thro_min) + 1) / 2.
    set final_std_throttle to (max(0.60, thro_min) * 2 + 1) / 3.
    print_engines_simple_info(elist).
}
set_engine_parameters(elist).

set mu to ship:body:mu.
set Rm to ship:body:radius.
set g0 to mu / ship:body:radius^2.

set sma to ship:orbit:semimajoraxis.
set ecc to ship:orbit:eccentricity.
set eta0 to ship:orbit:trueanomaly.

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
function set_descent_phase_target {
    set desRT to (target_geo:position-ship:body:position):mag + 100.  // 100 m above ground
    set desVRT to -8.  // 8 m/s downward
    set THETA_T to eta0 + __peg_get_angle(__raxis, __haxis, __taxis, target_geo:position-ship:body:position).
    set desTHETA_T to THETA_T - 500/Rm*180/constant:pi.  // 500 m before target
    set desVTT to 40.  // 40 m/s lateral speed
    print "Target position: " + target_geo AT(0,6).
}
set_descent_phase_target().
function set_approach_phase_target {
    set appRT to V(0, 0, 0).  //
    set appVT to V(0, 0, -0.2). // 0.2 m/s downward
    set appAT to V(0, 0, 0). // no acceleration
    set appJx to 0.  // no Jerk
}
set_approach_phase_target().

// action group 10 is for reset engine and target information
// staging can also update engine information
on ("0"+ag10+stage:number) {
    set_engine_parameters(get_active_engines()).
    set target_geo to addons:tr:gettarget.
    set_descent_phase_target().
    set_approach_phase_target().
    return true.
}

function phase_descent {
    print "Preparing guidance...                      " AT(0,12).
    local a0 to f0/ship:mass * std_throttle.
    local __init_params to peg_get_initial_params(sma, ecc, mu, a0, ve, desRT, desVRT, desTHETA_T, desVTT).
    local T to __init_params[0].
    local A to __init_params[1].
    local B to __init_params[2].
    local theta0 to __init_params[3].
    local init_num_iter to __init_params[4].
    print "Iter " + init_num_iter + ", T = " + round(T) + ", dv = "+ round(__peg_get_dv(a0, ve, T)) + "     " AT(0,14).
    print "dtheta = " + round(theta0 - eta0) + ", A = " + round(A, 3) + ", B = " + round(B, 3) + "     " AT(0,15).
    
    local ignition_time to time:seconds.
    if not P_NOWAIT {set ignition_time to get_time_to_theta(sma, ecc, mu, time:seconds, ship:orbit:trueanomaly, theta0).}
    print "Calculate converged, wating for ignition..." AT(0,12).
    when (true) then {
        print "Time to ignition: " + round(ignition_time - time:seconds) + ", eta = " + round(ship:orbit:trueanomaly) + "->" + round(theta0) + "  " AT(0,13).
        if (time:seconds >= ignition_time) {return false.}  // end trigger
        return true.
    }
    local _ullage_time to 0.
    if enginfo:ullage {set _ullage_time to 2.}
    
    wait until time:seconds >= ignition_time - 60.
    print "Aligning to target...                      " AT(0,12).
    lock lo_raxis to up:forevector.
    lock lo_haxis to vcrs(lo_raxis, ship:velocity:surface):normalized.
    lock lo_taxis to vcrs(lo_haxis, lo_raxis):normalized.
    lock lo_r to ship:body:position:mag.
    lock lo_vr to ship:verticalspeed.
    lock lo_theta to THETA_T - __peg_get_angle(lo_raxis, lo_haxis, lo_taxis, target_geo:position-ship:body:position).
    lock lo_vtheta to ship:groundspeed.
    lock lo_acc to f0/ship:mass * std_throttle.
    lock lo_frcomp to peg_get_frcomp(0, lo_r, lo_vtheta, lo_acc, A, B).
    local _fhcomp_pid to pidLoop(5, 0.05, 0.03, -0.1, 0.1).
    set _fhcomp_pid:setpoint to 0.
    local fhcomp to 0.
    lock lo_ftcomp to -sqrt(1-lo_frcomp^2-fhcomp^2).
    lock steering to lookDirUp(lo_frcomp*lo_raxis + lo_ftcomp*lo_taxis + fhcomp*lo_haxis, -up:forevector).  // face up
    RCS ON.
    wait until time:seconds >= ignition_time - _ullage_time.
    print "Braking start.                             " AT(0,12).
    activate_engines(elist).
    local _time_begin to time:seconds.
    lock lo_tt to time:seconds - _time_begin.
    lock lo_frcomp to peg_get_frcomp(lo_tt, lo_r, lo_vtheta, lo_acc, A, B).
    local throttle_target to std_throttle.
    lock throttle to throttle_target.

    local num_iter to 0.
    until (T - lo_tt < 5 or lo_r < desRT or ship:groundspeed < desVTT) {
        local __new_control to peg_step_control(lo_tt, lo_r, lo_vr, lo_theta, lo_vtheta, ship:mass, f0, thro_min, 1, std_throttle, ve, T, A, B, desRT, desVRT, desTHETA_T, desVTT).
        set A to __new_control[0].
        set B to __new_control[1].
        set T to __new_control[2].
        set _time_begin to time:seconds.
        set fhcomp to _fhcomp_pid:update(time:seconds, -vdot(target_geo:position:normalized, lo_haxis)).
        set throttle_target to __new_control[3].
        local theta_error to __new_control[4].

        set num_iter to num_iter + 1.
        print "Iter: "+ num_iter+", T = " + round(T) + ", dv = " + round(__peg_get_dv(lo_acc, ve, T)) + "     " AT(0,14).
        print "A = " + round(A, 3) + ", thro = " + round(throttle_target, 3) + ", E = " + round(theta_error/180*constant:pi*Rm/1000, 4) + " km    " AT(0,15).
    }
    lock steering to "kill".
    set __gap_throttle to std_throttle.
    lock throttle to __gap_throttle.
}

function phase_approach {
    // approach phase have a more precise targeting
    print "Approach phase.                            " AT(0,12).
    // reference frame: origin point is located at the ground target point
    // and adopt up-fore axis system.
    lock lo_raxis to up:forevector.
    lock lo_haxis to vcrs(lo_raxis, ship:velocity:surface):normalized.
    lock lo_taxis to vcrs(lo_haxis, lo_raxis):normalized.

    lock lo_r to V(-target_geo:position*lo_taxis, -target_geo:position*lo_haxis, ship:bounds:bottomaltradar).
    lock lo_v to V(ship:velocity:surface*lo_taxis, ship:velocity:surface*lo_haxis, ship:velocity:surface*lo_raxis).

    local qT to quadratic_get_burntime(lo_r, lo_v, appRT, appVT, appAT, appJx).
    local __control to quadratic_step_control(lo_r, lo_v, appRT, appVT, appAT, qT).
    // local qT to __control[0].
    local qJ to __control[1].
    local qS to __control[2].
    
    local _time_begin to time:seconds.
    lock lo_tt to qT + time:seconds - _time_begin.

    // throttle and attitude control
    lock lo_af to appAT + qJ*lo_tt + qS*lo_tt^2/2 + V(0, 0, g0).
    lock steering to lookDirUp(lo_af:x*lo_taxis+lo_af:y*lo_haxis+lo_af:z*lo_raxis, sun:position).
    lock throttle to max(thro_min, min(1, ship:mass * lo_af:mag / f0)).

    until (lo_tt > -5 or lo_r:z < appRT:z) {
        set qT to lo_tt.
        set _time_begin to time:seconds.
        set __control to quadratic_step_control(lo_r, lo_v, appRT, appVT, appAT, qT).
        // set qT to __control[0].
        set qJ to __control[1].
        set qS to __control[2].
        // estimate remaining deltav by linear approximation
        local __dv to -(lo_af:mag + (appAT+V(0,0,g0)):mag)/2 * qT.
        print "T = " + round(qT) + ", dv = " + round(__dv) + "             " AT(0,14).
        print "thro = " + round(throttle, 2) + ", J = " + qJ + ", S = " + qS + "    " AT(0,15).
    }
    lock steering to "kill".
    set __gap_throttle to max(thro_min, min(1, ship:mass * lo_af:mag / f0)).
    lock throttle to __gap_throttle.
}

function phase_final {
    // final phase have no targeting, just reduce lateral speed and land.
    print "Final phase.                               " AT(0,12).
    lock lo_fvec to terminal_get_fvec().
    lock steering to lookDirUp(lo_fvec, sun:position).
    // vecDraw(v(0,0,0), {return steering:forevector*20.}, RGB(0, 255, 0), "attitude", 1, true).
    local bound_box to ship:bounds.
    local mythrott to max(thro_min, min(1, ship:mass * g0 / f0 * 0.8)).  // hover
    lock throttle to mythrott.
    local _target_attitude to lookDirUp(lo_fvec, sun:position).
    lock steering to _target_attitude.
    until (bound_box:bottomaltradar < 0.1) {
        local __new_control to terminal_step_control(bound_box:bottomaltradar, lo_fvec, ship:mass, f0, thro_min, 1, max(thro_min, min(1, ship:mass * (g0+0.2) / f0))).
        set _target_attitude to lookDirUp(__new_control[0], sun:position).
        set mythrott to __new_control[1].
    }
    lock steering to lookDirUp(up:forevector, sun:position).
    lock throttle to 0.
    wait until bound_box:bottomaltradar < 0.1.
    wait 0.2.
    unlock steering.
}

phase_descent().
phase_approach().
phase_final().
peg_finalize().
terminal_finalize().
unset __gap_throttle.
print "Landing completed." AT(0,22).
print "Target distance: " + round(target_geo:position:mag, 2) + " m" AT(0,23).