# KSP Atmosphere Research

A separate, read-only KSP 1.12 flight plugin for comparing six atmosphere candidates with the game's live vessel readings in stock/RSS/RO/FAR installations. The first RSS/RO/FAR flight supports the native KSP thermal composition, selected by the user. Ten in-game benchmarks now support managed Hermite curves over an immutable native-equation snapshot for the worker implementation; shared Unity curve copies fail concurrent testing. Production kOS-AFS/kOS-LTR integration remains separate.

- [Research and API decisions](docs/Research.md)
- [Installation, flights and log comparison](docs/FlightTest.md)
- [Benchmark results and recommended worker implementation](docs/BenchmarkResults.md)
- [Native performance and thread test: installation and procedure](docs/NativeBenchmark.md)
- [Installed thread-safety audit](docs/ThreadingAudit.md)
- [Exact inspected assembly identities](docs/inspected-assemblies.json)

## Build

On Windows with .NET Framework 4.8 and the local KSP installation:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1 -RunTests

Use -KspRoot "<KSP directory>" to build against another installation. The script invokes the installed Framework C# compiler directly; no NuGet restore, third-party SDK or mod compile dependency is needed. The csproj is also available for IDE/MSBuild environments. Tests additionally require Python 3. The package is artifacts/KSP-AtmosphereResearch.zip; nothing is installed into KSP by the build script.

The plugin uses only KSP and Unity at compile time. Optional FAR/Trajectories public APIs are discovered in the already loaded assemblies. The isolated MechJeb private diagnostic is for this experiment only. Copied reference DLLs are used for inspection, ignored by Git and excluded from the package.

## Candidate API

    AtmosphereSample gas = AtmosphereApi.SampleStockNow(body, latitudeDeg, longitudeDeg, altitudeM);
    // gas.PressurePa, gas.TemperatureK, gas.DensityKgM3, gas.Status

Run on Unity's main thread using the current ephemeris. The native composition is selected following first-flight validation; the full wrapper is still main-thread only. Stock thermal calls do not accept a future UT. Other candidates implement IAtmosphereCandidate.Sample with a freshly created AtmosphereQuery. Longitude is normalized; values are not silently clamped. API units are Pa, K, kg/m^3; altitude is above sea level.

## Analysis

    python tools/analyze.py "<session>/samples.csv" --output "<session>/comparison"

Only coherent, finite, in-atmosphere vehicle rows enter accuracy statistics. Geographic probes have no live reference. Keep environment.txt and body snapshots with the CSV so findings remain tied to installed versions and actual loaded atmosphere curves.

## Worker benchmark

Install the rebuilt ZIP and click Run benchmark in the flight panel. F8 hides/shows it. Results go to KSP-root/Logs/AtmosphereResearch/Benchmarks. There is no automatic benchmark. Details and limits are in [NativeBenchmark.md](docs/NativeBenchmark.md).

    python tools/analyze_benchmark.py "<benchmark-folder>"
