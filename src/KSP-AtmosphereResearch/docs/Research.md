# Atmosphere API investigation — steps 1 and 2

This document preserves the initial candidate study. The 2026-10-09 first flight supported native thermal on nighttime reentry, and the user selected that model. The initial study was followed by [performance and worker-thread verification](NativeBenchmark.md), backed by the [installed call audit](ThreadingAudit.md). The completed decision, seasonal failure diagnostic and kOS-ATM migration are summarized in [ResultsSummary.md](ResultsSummary.md).

## Evidence and installed versions

Inspected the IL and public/private signatures of the actual local assemblies, using the installed Mono.Cecil library without loading KSP into a standalone process. Full local inspection outputs are in the ignored artifacts/inspection directory. SHA-256, assembly version and module identities are recorded in [inspected-assemblies.json](inspected-assemblies.json). The copied FAR and MechJeb references remain ignored and are not bundled.

- FAR and FAR.Base: 0.16.1.2.
- Trajectories: 2.4.5.4, from the installed linuxgurugamer distribution; this is not necessarily the same revision as the supplied neuoy master link.
- MechJeb2: 2.15.0.0. The supplied master URL is not the current readable source; dev was checked and the installed methods were inspected separately.
- KSP Assembly-CSharp: version 0.0.0.0; its exact hash and MVID identify the inspected build. The logger records the actual KSP version and loaded assembly MVIDs at runtime.

## Candidate decisions

| Logger ID / entry point | Decision | Evidence and remaining question |
| --- | --- | --- |
| stock_thermal_now | Strongest native candidate; test | Uses GetAtmoThermalStats(false, sun, normalized direction, sun dot, up axis, altitude, out offset, ...) and GetFullTemperature(altitude, offset), the same composition as FlightIntegrator. Includes the loaded body's latitude, solar, axial-season and eccentricity curves. |
| body_altitude_baseline | Negative control; rejected as complete spatial model | GetPressure(altitude) and GetTemperature(altitude). Matches the general approach currently used by AFS and LTR. |
| flightglobals_position_baseline | Negative control; rejected as complete spatial model | The installed position temperature overload computes altitude and calls GetTemperature(altitude). Passing coordinates does not add solar or latitude corrections. |
| far_registered | Conditional candidate; defaults rejected as complete spatial model | Calls the installed public FARAtmosphere.GetGasProperties. FAR accepts location and UT, but its default delegates use altitude alone. Another mod may register different functions. Log IsCustom and compare actual outputs. |
| trajectories_position | Test the actual installed public helpers | StockAeroUtil.GetTemperature(worldPosition, body) and GetDensity(worldPosition, body) account for latitude and a shifted solar angle, but differ from the installed native season/eccentricity calculation. Pressure is supplied by body.GetPressure because this helper does not expose pressure. |
| mechjeb_private_diagnostic | Research comparison only; rejected as supported production API | Actual private GetTemperature, StaticPressure and AirDensity methods on a separate ReentrySimulation and separate copied SimCurves context. No active predictor or pool is used. |
| GetFullTemperature(Vector3d) | Reject; not implemented as a candidate | In this installed assembly it returns the thermal offset, not the full ambient temperature, and its solar vector is not normalized. Its name is misleading. The altitude/offset overload has the required composition. |
| FARVesselAero.SimulateAeroProperties / Trajectories force models | Reject as atmosphere query APIs | Return forces tied to a vessel rather than arbitrary-location gas properties; force inversion cannot uniquely determine temperature/pressure/density. |

The stock findings above come from the installed assembly, not from guesses based on method names. GetAtmoThermalStats returns an offset; temperature is base temperature plus atmosphereTemperatureSunMultCurve(altitude) times that offset. Native code also handles a small solar-normalization denominator at the poles. This makes pole probes useful when checking the other candidates.

FAR's default pressure is Pa; KSP pressure APIs use kPa. GasProperties computes density using pressure divided by specific gas constant and temperature. The live FARVesselAero method reads vessel.atmDensity, whereas its prediction method reads FARAtmosphere gas properties. A public prediction API therefore does not guarantee matching live flight. [FAR atmosphere source](https://github.com/KSPModStewards/Ferram-Aerospace-Research/blob/master/FerramAerospaceResearch/FARAtmosphere.cs), [FAR vessel source](https://github.com/KSPModStewards/Ferram-Aerospace-Research/blob/master/FerramAerospaceResearch/FARAeroComponents/FARVesselAero.cs).

The installed MechJeb temperature calculation uses latitude and solar normalization, but samples axialTemperatureSunMultCurve using a solar-axis dot value. It does not use the native axialTemperatureSunBiasCurve season term or eccentricityTemperatureBiasCurve. It has an unguarded division at polar geometry. Its pressure and density methods are private as well. Calling them on an isolated context preserves the exact installed calculation for comparison; it does not turn them into a stable API. [MechJeb source](https://github.com/MuMech/MechJeb2/blob/dev/MechJeb2/ReentrySimulation.cs).

Trajectories' installed public helper resembles MechJeb's temperature calculation and has the same polar/season limitations. Its force wrappers are a separate concern: StockModel packs/unpacks forces with altitude-only density and AeroDynamicModel's spatial density correction is commented out. Testing the position helper does not validate the entire Trajectories predictor. [StockModel source](https://github.com/neuoy/KSPTrajectories/blob/master/src/Plugin/AeroDynamicModels/Models/StockModel.cs), [AeroDynamicModel source](https://github.com/neuoy/KSPTrajectories/blob/master/src/Plugin/AeroDynamicModels/AeroDynamicModel.cs). Installed IL is the authority for the helper tested here.

## Coordinate, time and unit contracts

All query locations use body-fixed latitude/longitude in degrees and altitude above sea level in metres. Longitude wraps into [-180, 180). Negative altitude is permitted above the body's centre, to investigate below-sea-level behavior. Public samples use pressure Pa, temperature K and density kg/m^3. Internal stock density conversion receives kPa. FAR receives (latitude, longitude, altitude), Trajectories receives a world position, and MechJeb receives a body-relative world-axis position.

SampleStockNow and all diagnostic queries use the CURRENT ephemeris and current body orientation on Unity's main thread. Create a fresh query and sample it immediately. The native thermal method reads live orbital true anomaly and radius; it has no UT argument. A future-UT model cannot be produced merely by passing a future time to these stock methods. FAR exposes a UT parameter, but its defaults ignore it. No candidate here is claimed to predict future season or body rotation. Step 3 must decide whether a current-ephemeris approximation suffices or requires an explicit ephemeris/curve snapshot.

Vacuum temperature is not an ambient gas measurement. Raw candidate outputs are retained, including zero/NaN boundary results; invalid values are flagged rather than silently clamped. Exact atmospheric-depth boundaries are diagnostic probes, not ranking data.

## Runtime verification and compatibility limits

Live reference: vessel.staticPressurekPa * 1000, vessel.atmosphericTemperature, vessel.atmDensity. These are the game's active gas readings, not a recomputation from a candidate. vessel.externalTemperature is logged separately because FlightIntegrator makes it the maximum of ambient and shock temperature.

Sampling resumes after WaitForFixedUpdate, after physics callbacks. FlightIntegrator altitude, pressure, temperature, density, thermal offset and solar dot are captured before candidate calls. Reference coherence requires matching vessel/integrator values and altitude within one metre. Root/min/max part densities are also logged to expose gradients across the vehicle. The reference is specific to the game's live vessel sampling location; it is not a laboratory truth for every part. Coherence cannot prove that an arbitrary late-running mod uses identical update ordering, so inspect outliers and compare offset/solar fields too.

The native candidate uses the loaded CelestialBody and its virtual thermal methods, so RSS/Kopernicus/RO configuration curves are taken from the active game rather than hardcoded Earth tables. ModularFlightIntegrator or other plugins can override live behavior. Such patches may make the native candidate disagree with the vessel; that disagreement is precisely what the logger is meant to reveal. FAR's public registered functions are queried without replacing them. No hooks, physics controls, flight forces, save data or active mod predictor state are changed.

Each session records loaded assembly identities and each visited body's atmosphere settings and curve keys. Missing or changed mod APIs become unavailable/error rows; no substitution is hidden. Direct FAR delegate exceptions may be swallowed inside FAR itself and fall back to defaults; consult KSP.log if this happens. IsCustom also includes wind/gas constants and is not proof that pressure/temperature are customized.

## Completion and validation

The plugin was compiled against the installed KSP/Unity assemblies with warnings treated as errors. API contract tests verify coordinate wrapping, input rejection, pressure conversion, thermal offset composition and cutoff/status handling using lightweight stand-ins. Python tests verify comparison math and exclusion of probes, vacuum, stale references and nonfinite outputs. These tests do not emulate KSP physics. The first flight subsequently verified in-game loading and supported the native thermal composition on the tested RSS/RO/FAR nighttime reentry. The user selected that model; efficiency and frozen worker-kernel parity remain to be measured in game.
