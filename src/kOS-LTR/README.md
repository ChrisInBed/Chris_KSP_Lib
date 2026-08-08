# kOS-LTR

`kOS-LTR` (Lifting Trajectory) is a kOS addon for fast, open-loop atmospheric impact prediction. It mirrors the layout and public conventions of `src/kOS-AFS`, but assumes zero sideslip and zero bank. A speed-AOA profile determines the simulated attitude, while drag and lift coefficients are bilinearly interpolated over speed and log density.

The predictor integrates body-fixed position and surface velocity with an adaptive RKF45 method. Gravity, drag, lift, Coriolis acceleration, and centrifugal acceleration are included. When the trajectory crosses `target_altitude`, a bounded Newton iteration refines the crossing time and impact state.

## Build and install

Open `kOS-LTR.sln` or build `kOS-LTR/kOS-LTR.csproj` for .NET Framework 4.8. The project follows the same local kOS, FAR, Unity, and NuGet reference layout as `kOS-AFS`; adjust the reference paths if your KSP development tree differs.

Copy `kOS-LTR.dll` into a GameData plugin directory, for example `GameData/kOS-LTR/Plugins/`. FAR and kOS must also be installed.

## kOS API

The addon is available as `ADDONS:LTR`.

- Read-only vessel values: `AOA`, `AOS`, `BANK`, `REFAREA`, `CD`, `CL`, `HEATFLUX`, `GEEFORCE`, `DYNAMICPRESSURE`, `DENSITY`, `LANGUAGE`.
- Body model: `MU`, `R`, `MOLAR_MASS`, `ATM_HEIGHT`, `BODYSPIN`, `ATMALTSAMPLES`, `ATMLOGDENSITYSAMPLES`, `ATMTEMPSAMPLES`.
- Vehicle/aero model: `MASS`, `AREA`, `ROTATION`, `AOAREVERSAL`, `CTRLSPEEDSAMPLES`, `CTRLAOASAMPLES`, `AEROSPEEDSAMPLES`, `AEROLOGDENSITYSAMPLES`, `AEROCDSAMPLES`, `AEROCLSAMPLES`, `SETAERODSFROMALT(altitudes)`.
- Target: `TARGET_ALTITUDE`, `RTARGET`.
- Predictor: `PREDICT_MIN_STEP`, `PREDICT_MAX_STEP`, `PREDICT_TMAX`.
- Synchronous helpers: `GETAOACMD(speed)`, `GETSTATE()`, `GETFARAEROCOEFS(args)`, `GETFARAEROCOEFSEST(args)`, `GETDENSITYAT(altitude)`, `GETDENSITYEST(altitude)`, `GETALTEST(density)`, `INITATMMODEL()`, `DIRECTIONTOANGLEAXIS(direction)`. For kOS-AFS compatibility, `GETAOACMD` also accepts a `vecR`/`vecV` state lexicon; both forms return a lexicon containing `AOA`.
- Async prediction: `ASYNCSIMATMTRAJ(args)`, `CHECKTASK(handle)`, `GETTASKRESULT(handle)`.

`ASYNCSIMATMTRAJ` accepts `LEXICON("t", t0, "vecR", bodyCenteredPosition, "vecV", surfaceVelocity)`. A completed result contains `ok`, `status`, `t`, `finalVecR`, `finalVecV`, `nsteps`, and `msg`. `status` is `COMPLETED`, `TIMEOUT`, `OVERSHOOT`, or `FAILED`. Fetching a result removes its task record.

Set all sample axes and coefficient matrices before starting a prediction. Speed samples must increase strictly. Log-density samples may increase or decrease strictly, which allows `SETAERODSFROMALT` to consume either ascending or descending altitude grids.
