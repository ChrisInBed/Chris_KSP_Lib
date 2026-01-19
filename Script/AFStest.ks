runOncePath("0:/lib/atm_utils.ks").
runOncePath("0:/lib/chrismath.ks").
runOncePath("0:/lib/edllib/uentry_core.ks").

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
entry_set_AOAprofile(
    list(400, 3500, 8000), // speed profile in m/s
    list(13, 25, 32) // AOA profile in degrees
).

local aeroSpeedSamples to list().
mlinspace(400, 8000, 32, aeroSpeedSamples).
local aeroAltSamples to list().
mlinspace(15e3, body:atm:height-100, 32, aeroAltSamples).
entry_async_set_aeroprofile(
    aeroSpeedSamples,
    aeroAltSamples
).
wait until entry_aeroprofile_process["idle"].

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
local jobid to AFS:AsyncSimAtmTraj(lexicon(
    "t", 0, "y4", startState,
    "bank_i", bank_i, "bank_f", bank_f,
    "energy_i", energy_i, "energy_f", energy_f
)).
wait until AFS:CheckTask(jobid).
local result1 to AFS:GetTaskResult(jobid).
print "Final predicted range = " + (result1["finalState"][1]/180*constant:PI*body:radius*1e-3) + " km.".
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