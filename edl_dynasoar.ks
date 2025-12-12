print "Dynasoar EDL guidance".

function stage1 {
    print "Gliding to entry point".
    lock steering to srfprograde * R(-30, 0, 0).
    wait until ship:altitude < 85000.
    print "Entry point reached, airbraking phase start".
    // pitch control
    set _pitch to 30.
    set _maxpitch to 30.  // maximum pitch angle for airbraking
    lock _targetV to -10 + ((-150) - (-10)) / (85000 - 30000) * (ship:altitude - 30000).  // target vertical velocity
    set _stop_height to 30000.  // stop height
    set _pitch_PID to pidLoop(0.3, 0.005, 0.001, 0, _maxpitch).
    set _pitch_PID:setpoint to _targetV.
    // roll control
    set _roll to 0.
    set _maxroll to 20.  // maximum roll angle for airbraking
    lock _spot to addons:tr:gettarget.
    lock _target_direction to _spot:position / _spot:position:mag.
    lock __target_h to vxcl(up:vector, _target_direction).
    lock _target_haxis to __target_h / __target_h:mag.
    lock _target_baxis to vcrs(_target_haxis, up:vector).  // it's on the left
    lock _bankV to vdot(ship:velocity:surface, _target_baxis).
    set _roll_PID to pidLoop(0.5, 0.005, 0.001, -_maxroll, _maxroll).
    set _roll_PID:setpoint to 0.
    // control loop
    lock _yaw to _pitch * tan(-_roll).
    lock steering to srfPrograde * R(-_pitch, _yaw, _roll).
    vecDraw(v(0,0,0), _target_baxis * _bankV, RGB(0, 255, 0), "bank V", 1.0, true).
    until ship:altitude < _stop_height or ship:airspeed < 2000 {
        set _pitch to max(0, min(_maxpitch, _pitch_PID:update(time:seconds, ship:verticalspeed))).
        set _roll to max(-_maxroll, min(_maxroll, _roll_PID:update(time:seconds, _bankV))).
        print "Pitch: " + round(_pitch, 1) + ", Roll: " + round(_roll, 1) + ", Altitude: " + round(ship:altitude, 0) + ", Vertical Speed: " + round(ship:verticalspeed, 0) + ", Bank V: " + round(_bankV, 1).
        wait 0.1.
    }
}

stage1().