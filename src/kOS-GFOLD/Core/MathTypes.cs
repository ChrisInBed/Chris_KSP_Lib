using System;
using System.Collections.Generic;

namespace KOSGFOLD.Core
{
    public struct Vec3
    {
        public readonly double X, Y, Z;
        public Vec3(double x, double y, double z) { X = x; Y = y; Z = z; }
        public double Norm2 { get { return X * X + Y * Y + Z * Z; } }
        public double Norm { get { return Math.Sqrt(Norm2); } }
        public bool IsFinite { get { return Finite(X) && Finite(Y) && Finite(Z); } }
        public Vec3 Normalized()
        {
            double n = Norm;
            if (!(n > 0) || !Finite(n)) throw new ArgumentException("Cannot normalize a zero or non-finite vector");
            return this / n;
        }
        public static double Dot(Vec3 a, Vec3 b) { return a.X * b.X + a.Y * b.Y + a.Z * b.Z; }
        public static Vec3 Cross(Vec3 a, Vec3 b) { return new Vec3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X); }
        public static Vec3 operator +(Vec3 a, Vec3 b) { return new Vec3(a.X + b.X, a.Y + b.Y, a.Z + b.Z); }
        public static Vec3 operator -(Vec3 a, Vec3 b) { return new Vec3(a.X - b.X, a.Y - b.Y, a.Z - b.Z); }
        public static Vec3 operator -(Vec3 a) { return new Vec3(-a.X, -a.Y, -a.Z); }
        public static Vec3 operator *(Vec3 a, double s) { return new Vec3(a.X * s, a.Y * s, a.Z * s); }
        public static Vec3 operator *(double s, Vec3 a) { return a * s; }
        public static Vec3 operator /(Vec3 a, double s) { return new Vec3(a.X / s, a.Y / s, a.Z / s); }
        public double[] ToArray() { return new[] { X, Y, Z }; }
        public static Vec3 FromArray(double[] x) { if (x == null || x.Length != 3) throw new ArgumentException("Vector must contain three values"); return new Vec3(x[0], x[1], x[2]); }
        public override string ToString() { return string.Format("[{0:R},{1:R},{2:R}]", X, Y, Z); }
        internal static bool Finite(double x) { return !double.IsNaN(x) && !double.IsInfinity(x); }
    }

    internal static class Dense
    {
        internal static double[,] Identity(int n) { double[,] r = new double[n, n]; for (int i = 0; i < n; ++i) r[i, i] = 1; return r; }
        internal static double[,] Copy(double[,] a) { return (double[,])a.Clone(); }
        internal static double[,] Add(double[,] a, double[,] b) { int n = a.GetLength(0), m = a.GetLength(1); double[,] r = new double[n, m]; for (int i = 0; i < n; ++i) for (int j = 0; j < m; ++j) r[i, j] = a[i, j] + b[i, j]; return r; }
        internal static double[,] Sub(double[,] a, double[,] b) { return Add(a, Scale(b, -1)); }
        internal static double[,] Scale(double[,] a, double s) { int n = a.GetLength(0), m = a.GetLength(1); double[,] r = new double[n, m]; for (int i = 0; i < n; ++i) for (int j = 0; j < m; ++j) r[i, j] = a[i, j] * s; return r; }
        internal static double[,] Mul(double[,] a, double[,] b)
        {
            int n = a.GetLength(0), p = a.GetLength(1), m = b.GetLength(1); double[,] r = new double[n, m];
            for (int i = 0; i < n; ++i) for (int k = 0; k < p; ++k) { double v = a[i, k]; if (v == 0) continue; for (int j = 0; j < m; ++j) r[i, j] += v * b[k, j]; }
            return r;
        }
        internal static double[] Mul(double[,] a, double[] x) { int n = a.GetLength(0), m = a.GetLength(1); double[] r = new double[n]; for (int i = 0; i < n; ++i) for (int j = 0; j < m; ++j) r[i] += a[i, j] * x[j]; return r; }
        internal static double Norm1(double[,] a) { double best = 0; for (int j = 0; j < a.GetLength(1); ++j) { double s = 0; for (int i = 0; i < a.GetLength(0); ++i) s += Math.Abs(a[i, j]); best = Math.Max(best, s); } return best; }
        internal static double[,] Solve(double[,] a, double[,] b)
        {
            int n = a.GetLength(0), m = b.GetLength(1); double[,] aa = Copy(a), bb = Copy(b);
            for (int k = 0; k < n; ++k)
            {
                int pivot = k; double pv = Math.Abs(aa[k, k]);
                for (int i = k + 1; i < n; ++i) if (Math.Abs(aa[i, k]) > pv) { pv = Math.Abs(aa[i, k]); pivot = i; }
                if (pv < 1e-18) throw new InvalidOperationException("Singular matrix in matrix exponential");
                if (pivot != k) for (int j = k; j < n; ++j) { double t = aa[k, j]; aa[k, j] = aa[pivot, j]; aa[pivot, j] = t; }
                if (pivot != k) for (int j = 0; j < m; ++j) { double t = bb[k, j]; bb[k, j] = bb[pivot, j]; bb[pivot, j] = t; }
                for (int i = k + 1; i < n; ++i) { double f = aa[i, k] / aa[k, k]; aa[i, k] = 0; for (int j = k + 1; j < n; ++j) aa[i, j] -= f * aa[k, j]; for (int j = 0; j < m; ++j) bb[i, j] -= f * bb[k, j]; }
            }
            double[,] x = new double[n, m];
            for (int i = n - 1; i >= 0; --i) for (int j = 0; j < m; ++j) { double s = bb[i, j]; for (int k = i + 1; k < n; ++k) s -= aa[i, k] * x[k, j]; x[i, j] = s / aa[i, i]; }
            return x;
        }
        // Higham scaling/squaring with the [13/13] Pade approximant.
        internal static double[,] Exponential(double[,] a)
        {
            int n = a.GetLength(0); if (n != a.GetLength(1)) throw new ArgumentException("Matrix exponential requires a square matrix");
            const double theta13 = 5.371920351148152; double norm = Norm1(a); int s = norm <= theta13 ? 0 : Math.Max(0, (int)Math.Ceiling(Math.Log(norm / theta13, 2)));
            double[,] x = Scale(a, 1.0 / Math.Pow(2, s)), x2 = Mul(x, x), x4 = Mul(x2, x2), x6 = Mul(x4, x2), id = Identity(n);
            double[] c = { 64764752532480000.0, 32382376266240000.0, 7771770303897600.0, 1187353796428800.0, 129060195264000.0, 10559470521600.0, 670442572800.0, 33522128640.0, 1323241920.0, 40840800.0, 960960.0, 16380.0, 182.0, 1.0 };
            double[,] uInner = Add(Mul(x6, Add(Add(Scale(x6, c[13]), Scale(x4, c[11])), Scale(x2, c[9]))), Add(Add(Scale(x6, c[7]), Scale(x4, c[5])), Add(Scale(x2, c[3]), Scale(id, c[1]))));
            double[,] u = Mul(x, uInner);
            double[,] v = Add(Mul(x6, Add(Add(Scale(x6, c[12]), Scale(x4, c[10])), Scale(x2, c[8]))), Add(Add(Scale(x6, c[6]), Scale(x4, c[4])), Add(Scale(x2, c[2]), Scale(id, c[0]))));
            double[,] r = Solve(Sub(v, u), Add(v, u));
            for (int i = 0; i < s; ++i) r = Mul(r, r);
            return r;
        }
    }

    internal sealed class Affine
    {
        internal readonly Dictionary<int, double> Terms = new Dictionary<int, double>();
        internal double Constant;
        internal Affine() { }
        internal Affine(double constant) { Constant = constant; }
        internal static Affine Var(int i, double c = 1) { Affine a = new Affine(); a.Add(i, c); return a; }
        internal Affine Clone() { Affine a = new Affine(Constant); foreach (KeyValuePair<int, double> kv in Terms) a.Terms[kv.Key] = kv.Value; return a; }
        internal Affine Add(int i, double c) { double old; Terms.TryGetValue(i, out old); double next = old + c; if (Math.Abs(next) < 1e-16) Terms.Remove(i); else Terms[i] = next; return this; }
        internal Affine Plus(Affine b, double scale = 1) { Constant += scale * b.Constant; foreach (KeyValuePair<int, double> kv in b.Terms) Add(kv.Key, scale * kv.Value); return this; }
        internal Affine Scaled(double s) { Affine a = new Affine(Constant * s); foreach (KeyValuePair<int, double> kv in Terms) a.Terms[kv.Key] = kv.Value * s; return a; }
        internal double Eval(double[] x) { double v = Constant; foreach (KeyValuePair<int, double> kv in Terms) v += kv.Value * x[kv.Key]; return v; }
    }
}
