runOncePath("0:/lib/atm_utils.ks").
addons:AFS:InitAtmModel().
clearScreen.

until (ag1) {
    local densityPred to addons:AFS:GetDensityEst(ship:altitude).
    local densityReal to addons:AFS:GetDensityAt(ship:altitude).
    local CLD to atm_get_CLD_at(addons:AFS:AOA, ship:airspeed, ship:altitude).
    local _factor to densityReal * ship:airspeed^2 / 2 * addons:AFS:REFAREA * 1e-3.
    local drag to CLD["Cd"] * _factor.
    local lift to CLD["Cl"] * _factor.
    print "Alt=" + round(ship:altitude*1e-3, 0) + "km:DP=" + round(densityPred, 3) + ";DR=" + round(densityReal, 3) + "    " AT(0,1).
    print "Drag=" + round(drag, 3) + " kN; Lift=" + round(lift, 3) + " kN." AT(0,2).
    wait 0.2.
}