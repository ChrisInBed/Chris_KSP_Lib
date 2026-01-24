runOncePath("0:/lib/chrismath.ks").
declare global __ORBIT_TIME_N to 23.

function get_orbit_latus_rectum {
    parameter sma.
    parameter ecc.
    return abs(sma * (1 - ecc^2)).
}

function get_orbit_period {
    parameter sma.
    parameter mu.
    return 2 * constant:pi * sqrt(sma^3 / mu).
}

function get_orbit_angular_momentum {
    parameter sma.
    parameter ecc.
    parameter mu.
    return sqrt(mu * get_orbit_latus_rectum(sma, ecc)).
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
    return get_orbit_latus_rectum(sma, ecc) / (1 + ecc * cos(theta)).
}

function get_orbit_v_at_theta {
    parameter sma.
    parameter ecc.
    parameter theta.
    parameter mu.
    local _p to get_orbit_latus_rectum(sma, ecc).
    return sqrt(mu/_p * (1+2*ecc*cos(theta)+ecc^2)).
}

function get_orbit_vr_at_theta {
    parameter sma.
    parameter ecc.
    parameter theta.
    parameter mu.
    local _p to get_orbit_latus_rectum(sma, ecc).
    return sqrt(mu/_p) * ecc * sin(theta).
}

function get_orbit_vt_at_theta {
    parameter sma.
    parameter ecc.
    parameter theta.
    parameter mu.
    local _p to get_orbit_latus_rectum(sma, ecc).
    return sqrt(mu/_p) * (1 + ecc * cos(theta)).
}

function get_orbit_omega_at_theta {
    parameter sma.
    parameter ecc.
    parameter theta.
    parameter mu.
    local _p to get_orbit_latus_rectum(sma, ecc).
    return sqrt(mu/_p^3) * (1 + ecc * cos(theta))^2.
}

function get_orbit_vecVR_at_theta {
    parameter sma.
    parameter ecc.
    parameter unitUy.
    parameter theta.
    parameter unitRref.
    parameter etaref.
    parameter mu.

    local _p to get_orbit_latus_rectum(sma, ecc).
    local magR to _p/(1+ecc*cos(theta)).
    local unitR to angleAxis(-(theta-etaref), unitUy) * unitRref.
    local vecR to unitR * magR.
    local _f1 to (mu/_p)^0.5.
    local magVR to _f1 * ecc * sin(theta).
    local magVT to _f1 * (1 + ecc * cos(theta)).
    local unitTH to vCrs(unitR, unitUy).
    local vecV to unitR * magVR + unitTH * magVT.
    return list(vecV, vecR).
}

function get_orbit_element_from_VR {
    parameter vecR.
    parameter vecV.
    parameter mu.

    local rr to vecR:mag.
    local vv to vecV:mag.
    local vecH to vCrs(vecV, vecR).
    local vecE to vCrs(vecH, vecV)/mu - vecR / rr.
    local ecc to vecE:mag.
    local erg to 0.5*vv^2 - mu/rr.
    local sma to -mu/erg*0.5.
    local inc to arcCos(-vecH:z / vecH:mag).
    local TA to arcCos(vDot(vecE, vecR) / (ecc * rr)).
    if (vDot(vecR, vecV) < 0) {
        set TA to 360 - TA.
    }
    return lexicon(
        "sma", sma,
        "ecc", ecc,
        "inc", inc,
        "TA", TA
    ).
}

function get_ground_vecR_at_time {
    parameter tt.
    parameter vecRref.
    parameter tref.
    parameter omega.

    local vecRT to angleAxis(omega:mag*180/constant:pi *(tt-tref), -omega:normalized) * vecRref.
    return vecRT.
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
    // Kepler's second law to calculate time to thetaT from theta0
    // $T = (\mu p)^{-1/2} \int_{\theta_0}^{\theta_T} r(\theta)^2 d\theta$
    local dtheta to (thetaT - theta0) / (__ORBIT_TIME_N - 1).
    local f_arr to list().
    local _factor to (get_orbit_latus_rectum(sma, ecc)^3/mu)^0.5.
    from {local i to 0.} until i = __ORBIT_TIME_N step {set i to i+1.} do {
        f_arr:add(1/(1+ecc*cos(theta0+dtheta*i))^2).
    }
    return mintegral(f_arr, dtheta/180*constant:pi) * _factor + t0.
}

function get_active_waypoint {
    for wp in allWaypoints() {
        if wp:isselected return wp.
    }
    return 0.
}

function get_target_geo {
    local activewp to get_active_waypoint().
    if (activewp = 0) {
        return 0.
    }
    return activewp:geoPosition.
}

function get_geo_slope {
    parameter geo.

    // calculate gradient (1m resolution)
    local delta to 1.
    local rL to (geo:position-geo:body:position):mag.
    local geo1 to geo:body:geoPositionLATLNG(geo:lat+delta/rL*180/constant:pi, geo:lng).
    local geo2 to geo:body:geoPositionLATLNG(geo:lat, geo:lng+delta/(rL*cos(geo:lat))*180/constant:pi).
    local h0 to geo:TERRAINHEIGHT.
    local dh1 to geo1:TERRAINHEIGHT - h0.
    local dh2 to geo2:TERRAINHEIGHT - h0.
    
    return arcTan(sqrt(dh1^2 + dh2^2)/delta).
}

function get_geo_sample {
    parameter geo.
    parameter xlim.

    local rL to (geo:position-geo:body:position):mag.
    local deltaX to (RANDOM() - 0.5) * 2 * xlim.
    local deltaY to (RANDOM() - 0.5) * 2 * xlim.
    return geo:body:geoPositionLATLNG(geo:lat+deltaY/rL*180/constant:pi, geo:lng+deltaX/(rL*cos(geo:lat))*180/constant:pi).
}