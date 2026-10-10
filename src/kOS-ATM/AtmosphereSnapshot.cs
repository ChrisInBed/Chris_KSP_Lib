using System;

namespace KOSAtmosphere
{
    public struct AtmosphereSample
    {
        public readonly double PressurePa, TemperatureK, Density, TemperatureOffsetK;
        internal AtmosphereSample(double p, double t, double rho, double offset) { PressurePa = p; TemperatureK = t; Density = rho; TemperatureOffsetK = offset; }
    }
    internal sealed class SnapshotData
    {
        internal string BodyName;
        internal double Epoch, Depth, Radius, Molar, Gas, Space, PressureSea, TempSea, Lapse, GasLapse, Anomaly, EccFraction, EccSpan, InverseScale, Mu;
        internal bool HasAir, UsePressure, PressureNormalized, UseTemp, TempNormalized;
        internal AtmosphereVector Axis, North, Spin, SunFromCenter, ZeroLongitude, EastLongitude, ColumnUp;
        internal FloatRotation Lag;
        internal HermiteCurve Pressure, Temperature, SunMult, LatBias, LatMult, AxialBias, AxialMult, EccBias;
        internal EllipticOrbit SeasonOrbit;
        internal OrbitTerm[] OrbitTerms;
    }
    internal sealed class OrbitTerm
    {
        internal readonly EllipticOrbit Orbit;
        internal readonly double Sign;
        internal readonly AtmosphereVector InitialPosition;
        internal OrbitTerm(EllipticOrbit orbit, double sign) { Orbit = orbit; Sign = sign; InitialPosition = orbit.Position(0); }
    }
    /// <summary>Immutable, reusable atmosphere and orbital snapshot. All queries are managed and thread safe.</summary>
    public sealed partial class AtmosphereSnapshot
    {
        public string BodyName { get; private set; }
        public double EpochUT { get; private set; }
        public double AtmosphereDepth { get { return depth; } }
        public double BodyRadius { get { return radius; } }
        public AtmosphereVector AngularVelocity { get { return spin; } }
        private readonly HermiteCurve pressure, temperature, sunMult, latBias, latMult, axialBias, axialMult, eccBias;
        private readonly double depth, radius, molar, gas, space, pressureSea, tempSea, lapse, gasLapse, anomaly, eccFraction, eccSpan, inverseScale, mu;
        private readonly bool hasAir, usePressure, pressureNormalized, useTemp, tempNormalized;
        private readonly AtmosphereVector axis, north, spin, sunFromCenter, zeroLongitude, eastLongitude, columnUp;
        private readonly double spinSpeed;
        private readonly FloatRotation lag;
        private readonly EllipticOrbit seasonOrbit;
        private readonly double seasonAnomaly0, seasonRadius0;
        private readonly OrbitTerm[] orbitTerms;
        internal AtmosphereSnapshot(SnapshotData d)
        {
            BodyName = d.BodyName; EpochUT = d.Epoch; depth = d.Depth; radius = d.Radius; molar = d.Molar; gas = d.Gas; space = d.Space;
            pressureSea = d.PressureSea; tempSea = d.TempSea; lapse = d.Lapse; gasLapse = d.GasLapse; anomaly = d.Anomaly;
            eccFraction = d.EccFraction; eccSpan = d.EccSpan; inverseScale = d.InverseScale; mu = d.Mu;
            hasAir = d.HasAir; usePressure = d.UsePressure; pressureNormalized = d.PressureNormalized; useTemp = d.UseTemp; tempNormalized = d.TempNormalized;
            axis = d.Axis; north = d.North; spin = d.Spin; spinSpeed = spin.Length; sunFromCenter = d.SunFromCenter; zeroLongitude = d.ZeroLongitude; eastLongitude = d.EastLongitude; columnUp = d.ColumnUp;
            lag = d.Lag; pressure = d.Pressure; temperature = d.Temperature; sunMult = d.SunMult; latBias = d.LatBias; latMult = d.LatMult; axialBias = d.AxialBias; axialMult = d.AxialMult; eccBias = d.EccBias;
            seasonOrbit = d.SeasonOrbit;
            if (seasonOrbit != null) { OrbitState initial = seasonOrbit.StateAt(0); seasonAnomaly0 = initial.TrueAnomaly; seasonRadius0 = initial.Radius; }
            orbitTerms = d.OrbitTerms == null ? new OrbitTerm[0] : (OrbitTerm[])d.OrbitTerms.Clone();
        }
        /// <summary>Body-fixed latitude/longitude in degrees, ASL metres, absolute universal time.</summary>
        public AtmosphereSample EvaluateGeographic(double latitude, double longitude, double altitude, double universalTime)
        {
            RequireFinite(latitude, "latitude"); RequireFinite(longitude, "longitude");
            if (latitude < -90 || latitude > 90) throw new ArgumentOutOfRangeException("latitude");
            double phi = latitude * Math.PI / 180, lambda = (longitude % 360) * Math.PI / 180;
            AtmosphereVector up = north * Math.Sin(phi) + (zeroLongitude * Math.Cos(lambda) + eastLongitude * Math.Sin(lambda)) * Math.Cos(phi);
            return EvaluateRotatingUp(up.Normalized, altitude, universalTime - EpochUT);
        }
        /// <summary>Position in a body-fixed frame whose axes equal world axes at EpochUT; elapsed seconds since EpochUT.</summary>
        public AtmosphereSample EvaluatePosition(double x, double y, double z, double elapsedSeconds)
        {
            AtmosphereVector radial = new AtmosphereVector(x, y, z);
            double r = radial.Length;
            if (!AtmosphereVector.Finite(r) || r <= 0) throw new ArgumentException("Invalid body-centered position");
            return EvaluateRotatingUp(radial / r, r - radius, elapsedSeconds);
        }
        /// <summary>Same geographic column as the capture vessel, at the snapshot epoch.</summary>
        public AtmosphereSample EvaluateColumn(double altitude) { return EvaluateRotatingUp(columnUp, altitude, 0); }
        public double ScaleHeightColumn(double altitude)
        {
            return ScaleHeight(altitude, EvaluateColumn(altitude).TemperatureK);
        }
        public double ScaleHeight(double altitude, double temperatureK)
        {
            double r = radius + altitude;
            return hasAir && molar > 0 && mu > 0 ? gas * temperatureK * r * r / (molar * mu) : 0;
        }
        /// <summary>Invert this snapshot's capture column. Clamp outside [0, depth]; reject multiple roots.</summary>
        public double AltitudeForDensity(double density)
        {
            RequireFinite(density, "density"); if (density < 0) throw new ArgumentOutOfRangeException("density");
            if (!hasAir || density == 0) return depth;
            if (density >= EvaluateColumn(0).Density) return 0;
            double low = 0, high = depth, previous = EvaluateColumn(0).Density - density; int roots = 0;
            for (int i = 1; i <= 128; i++)
            {
                double h = depth * i / 128, delta = EvaluateColumn(h).Density - density;
                if ((previous > 0 && delta <= 0) || (previous < 0 && delta >= 0)) { roots++; low = depth * (i - 1) / 128; high = h; }
                previous = delta;
            }
            if (roots != 1) throw new InvalidOperationException("Density does not have a unique altitude in this atmospheric column");
            double sign = EvaluateColumn(low).Density - density;
            for (int i = 0; i < 48; i++)
            {
                double mid = (low + high) * .5, delta = EvaluateColumn(mid).Density - density;
                if ((sign > 0 && delta > 0) || (sign < 0 && delta < 0)) low = mid; else high = mid;
            }
            return (low + high) * .5;
        }
        private AtmosphereSample EvaluateRotatingUp(AtmosphereVector up, double h, double elapsed)
        {
            RequireFinite(h, "altitude"); RequireFinite(elapsed, "elapsedSeconds");
            if (h <= -radius) throw new ArgumentOutOfRangeException("altitude");
            if (!hasAir || h >= depth) return new AtmosphereSample(0, 0, 0, 0);
            if (spinSpeed > 0 && elapsed != 0) up = AtmosphereVector.Rotate(up, spin / spinSpeed, (spinSpeed * elapsed) % (2 * Math.PI));
            AtmosphereVector sunPosition = sunFromCenter;
            OrbitState seasonState = default(OrbitState); bool hasSeasonState = false;
            if (elapsed != 0)
                foreach (OrbitTerm term in orbitTerms)
                {
                    if (term.Orbit == seasonOrbit) { seasonState = term.Orbit.StateAt(elapsed); hasSeasonState = true; sunPosition += (seasonState.Position - term.InitialPosition) * (term.Sign * inverseScale); }
                    else sunPosition += (term.Orbit.Position(elapsed) - term.InitialPosition) * (term.Sign * inverseScale);
                }
            AtmosphereVector ray = sunPosition - up * ((radius + h) * inverseScale);
            FloatVector direction = new FloatVector(ray.Normalized), upFloat = new FloatVector(up), axisFloat = new FloatVector(axis);
            double axisSun = FloatVector.Dot(direction, axisFloat), axisUp = FloatVector.Dot(axisFloat, upFloat);
            double polar = AcosLikeNative(axisUp), solar = AcosLikeNative(axisSun);
            double max = (1 + Math.Cos(solar - polar)) * .5, min = (1 + Math.Cos(solar + polar)) * .5;
            if (polar > Math.PI / 2) polar = Math.PI - polar;
            double shifted = (1 + FloatVector.Dot(direction, lag.Apply(upFloat))) * .5;
            double range = max - min, normalizedSun = shifted;
            if (range > .001) { normalizedSun = (shifted - min) / range; if (double.IsNaN(normalizedSun)) normalizedSun = shifted > .5 ? 1 : 0; }
            else normalizedSun = min + range * .5;
            float latitude = (float)(Math.PI / 2 - polar) * 57.29578f;
            double seasonalAnomaly = anomaly, fraction = eccFraction;
            if (seasonOrbit != null && elapsed != 0)
            {
                if (!hasSeasonState) seasonState = seasonOrbit.StateAt(elapsed);
                double delta = seasonState.TrueAnomaly - seasonAnomaly0;
                seasonalAnomaly += delta;
                if (!double.IsNaN(fraction)) fraction += (seasonState.Radius - seasonRadius0) / eccSpan;
            }
            float seasonDegrees = ((float)seasonalAnomaly * 57.29578f + 360f) % 360f;
            if (seasonDegrees < 0) seasonDegrees += 360f;
            double offset = latBias.Evaluate(latitude) + (double)latMult.Evaluate(latitude) * normalizedSun
                + (double)(axialBias.Evaluate(seasonDegrees) * axialMult.Evaluate(latitude))
                + (double.IsNaN(fraction) ? 0 : eccBias.Evaluate((float)fraction));
            double p = usePressure ? (pressureNormalized ? (float)((float)pressureSea * Clamp01(pressure.Evaluate((float)(h / depth)))) : pressure.Evaluate((float)h))
                : pressureSea * Math.Pow(1 - lapse * h / tempSea, gasLapse);
            double t = useTemp ? (tempNormalized ? LerpTemperature(temperature.Evaluate((float)(h / depth))) : temperature.Evaluate((float)h))
                : tempSea - lapse * h;
            t += sunMult.Evaluate((float)h) * offset;
            double density = p <= 0 || t <= 0 ? 0 : p * 1000 * molar / (gas * t);
            if (!AtmosphereVector.Finite(p) || !AtmosphereVector.Finite(t) || !AtmosphereVector.Finite(density) || density < 0)
                throw new InvalidOperationException("Atmosphere configuration produced invalid gas properties");
            return new AtmosphereSample(p * 1000, t, density, offset);
        }
        private double LerpTemperature(double t) { t = Clamp01(t); return (1 - t) * space + t * tempSea; }
        private static double Clamp01(double x) { return Math.Max(0, Math.Min(1, x)); }
        private static double AcosLikeNative(double x) { double a = Math.Acos(x); return double.IsNaN(a) ? (x < 0 ? Math.PI : 0) : a; }
        internal static void RequireFinite(double x, string name) { if (!AtmosphereVector.Finite(x)) throw new ArgumentException(name + " must be finite"); }
    }
}
