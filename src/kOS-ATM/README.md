# kOS-ATM

[AtmosphereModel.md](AtmosphereModel.md) describes the reconstructed equations, curve inputs, solar/seasonal geometry, future-time propagation and validation limits.

kOS-ATM provides ambient pressure (Pa), temperature (K), and density (kg/m³) using the KSP 1.12.5 thermal equations and the loaded body's atmosphere configuration. Latitude, longitude, Sun height, season and eccentricity are included. RSS/RO/FAR Earth is the researched environment; [results and failure analysis](../KSP-AtmosphereResearch/docs/ResultsSummary.md) explain the decision and its limits.

## Install this migration

Close KSP. Extract `artifacts/kOS-ATM-integration.zip`. Copy its GameData contents into KSP's GameData and replace the old AFS/LTR DLLs. Keep exactly one copy of each:

- GameData/kOS-ATM/Plugins/kOS-ATM.dll
- GameData/kOS-AFS/Plugins/kOS-AFS.dll
- GameData/kOS-LTR/Plugins/kOS-LTR.dll

Existing installations may keep AFS/LTR under another plugin directory. Replace those files there instead of leaving duplicate assemblies. kOS and FAR remain required for AFS/LTR; Unity.Mathematics comes from the installed KSPBurst dependency. kOS-ATM itself does not require FAR or KSPBurst. No third-party DLLs are bundled.

Copy the included Script files into the matching locations in the kOS archive (volume 0). The package includes the five changed production scripts and boot/atm_check.ks. Old script copies calling InitAtmModel, GetDensityEst or GetAltEst must be updated together with the DLLs.

## kOS queries

```kerboscript
local gas_sample to addons:ATM:GetAt(lexicon(
    "body", ship:body,
    "latitude", ship:geoposition:lat,
    "longitude", ship:geoposition:lng,
    "altitude", ship:altitude,
    "ut", time:seconds
)).
print gas_sample["temperature"].
print gas_sample["pressure"].
print gas_sample["density"].
```

GetAt requires latitude/longitude in degrees and ASL altitude in metres. Body defaults to the vessel's body, and ut defaults to capture time. Longitude wraps; latitude must lie in [-90,90]. Negative altitude is allowed above the body's centre. At or above atmosphere depth, pressure, temperature and density return zero; that temperature is a vacuum sentinel, not a gas measurement. The lexicon also contains temperature_offset.

GETDENSITYAT(altitude), GETSCALEHEIGHTAT(altitude), and GETALTFORDENSITY(density) use the vessel's current geographic column and current time. The last helper searches [0, atmosphere depth], clamps densities above the sea-level value to 0 m, returns atmosphere depth for zero density and rejects ambiguous multiple roots. These one-argument helpers have spatial context; they are not global altitude-only atmosphere models.

DENSITY, TEMPERATURE and PRESSURE suffixes expose the vessel's measured ambient readings. Temperature is atmosphericTemperature, not external/shock temperature.

## Reusable snapshots and trajectory time

```kerboscript
local atmosphere_ref to addons:ATM:Snapshot().
local future_gas to atmosphere_ref:GetAt(lexicon(
    "latitude", ship:geoposition:lat,
    "longitude", ship:geoposition:lng,
    "altitude", 50000,
    "ut", atmosphere_ref:EpochUT + 300
)).
local predict_args to lexicon(
    "t", 0, "vecR", -ship:body:position,
    "vecV", ship:velocity:surface,
    "atmosphere", atmosphere_ref
).
// Configure LTR's vehicle/aerodynamic tables first.
local job_handle to addons:LTR:AsyncSimAtmTraj(predict_args).
```

Snapshot captures the vessel body and column. SNAPSHOTBODY(body_ref) captures another body, with the equatorial 0° longitude column. A snapshot exposes BODYNAME, EPOCHUT, DEPTH, GETAT(args), GETCOLUMN(altitude), GETDENSITYAT(altitude), GETSCALEHEIGHTAT(altitude), and GETALTFORDENSITY(density). GETCOLUMN uses its captured column and epoch.

AFS/LTR's `t` is elapsed simulation seconds since the snapshot epoch, not absolute UT. vecR/vecV are body-fixed position/surface velocity in axes aligned with the game's raw world axes at that epoch. A chained segment must reuse the same snapshot and the previous result's t. A future coast state must be rotated back into that epoch's body-fixed frame before integration, as UEntry does. Supplying no snapshot causes an automatic capture at task submission; that is suitable for a fresh t=0 state only. InitBody and BODYSPIN must agree with the snapshot; a wrong body or spin is rejected.

The new equations use managed Kepler propagation for each celestial orbital link and rotation for the body's surface. Capture verifies orbit phase and vector-axis conversion against KSP's propagated positions at epoch and +3600 seconds. No live body, orbit, Unity curve, transform, mutable cache, or game API is accessed during managed evaluation. Capture belongs on the main thread. Refresh snapshots for each new state/frame, body change, or configuration change; retain one for related/chained predictions.

C# consumers reference kOS-ATM.dll and call AtmosphereCapture.Capture(vessel) on the main thread. AtmosphereSnapshot.EvaluateGeographic(lat,lon,h,absoluteUT) and EvaluatePosition(x,y,z,elapsedSeconds) are reusable worker APIs. Snapshot creation is separate from query cost.

## Build and checks

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File src/kOS-ATM/build.ps1 -RunTests
```

The script builds all three plugins, runs managed and predictor tests, compiles all six scripts with the installed kOS compiler, checks the migration and new KerboScript identifiers, and creates the integration ZIP. It requires a .NET SDK (Roslyn) and .NET Framework 4.8 reference assemblies. Use -KspRoot and -ReferenceRoot for another installation. ReferenceRoot optionally supplies local Unity.Mathematics.dll and FAR/FAR.Base DLL copies; otherwise the installed GameData paths are used. References are ignored and not distributed. The csproj files also share src/AtmosphereAddons.props and use an ATM project reference; old NuGet/build-tool and external kOS test-project dependencies have been removed.

Offline tests pass, including one million concurrent future queries and parallel AFS/LTR predictions. Run `runpath("0:/boot/atm_check.ks").` on the pad, in ascent and on reentry to check loading and current temperature/density parity. That script writes no log files. Then fly UEntry/BORG normally. Future-time accuracy and performance of the integrated implementation still need in-game acceptance; the previous 0.482 µs query benchmark measured the frozen research kernel.

Curve weights and looping wraps, custom virtual thermal overrides, nonelliptical celestial orbits and a heated primary star are rejected. Runtime patches or weather mods that replace live thermal behavior can still differ from this configuration-based port and require renewed comparison. No logger altitude correction was made.
