parameter P_GUI to true.
parameter P_PREC to false.
parameter P_NOWAIT is false.
parameter P_ADJUST is v(0, 0, 0).
parameter P_ENGINE is "current".
set config:IPU to 1000.  // high efficiency (highest: 2000)

runOncePath("0:/lib/landlib/peg.ks").
runOncePath("0:/lib/landlib/quadratic.ks").
runOncePath("0:/lib/landlib/terminal.ks").
runOncePath("0:/lib/engine_utility.ks").
declare global guidance_status to "inactive".
runOncePath("0:/lib/landlib/gui_utils.ks").

clearGuis().

// state variables
declare global done to false.
declare global guidance_active to true.
global lock break_guidance_cycle to (done or (not guidance_active)).
declare global ignite_now to P_NOWAIT.
declare global start_phase to "descent".
declare global add_approach_phase to false.
declare global target_rotation to 0.
declare global target_geo to ship:geoposition.
declare global target_height to 0.
declare global unitRtgt to V(0, 0, 0).
declare global unitHtgt to V(0, 0, 0).
declare global unitTtgt to V(0, 0, 0).
declare global desRT to 0.
declare global desLT to 0.
declare global desVRT to 0.
declare global desVLT to 0.
declare global TiS to R(0,0,0).  // Engine:facing:inverse * Ship:facing, default to be I matrix
declare global f0 to 0.
declare global ve to 0.
declare global thro_min to 0.
declare global spooluptime to 0.
declare global ullage_time to 0.
global lock ullage to (ullage_time > 1e-3).
declare global std_throttle to thro_min.
declare global final_std_throttle to thro_min.
declare global mu to 0.
declare global g0 to 0.
declare global __gap_throttle to 0.  // between phases, throttle will be locked to this value
declare global __refT to 0.  // reference time for ship-raw reference frame
declare global vecbodyomega to V(0, 0, 0).  // body angular velocity
global lock lo_toInertial to angleAxis(vecbodyomega:mag*180/constant:pi*(time:seconds-__refT), -vecbodyomega:normalized).  // ship-raw to inertial reference frame
declare global sma to 0.
declare global ecc to 0.
declare global unitRref to V(0, 0, 0).
declare global unitUy to V(0, 0, 0).
declare global etaref to 0.
declare global hudtextsize to 15.
declare global hudtextcolor to RGB(22/255, 255/255, 22/255).
// set steeringManager:showfacingvectors to true.

function init_print {
    // line 1~10: target position
    // line 11~20: guidance state
    clearScreen.
    print "PEG landing guidance" AT(0,0).
    print "============= Configuration ============" AT(0,1).
    print "================ State =================" AT(0,11).
    print "================ Result ================" AT(0,21).
}

function initialize_guidance {
    // set all state variables to initial values
    // then update the GUI
    set guidance_active to true.
    set ignite_now to P_NOWAIT.
    set start_phase to "descent".
    set guidance_status to "inactive".

    set __refT to time:seconds.
    set unitRref to -ship:body:position:normalized.
    set etaref to ship:orbit:trueanomaly.
    set unitUy to vCrs(ship:velocity:orbit, unitRref):normalized.
    set vecbodyomega to -ship:body:angularVel.
    set sma to ship:orbit:semimajoraxis.
    set ecc to ship:orbit:eccentricity.
    set mu to ship:body:mu.
    set g0 to mu / ship:body:radius^2.

    set target_rotation to 0.
    // update_target_geo().
    set unitRtgt to (target_geo:position - body:position):normalized.
    set unitTtgt to vCrs(unitRtgt, unitUy):normalized.
    set unitHtgt to vCrs(unitRtgt, unitTtgt):normalized.

    local elist to list().
    if P_ENGINE = "current" {
        set elist to get_active_engines().
    }
    else {
        set elist to search_engine(P_ENGINE).
    }
    set_engine_parameters(elist).

    set add_approach_phase to P_PREC.
    if add_approach_phase {
        set desRT to 100.
        set desLT to 500.
        set desVRT to 3.
        set desVLT to 40.
    }
    else {
        set desRT to 100.
        set desLT to 0.
        set desVRT to 3.
        set desVLT to 0.
    }

    if P_GUI {
        set guidance_active to false.
        if ((not (defined gui_maingui)) or (not gui_maingui:visible)) {
            gui_make_peglandgui().
        }
        gui_update_config_settings_display().
        gui_update_target_settings_display().
        gui_update_descent_settings_display().
        gui_update_engine_settings_display().
    }
}

function print_engines_simple_info {
    parameter elist.
    local _summary to get_engines_info(elist).
    print "Thrust = " + round(_summary:thrust, 2) + "kN       " AT(0,2).
    print "Isp = " + round(_summary:ISP, 1) + "s       " AT (0,3).
    print "Minthrottle = " + round(_summary:minthrottle, 2) + "       " AT(0,4).
    print "Ullage = " + _summary:ullage + "   " AT(0,5).
    print "Spool-up time = " + _summary:spooluptime AT(0,6).
}

function set_engine_parameters {
    parameter elist.
    local enginfo to get_engines_info(elist).
    if (enginfo:thrust < 1e-7) {
        hudtext("No thrust available", 4, 2, hudtextsize, hudtextcolor, false).
        return.
    }
    set TiS to enginfo:TiS.
    set f0 to enginfo:thrust.
    set ve to enginfo:ISP * 9.81.
    set thro_min to enginfo:minthrottle.
    set spooluptime to enginfo:spooluptime.
    set std_throttle to (max(0.90, thro_min) + 1) / 2.
    set final_std_throttle to (max(0.60, thro_min) + 1) / 2.
    if (enginfo:ullage) {
        set ullage_time to 2.
    }
    else {
        set ullage_time to 0.
    }
    print_engines_simple_info(elist).
}

function update_target_geo {
    // move target position
    local _target_geo to get_target_geo().
    if _target_geo = 0 {
        hudtext("No active waypoint", 4, 2, hudtextsize, hudtextcolor, false).
        set target_geo to ship:geoposition.
        set target_height to 0.
        return.
    }
    set target_geo to _target_geo.
    local adjfactor to 180/constant:pi/(ship:body:radius+target_geo:terrainheight).
    set target_geo to ship:body:geopositionlatlng(target_geo:lat+P_ADJUST:x*adjfactor, target_geo:lng+P_ADJUST:y*adjfactor*cos(target_geo:lat)).
    set target_height to P_ADJUST:z.
    print "Target position: " + target_geo AT(0,7).
}

function get_target_steering {
    parameter burnvec.
    parameter target_rotation.
    local topvec to vCrs(burnvec, unitUy):normalized.
    set topvec to angleAxis(target_rotation, burnvec) * topvec.
    return lookDirUp(burnvec, topvec) * TiS.
}

// action group 10 is for reset engine and target information
// staging can also update engine information
on ("0"+ag10+stage:number) {
    if (not P_GUI) {
        set P_ADJUST to v(0,0,0).
        update_target_geo().
    }
    set_engine_parameters(get_active_engines()).
    if P_GUI {
        gui_update_target_settings_display().
        gui_update_engine_settings_display().
    }
    return true.
}

function phase_descent {
    if (break_guidance_cycle) return.
    print "Preparing guidance...                      " AT(0,12).
    set guidance_status to "PEG initialization".
    peg_init().
    unlock steering.
    lock throttle to 0.
    local a0 to f0/ship:mass * std_throttle.
    local vecRL to V(0, 0, 0).
    local vecVL_rht to V(0, 0, 0).
    function set_descent_phase_target {
        set vecRL to target_geo:position-ship:body:position.
        set vecRL to vecRL:normalized * (vecRL:mag + desRT).
        local unitTHL to vCrs(vecRL, unitUy):normalized.
        set vecRL to vecRL - unitTHL * desLT.
        set vecVL_rht to V(-desVRT, 0, desVLT).
    }
    local __toInertial to lo_toInertial.
    set_descent_phase_target().
    local gst to peg_get_initial_params(
        lexicon("vecRL", __toInertial * vecRL, "vecVL_rht", vecVL_rht, "vecbodyomega", vecbodyomega),
        lexicon("sma", sma, "ecc", ecc, "unitUy", __toInertial * unitUy, "unitRref", __toInertial * unitRref, "etaref", etaref),
        lexicon("ve", ve, "thrust", f0, "throttle", std_throttle, "mass", ship:mass, "thro_min", thro_min, "thro_max", 1)
    ).
    if (gst = 0) {
        hudtext("PEG initialization failed, check your landing orbit parameters", 4, 2, 12, hudtextcolor, false).
        if P_GUI {
            gui_update_msg_display("PEG initialization failed, check your landing orbit parameters").
        }
        set guidance_active to false.
        return.
    }
    // vecDraw({return ship:body:position+gst["vecRF"].}, {return gst["vecRF"]:normalized*30000.}, RGB(255, 0, 0), "RF", 1, true).
    // vecDraw({return ship:body:position+(gst["vecRF"]-gst["vecErr"]).}, {return (gst["vecRF"]-gst["vecErr"]):normalized*30000.}, RGB(0, 255, 0), "RL", 1, true).
    local theta0 to gst["eta0"].
    local init_num_iter to gst["numiter"].
    print "Iter " + init_num_iter + ", T = " + round(gst["T"]) + ", dv = "+ round(__peg_get_dv(a0, ve, gst["T"])) + "     " AT(0,14).
    if P_GUI {
        gui_update_status_display(lexicon(
            "status", "PEG initialization",
            "numiter", init_num_iter,
            "height", alt:radar,
            "distance", target_geo:distance,
            "error", gst["vecErr"]:mag,
            "vspeed", ship:verticalspeed,
            "hspeed", ship:groundspeed,
            "T", gst["T"],
            "dv", __peg_get_dv(a0, ve, gst["T"]),
            "throttle", std_throttle
        )).
    }

    local ignition_time to time:seconds.
    local lock __lo_thetanow to etaref + __peg_get_angle(unitRref, -ship:body:position, unitUy).
    if not ignite_now {set ignition_time to get_time_to_theta(sma, ecc, mu, time:seconds, __lo_thetanow, theta0).}
    // convert to body-fixed reference frame (at ignition time)
    local __toBodyfixed to angleAxis(vecbodyomega:mag*180/constant:pi*(__refT-ignition_time), -vecbodyomega:normalized).
    set gst["unituK"] to __toBodyfixed * gst["unituK"].
    set gst["deruK"] to __toBodyfixed * gst["deruK"].
    set gst["vecV0"] to __toBodyfixed * gst["vecV0"].
    set gst["vecVF"] to __toBodyfixed * gst["vecVF"].
    set gst["vecR0"] to __toBodyfixed * gst["vecR0"].
    set gst["vecRF"] to __toBodyfixed * gst["vecRF"].
    set gst["vecGAV1"] to __toBodyfixed * gst["vecGAV1"].
    set gst["vecGAV2"] to __toBodyfixed * gst["vecGAV2"].
    set gst["unitHref"] to __toBodyfixed * gst["unitHref"].

    print "Calculate converged, wating for ignition..." AT(0,12).
    set guidance_status to "Waiting for ignition".
    when (true) then {
        local msg to "Time to ignition: " + round(ignition_time - time:seconds) + ", eta = " + round(__lo_thetanow) + "->" + round(theta0).
        print msg + "  " AT(0,13).
        if P_GUI {gui_update_msg_display(msg).}
        if (time:seconds >= ignition_time or done) {return false.}  // end trigger
        return true.
    }

    wait until time:seconds >= ignition_time - 60 or (break_guidance_cycle).
    if (break_guidance_cycle) return.
    print "Aligning to target...                      " AT(0,12).
    set guidance_status to "Aligning to target".
    if P_GUI {gui_update_msg_display("Aligning to target...").}
    local throttle_control to initialize_throttle_control(f0, thro_min, std_throttle*f0).
    local throttle_target to simple_get_throttle(std_throttle, thro_min).
    local steering_target to R(0, 0, 0).
    function update_steering_target {
        parameter tt.
        set steering_target to get_target_steering(peg_get_burnvec(tt, gst), target_rotation).
    }
    RCS ON.
    update_steering_target(0).
    lock steering to steering_target.
    until time:seconds >= ignition_time - ullage_time. {
        update_steering_target(0).  // response to roll change by user input
        wait 0.  // wait until next physical tick
    }
    print "Braking start.                             " AT(0,12).
    set guidance_status to "descent".
    set ship:control:translation to TiS:inverse * V(0, 0, 1).  // ullage control
    wait ullage_time.
    lock throttle to throttle_target.
    set ship:control:translation to V(0,0,0).  // disable ullage control
    local _time_begin to time:seconds.
    lock lo_tt to time:seconds - _time_begin.

    // inner loop: update axis and steering
    when (guidance_status = "descent") then {
        update_steering_target(lo_tt).
        set throttle_control["maxthrust"] to f0.
        set throttle_control["minthrottle"] to thro_min.
        set throttle_control["throttle"] to throttle.
        set throttle_control["thrust"] to get_curthrust()*0.25 + throttle_control["thrust"]*0.75.  // moving average
        set throttle_target to update_throttle_control(throttle_control).
        return true.
    }
    // outer loop: update control and throttle
    local num_iter to 0.
    local _old_ground_speed to ship:groundspeed.
    until (gst["T"] - lo_tt < 0 or ship:body:distance < vecRL:mag or ship:groundspeed < vecVL_rht:z) {
        if (break_guidance_cycle) return.
        local __time_begin to time:seconds.
        set gst["T"] to gst["T"] - lo_tt.
        set gst["K"] to gst["K"] - lo_tt.
        set gst["vecV0"] to ship:velocity:surface.
        set gst["vecR0"] to -ship:body:position.
        set gst["throttle"] to std_throttle.
        set_descent_phase_target().
        peg_step_control(
            lexicon("vecRL", vecRL, "vecVL_rht", vecVL_rht, "vecbodyomega", V(0,0,0)),
            lexicon("ve", ve, "thrust", f0, "throttle", std_throttle, "mass", ship:mass, "thro_min", thro_min, "thro_max", 1),
            gst
        ).
        if (abs(gst["T"]) < 1e-6 or abs(gst["T"]) > 1e6) {
            print "Descent iteration diverged, aborting guidance" AT(0, 16).
            hudtext("Descent iteration diverged, aborting guidance", 4, 2, 12, hudtextcolor, false).
            if P_GUI {
                gui_update_msg_display("Descent iteration diverged, aborting guidance").
            }
            set guidance_active to false.
            unlock steering.
            unlock throttle.
            return.
        }
        set _time_begin to __time_begin.
        set throttle_control["thrust_target"] to gst["throttle"]*f0.
        set num_iter to num_iter + 1.
        print "Iter: "+ num_iter+", T = " + round(gst["T"]) + ", dv = " + round(__peg_get_dv(throttle_control["thrust_target"]/ship:mass, ve, gst["T"])) + "     " AT(0,14).
        print "thro = " + round(gst["throttle"], 3) + ", E = " + round(gst["vecErr"]:mag/1000, 4) + " km    " AT(0,15).
        if P_GUI {
            gui_update_status_display(lexicon(
                "status", "descent",
                "numiter", num_iter,
                "height", alt:radar,
                "distance", target_geo:distance,
                "error", gst["vecErr"]:mag,
                "vspeed", ship:verticalspeed,
                "hspeed", ship:groundspeed,
                "T", gst["T"],
                "dv", __peg_get_dv(throttle_control["thrust_target"]/ship:mass, ve, gst["T"]),
                "throttle", gst["throttle"]
            )).
        }
        if gst["T"] < 10 and (gst["T"] <= 0 or ship:groundspeed / (abs(ship:verticalspeed) + 0.001) < 1.5 or (ship:groundspeed > _old_ground_speed)) {
            break.
        }
        set _old_ground_speed to ship:groundspeed.
        wait 0.  // wait until next physical tick
    }
    set guidance_status to "waiting for next phase".
    lock steering to "kill".
    set __gap_throttle to throttle_target.
    lock throttle to __gap_throttle.
}

function phase_approach {
    // approach phase have a more precise targeting
    if (break_guidance_cycle) return.
    print "Approach phase.                            " AT(0,12).
    set guidance_status to "approach".
    local lock appRT to V(0, 0, target_height).
    local appVT to V(0, 0, -0.5). // 0.5 m/s downward
    local appAT to V(0, 0, 0). // no acceleration
    local appJx to 0.  // no Jerk
    local raxis to V(0, 0, 1).
    local haxis to V(0, 0, 1).
    local taxis to V(0, 0, 1).
    local bound_box to ship:bounds.
    local rr to V(0, 0, 0).
    local vv to V(0, 0, 0).
    function update_state {
        // reference frame: origin point is located at the ground target point
        // and adopt up-fore axis system.
        set raxis to up:forevector.
        set haxis to vcrs(raxis, ship:velocity:surface):normalized.
        set taxis to vcrs(haxis, raxis):normalized.

        set rr to V(-target_geo:position*taxis, -target_geo:position*haxis, bound_box:bottomaltradar).
        set vv to V(ship:velocity:surface*taxis, ship:velocity:surface*haxis, ship:verticalspeed).
    }
    update_state().

    local __control to quadratic_step_control(rr, vv, appRT, appVT, appAT, appJx, 120).
    local qT to __control[0].
    local qJ to __control[1].
    local qS to __control[2].
    
    local _time_begin to time:seconds.
    lock lo_tt to qT + time:seconds - _time_begin.
    local steering_target to "kill".
    lock steering to steering_target.
    local throttle_target to __gap_throttle.
    lock throttle to throttle_target.
    local _af to V(0,0,0).

    // inner loop: update state, steering and throttle
    when (guidance_status = "approach") then {
        local _tt to lo_tt.
        update_state().
        set _af to appAT + qJ*_tt + qS*_tt^2/2 + V(0, 0, g0).
        set steering_target to get_target_steering(_af:x*taxis + _af:y*haxis + _af:z*raxis, target_rotation).
        set throttle_target to simple_get_throttle(ship:mass*_af:mag/f0, thro_min).
        return true.
    }

    local numiter to 1.
    until (lo_tt > -5 or rr:z < appRT:z) {
        if (break_guidance_cycle) return.
        local __time_begin to time:seconds.
        set __control to quadratic_step_control(rr, vv, appRT, appVT, appAT, appJx, lo_tt).
        set _time_begin to __time_begin.
        set qT to __control[0].
        set qJ to __control[1].
        set qS to __control[2].
        // estimate remaining deltav by linear approximation
        local __dv to -(_af:mag + (appAT+V(0,0,g0)):mag)/2 * qT.
        print "T = " + round(qT) + ", dv = " + round(__dv) + "             " AT(0,14).
        print "thro = " + round(throttle, 2) + "    " AT(0,15).
        if P_GUI {
            gui_update_status_display(lexicon(
                "status", "approach",
                "numiter", numiter,
                "height", alt:radar,
                "distance", target_geo:distance,
                "error", 0,
                "vspeed", ship:verticalspeed,
                "hspeed", ship:groundspeed,
                "T", -qT,
                "dv", __dv,
                "throttle", throttle_target*(1-thro_min)+thro_min
            )).
        }
        set numiter to numiter + 1.
        wait 0.  // wait until next physical tick
    }
    set guidance_status to "waiting for next phase".
    lock steering to "kill".
    set __gap_throttle to throttle_target.
    lock throttle to __gap_throttle.
}

function phase_final {
    if (break_guidance_cycle) return.
    // final phase have no targeting, just reduce lateral speed and land.
    print "Final phase.                               " AT(0,12).
    set guidance_status to "final".
    terminal_init().
    lock lo_fvec to terminal_get_fvec().
    lock steering to get_target_steering(lo_fvec, target_rotation).
    local bound_box to ship:bounds.
    lock _height to bound_box:bottomaltradar - target_height.
    local vrT to -0.05.  // 5 cm/s downward
    local _extra_g to 0.2.
    lock lo_final_throttle to max(min(thro_min+0.1, 1), ship:mass*(g0+_extra_g)/f0).
    lock lo_af1 to final_std_throttle * f0 / ship:mass.
    lock lo_af2 to lo_final_throttle * f0 / ship:mass.
    local T2 to 5.

    if (not add_approach_phase) {
        if (not terminal_time_to_fire(_height+ship:verticalspeed*(spooluptime+ullage_time), vrT, lo_af1, lo_af2, T2)) {
            // waiting for ignition
            lock throttle to 0.
            until (break_guidance_cycle) or terminal_time_to_fire(_height+ship:verticalspeed*(spooluptime+ullage_time), vrT, lo_af1, lo_af2, T2) {wait 0.}
            set ship:control:translation to TiS:inverse * V(0, 0, 1).  // ullage control
            until engine_stability(get_active_engines()) > 0.999 and terminal_time_to_fire(_height+ship:verticalspeed*(spooluptime), vrT, lo_af1, lo_af2, T2) {wait 0.}
        }
    }
    local __new_control to terminal_step_control(_height, vrT, ship:mass, f0, thro_min, 1, final_std_throttle, lo_final_throttle, T2).
    local throttle_target to simple_get_throttle(__new_control[1], thro_min).
    lock throttle to throttle_target.
    set ship:control:translation to V(0,0,0).  // disable ullage control
    local _target_attitude to get_target_steering(lo_fvec, target_rotation).
    lock steering to _target_attitude.
    until (_height < 0.2 or ((not add_approach_phase) and ship:verticalspeed > vrT - 0.05)) {
        if (break_guidance_cycle) return.
        set __new_control to terminal_step_control(_height, vrT, ship:mass, f0, thro_min, 1, final_std_throttle, lo_final_throttle, T2).
        set _target_attitude to get_target_steering(__new_control[0], target_rotation).
        set throttle_target to simple_get_throttle(__new_control[1], thro_min).
        wait 0.  // wait until next physical tick
    }
    lock steering to get_target_steering(up:forevector, target_rotation).
    lock throttle to 0.
    wait until _height < 0.2 or (break_guidance_cycle).
    wait 0.2.
    unlock steering.
    unlock throttle.
    set guidance_status to "completed".
}

function summary_guidance {
    if (break_guidance_cycle) return.
    print "Landing completed." AT(0,22).
    print "Target distance: " + round(target_geo:distance, 2) + " m" AT(0,23).
    local __errorfactor to 1/180*constant:pi*(ship:body:radius+target_geo:terrainheight).
    local __errorNorth to (ship:geoposition:lat-target_geo:lat)*__errorfactor.
    local __errorEast to (ship:geoposition:lng-target_geo:lng)*__errorfactor*cos(target_geo:lat).
    print "Error: " + round(__errorNorth, 2) + " m (North), "
        + round(__errorEast, 2) + " m (East)" AT(0,24).
    if P_GUI {
        gui_update_status_display(lexicon(
            "status", "completed",
            "numiter", 0,
            "height", alt:radar,
            "distance", target_geo:distance,
            "error", vxcl(up:forevector, target_geo:position):mag,
            "vspeed", ship:verticalspeed,
            "hspeed", ship:groundspeed,
            "T", 0,
            "dv", 0,
            "throttle", 0
        )).
        gui_update_msg_display("Landing completed. Error = " + round(__errorNorth, 2) + " m (N), " + round(__errorEast, 2) + " m (E)").
    }
}

function main {
    init_print().
    update_target_geo().
    until done {
        initialize_guidance().
        wait until guidance_active or done.
        if (start_phase = "descent" and (not done)) {
            phase_descent().
            if (add_approach_phase) {phase_approach().}
            phase_final().
            summary_guidance().
        }
        else if (start_phase = "approach" and (not done)) {
            phase_approach().
            phase_final().
            summary_guidance().
        }
        else if (start_phase = "final" and (not done)) {
            phase_final().
        }
        if (not P_GUI) {
            set done to true.
            set guidance_active to false.
        }
        unlock steering.
        unlock throttle.
    }
    clearGuis().
}

main().