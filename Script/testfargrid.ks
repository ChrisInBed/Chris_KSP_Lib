runOncePath("0:/lib/atm_utils.ks").
runOncePath("0:/lib/chrismath.ks").
addons:AFS:InitAtmModel().
clearScreen.

local vsamples to list().
mlinspace(1, 8001, 41, vsamples).
local altsamples to list().
mlinspace(0, 135e3, 28, altsamples).

local Cdlist to list().
local Cllist to list().
from {local i to 0.} until i = vsamples:length step {set i to i+1.} do {
    local Cdrow to list().
    local Clrow to list().
    from {local j to 0.} until j = altsamples:length step {set j to j+1.} do {
        local height to altsamples[j].
        local vv to vsamples[i].
        local CLD to atm_get_CLD_at(35, vv, height).
        Cdrow:add(CLD["Cd"]).
        Clrow:add(CLD["Cl"]).
    }
    Cdlist:add(Cdrow).
    Cllist:add(Clrow).
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