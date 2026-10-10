# KSP atmosphere research: decision and failure analysis

## Decision

Use the installed KSP 1.12.5 thermal equations with immutable managed Hermite curves. Capture game configuration, orientation and celestial orbits on the main thread; evaluate worker queries using copied numeric data. “Native” means KSP's physical temperature composition, not calling live Unity/KSP APIs from a worker. The production implementation is [kOS-ATM](../../kOS-ATM/README.md).

This conclusion applies to the tested RSS Earth / RO / FAR environment: FAR 0.16.1.2, Trajectories 2.4.5.4 and MechJeb2 2.15.0.0 (assembly versions). The installed DLLs, rather than the latest upstream branches, were inspected. Exact assembly identities are in [inspected-assemblies.json](inspected-assemblies.json).

## Accuracy evidence

The first flight covered ascent, suborbital flight and nighttime reentry. The strict live-reference comparison contains 2,032 coherent atmospheric samples. Ascent samples with a sampling-location mismatch were excluded from that ranking; the logger alignment is intentionally unchanged, as requested. These errors include the remaining small location/altitude difference.

| Candidate | Mean absolute density error | Maximum density error | Mean absolute temperature error |
| --- | ---: | ---: | ---: |
| KSP native thermal | 0.006609% | 0.011430% | 0.001276 K |
| Altitude-only / FlightGlobals / FAR default | 1.802079% | 7.018770% | 4.426303 K |
| MechJeb private diagnostic | 0.800752% | 4.143427% | 1.959882 K |
| Trajectories position helper | 0.800777% | 4.143444% | 1.959939 K |

Pressure was effectively the same across candidates at the same queried altitude. Its live-reference mean error was 0.232626 Pa and follows the sampling-location difference. The remaining density differences are primarily temperature differences, not a pressure or ideal-gas-law failure. Longitude probes changed native density by up to 3.74% at fixed altitude/latitude/time; these demonstrate spatial dependence, but have no live vessel reference at the probe locations.

[Full first-flight report](../artifacts/Logs/20261009T130829047Z_c5d8bd2e/analysis/report.html).

## Why FAR's registered atmosphere approach failed this comparison

The public FARAtmosphere API accepts latitude, longitude, altitude and UT, but its installed default pressure and temperature delegates only use altitude. Every recorded FAR row reported IsCustom=False, and its in-air pressure/temperature/density matched the altitude-only control. Supplying coordinates and time therefore did not add the latitude, solar or seasonal correction.

This does not establish that FAR's live flight physics uses this wrong density: the inspected live vessel path reads vessel.atmDensity. FAR's hypothetical-force prediction path instead reads FARAtmosphere.GetGasProperties. Those are different contracts. A plugin can register custom FAR functions, so a different installation must be checked again. IsCustom also includes wind and gas constants; True would not, by itself, demonstrate spatial temperature support.

There were 449 invalid FAR densities in vacuum (310 vehicle rows, 139 probes): zero pressure and zero temperature lead to 0/0 in the gas-properties density calculation. FAR's force predictor separately guards these vacuum gas values. The research adapter exposed the undefined conversion; it is not evidence of a FAR in-air force failure.

## Why Trajectories and MechJeb differed

Both installed helpers implement an older seasonal expression. With B the latitude bias, L the latitude solar multiplier, N the normalized shifted Sun height, A the axial multiplier, S the seasonal bias, E the eccentricity bias, latitude phi, solar-axis dot d and orbital true anomaly nu, their offset is approximately:

```text
legacy offset = B(|phi|) + L(|phi|) * N + A(d)
KSP offset    = B(|phi|) + L(|phi|) * N + S(nu in degrees) * A(|phi|) + E(orbital distance fraction)
temperature   = base temperature(h) + altitudeSunMultiplier(h) * offset
```

The legacy code passes a dimensionless dot product to a curve whose RSS keys cover latitude 0–90 degrees, and omits the actual seasonal bias curve. In this flight d remained negative (about -0.3906), so A(d) clamps to its zero first key. KSP still applies the roughly -16.496 K seasonal bias, modulated by latitude and altitude. RSS's altitude solar multiplier changes sign in several layers, explaining why the legacy error also changes sign with altitude. The installed Earth eccentricity curve is zero, so its omission cannot explain this flight's error.

A new same-position diagnostic fits one seasonal bias across 2,352 vehicle samples with native density above 1e-6 kg/m³. This set deliberately includes ascent: both candidates query the same location, so the vessel-reference location mismatch does not affect this difference. It is separate from the 2,032-sample live ranking above.

| Seasonal-term diagnostic | Trajectories | MechJeb2 |
| --- | ---: | ---: |
| Fitted native seasonal bias | -16.49623 K | -16.49595 K |
| Original helper-minus-native temperature MAE | 2.464600 K | 2.464516 K |
| Residual MAE after seasonal expression | 0.000344 K | 0.000430 K |
| Residual maximum | 0.002661 K | 0.003053 K |

The seasonal expression explains over 99.99999% of the squared same-position temperature difference. This is strong evidence for the failure reason, supported independently by the inspected expression. The fitted bias is inferred from this flight, not an independently logged orbital anomaly or a validation over a seasonal cycle. Small residuals can include phase drift and the helpers' float/solar-geometry differences. The exact density ratio also satisfies rhoLegacy/rhoNative = TNative/TLegacy to within 4.45e-16 in this set.

![Seasonal mismatch diagnostic](../artifacts/Logs/20261009T130829047Z_c5d8bd2e/analysis/08_legacy_seasonal_failure.png)

Both helpers also lack native's guarded acos fallback and its small day/night-range branch. Polar rounding can produce an out-of-domain acos or a zero/tiny normalization denominator. Trajectories had 62 invalid atmospheric pole results, MechJeb 64; native had none. This rules out the helpers as robust general atmosphere APIs.

MechJeb's tested methods are private and were invoked on an isolated diagnostic context; they are not a supported production API. Trajectories' public position helper is available, but testing it does not validate every atmosphere/force path in its full predictor. No general claim about either mod's complete trajectory accuracy is made here.

Reproduce the diagnostic with `python tools/analyze_failures.py artifacts/Logs/20261009T130829047Z_c5d8bd2e` from the research project. CSV residuals and failure_diagnostics.json are alongside the first-flight analysis.

## Efficiency and thread safety

All ten benchmark sessions completed: pad, ascent, reentry, and reentry with UEntry active. The managed implementation passed 11,468,800 timed calls and 161,000 exact sweep queries across one, two and four workers, with zero mismatches, checksum failures or exceptions. Maximum relevant density discrepancy versus native was 0.0000293%; maximum atmospheric temperature discrepancy was 0.0000611 K.

One-worker managed queries took 0.477–0.497 microseconds, median 0.482 microseconds. Thus 100,000 queries cost about 48 ms and six RKF45 atmosphere calls about 2.9 microseconds, excluding other integrator work. These are measurements of the frozen-ephemeris research kernel. The production future-time orbit propagation adds work and needs its own in-game timing; standalone tests cannot substitute for that measurement.

Direct native calls access live transforms and orbit state even when body-flux calculation is disabled. They are unsuitable for the workers. Copied Unity curves passed serial parity, but shared copies failed every multiworker trial: 706 of 46,000 exact sweep queries failed with two workers; 7,079 of 92,000 failed with four. Errors reached roughly 1.48 million K and 51.68 MPa. The precise engine mechanism was not isolated; claiming a specific cache race would overstate the evidence. The observed implementation is rejected despite Unity's ThreadSafeAttribute.

[Benchmark report](../artifacts/Logs/Benchmarks/analysis/report.html), [portable benchmark summary](BenchmarkResults.md), [installed threading audit](ThreadingAudit.md).

## Production migration and validation scope

kOS-ATM owns all atmospheric equations, curves and inverse-column helpers. AFS/LTR no longer contain atmospheric sample arrays, interpolation/extrapolation code, or atmospheric initialization/query suffixes. They retain aerodynamic tables and live vessel telemetry. InitBody initializes gravity, radius and raw kOS-compatible spin.

Each prediction captures or receives an immutable ATM snapshot before starting a worker. All six RKF45 stages query their own position and elapsed time. AFS now clones its mutable aerodynamic/guidance configuration before starting a task, as LTR already did. UEntry shares a snapshot across related bank-plan evaluations; BORG shares one across chained trajectory segments. The snapshot advances body rotation, celestial relative motion, seasonal anomaly and eccentricity with managed equations, rather than freezing the Sun or using an altitude density table.

FAR coefficient calibration divides hypothetical FAR forces by FAR's own gas density and retains that density as the calibration axis. Dividing those forces by the newly selected ambient density would incorrectly rescale Cd/Cl. This migration does not replace FAR's force sampler or introduce a temperature/Mach axis into the existing aerodynamic tables.

All six changed/new scripts compile with the installed kOS compiler, and introduced identifiers pass the repository reserved-name check. Offline validation covers analytic Hermite/orbit/rotation cases, gas units, poles, exact cutoff, inverse queries, one million concurrent future queries, and 32 concurrent AFS/LTR fixture predictions with terminal and chained-time checks. The actual game flight and benchmarks validate the earlier native/frozen managed model, not this newly integrated future-time implementation. Its capture validates the Kepler port against installed KSP at epoch and +3600 s; the supplied smoke test enables the next in-game acceptance check. Runtime thermal hooks, weather delegates, unsupported curve weights/wraps, binary-star heating and nonelliptical celestial orbits are outside the supported port. Unsupported curve/orbit/thermal-override cases fail explicitly.
