using System;
using System.Collections.Generic;
using System.Linq;

namespace KOSGFOLD.Core
{
    internal sealed class Mesh
    {
        internal readonly double[] Times; internal readonly bool[] Discontinuous;
        internal Mesh(double[] times, bool[] discontinuous) { Times = times; Discontinuous = discontinuous; }
    }
    internal static class MeshBuilder
    {
        internal static Mesh Build(int nodes, double tf, double tc, double? te)
        {
            List<double> events = new List<double> { 0, tf }; if (tc > 1e-9 && tc < tf - 1e-9) events.Add(tc); if (te.HasValue && te.Value > 1e-9 && te.Value < tf - 1e-9) events.Add(te.Value); events.Sort();
            List<double> unique = new List<double>(); foreach (double x in events) if (unique.Count == 0 || Math.Abs(x - unique[unique.Count - 1]) > 1e-8 * Math.Max(1, tf)) unique.Add(x);
            int segments = unique.Count - 1, intervals = nodes - 1; if (intervals < segments) throw new ArgumentException("nodes is too small for active events"); int remaining = intervals - segments; int[] counts = Enumerable.Repeat(1, segments).ToArray();
            double total = tf; double[] rem = new double[segments]; for (int i = 0; i < segments; ++i) { double exact = remaining * (unique[i + 1] - unique[i]) / total; int add = (int)Math.Floor(exact); counts[i] += add; rem[i] = exact - add; }
            int used = counts.Sum(); while (used < intervals) { int best = 0; for (int i = 1; i < segments; ++i) if (rem[i] > rem[best]) best = i; counts[best]++; rem[best] = -1; used++; }
            List<double> times = new List<double> { 0 }; for (int s = 0; s < segments; ++s) for (int j = 1; j <= counts[s]; ++j) times.Add(unique[s] + (unique[s + 1] - unique[s]) * j / counts[s]);
            bool[] disc = new bool[times.Count]; for (int i = 1; i < times.Count - 1; ++i) foreach (double e in unique) if (e > 0 && e < tf && Math.Abs(times[i] - e) < 1e-7 * Math.Max(1, tf)) disc[i] = true;
            return new Mesh(times.ToArray(), disc);
        }
    }
}
