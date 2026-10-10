using System;
using System.Collections.Generic;
using System.Threading;
using UnityEngine;

namespace KOSAtmosphere
{
    [KSPAddon(KSPAddon.Startup.Instantly, true)]
    public sealed class AtmosphereMainThread : MonoBehaviour
    {
        internal static int ThreadId;
        public void Awake() { ThreadId = Thread.CurrentThread.ManagedThreadId; }
    }
    /// <summary>Only this class reads game state. Call on Unity's main thread before starting workers.</summary>
    public static class AtmosphereCapture
    {
        private static void RequireMainThread()
        {
            if (AtmosphereMainThread.ThreadId == 0 || Thread.CurrentThread.ManagedThreadId != AtmosphereMainThread.ThreadId)
                throw new InvalidOperationException("Capture atmosphere snapshots on the KSP main thread");
        }
        private static AtmosphereVector Copy(Vector3d p) { return new AtmosphereVector(p.x, p.y, p.z); }
        public static AtmosphereVector AngularVelocity(CelestialBody body)
        {
            RequireMainThread();
            // Exactly kOS BodyTarget.RawAngularVelFromRelative, not KSP's relative vector.
            Vector3 relative = body.angularVelocity;
            Vector3 raw = kOS.Utilities.VesselUtils.GetFacing(body).Rotation * new Vector3(relative.x, -relative.z, relative.y);
            return Copy(raw);
        }
        public static AtmosphereSnapshot Capture(CelestialBody body)
        {
            RequireMainThread();
            if (body == null) throw new ArgumentNullException("body");
            return Capture(body, Copy(body.GetWorldSurfacePosition(0, 0, 0) - body.position).Normalized);
        }
        public static AtmosphereSnapshot Capture(Vessel vessel)
        {
            RequireMainThread();
            if (vessel == null) throw new ArgumentNullException("vessel");
            return Capture(vessel.mainBody, Copy(vessel.CoMD - vessel.mainBody.position).Normalized);
        }
        public static AtmosphereSnapshot Capture(CelestialBody body, AtmosphereVector columnUp)
        {
            RequireMainThread(); if (body == null) throw new ArgumentNullException("body");
            if (body.GetType().GetMethod("GetAtmoThermalStats").DeclaringType != typeof(CelestialBody))
                throw new NotSupportedException("Custom body thermal overrides require a dedicated atmosphere adapter");
            SnapshotData d = new SnapshotData();
            d.BodyName = body.bodyName; d.Epoch = Planetarium.GetUniversalTime();
            d.HasAir = body.atmosphere; d.Depth = body.atmosphereDepth; d.Radius = body.Radius; d.Mu = body.gravParameter;
            d.ColumnUp = columnUp.Normalized; d.Axis = Copy(body.bodyTransform.up); d.Spin = AngularVelocity(body);
            // GetRelSurfaceNVector is a local vector and ignores body orientation.
            // GetWorldSurfacePosition applies this body's BodyFrame, including tilt/rotation.
            d.North = Copy(body.GetWorldSurfacePosition(90, 0, 0) - body.position).Normalized;
            d.ZeroLongitude = Copy(body.GetWorldSurfacePosition(0, 0, 0) - body.position).Normalized;
            d.EastLongitude = Copy(body.GetWorldSurfacePosition(0, 90, 0) - body.position).Normalized;
            if (!d.HasAir || d.Depth <= 0) { d.HasAir = false; return new AtmosphereSnapshot(d); }
            CelestialBody sun = Planetarium.fetch.Sun;
            if (sun == null || sun.scaledBody == null || body == sun) throw new NotSupportedException("A distinct primary sun is required for this atmosphere");
            d.Molar = body.atmosphereMolarMass; d.Gas = PhysicsGlobals.IdealGasConstant; d.Space = PhysicsGlobals.SpaceTemperature;
            d.PressureSea = body.atmospherePressureSeaLevel; d.TempSea = body.atmosphereTemperatureSeaLevel;
            d.Lapse = body.atmosphereTemperatureLapseRate; d.GasLapse = body.atmosphereGasMassLapseRate;
            d.UsePressure = body.atmosphereUsePressureCurve; d.PressureNormalized = body.atmospherePressureCurveIsNormalized;
            d.UseTemp = body.atmosphereUseTemperatureCurve; d.TempNormalized = body.atmosphereTemperatureCurveIsNormalized;
            Quaternion lag = Quaternion.AngleAxis(45 * Mathf.Sign((float)body.rotationPeriod), body.bodyTransform.up);
            d.Lag = new FloatRotation(lag.x, lag.y, lag.z, lag.w);
            d.SunFromCenter = Copy((Vector3d)sun.scaledBody.transform.position - ScaledSpace.LocalToScaledSpace(body.position));
            d.InverseScale = ScaledSpace.InverseScaleFactor;
            CelestialBody reference = CelestialBody.GetBodyReferencing(body, sun);
            Orbit season = reference.orbit;
            d.SeasonOrbit = CopyOrbit(season, d.Epoch); d.Anomaly = season.trueAnomaly;
            d.EccFraction = season.eccentricity == 0 ? double.NaN : (season.radius - season.PeR) / (season.ApR - season.PeR);
            d.EccSpan = season.ApR - season.PeR;
            var cache = new Dictionary<Orbit, EllipticOrbit>(); cache[season] = d.SeasonOrbit;
            var signs = new Dictionary<Orbit, double>();
            AddPath(body, -1, signs); AddPath(sun, 1, signs);
            var terms = new List<OrbitTerm>();
            foreach (var pair in signs)
            {
                if (pair.Value == 0) continue;
                EllipticOrbit orbit;
                if (!cache.TryGetValue(pair.Key, out orbit)) { orbit = CopyOrbit(pair.Key, d.Epoch); cache.Add(pair.Key, orbit); }
                terms.Add(new OrbitTerm(orbit, pair.Value));
            }
            d.OrbitTerms = terms.ToArray();
            d.Pressure = CopyCurve(body.atmospherePressureCurve, "pressure"); d.Temperature = CopyCurve(body.atmosphereTemperatureCurve, "temperature");
            d.SunMult = CopyCurve(body.atmosphereTemperatureSunMultCurve, "altitude solar multiplier"); d.LatBias = CopyCurve(body.latitudeTemperatureBiasCurve, "latitude bias");
            d.LatMult = CopyCurve(body.latitudeTemperatureSunMultCurve, "latitude solar multiplier"); d.AxialBias = CopyCurve(body.axialTemperatureSunBiasCurve, "seasonal bias");
            d.AxialMult = CopyCurve(body.axialTemperatureSunMultCurve, "seasonal latitude multiplier"); d.EccBias = CopyCurve(body.eccentricityTemperatureBiasCurve, "eccentricity bias");
            return new AtmosphereSnapshot(d);
        }
        private static void AddPath(CelestialBody body, double sign, Dictionary<Orbit, double> signs)
        {
            var visited = new HashSet<CelestialBody>();
            while (body != null && body.orbit != null && body.orbit.referenceBody != body)
            {
                if (!visited.Add(body)) throw new InvalidOperationException("Cyclic celestial hierarchy");
                Orbit orbit = body.orbit; double existing; signs.TryGetValue(orbit, out existing); signs[orbit] = existing + sign;
                body = orbit.referenceBody;
            }
        }
        private static EllipticOrbit CopyOrbit(Orbit orbit, double epoch)
        {
            if (orbit == null) throw new NotSupportedException("Missing celestial orbit");
            // KSP Orbit's local vector is Z-up; world/trajectory vectors use xzy.
            Vector3d peri = orbit.getRelativePositionFromTrueAnomaly(0).xzy;
            Vector3d transverse = orbit.getRelativePositionFromTrueAnomaly(Math.PI / 2).xzy;
            var result = new EllipticOrbit(orbit.semiMajorAxis, orbit.eccentricity, orbit.getMeanAnomalyAtUT(epoch), orbit.period, Copy(peri), Copy(transverse));
            // Verify the orientation/phase port against this installed KSP, including a future point.
            foreach (double dt in new[] { 0.0, 3600.0 })
            {
                AtmosphereVector expected = Copy(orbit.getRelativePositionAtUT(epoch + dt).xzy), actual = result.Position(dt);
                if ((actual - expected).Length > Math.Max(.01, expected.Length * 1e-8))
                    throw new NotSupportedException("Installed celestial orbit disagrees with managed Kepler propagation");
            }
            return result;
        }
        private static HermiteCurve CopyCurve(FloatCurve source, string name)
        {
            if (source == null) throw new NotSupportedException("Missing atmosphere curve: " + name);
            AnimationCurve curve = source.Curve;
            if (curve.preWrapMode == WrapMode.Loop || curve.preWrapMode == WrapMode.PingPong || curve.postWrapMode == WrapMode.Loop || curve.postWrapMode == WrapMode.PingPong)
                throw new NotSupportedException("Looping atmosphere curve: " + name);
            Keyframe[] nativeKeys = curve.keys; var keys = new CurveKey[nativeKeys.Length];
            for (int i = 0; i < keys.Length; i++)
            {
                Keyframe k = nativeKeys[i]; if (k.weightedMode != WeightedMode.None) throw new NotSupportedException("Weighted atmosphere curve: " + name);
                keys[i] = new CurveKey(k.time, k.value, k.inTangent, k.outTangent);
            }
            return new HermiteCurve(keys);
        }
    }
}
