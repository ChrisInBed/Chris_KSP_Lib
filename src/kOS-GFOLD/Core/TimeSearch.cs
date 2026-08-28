using System;
using System.Collections.Generic;
using System.Diagnostics;

namespace KOSGFOLD.Core
{
    internal sealed class SearchOutcome { internal PlannerResult Best; internal int Evaluations; internal bool Deadline; internal PlannerStatus LastStatus = PlannerStatus.Infeasible; internal string LastMessage = "No candidate evaluated"; }
    internal static class TimeSearch
    {
        internal static SearchOutcome Cold(double tfMin, double tfMax, bool pit, int budget, Stopwatch watch, Func<double, double, PlannerResult> solve)
        {
            SearchOutcome o = new SearchOutcome(); if (!pit) SearchSurface(o, tfMin, tfMax, budget, watch, solve, null); else SearchPit(o, tfMin, tfMax, budget, watch, solve, null, 0); return o;
        }
        internal static SearchOutcome Local(double tfMin, double tfMax, bool pit, int budget, Stopwatch watch, Func<double, double, PlannerResult> solve, double tfGuess, double teGuess)
        {
            SearchOutcome o = new SearchOutcome(); HashSet<string> seen = new HashSet<string>(); if (!pit) { foreach (double f in new[] { 0.8, 0.9, 1.0, 1.1, 1.2 }) Evaluate(o, Clamp(tfGuess * f, tfMin, tfMax), 1, budget, watch, solve, seen); if (o.Best == null) SearchSurface(o, tfMin, tfMax, budget, watch, solve, seen); }
            else { double sg = Clamp(teGuess / Math.Max(tfGuess, 1e-6), 0.02, 0.98); foreach (double f in new[] { 0.85, 1.0, 1.15 }) foreach (double ds in new[] { -0.1, 0.0, 0.1 }) Evaluate(o, Clamp(tfGuess * f, tfMin, tfMax), Clamp(sg + ds, 0.02, 0.98), budget, watch, solve, seen); if (o.Best == null) SearchPit(o, tfMin, tfMax, budget, watch, solve, seen, o.Evaluations); }
            return o;
        }
        private static void SearchSurface(SearchOutcome o, double lo, double hi, int budget, Stopwatch watch, Func<double, double, PlannerResult> solve, HashSet<string> seen)
        {
            if (seen == null) seen = new HashSet<string>(); List<double> sampled = new List<double>(); for (int i = 0; i < 7; ++i) { double tf = lo + (hi - lo) * i / 6; sampled.Add(tf); Evaluate(o, tf, 1, budget, watch, solve, seen); }
            while (o.Evaluations < budget && !o.Deadline) { double center = o.Best == null ? (lo + hi) / 2 : o.Best.Tf, left = lo, right = hi; foreach (double x in sampled) { if (x < center && x > left) left = x; if (x > center && x < right) right = x; } double next = (right - center) >= (center - left) ? (center + right) / 2 : (left + center) / 2; if (Math.Abs(next - center) < 1e-8) break; sampled.Add(next); Evaluate(o, next, 1, budget, watch, solve, seen); }
        }
        private static void SearchPit(SearchOutcome o, double lo, double hi, int budget, Stopwatch watch, Func<double, double, PlannerResult> solve, HashSet<string> seen, int already)
        {
            if (seen == null) seen = new HashSet<string>(); double dt = (hi - lo) / 3, ds = 0.48; for (int i = 0; i < 4; ++i) foreach (double sv in new[] { 0.02, 0.5, 0.98 }) Evaluate(o, lo + dt * i, sv, budget, watch, solve, seen);
            int level = 1; while (o.Evaluations < budget && !o.Deadline && o.Best != null) { double tfStep = dt / Math.Pow(2, level), sStep = ds / Math.Pow(2, level); double centerS = o.Best.Te / o.Best.Tf; bool any = false; foreach (double tf in new[] { o.Best.Tf - tfStep, o.Best.Tf + tfStep }) foreach (double sv in new[] { centerS - sStep, centerS, centerS + sStep }) { int before = o.Evaluations; Evaluate(o, Clamp(tf, lo, hi), Clamp(sv, 0.02, 0.98), budget, watch, solve, seen); any |= before != o.Evaluations; } if (!any) break; level++; }
        }
        private static void Evaluate(SearchOutcome o, double tf, double s, int budget, Stopwatch watch, Func<double, double, PlannerResult> solve, HashSet<string> seen)
        {
            if (o.Evaluations >= budget || o.Deadline) return; if (watch.Elapsed.TotalSeconds >= 2 && o.Evaluations > 0) { o.Deadline = true; return; } string key = tf.ToString("R") + "/" + s.ToString("R"); if (!seen.Add(key)) return; PlannerResult r = solve(tf, s); o.Evaluations++; o.LastStatus = r.Status; o.LastMessage = r.Message; if (r.Ok && Better(r, o.Best)) o.Best = r;
        }
        private static bool Better(PlannerResult a, PlannerResult b) { if (b == null) return true; double tol = Math.Max(0.001, 1e-6 * Math.Max(1, a.LandingError)); if (a.LandingError < b.LandingError - tol) return true; if (Math.Abs(a.LandingError - b.LandingError) <= tol && a.FuelUsed < b.FuelUsed - 1e-8) return true; return false; }
        private static double Clamp(double x, double lo, double hi) { return Math.Max(lo, Math.Min(hi, x)); }
    }
}
