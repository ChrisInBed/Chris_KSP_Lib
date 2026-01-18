runOncePath("0:/lib/atm_utils.ks").

if (not addons:hasaddon("AFS")) {
    print "AFS addon is not installed. Please install the AFS addon to use this script.".
    print 1/0.
}
set AFS to addons:AFS.

// set basic ship parameters
AFS:InitAtmModel().
// set AFS:mu to body:mu.
// set AFS:R to body:radius.
// set AFS:molar_mass to body:atm:molarmass.
// set AFS:atm_height to body:atm:height.

set AFS:mass to ship:mass.
set AFS:area to AFS:REFAREA.
set AFS:bank_max to 70.
declare global bank_i to 20.
declare global bank_f to 10.
declare global energy_i to get_spercific_energy(body:radius+ship:altitude, ship:velocity:orbit:mag).
declare global energy_f to get_spercific_energy(body:radius+23e3, 450).
set AFS:k_QEGC to 1.
set AFS:k_C to 5.
set AFS:t_reg to 120.
set AFS:Qdot_max to 5e5.
set AFS:acc_max to 30.
set AFS:dynp_max to 15e3.
set AFS:L_min to 0.5.
set AFS:target_energy to energy_f.
set AFS:predict_min_step to 0.
set AFS:predict_max_step to 0.5.
set AFS:predict_tmax to 3600.
set AFS:predict_traj_dSqrtE to 300.
set AFS:predict_traj_dH to 10e3.

// Initialize Energy, AOA, Cl, Cd profiles
declare global speedsamples to list(400, 3500, 8000).
declare global AOAProfile to list(13, 25, 32).
declare global HProfile to list(20e3, 40e3, 80e3).
declare global EProfile to list().
declare global ClProfile to list().
declare global CdProfile to list().
from {local i to 0.} until i = speedsamples:length step {set i to i+1.} do {
    EProfile:add(get_spercific_energy(body:radius+HProfile[i], speedsamples[i])).
    local CLD to atm_get_CLD_at(AOAProfile[i], speedsamples[i], HProfile[i]).
    ClProfile:add(CLD["Cl"]).
    CdProfile:add(CLD["Cd"]).
}
set AFS:speedsamples to speedsamples.
set AFS:AOAsamples to AOAProfile.
set AFS:energysamples to EProfile.
set AFS:Clsamples to ClProfile.
set AFS:Cdsamples to CdProfile.

print "Lift and Drag coefficients profiles:".
// print "AOA (deg): " + AOAProfile.
// print "Altitude (m): " + HProfile.
print "Cl: " + ClProfile.
print "Cd: " + CdProfile.

function get_spercific_energy {
    parameter rr.
    parameter vv.
    return -body:mu/rr + 0.5*vv*vv.
}

// test item: AOA and Bank command
print "V = 6km/s, Alt = 80km, Bank = " + AFS:GetBankCmd(lexicon(
    "y4", list(80e3+body:radius, 0, 6e3, -5),
    "bank_i", bank_i, "bank_f", bank_f,
    "energy_i", energy_i, "energy_f", energy_f
))["Bank"] + " degrees. AOA = " + AFS:GetAOACmd(lexicon(
    "y4", list(80e3+body:radius, 0, 6e3, -5)
))["AOA"] + " degrees.".

// test item: Predictor
declare global startState to list(body:radius+140e3, 0, 7.8e3, -1).
declare global newRange to 0.
declare global lastRange to 0.

declare global numiter to 0.
declare global result to lexicon().
until (false) {
    local jobid to AFS:AsyncSimAtmTraj(lexicon(
        "t", 0, "y4", startState,
        "bank_i", bank_i, "bank_f", bank_f,
        "energy_i", energy_i, "energy_f", energy_f
    )).
    wait until AFS:CheckTask(jobid).
    set result to AFS:GetTaskResult(jobid).
    set newRange to result["finalState"][1]/180*constant:PI*body:radius.
    if (abs(newRange - lastRange) < 1e3) break.
    set lastRange to newRange.
    // Renew aerodynamic profiles based on predicted trajectory
    set EProfile to list().
    set ClProfile to list().
    set CdProfile to list().
    from {local i to result["trajE"]:length-1.} until i = -1 step {set i to i-1.} do {
        EProfile:add(result["trajE"][i]).
        local CLD to atm_get_CLD_at(result["trajAOA"][i], result["trajV"][i], result["trajR"][i] - body:radius).
        ClProfile:add(CLD["Cl"]).
        CdProfile:add(CLD["Cd"]).
        print "V=" + round(result["trajV"][i]/1e3, 1) + ",Alt=" + round((result["trajR"][i]-body:radius)/1e3, 0) + ",Cl=" + round(CLD["Cl"], 3) + ",Cd=" + round(CLD["Cd"], 3) + ",AOA=" + round(result["trajAOA"][i], 1) + "    ".
    }
    set AFS:energysamples to EProfile.
    set AFS:Clsamples to ClProfile.
    set AFS:Cdsamples to CdProfile.
    set numiter to numiter + 1.
    print "Iteration " + numiter + ": predicted range = " + (newRange/1e3) + " km.".
}

print "Final predicted range = " + (newRange/1e3) + " km after " + numiter + " iterations.".

// Test deriative
local jobid to AFS:AsyncSimAtmTraj(lexicon(
    "t", 0, "y4", startState,
    "bank_i", bank_i, "bank_f", bank_f,
    "energy_i", energy_i, "energy_f", energy_f
)).
wait until AFS:CheckTask(jobid).
local result1 to AFS:GetTaskResult(jobid).
set jobid to AFS:AsyncSimAtmTraj(lexicon(
    "t", 0, "y4", startState,
    "bank_i", bank_i+0.1, "bank_f", bank_f,
    "energy_i", energy_i, "energy_f", energy_f
)).
wait until AFS:CheckTask(jobid).
local result2 to AFS:GetTaskResult(jobid).
local dRange_dBanki to (result2["finalState"][1]-result1["finalState"][1])/180*constant:PI*body:radius*1e-3/0.1.
print "dRange/dBanki = " + toSciFormat(dRange_dBanki) + " km/deg.".

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