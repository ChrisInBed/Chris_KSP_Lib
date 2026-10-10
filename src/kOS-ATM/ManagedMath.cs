using System;

namespace KOSAtmosphere
{
    // Value-only arithmetic. This file has no KSP or Unity dependency.
    public struct AtmosphereVector
    {
        public readonly double X, Y, Z;
        public AtmosphereVector(double x, double y, double z) { X = x; Y = y; Z = z; }
        public double Length { get { return Math.Sqrt(X * X + Y * Y + Z * Z); } }
        public AtmosphereVector Normalized { get { double n = Length; if (!(n > 0) || !Finite(n)) throw new ArgumentException("Invalid radial vector"); return this / n; } }
        public static bool Finite(double x) { return !double.IsNaN(x) && !double.IsInfinity(x); }
        public static double Dot(AtmosphereVector a, AtmosphereVector b) { return a.X * b.X + a.Y * b.Y + a.Z * b.Z; }
        public static AtmosphereVector Cross(AtmosphereVector a, AtmosphereVector b) { return new AtmosphereVector(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X); }
        public static AtmosphereVector operator +(AtmosphereVector a, AtmosphereVector b) { return new AtmosphereVector(a.X + b.X, a.Y + b.Y, a.Z + b.Z); }
        public static AtmosphereVector operator -(AtmosphereVector a, AtmosphereVector b) { return new AtmosphereVector(a.X - b.X, a.Y - b.Y, a.Z - b.Z); }
        public static AtmosphereVector operator *(AtmosphereVector a, double b) { return new AtmosphereVector(a.X * b, a.Y * b, a.Z * b); }
        public static AtmosphereVector operator /(AtmosphereVector a, double b) { return new AtmosphereVector(a.X / b, a.Y / b, a.Z / b); }
        public static AtmosphereVector Rotate(AtmosphereVector v, AtmosphereVector axis, double radians)
        {
            if (radians == 0) return v;
            double c = Math.Cos(radians), s = Math.Sin(radians);
            return v * c + Cross(axis, v) * s + axis * (Dot(axis, v) * (1 - c));
        }
    }
    internal struct FloatVector
    {
        internal readonly float X, Y, Z;
        internal FloatVector(AtmosphereVector v) { X = (float)v.X; Y = (float)v.Y; Z = (float)v.Z; }
        internal FloatVector(float x, float y, float z) { X = x; Y = y; Z = z; }
        internal static float Dot(FloatVector a, FloatVector b) { return a.X * b.X + a.Y * b.Y + a.Z * b.Z; }
    }
    internal struct FloatRotation
    {
        internal readonly float X, Y, Z, W;
        internal FloatRotation(float x, float y, float z, float w) { X = x; Y = y; Z = z; W = w; }
        // Unity's managed Quaternion * Vector3 expression, preserving float rounding.
        internal FloatVector Apply(FloatVector p)
        {
            float x = X * 2f, y = Y * 2f, z = Z * 2f;
            float xx = X * x, yy = Y * y, zz = Z * z, xy = X * y, xz = X * z, yz = Y * z, wx = W * x, wy = W * y, wz = W * z;
            return new FloatVector((1f - (yy + zz)) * p.X + (xy - wz) * p.Y + (xz + wy) * p.Z,
                (xy + wz) * p.X + (1f - (xx + zz)) * p.Y + (yz - wx) * p.Z,
                (xz - wy) * p.X + (yz + wx) * p.Y + (1f - (xx + yy)) * p.Z);
        }
    }
    internal struct CurveKey
    {
        internal readonly float Time, Value, InTangent, OutTangent;
        internal CurveKey(float t, float v, float a, float b) { Time = t; Value = v; InTangent = a; OutTangent = b; }
    }
    internal sealed class HermiteCurve
    {
        private readonly CurveKey[] keys;
        internal HermiteCurve(CurveKey[] source)
        {
            keys = (CurveKey[])source.Clone();
            for (int i = 0; i < keys.Length; i++)
            {
                if (!AtmosphereVector.Finite(keys[i].Time) || !AtmosphereVector.Finite(keys[i].Value)
                    || float.IsNaN(keys[i].InTangent) || float.IsNaN(keys[i].OutTangent)
                    || (i > 0 && keys[i].Time <= keys[i - 1].Time))
                    throw new NotSupportedException("Atmosphere curves require finite values and strictly increasing keys");
            }
        }
        internal float Evaluate(float x)
        {
            if (keys.Length == 0) return 0;
            if (x <= keys[0].Time) return keys[0].Value;
            if (x >= keys[keys.Length - 1].Time) return keys[keys.Length - 1].Value;
            int lo = 0, hi = keys.Length - 1;
            while (hi - lo > 1) { int m = (lo + hi) / 2; if (keys[m].Time <= x) lo = m; else hi = m; }
            CurveKey a = keys[lo], b = keys[hi];
            if (float.IsInfinity(a.OutTangent) || float.IsInfinity(b.InTangent)) return a.Value;
            double h = (double)b.Time - a.Time, t = ((double)x - a.Time) / h;
            return (float)((2 * t * t * t - 3 * t * t + 1) * a.Value + (t * t * t - 2 * t * t + t) * h * a.OutTangent
                + (-2 * t * t * t + 3 * t * t) * b.Value + (t * t * t - t * t) * h * b.InTangent);
        }
    }
    internal struct OrbitState
    {
        internal readonly AtmosphereVector Position;
        internal readonly double Radius, TrueAnomaly;
        internal OrbitState(AtmosphereVector p, double r, double anomaly) { Position = p; Radius = r; TrueAnomaly = anomaly; }
    }
    internal sealed class EllipticOrbit
    {
        private readonly double major, eccentricity, mean0, motion, minor;
        private readonly AtmosphereVector periapsis, transverse;
        internal EllipticOrbit(double a, double e, double m, double period, AtmosphereVector p, AtmosphereVector q)
        {
            if (!(a > 0) || !(period > 0) || e < 0 || e >= 1 || !AtmosphereVector.Finite(a)
                || !AtmosphereVector.Finite(e) || !AtmosphereVector.Finite(m) || !AtmosphereVector.Finite(period))
                throw new NotSupportedException("kOS-ATM requires elliptical celestial-body orbits");
            major = a; eccentricity = e; mean0 = m; motion = 2 * Math.PI / period; minor = a * Math.Sqrt(1 - e * e);
            periapsis = p.Normalized; transverse = q.Normalized;
        }
        private double EccentricAnomaly(double elapsed)
        {
            double m = (mean0 + motion * elapsed) % (2 * Math.PI);
            if (m > Math.PI) m -= 2 * Math.PI; if (m < -Math.PI) m += 2 * Math.PI;
            // Bracketed Newton remains reliable near e=1 and periapsis.
            double lo = -Math.PI, hi = Math.PI, e = eccentricity < .8 ? m : (m >= 0 ? Math.PI : -Math.PI);
            for (int i = 0; i < 64; i++)
            {
                double f = e - eccentricity * Math.Sin(e) - m;
                if (Math.Abs(f) < 2e-15) return e;
                if (f > 0) hi = e; else lo = e;
                double next = e - f / (1 - eccentricity * Math.Cos(e));
                e = next > lo && next < hi ? next : (lo + hi) * .5;
            }
            return e;
        }
        internal OrbitState StateAt(double elapsed)
        {
            double e = EccentricAnomaly(elapsed), c = Math.Cos(e), s = Math.Sin(e);
            return new OrbitState(periapsis * (major * (c - eccentricity)) + transverse * (minor * s), major * (1 - eccentricity * c),
                Math.Atan2(Math.Sqrt(1 - eccentricity * eccentricity) * s, c - eccentricity));
        }
        internal AtmosphereVector Position(double elapsed)
        {
            double e = EccentricAnomaly(elapsed);
            return periapsis * (major * (Math.Cos(e) - eccentricity)) + transverse * (minor * Math.Sin(e));
        }
        internal double TrueAnomaly(double elapsed)
        {
            double e = EccentricAnomaly(elapsed);
            return Math.Atan2(Math.Sqrt(1 - eccentricity * eccentricity) * Math.Sin(e), Math.Cos(e) - eccentricity);
        }
        internal double Radius(double elapsed) { return major * (1 - eccentricity * Math.Cos(EccentricAnomaly(elapsed))); }
    }
}
