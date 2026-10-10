# Native thermal benchmark decision — 2026-10-09

Ten supplied in-game runs cover pad (3), ascent (3), reentry (3), and reentry with UEntry active (1). The complete report and six PNG/SVG figure pairs are in artifacts/Logs/Benchmarks/analysis/report.html; report.md and machine-readable summaries accompany it. tools/report_benchmarks.py reproduces the combined report. Original logs are unchanged and all 50 input hashes are recorded.

## Recommended worker implementation

Keep the native KSP atmosphere equations and loaded curve keys. Use managed Hermite curve evaluation with private immutable key arrays and scalar/vector state captured on the main thread. The live CelestialBody API remains main-thread only.

| Implementation | Observed cost | Concurrency result |
|---|---|---|
| Full native wrapper, main | 1.05-1.28 us/query by run | Not suitable for direct worker calls: live transform access |
| Copied Unity curves, one worker | 0.296-0.324 us/query | No one-worker failures observed; concurrent sharing fails |
| Managed Hermite, one worker | 0.477-0.497 us/query | Zero failures at 1/2/4 workers |

The frozen kernels receive prepared radial geometry and avoid live API/coordinate-conversion overhead. All timings include harness traversal, checksum and cancellation checks; about 16% of the workload is vacuum. These are not complete integration timings or air-only benchmarks.

Managed Hermite completes 11,468,800 timed worker calls plus 161,000 exact-reference sweep queries with zero mismatches, checksum failures or exceptions. Against the full same-frame native API, its maximum sufficient-density relative error is 0.0000292923%, maximum atmospheric temperature error is 0.0000610352 K, and maximum pressure error is 0.00190735 Pa. The single UEntry-active run costs 0.496741 us/query, approximately 3.1% above the median of the three earlier reentry runs; this does not establish causal slowdown.

At 0.48 us/query, 100,000 calls add about 48 ms. Six evaluations per attempted RKF45 step add about 2.9 us before other work or retries. Warm snapshot capture takes 32.8-41.7 us (median 33.7 us), with the first observed capture 501.3 us. There is no evidence here that a coarser lookup table is necessary. The allocation counter is unavailable, so bytes/query are unknown.

## Shared native curves are rejected

The actual installed AnimationCurve.Evaluate has ThreadSafeAttribute, but concurrent evaluation of the shared copied-curve candidate fails in every two/four-worker run. There are 706 bad exact-reference sweep queries with two workers and 7,079 with four, plus 300/300 timed checksums fail. These produce discrepancies up to 1,477,377 K and 51.684 MPa; they are not rounding noise. No exception is needed for a concurrency failure.

One native worker has no mismatch in 1,638,400 timed calls, and serial copied-native parity has zero recorded difference from KSP. Per-worker native curve ownership or serialization might avoid the shared-instance condition, but neither has been tested. Managed interpolation avoids this native shared evaluation path entirely. The specific internal engine mechanism is not isolated by these logs.

## Limits and corrected analysis

At 139,999 m, the native API returns zero pressure while managed interpolation returns about 1.10e-11 Pa and density near 7e-17 kg/m3. Temperature is still positive. These locations are atmospheric boundary-rounding cases, not vacuum failures; they enter temperature checks but cannot enter relative-density error against zero. At and above 140 km, both snapshot variants return zero pressure and density.

Worker frame stages contain only 2-4 frames and cannot establish tail latency or an FPS effect. Rows named idle carry the previous run's frame buffer and GC interval; the combined report excludes those rows from conclusions. No collection is recorded in timing batches or valid active frame stages, which does not prove zero allocation.

The model still freezes solar/orbit state at capture UT. Integration must define future-time body rotation and conversion from UEntry's rotating/body-fixed state into snapshot axes, and determine whether seasonal ephemeris evolution needs explicit updates. These benchmarks do not validate other body types, runtime method patches, weighted/looping curves or other seasons. No flight-library or altitude-alignment changes are made during this analysis.
