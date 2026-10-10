# Installed native thermal call audit

Inspected KSP Assembly-CSharp MVID 4b449f28-41f8-4227-adfa-ad3149c8fdba and UnityEngine.CoreModule MVID 12e76cd5-0cc6-4cf1-9e75-9e981cb725af. Full generated audit is artifacts/inspection/native-threading-audit.txt. tools/InspectThreading.cs reproduces the call/field/attribute listing using the same Mono.Cecil inspection dependency as the initial study.

| Boundary | Installed evidence | Decision |
|---|---|---|
| Full GetAtmoThermalStats(false, ...) | Transform position/up calls before the getBodyFlux branch; live orbit/trueAnomaly/radius reads | Main thread only |
| GetFullTemperature(altitude, offset) | GetTemperature + FloatCurve.Evaluate | Reads live body/settings/curve ownership; not used on workers |
| GetPressure | Reads live body flags/settings and pressure curve | Not used on workers |
| FloatCurve.Evaluate | Direct AnimationCurve.Evaluate call | Copy curves rather than share mutable game-owned configuration |
| AnimationCurve.Evaluate | UnityEngine.Bindings.ThreadSafeAttribute | Runtime tests reject concurrent sharing of private copies; one-worker results alone do not justify sharing |
| Quaternion * Vector3 and Vector3.Dot | Managed field/arithmetic IL | Use with captured value inputs on workers |
| Quaternion.AngleAxis | Native binding declares IsThreadSafe=True | Still captured on main thread in this test |
| Managed Hermite kernel | Copied unweighted keys, managed arithmetic and private read-only state | Test parity and deterministic concurrent use |

Native thermal equations were reconstructed only for the frozen variants, including the guarded polar denominator (range <= 0.001), hemisphere-folded latitude, 45-degree lag signed by rotation period, axial bias times latitude multiplier, orbital eccentricity term, loaded temperature/pressure curves and body-specific ideal gas conversion. GetAtmoThermalStats(false, ...) does not write bodyTemperature on this audited path. The frozen implementation omits unused flux calculations, which do not enter ambient temperature for false.

The first flight supports choosing this temperature model. It does not establish worker safety, model portability to body overrides/patches, future ephemeris correctness, or efficiency. The new runtime parity and performance tests cover the tested assembly/configuration and snapshot workload. A lock around native calls cannot synchronize KSP/Unity's scene updates and does not remove a main-thread requirement.

Source corroboration: [Unity 2019.4 curve bindings](https://github.com/Unity-Technologies/UnityCsReference/blob/2019.4/Runtime/Export/Animation/AnimationCurve.bindings.cs), [Unity 2019.4 Transform bindings](https://github.com/Unity-Technologies/UnityCsReference/blob/2019.4/Runtime/Transform/ScriptBindings/Transform.bindings.cs).

## Subsequent runtime result

The ten 2026-10-09 benchmark runs overturn the shared-native-curve candidate. Despite the installed annotation, shared copies produce large output discrepancies with 2/4 workers in every run. The managed Hermite variant has no mismatch or exception over 11,468,800 timed calls. See [BenchmarkResults.md](BenchmarkResults.md) for the recommendation and limits. An eligible binding annotation is not sufficient evidence of safe concurrent shared-instance use in this tested runtime.
