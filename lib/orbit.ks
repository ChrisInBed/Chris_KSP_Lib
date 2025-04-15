function get_orbit_period {
    parameter sma.
    parameter mu.
    return 2 * constant:pi * sqrt(sma^3 / mu).
}

function get_orbit_angular_momentum {
    parameter sma.
    parameter ecc.
    parameter mu.
    return sqrt(mu * sma * (1 - ecc^2)).
}

function get_orbit_energy_per_mass {
    parameter sma.
    parameter mu.
    return -mu / (2 * sma).
}

function get_orbit_v_at_r {
    parameter sma.
    parameter rr.
    parameter mu.
    return sqrt(mu * (2/rr - 1/sma)).
}

function get_orbit_r_at_theta {
    parameter sma.
    parameter ecc.
    parameter theta.
    return sma * (1 - ecc ^ 2) / (1 + ecc * cos(theta)).
}

function get_orbit_v_at_theta {
    parameter sma.
    parameter ecc.
    parameter theta.
    parameter mu.
    return sqrt(mu/(sma*(1-ecc^2)) * (1+2*ecc*cos(theta)+ecc^2)).
}

function get_orbit_vr_at_theta {
    parameter sma.
    parameter ecc.
    parameter theta.
    parameter mu.
    return sqrt(mu/(sma*(1-ecc^2))) * ecc * sin(theta).
}

function get_orbit_vt_at_theta {
    parameter sma.
    parameter ecc.
    parameter theta.
    parameter mu.
    return sqrt(mu/(sma*(1-ecc^2))) * (1 + ecc * cos(theta)).
}

function get_orbit_omega_at_theta {
    parameter sma.
    parameter ecc.
    parameter theta.
    parameter mu.
    return sqrt(mu/(sma*(1-ecc^2))^3) * (1 + ecc * cos(theta))^2.
}

function get_time_to_theta {
    parameter sma.
    parameter ecc.
    parameter mu.
    parameter t0.
    parameter theta0.
    parameter thetaT.

    set theta0 to mod(theta0+360, 360).
    set thetaT to mod(thetaT+360, 360).
    if (thetaT < theta0) {
        set thetaT to thetaT + 360.
    }
    local r0 to get_orbit_r_at_theta(sma, ecc, theta0).
    local dt to get_orbit_period(sma, mu) / 3600.  // interval time
    local coef to sqrt(mu/sma/(1-ecc^2)).
    local _theta to theta0.
    local _tt to t0.
    local rr to r0.
    local _last_theta to _theta.
    until (_theta >= thetaT) {
        local dtheta to dt * coef * (ecc * cos(_theta) + 1) / rr * 180 / constant:pi.
        local dr to dt * coef * ecc * sin(_theta).
        set _last_theta to _theta.
        set _theta to mod(_theta + dtheta, 360).
        set rr to rr + dr.
        set _tt to _tt + dt.
        // print "Integral: dt = " + round(_tt-t0) + ", theta = " + round(_theta) + ", thetaT = " + round(thetaT) + "  " AT(0, 13).
    }
    // linear interpolation
    return _tt - (_theta - thetaT) / (_theta - _last_theta) * dt.
}