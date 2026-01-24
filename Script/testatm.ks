// Test calculation accuracy of atm model
clearScreen.
runOncePath("0:/lib/atm_utils.ks").
addons:AFS:InitAtmModel().

// print "Sealevel pressure = " + body:atm:sealevelpressure + " atm".
// print "Sealevel temperature = " + body:atm:altitudetemperature(0) + " K".
// print "Sealevel density = " + addons:AFS:GetDensityAt(0) + " kg/m^3".

function toSciFormat {
    parameter val.
    parameter _round to 3.
    if (val = 0) {
        return "0".
    }
    local exponent to floor(log10(abs(val))).
    local mantissa to val / (10 ^ exponent).
    return round(mantissa, _round):tostring + "E" + exponent.
}

declare global Hsamples to list(0, 5e3, 10e3, 20e3, 40e3, 60e3, 80e3, 100e3, 120e3).

until ag1 {
    from {local i to 0.} until i = Hsamples:length step {set i to i + 1.} do {
        local height to Hsamples[i].
        local temperature to body:atm:altitudetemperature(height).
        local rhoPred to addons:AFS:GetDensityEst(height).
        local rhoReal to addons:AFS:GetDensityAt(height).
        // local rhoReal to atm_get_density_at_altitude(height).
        // print "Height = " + round(height*1e-3, 0) + " Pred = " + round(log10(rhoPred), 3) + " Real = " + round(log10(rhoReal), 3) + " T = " + round(temperature, 2) AT (0, i).
        print "Height = " + round(height*1e-3, 0) + " Pred = " + toSciFormat(rhoPred) + " Real = " + toSciFormat(rhoReal) + " T = " + round(temperature, 2) AT (0, i).
    }
}