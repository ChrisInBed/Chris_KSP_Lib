runOncePath("0:/lib/atm_utils.ks").
runOncePath("0:/lib/chrismath.ks").
runOncePath("0:/lib/utils.ks").
runOncePath("0:/lib/edllib/uentry_core.ks").
clearScreen.

set AFS to addons:AFS.

local vsamples to list().
mlinspace(1, 8001, 41, vsamples).
local altsamples to list().
mlinspace(0, 140e3, 28, altsamples).

local Cdlist to list().
local Cllist to list().
local CdlistEst to list().
local CllistEst to list().
from {local i to 0.} until i = vsamples:length step {set i to i+1.} do {
    local Cdrow to list().
    local Clrow to list().
    local CdrowEst to list().
    local ClrowEst to list().
    local vv to vsamples[i].
    local AOACmd to AFS:GetAOACmd(lexicon("y4", list(0,0,vv,0)))["AOA"].
    local _msg to "".
    from {local j to 0.} until j = altsamples:length step {set j to j+1.} do {
        local height to altsamples[j].
        local CLD to atm_get_CLD_at(AOACmd, vv, height).
        local CLDEst to AFS:GetFARAeroCoefsEst(lexicon(
            "speed", vv,
            "altitude", height
        )).
        Cdrow:add(CLD["Cd"]).
        Clrow:add(CLD["Cl"]).
        CdrowEst:add(CLDEst["Cd"]).
        ClrowEst:add(CLDEst["Cl"]).
        set _msg to _msg + round(height*1e-3) + "(" + round(CLD["Cd"],2) + "/" + round(CLDEst["Cd"],2)
            + "," + round(CLD["Cl"],2) + "/" + round(CLDEst["Cl"],2) + ")".
    }
    print "v=" + round(vv*1e-3,1) + ";AOA=" + round(AOACmd,1) + "; " + _msg.
    Cdlist:add(Cdrow).
    Cllist:add(Clrow).
    CdlistEst:add(CdrowEst).
    CllistEst:add(ClrowEst).
}

// Log results to file
function log_aero_profiles {
    parameter filename.
    parameter Cdlist.

    for Cdrow in Cdlist {
        local line to "".
        for Cd in Cdrow {
            set line to line + Cd:toString + ",".
        }
        log line to filename.
    }
}

log_aero_profiles("0:/aero_Cd_profile.csv", Cdlist).
log_aero_profiles("0:/aero_Cl_profile.csv", Cllist).
log_aero_profiles("0:/aero_Cd_profile_est.csv", CdlistEst).
log_aero_profiles("0:/aero_Cl_profile_est.csv", CllistEst).