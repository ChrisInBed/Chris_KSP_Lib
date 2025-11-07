function atm_get_density_at_altitude {
    parameter _altitude.
    return body:atm:ALTITUDEPRESSURE(_altitude) * 101325
      * body:atm:MOLARMASS
      / (8.314 * body:atm:ALTITUDETEMPERATURE(_altitude)).
}

function atm_get_sealevel_density {
    return atm_get_density_at_altitude(0).
}

function atm_get_scale_height {
    local rho0 to atm_get_sealevel_density().
    local halfheight to body:atm:height / 2.
    local rho1 to atm_get_density_at_altitude(halfheight).
    return halfheight/ln(rho0/rho1).
}

function atm_get_LD_at {
    parameter _AOA.
    parameter _speed.
    parameter _altitude.

    local unitV to (R(_AOA, 0, 0)*ship:facing):forevector.
    local unitL to (R(_AOA-90, 0, 0)*ship:facing):forevector.
    local forcevec to addons:far:aeroforceat(_altitude, unitV * _speed).
    local Lforce to vdot(forcevec, unitL).
    local Dforce to -vdot(forcevec, unitV).
    return list(Lforce, Dforce).
}