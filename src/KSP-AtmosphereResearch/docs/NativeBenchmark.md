# Native thermal: efficiency and worker-thread verification

The native KSP thermal composition is selected from the first flight. Altitude alignment is left unchanged as requested. This test does not change kOS-AFS, kOS-LTR or your flight controls.

## Install and run

1. Close KSP. Extract the new KSP-AtmosphereResearch.zip into GameData, replacing the existing research DLL and cfg. Keep only one copy of the DLL.
2. Enter flight with a vehicle around Earth. You may start on the launchpad: a new panel appears at the upper right. F8 hides/shows it. Click **Run benchmark** once.
3. Wait for **Complete**. The test has a 60-second wall-time ceiling and a Cancel button. Usually it should take a few to a few tens of seconds; the duration is not measured until you run it.
4. Repeat three times on the pad, then once during ascent and once during reentry (or stable atmospheric flight). Include one run with UEntry's background prediction active to measure contention. The panel does not require kOS commands or special instruments.
5. Copy the new folders under **KSP-root/Logs/AtmosphereResearch/Benchmarks/** back to **src/KSP-AtmosphereResearch/artifacts/Benchmarks/** and provide the folder path. Retain completion.txt and environment.txt with the CSV files.

The ordinary flight logger pauses during each benchmark and resumes afterwards. Set benchmarkEnabled=false in AtmosphereResearch.cfg to remove the panel. The normal logger's enabled flag and benchmarkEnabled are independent; enabled=false can disable regular flight logging while preserving benchmarks.

## Why full native calls stay on the main thread

The installed GetAtmoThermalStats(false, ...) directly reads sun.scaledBody.transform.position, body.bodyTransform.up and body.scaledBody.transform.position, then live orbit fields. These reads happen even with getBodyFlux=false. The full SampleStockNow wrapper also reads live transforms, Planetarium and ScaledSpace state. A caller-side lock cannot make these operations valid on Unity's worker threads or synchronize the rest of the game. Passing prepared geometry does not remove the internal transform reads.

Consequently the full native query is disqualified for direct use in the background integrator by the call audit. It is benchmarked on the main thread, not executed unsafely off-thread to see whether it happens to survive.

There is a useful narrower contract: this installation's AnimationCurve.Evaluate method carries UnityEngine.Bindings.ThreadSafeAttribute. FloatCurve.Evaluate just calls that method. The benchmark checks the loaded runtime attribute again before enabling copied-native-curve workers. Unity 2019.4's [curve bindings](https://github.com/Unity-Technologies/UnityCsReference/blob/2019.4/Runtime/Export/Animation/AnimationCurve.bindings.cs) declare Evaluate thread safe, whereas [Transform bindings](https://github.com/Unity-Technologies/UnityCsReference/blob/2019.4/Runtime/Transform/ScriptBindings/Transform.bindings.cs) read native scene state. These sources support the API boundary; the installed DLL audit is the version-specific evidence.

## Three implementations and a control

- **full_native_main**: the selected original wrapper, including coordinate conversion, native GetAtmoThermalStats/GetFullTemperature/GetPressure/density calls and wrapper allocations.
- **copied_native_curves**: native thermal equations reconstructed from the installed IL, with current body/solar/orbit state frozen on the main thread and privately copied AnimationCurve objects. Each worker computes local solar geometry, temperature, pressure and density without retaining or accessing a live body, orbit or transform. Curves are read only. The quaternion for the native 45-degree thermal lag is captured on the main thread; worker quaternion multiplication and vector dot products are managed value math in the inspected DLL.
- **managed_hermite**: the same frozen thermal equations with binary-search cubic Hermite evaluation over private copied keys. This avoids Unity native calls in the kernel. Weighted keys and looping curves are explicitly unsupported and cause this variant to be skipped, rather than silently evaluated incorrectly. It is an alternative under evaluation, not an assumed exact replica of Unity float rounding.
- **harness_control_main**: a constant output to measure traversal/delegate/checksum/instrumentation overhead. Do not subtract noisy timings and interpret the remainder as exact CPU instruction cost.

Neither frozen variant is currently a production replacement. They preserve the selected model's solar/latitude/season terms using captured state; they do not keep season, ephemeris or rotation synchronized indefinitely. Inputs supply a body-relative radial unit vector in the snapshot's world axes, as an integrator can derive from its position vector. Main-thread latitude/longitude conversion is excluded from the frozen kernel. A body-fixed/world-axis conversion and future-UT ephemeris contract must be designed when integrating the final model. Native versus frozen comparison therefore includes different API-envelope costs; both costs are reported.

The pressure and temperature normalized-curve and lapse-rate branches are included. Body subclass overrides, runtime patches, weighted curves or different game versions may change behavior; the parity check is required for this installed setup. Snapshot capture creates eight copied curves, once per test; its time and allocation cost are logged separately.

## Test design

Every run captures 460 deterministic locations: a global latitude/longitude grid including both exact poles and near-poles, below-sea-level altitude, several atmospheric heights, depth-1/depth/depth+1 and a local path around the vehicle. Native reference and snapshot capture are completed in the same frame, without yielding, to eliminate evolving ephemeris as a parity confound. This setup does 460 native queries in one frame; timed main-thread work afterwards is broken into small batches.

Parity compares both frozen versions with the full KSP API at these locations. It does not compare against live vehicle gas fields; the first flight already established that part of the model selection.

After untimed warmup, main-thread measurements use 20 batches per implementation, at most 256 calls per batch, with a soft 2 ms limit checked every 32 calls. The control has the same loop structure. No forced GC is performed.

Worker tests use **1, 2 and 4 dedicated background threads**, synchronized by a start gate, with five timed repetitions of 32,768 calls per worker. They all share one immutable snapshot, including shared private copied native curves. Traversal order varies across worker and repetition. Each repetition performs an untimed full-location sweep against that variant's main-thread output before timing, requiring exact deterministic doubles. Timed output checksums are also compared with the expected checksum for that exact traversal after stopping the timer; checksum mismatches contribute to the determinism counter and are logged separately. Exceptions and mismatches are recorded. This checks concurrency separately from native-versus-snapshot approximation error. No worker writes files, reads the vessel, or reads the current game ephemeris.

The 100,000-evaluation standalone parallel test checks managed mathematics with stand-ins. It does not prove Unity native behavior; the in-game test is still necessary. Stress-test success alone cannot prove arbitrary code thread safe: the static API/lifetime audit and runtime results need to agree.

## Outputs, performance interpretation and disk use

Each manual run writes:

- timings.csv: measured batches, ns/call, allocated bytes if the runtime supports its per-thread counter, GC collection deltas, checksum, determinism mismatches and exceptions. Allocation -1 means unavailable. Stopwatch allocation and loop bookkeeping are included. GC counters are process-wide, so concurrent workers may observe the same collection.
- parity.csv: native and frozen values, errors and validity for 460 locations per variant; 920 rows with both variants available.
- frames.csv: baseline/main/worker-stage frame-time median, p95, maximum and process-wide GC deltas. These are observations of the running game, not isolated causal attribution of all frame changes to the benchmark.
- environment.txt: KSP/Unity, loaded assembly versions/MVIDs, CPU count, timing frequency, runtime curve thread-safety declaration, snapshot capture cost and worker parameters.
- completion.txt: Complete, Cancelled or setup failure, with wall duration.

Only aggregate timing batches and one parity set are written; there is no per-call log during the millions of timed evaluations. Typical output should be well below 1 MB per run; logging stops after completion and never starts automatically. Ordinary flight logs retain their previous behavior.

Run the standard-library analyzer after copying results:

python src/KSP-AtmosphereResearch/tools/analyze_benchmark.py PATH_TO_A_BENCHMARK_FOLDER

It writes analysis/report.md, analysis/timing_summary.csv and analysis/parity_summary.csv. It reports ns/call, call budgets and observed concurrency results without inventing a UEntry performance requirement. LTR uses six derivative evaluations per attempted RKF45 step, with rejected steps adding more work; a query microbenchmark is not a complete trajectory-integration benchmark. Group wall throughput includes the correctness sweeps, untimed checksum checks, main-thread completion polling and scheduler overhead. Per-worker timings measure the kernel loop. One worker is the closest comparison with the current asynchronous LTR task, while 2/4 workers expose contention and shared-curve behavior.

Initial parity targets are max density error <= 0.01% for reference density >= 1e-8 kg/m3, max atmospheric temperature error <= 0.02 K, finite physically valid outputs and zero determinism mismatches/exceptions. These are provisional validation gates, not measured results. Thin air and vacuum are audited separately, not allowed to dominate relative-error metrics. Speed suitability will be judged against the returned timings and actual integrator workload; we have not measured in-game performance yet.

## Results from the first ten benchmark runs

The study is complete for these supplied sessions. Shared copied Unity curves fail every 2/4-worker trial; managed Hermite passes all observed concurrency and numerical parity checks. See [BenchmarkResults.md](BenchmarkResults.md). The test harness still includes the failing variant as an experimental comparison, not a production API.
