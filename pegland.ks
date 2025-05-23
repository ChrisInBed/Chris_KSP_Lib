parameter P_NOWAIT is false.
parameter P_ALLOW_RESTART is true.
parameter P_ADJUST is v(0, 0, 0).
parameter P_ENGINE is "current".
clearScreen.
print "PEG landing guidance" AT(0,0).
print "============= Configuration ============" AT(0,1).
print "================ State =================" AT(0,11).
print "================ Result ================" AT(0,21).

// line 1~10: target position
// line 11~20: guidance state

runOncePath("0:/lib/landlib/peg.ks").
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
    print "Spool-up time = " + _summary:spooluptime AT(0,6).
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
    set spooluptime to enginfo:spooluptime.
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
set target_height to 0.
// set __target_draw to vecDraw({return target_geo:position.}, {return (target_geo:position-ship:body:position):normalized * 50.}, RGB(255, 0, 0), "target", 1, true).
function update_target_geo {
    // move target position
    set target_geo to addons:tr:gettarget.
    local adjfactor to 180/constant:pi/(ship:body:radius+target_geo:terrainheight).
    set target_geo to ship:body:geopositionlatlng(target_geo:lat+P_ADJUST:x*adjfactor, target_geo:lng+P_ADJUST:y*adjfactor*cos(target_geo:lat)).
    set target_height to P_ADJUST:z.
    print "Target position: " + target_geo AT(0,7).
}
update_target_geo().
function set_descent_phase_target {
    set desRT to (target_geo:position-ship:body:position):mag + target_height + 150.  // 150 m above ground
    set desVRT to -3.  // 3 m/s downward
    set THETA_T to eta0 + __peg_get_angle(__raxis, __haxis, __taxis, target_geo:position-ship:body:position).
    set desTHETA_T to THETA_T - 0/Rm*180/constant:pi.  // 0 m before target
    set desVTT to 0.  // 0 m/s lateral speed
}
set_descent_phase_target().

// action group 10 is for reset engine and target information
// staging can also update engine information
on ("0"+ag10+stage:number) {
    set P_ADJUST to v(0,0,0).
    update_target_geo().
    set_engine_parameters(get_active_engines()).
    set_descent_phase_target().
    return true.
}

set landing_phase to 0.

function phase_descent {
    print "Preparing guidance...                      " AT(0,12).
    set landing_phase to 1.
    local a0 to f0/ship:mass * std_throttle.
    local __init_params to peg_get_initial_params(sma, ecc, mu, a0, ve, desRT, desVRT, desVTT, desTHETA_T).
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
    lock lo_r to ship:body:position:mag.
    lock lo_vr to ship:verticalspeed.
    lock lo_vtheta to ship:groundspeed.
    local throttle_target to std_throttle.
    lock lo_acc to f0/ship:mass * std_throttle.

    local raxis to V(0, 0, 1).
    local haxis to V(0, 0, 1).
    local taxis to V(0, 0, 1).
    function update_axis {
        set raxis to up:forevector.
        set haxis to vcrs(raxis, ship:velocity:surface):normalized.
        set taxis to vcrs(haxis, raxis):normalized.
    }
    local steering_target to R(0, 0, 0).
    local fhcomp to 0.
    function update_steering_target {
        parameter tt.
        local frcomp to peg_get_frcomp(tt, lo_r, lo_vtheta, lo_acc, A, B).
        local ftcomp to -sqrt(max(0, 1-frcomp^2-fhcomp^2)).
        set steering_target to lookDirUp(frcomp*raxis + ftcomp*taxis + fhcomp*haxis, up:forevector).
    }
    RCS ON.
    update_axis().
    update_steering_target(0).
    lock steering to steering_target.
    wait until time:seconds >= ignition_time - _ullage_time.
    print "Braking start.                             " AT(0,12).
    activate_engines(elist).
    local _fhcomp_pid to pidLoop(5, 0.05, 0.03, -0.1, 0.1).
    local _time_begin to time:seconds.
    lock lo_tt to time:seconds - _time_begin.
    lock throttle to throttle_target.

    // inner loop: update axis and steering
    local latency to 0.1.
    when (landing_phase = 1) then {
        update_axis().
        local _time_now to time:seconds.
        update_steering_target(lo_tt+latency).
        set latency to time:seconds - _time_now.
        return true.
    }
    // outer loop: update control and throttle
    local num_iter to 0.
    local _old_ground_speed to ship:groundspeed.
    until (T - lo_tt < 0 or lo_r < desRT) {
        local __time_begin to time:seconds.
        local _theta to THETA_T - __peg_get_angle(raxis, haxis, taxis, target_geo:position-ship:body:position).
        local __new_control to peg_step_control(lo_tt, lo_r, lo_vr, _theta, lo_vtheta, ship:mass, f0, thro_min, 1, std_throttle, ve, T, A, B, desRT, desVRT, desVTT, desTHETA_T).
        set _time_begin to __time_begin.
        set A to __new_control[0].
        set B to __new_control[1].
        set T to __new_control[2].
        set throttle_target to __new_control[3].
        if (_theta > THETA_T) {set fhcomp to 0.}
        else {set fhcomp to _fhcomp_pid:update(time:seconds, -vdot(target_geo:position:normalized, haxis)).}
        local theta_error to __new_control[4].

        set num_iter to num_iter + 1.
        print "Iter: "+ num_iter+", T = " + round(T) + ", dv = " + round(__peg_get_dv(lo_acc, ve, T)) + "     " AT(0,14).
        print "A = " + round(A, 3) + ", thro = " + round(throttle_target, 3) + ", E = " + round(theta_error/180*constant:pi*Rm/1000, 4) + " km    " AT(0,15).
        if T < 10 and (T <= 0 or ship:groundspeed / (abs(ship:verticalspeed) + 0.001) < 1.5 or (ship:groundspeed > _old_ground_speed)) {
            break.
        }
        set _old_ground_speed to ship:groundspeed.
    }
    set landing_phase to 0.
    lock steering to "kill".
    set __gap_throttle to throttle_target.
    lock throttle to __gap_throttle.
}

function phase_final {
    // final phase have no targeting, just reduce lateral speed and land.
    if (P_ALLOW_RESTART) {
        lock throttle to 0.
        if (enginfo:ullage) {set ship:control:fore to 0.5.}
    }
    else {lock throttle to thro_min.}
    print "Final phase.                               " AT(0,12).
    set landing_phase to 3.
    local bound_box to ship:bounds.
    lock _height to bound_box:bottomaltradar - target_height.
    local vrT to -0.05.  // 5 cm/s downward
    lock lo_std_throttle to max(thro_min, min(final_std_throttle, ship:mass * (g0+0.4) / f0)).
    lock lo_fvec to terminal_get_fvec().
    lock steering to lookDirUp(lo_fvec, sun:position).
    // vecDraw(v(0,0,0), {return steering:forevector*20.}, RGB(0, 255, 0), "attitude", 1, true).
    wait until vang(ship:facing:forevector, steering:forevector) < 40 and terminal_time_to_fire(_height+ship:verticalspeed*spooluptime, vrT, ship:mass, f0, lo_std_throttle).
    local throttle_target to lo_std_throttle.
    lock throttle to throttle_target.
    set ship:control:fore to 0.
    local _target_attitude to lookDirUp(lo_fvec, sun:position).
    lock steering to _target_attitude.
    until (_height < 0.1 or abs(ship:verticalspeed) < 0.1) {
        local __new_control to terminal_step_control(_height, vrT, ship:mass, f0, thro_min, 1, lo_std_throttle).
        set _target_attitude to lookDirUp(__new_control[0], sun:position).
        set throttle_target to __new_control[1].
    }
    lock steering to lookDirUp(up:forevector, sun:position).
    lock throttle to 0.
    wait until _height < 0.1.
    wait 0.2.
    unlock steering.
}

phase_descent().
phase_final().
peg_finalize().
terminal_finalize().
unset __gap_throttle.
unset landing_phase.
print "Landing completed." AT(0,22).
print "Target distance: " + round(target_geo:distance, 2) + " m" AT(0,23).
set __errorfactor to 1/180*constant:pi*(ship:body:radius+target_geo:terrainheight).
print "Error: " + round((ship:geoposition:lat-target_geo:lat)*__errorfactor, 2) + " m (North), "
     + round((ship:geoposition:lng-target_geo:lng)*__errorfactor*cos(target_geo:lat), 2) + " m (East)" AT(0,24).
unset __errorfactor.