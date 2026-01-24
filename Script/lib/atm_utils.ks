function atm_get_density_at_altitude {
    parameter _altitude.
    return addons:AFS:GetDensityAt(_altitude).
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

function atm_get_CLD_at {
    parameter _AOA.
    parameter _speed.
    parameter _altitude.
    // Return a lexicon with keys: Cl, Cd

    // // weired values will be acquired near atomosphere edge, clamp altitude
    // local hs to atm_get_scale_height().
    // if (_altitude > body:atm:height - hs) {
    //     set _altitude to body:atm:height - hs.
    // }

    return addons:AFS:GetFARAeroCoefs(lexicon(
        "AOA", _AOA,
        "speed", _speed,
        "altitude", _altitude
    )).
}