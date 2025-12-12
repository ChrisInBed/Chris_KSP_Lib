runOncePath("0:/lib/atm_utils.ks").

if (not addons:hasaddon("AFS")) {
    print "AFS addon is not installed. Please install the AFS addon to use this script.".
    print 1/0.
}
if (not addons:hasaddon("FAR")) {
    print "FAR addon is not installed. Please install the FAR addon to use this script.".
    print 1/0.
}

set AFS to addons:AFS.
set FAR to addons:FAR.

// set basic ship parameters
set AFS:mu to body:mu.
set AFS:R to body:radius.
set AFS:rho0 to atm_get_sealevel_density().
set AFS:hs to atm_get_scale_height().
set AFS:mass to ship:mass.
set AFS:area to FAR:REFAREA.
declare global bank_i to 50.
declare global bank_f to 10.
declare global energy_i to get_spercific_energy(body:radius+ship:altitude, ship:velocity:orbit:mag).
declare global energy_f to get_spercific_energy(body:radius+10e3, 300).
// set AFS:k_QEGC to 1.
// set AFS:k_C to 1.
// set AFS:t_reg to 60.
set AFS:Qdot_max to 5e6.
set AFS:acc_max to 30.
set AFS:dynp_max to 15e3.
set AFS:L_min to 0.5.
set AFS:target_energy to energy_f.
set AFS:predict_min_step to 0.
set AFS:predict_max_step to 0.5.
set AFS:predict_tmax to 3600.
set AFS:speedsamples to list(300, 2000, 8000).
declare global AOAProfile to list(15, 35, 40).
declare global HProfile to list(10e3, 60e3, 80e3).
declare global ClProfile to list().
declare global CdProfile to list().
from {local i to 0.} until i = 3 step {set i to i+1.} do {
    local CLD to atm_get_CLD_at(AOAProfile[i], AFS:speedsamples[i], HProfile[i]).
    ClProfile:add(CLD[0]).
    CdProfile:add(CLD[1]).
}
set AFS:Clsamples to ClProfile.
set AFS:Cdsamples to CdProfile.
print "Lift and Drag coefficients profiles:".
print "AOA (deg): " + AOAProfile.
print "Altitude (m): " + HProfile.
print "Cl: " + ClProfile.
print "Cd: " + CdProfile.

function get_spercific_energy {
    parameter rr.
    parameter vv.
    return -body:mu/rr + 0.5*vv*vv.
}

// test item: Bank command
print "V = 6km/s, Alt = 80km, Bank = " + AFS:GetBankCmd(lexicon(
    "y4", list(80e3+body:radius, 0, 6e3, -5),
    "bank_i", bank_i, "bank_f", bank_f,
    "energy_i", energy_i, "energy_f", energy_f
)) + " degrees.".

// test item: Predictor
declare global startState to list(body:radius+150e3, 0, 7.8e3, -5).
print "Predictor test from 150km altitude, 7.8km/s speed, -5 deg path angle.".
declare global startComputeTime to time:seconds.
declare global jobid to AFS:AsyncSimAtmTraj(lexicon(
    "t", 0, "y4", startState,
    "bank_i", bank_i, "bank_f", bank_f,
    "energy_i", energy_i, "energy_f", energy_f
)).
wait until AFS:CheckTask(jobid).
// until (AFS:CheckTask(jobid)) {local i to 1.}
declare global endComputeTime to time:seconds.
print "Computation time: " + (endComputeTime - startComputeTime) + " seconds.".
declare global result to AFS:GetTaskResult(jobid).
print "Predicted final state after atmospheric trajectory:".
print result.