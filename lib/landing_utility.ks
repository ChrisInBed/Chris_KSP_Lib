function adjust_landing_position {
    parameter timeout is 60.
    parameter minthrottle is 0.
    set begintime to time:seconds.
    if (not addons:tr:available) {
        print "trajectories not available".
        return 0.
    }
    if (not addons:tr:hasimpact) {
        print "no impact point".
        return 0.
    }
    if (not addons:tr:hastarget) {
        print "no target point".
        return 0.
    }
    lock target_geo to addons:tr:gettarget.
    lock impact_geo to addons:tr:impactpos.

    // lock correctvec to target_geo:position - impact_geo:altitudeposition(target_geo:terrainheight - impact_geo:terrainheight).
    lock correctvec to target_geo:position - impact_geo:position.
    lock dist to correctvec:mag.

    lock steering to correctvec.
    wait until vAng(ship:facing:vector, correctvec) < 1.
    // gradient descent for ground distance
    lock throttle to max(minthrottle,min(1,(dist-20)/100)).
    set lastdist to dist.
    until (time:seconds > begintime + timeout) or (vAng(ship:facing:vector, correctvec) > 10) or (throttle <= minthrottle + 0.01) {
        if (dist > lastdist) break.
        wait 0.05.
    }

    print "impact postition corrected. Final landing site is " + dist + " meters from target".
    lock throttle to 0.
    wait 1.
    unlock throttle.
    unlock steering.
}