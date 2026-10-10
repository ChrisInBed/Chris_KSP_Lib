# kOS-LTR

`kOS-LTR` (Lifting Trajectory) is a kOS addon for fast, open-loop atmospheric impact prediction. It mirrors the layout and public conventions of `src/kOS-AFS`, but assumes zero sideslip and zero bank. A speed-AOA profile determines the simulated attitude, while drag and lift coefficients are bilinearly interpolated over speed and log density.

The predictor integrates body-fixed position and surface velocity with an adaptive RKF45 method. Gravity, drag, lift, Coriolis acceleration, and centrifugal acceleration are included. When the trajectory crosses `target_altitude`, a bounded Newton iteration refines the crossing time and impact state.

## Build and install

Build all three addons with `../kOS-ATM/build.ps1 -RunTests`; see [kOS-ATM installation and API](../kOS-ATM/README.md). The project references kOS-ATM and shared `../AtmosphereAddons.props` for .NET Framework 4.8, installed KSP/kOS/FAR and local reference paths.

Copy `kOS-LTR.dll` into a GameData plugin directory, for example `GameData/kOS-LTR/Plugins/`. FAR, kOS, kOS-ATM and the KSPBurst Unity.Mathematics dependency must also be installed. Replace the matching scripts with the DLLs.

## kOS API

The addon is available as `ADDONS:LTR`.

- Read-only vessel values: `AOA`, `AOS`, `BANK`, `REFAREA`, `CD`, `CL`, `HEATFLUX`, `GEEFORCE`, `DYNAMICPRESSURE`, `DENSITY`, `LANGUAGE`.
- Body model: `MU`, `R`, `BODYSPIN`; initialize with `INITBODY()`. Atmosphere equations and data are owned by kOS-ATM.
- Vehicle/aero model: `MASS`, `AREA`, `ROTATION`, `AOAREVERSAL`, `CTRLSPEEDSAMPLES`, `CTRLAOASAMPLES`, `AEROSPEEDSAMPLES`, `AEROLOGDENSITYSAMPLES`, `AEROCDSAMPLES`, `AEROCLSAMPLES`, `SETAERODSFROMALT(altitudes)`.
- Target: `TARGET_ALTITUDE`, `RTARGET`.
- Predictor: `PREDICT_MIN_STEP`, `PREDICT_MAX_STEP`, `PREDICT_TMAX`.
- Synchronous helpers: `GETAOACMD(speed)`, `GETSTATE()`, `GETFARAEROCOEFS(args)`, `GETFARAEROCOEFSEST(args)`, `INITBODY()`, `DIRECTIONTOANGLEAXIS(direction)`. For kOS-AFS compatibility, `GETAOACMD` also accepts a `vecR`/`vecV` state lexicon; both forms return a lexicon containing `AOA`.
- Async prediction: `ASYNCSIMATMTRAJ(args)`, `CHECKTASK(handle)`, `GETTASKRESULT(handle)`.

`ASYNCSIMATMTRAJ` accepts `LEXICON("t", elapsedSeconds, "vecR", bodyCenteredPosition, "vecV", surfaceVelocity, "atmosphere", atmosphereSnapshot)`, where `atmosphereSnapshot` comes from `ADDONS:ATM:SNAPSHOT()`. Position axes are fixed to the body at the snapshot epoch, and `t` is elapsed since that epoch. Chained predictions must retain the same snapshot. Omitting it captures at submission, suitable for a fresh `t=0` state. A completed result contains `ok`, `status`, `t`, `finalVecR`, `finalVecV`, `nsteps`, and `msg`. `status` is `COMPLETED`, `TIMEOUT`, `OVERSHOOT`, or `FAILED`. Fetching a result removes its task record.

Set all sample axes and coefficient matrices before starting a prediction. Speed samples must increase strictly. Log-density samples may increase or decrease strictly, which allows `SETAERODSFROMALT` to consume either ascending or descending altitude grids.

Each RKF45 stage evaluates kOS-ATM at its position/time. The snapshot advances solar/orbital geometry with managed equations. FAR aerodynamic coefficients and their density axis are calibrated using FAR’s own hypothetical-force gas properties, while trajectory density uses native thermal. The old atmospheric interpolation suffixes and arrays have been removed.
