# kOS-AFS

AFS supplies entry guidance, aerodynamic calibration and asynchronous RKF45 prediction. It now depends on [kOS-ATM](../kOS-ATM/README.md) for all atmospheric data. Build/install the three addons together with ../kOS-ATM/build.ps1 -RunTests and update the UEntry scripts from the integration package.

INITBODY() initializes MU, R and raw kOS-compatible BODYSPIN. INITATMMODEL(), MOLAR_MASS, ATM_HEIGHT, ATMALTSAMPLES, ATMTEMPSAMPLES, ATMLOGDENSITYSAMPLES, GETDENSITYAT, GETDENSITYEST and GETALTEST have been removed. Use ADDONS:ATM queries and snapshots instead. AFS's DENSITY suffix remains live vessel telemetry.

ASYNCSIMATMTRAJ(args) retains the existing bank/energy/state arguments and additionally accepts atmosphere from ADDONS:ATM:SNAPSHOT(). Its t is seconds since that snapshot's EPOCHUT. vecR/vecV belong to a body-fixed frame aligned with world axes at the epoch. Supply the same snapshot when reusing a future/chained state; an omitted snapshot is automatically captured at submission for a fresh t=0 state. UEntry's scripts now manage this epoch across coast propagation and related bank-plan evaluations.

Worker tasks clone all mutable control/aerodynamic arrays and matrices before execution. All RKF45 stages, the initial bank calculation, QEGC temperature/scale-height calculation and terminal-energy refinement use kOS-ATM at the appropriate position/time. No atmospheric altitude table remains in AFS.

FAR hypothetical force samples are normalized by FAR's own gas density; their log-density calibration axis follows that API. The trajectory force uses ATM's spatial density. This preserves the coefficient definition while adding native thermal density to the integrator. [Research evidence and limitations](../KSP-AtmosphereResearch/docs/ResultsSummary.md).
