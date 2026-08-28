using System;
using System.Collections.Generic;

namespace KOSGFOLD.Core
{
    internal sealed class LinearConstraint
    {
        internal readonly Affine Expr; internal readonly double Lower, Upper;
        internal LinearConstraint(Affine expr, double lower, double upper) { Expr = expr; Lower = lower; Upper = upper; }
    }
    internal sealed class ConeConstraint
    {
        internal readonly int RadialStart, RadialEnd, Axis;
        internal ConeConstraint(int radialStart, int radialEnd, int axis) { RadialStart = radialStart; RadialEnd = radialEnd; Axis = axis; }
    }
    internal sealed class ConicProblem
    {
        internal int Variables, StateCount, ControlStart, LandingErrorIndex; internal readonly int Nodes, Intervals;
        internal readonly List<LinearConstraint> Linear = new List<LinearConstraint>(); internal readonly List<ConeConstraint> Cones = new List<ConeConstraint>(); internal readonly Dictionary<int, double> Objective = new Dictionary<int, double>();
        internal readonly Mesh Mesh; internal readonly Normalizer Scale; internal readonly CandidateSpec Spec;
        internal ConicProblem(CandidateSpec spec, int nodes) { Spec = spec; Mesh = spec.Mesh; Scale = spec.Scale; Nodes = nodes; Intervals = nodes - 1; }
        internal int State(int node, int component) { return node * 7 + component; }
        internal int Control(int interval, int side, int component) { return ControlStart + interval * 8 + side * 4 + component; }
    }
    internal sealed class CandidateSpec
    {
        internal PlannerSession Session; internal double Epoch, Mass, Tf, Te, Tc; internal Vec3 Position, Velocity; internal bool EntryOnly; internal Mesh Mesh; internal Normalizer Scale;
    }
    internal sealed class SampleExpressions
    {
        internal Affine[] P = new Affine[3], V = new Affine[3], U = new Affine[3]; internal Affine Zeta, Sigma; internal double Time; internal EngineMode Engine; internal bool Entry;
    }

    internal static class GfoldProblemBuilder
    {
        private const double Inf = double.PositiveInfinity;
        internal static ConicProblem Build(CandidateSpec spec, bool fuelObjective, double landingLimit)
        {
            int n = spec.Mesh.Times.Length; ConicProblem p = new ConicProblem(spec, n); p.StateCount = n * 7; p.ControlStart = p.StateCount; p.Variables = p.ControlStart + (n - 1) * 8; p.LandingErrorIndex = p.Variables++;
            AddDynamics(p); AddBoundary(p); AddSamples(p); AddLandingCone(p);
            if (fuelObjective) { AddLinear(p, Affine.Var(p.LandingErrorIndex), -Inf, landingLimit); p.Objective[p.State(n - 1, 6)] = -1; }
            else p.Objective[p.LandingErrorIndex] = 1;
            return p;
        }

        private static void AddDynamics(ConicProblem p)
        {
            CandidateSpec s = p.Spec; Normalizer z = s.Scale; double[,] a = new double[6, 6], b = new double[6, 3]; double[] c = new double[6];
            for (int i = 0; i < 3; ++i) { a[i, i + 3] = 1; b[i + 3, i] = 1; c[i + 3] = s.Session.Frame.G0.ToArray()[i] / z.Acceleration; for (int j = 0; j < 3; ++j) { a[i + 3, j] = z.Time * z.Time * s.Session.Frame.Ap[i, j]; a[i + 3, j + 3] = z.Time * s.Session.Frame.Av[i, j]; } }
            for (int k = 0; k < p.Intervals; ++k)
            {
                double dt = p.Mesh.Times[k + 1] - p.Mesh.Times[k], hn = dt / z.Time; DiscreteStep d = LtiDiscretizer.Compute(a, b, c, hn);
                for (int row = 0; row < 6; ++row)
                {
                    Affine e = Affine.Var(p.State(k + 1, row));
                    for (int j = 0; j < 6; ++j) e.Add(p.State(k, j), -d.Phi[row, j]);
                    for (int j = 0; j < 3; ++j) { e.Add(p.Control(k, 0, j), -d.G0[row, j]); e.Add(p.Control(k, 1, j), -d.G1[row, j]); }
                    AddLinear(p, e, d.Gamma[row], d.Gamma[row]);
                }
                EngineMode mode = EngineAt(s, 0.5 * (p.Mesh.Times[k] + p.Mesh.Times[k + 1])); double beta = mode.Alpha * z.Acceleration * dt / 2;
                Affine mass = Affine.Var(p.State(k + 1, 6)).Plus(Affine.Var(p.State(k, 6)), -1); mass.Add(p.Control(k, 0, 3), beta).Add(p.Control(k, 1, 3), beta); AddLinear(p, mass, 0, 0);
                if (k + 1 < p.Intervals && !p.Mesh.Discontinuous[k + 1]) for (int j = 0; j < 4; ++j) { Affine continuity = Affine.Var(p.Control(k, 1, j)); continuity.Add(p.Control(k + 1, 0, j), -1); AddLinear(p, continuity, 0, 0); }
            }
        }

        private static void AddBoundary(ConicProblem p)
        {
            CandidateSpec s = p.Spec; Normalizer z = s.Scale; Vec3 p0 = z.PositionIn(s.Session.Frame.ToLocalPosition(s.Position)), v0 = z.VelocityIn(s.Session.Frame.ToLocalVector(s.Velocity)), vf = z.VelocityIn(s.Session.Frame.ToLocalVector(s.Session.Config.TargetVelocity)); double[] pa = p0.ToArray(), va = v0.ToArray(), vfa = vf.ToArray();
            for (int i = 0; i < 3; ++i) { AddLinear(p, Affine.Var(p.State(0, i)), pa[i], pa[i]); AddLinear(p, Affine.Var(p.State(0, i + 3)), va[i], va[i]); AddLinear(p, Affine.Var(p.State(p.Nodes - 1, i + 3)), vfa[i], vfa[i]); }
            AddLinear(p, Affine.Var(p.State(0, 6)), 0, 0); AddLinear(p, Affine.Var(p.State(p.Nodes - 1, 1)), -s.Session.Config.PitDepth / z.Length, -s.Session.Config.PitDepth / z.Length);
            AddLinear(p, Affine.Var(p.State(p.Nodes - 1, 6)), Math.Log(s.Session.DryMass / s.Mass), Inf);
        }

        private static void AddSamples(ConicProblem p)
        {
            CandidateSpec s = p.Spec; double[,] a = NormalizedA(s), b = NormalizedB(); double[] c = NormalizedC(s);
            for (int k = 0; k < p.Intervals; ++k)
            {
                AddPathAndControl(p, NodeSample(p, k, k, 0)); AddPathAndControl(p, NodeSample(p, k + 1, k, 1));
                double dt = p.Mesh.Times[k + 1] - p.Mesh.Times[k], hn = dt / s.Scale.Time; DiscreteStep half = LtiDiscretizer.Compute(a, b, c, hn / 2); SampleExpressions mid = new SampleExpressions(); mid.Time = 0.5 * (p.Mesh.Times[k] + p.Mesh.Times[k + 1]); mid.Engine = EngineAt(s, mid.Time); mid.Entry = IsEntry(s, mid.Time);
                for (int row = 0; row < 6; ++row)
                {
                    Affine e = new Affine(half.Gamma[row]); for (int j = 0; j < 6; ++j) e.Add(p.State(k, j), half.Phi[row, j]);
                    for (int j = 0; j < 3; ++j) { e.Add(p.Control(k, 0, j), half.G0[row, j] + 0.5 * half.G1[row, j]); e.Add(p.Control(k, 1, j), 0.5 * half.G1[row, j]); }
                    if (row < 3) mid.P[row] = e; else mid.V[row - 3] = e;
                }
                mid.Zeta = Affine.Var(p.State(k, 6)); double beta = mid.Engine.Alpha * s.Scale.Acceleration * dt / 8; mid.Zeta.Add(p.Control(k, 0, 3), -3 * beta).Add(p.Control(k, 1, 3), -beta);
                for (int j = 0; j < 3; ++j) { mid.U[j] = Affine.Var(p.Control(k, 0, j), 0.5).Plus(Affine.Var(p.Control(k, 1, j), 0.5)); } mid.Sigma = Affine.Var(p.Control(k, 0, 3), 0.5).Plus(Affine.Var(p.Control(k, 1, 3), 0.5)); AddPathAndControl(p, mid);
            }
        }

        private static SampleExpressions NodeSample(ConicProblem p, int node, int interval, int side)
        {
            SampleExpressions q = new SampleExpressions(); q.Time = p.Mesh.Times[node]; q.Engine = EngineAt(p.Spec, 0.5 * (p.Mesh.Times[interval] + p.Mesh.Times[interval + 1])); q.Entry = IsEntry(p.Spec, 0.5 * (p.Mesh.Times[interval] + p.Mesh.Times[interval + 1]));
            for (int i = 0; i < 3; ++i) { q.P[i] = Affine.Var(p.State(node, i)); q.V[i] = Affine.Var(p.State(node, i + 3)); q.U[i] = Affine.Var(p.Control(interval, side, i)); } q.Zeta = Affine.Var(p.State(node, 6)); q.Sigma = Affine.Var(p.Control(interval, side, 3)); return q;
        }

        private static void AddPathAndControl(ConicProblem p, SampleExpressions q)
        {
            CandidateSpec s = p.Spec; InitializeRequest cfg = s.Session.Config; Normalizer z = s.Scale;
            AddCone(p, q.U, q.Sigma); Affine tilt = q.U[1].Clone().Plus(q.Sigma, -Math.Cos(Deg(q.Entry ? cfg.EntryTilt : cfg.DescentTilt))); AddLinear(p, tilt, 0, Inf);
            if (s.Tf - q.Time <= cfg.TerminalTiltWindow + 1e-9) { Affine terminal = q.U[1].Clone().Plus(q.Sigma, -Math.Cos(Deg(cfg.TerminalTilt))); AddLinear(p, terminal, 0, Inf); }
            double mminus = MaxBurnMass(s, q.Time); if (!(mminus > s.Session.DryMass * 0.5)) throw new InvalidOperationException("maximum-thrust reference mass became non-positive"); double z0 = Math.Log(mminus / s.Mass), mu1 = q.Engine.Min / s.Mass * Math.Exp(-z0) / z.Acceleration, mu2 = q.Engine.Max / s.Mass * Math.Exp(-z0) / z.Acceleration;
            Affine delta = q.Zeta.Clone(); delta.Constant -= z0; Affine upper = q.Sigma.Clone().Plus(delta, mu2); AddLinear(p, upper, -Inf, mu2);
            Affine ss = q.Sigma.Scaled(1 / mu1).Plus(delta); ss.Constant -= 1; AddCone(p, new[] { delta.Scaled(Math.Sqrt(2)), ss.Clone().Plus(new Affine(-1)) }, ss.Clone().Plus(new Affine(1)));
            double speed = (q.Entry ? cfg.EntryMaxSpeed : cfg.DescentMaxSpeed) / z.Velocity; AddCone(p, q.V, new Affine(speed));
            double rs = (cfg.PitRadius - cfg.WallBuffer) / z.Length;
            if (!q.Entry)
            {
                AddLinear(p, q.P[1], 0, Inf); double tan = Math.Tan(Deg(cfg.DescentGlideSlope)); if (tan > 0) { Affine axis = q.P[1].Clone(); axis.Constant += tan * rs; AddCone(p, new[] { q.P[0].Scaled(tan), q.P[2].Scaled(tan) }, axis); }
            }
            else
            {
                AddCone(p, new[] { q.P[0], q.P[2] }, new Affine(rs)); AddLinear(p, q.P[1], -cfg.PitDepth / z.Length, 0); AddLinear(p, q.V[1], -Inf, 0); double tan = Math.Tan(Deg(cfg.EntryGlideSlope)); if (tan > 0) { Affine axis = q.P[1].Clone(); axis.Constant += cfg.PitDepth / z.Length; AddCone(p, new[] { q.P[0].Scaled(tan), q.P[2].Scaled(tan) }, axis); }
            }
        }

        private static void AddLandingCone(ConicProblem p) { AddCone(p, new[] { Affine.Var(p.State(p.Nodes - 1, 0)), Affine.Var(p.State(p.Nodes - 1, 2)) }, Affine.Var(p.LandingErrorIndex)); }
        private static void AddCone(ConicProblem p, Affine[] radial, Affine axis)
        {
            int start = p.Variables; for (int i = 0; i < radial.Length; ++i) { int v = p.Variables++; Affine e = Affine.Var(v).Plus(radial[i], -1); AddLinear(p, e, 0, 0); } int axisVar = p.Variables++; AddLinear(p, Affine.Var(axisVar).Plus(axis, -1), 0, 0); p.Cones.Add(new ConeConstraint(start, start + radial.Length, axisVar));
        }
        private static void AddLinear(ConicProblem p, Affine e, double lo, double hi) { p.Linear.Add(new LinearConstraint(e, lo, hi)); }
        private static double Deg(double x) { return x * Math.PI / 180; }
        private static EngineMode EngineAt(CandidateSpec s, double t) { return t < s.Tc ? s.Session.Mode1 : s.Session.Mode2; }
        private static bool IsEntry(CandidateSpec s, double t) { return s.EntryOnly || (s.Session.Config.PitDepth > 0 && t >= s.Te); }
        private static double MaxBurnMass(CandidateSpec s, double t) { double first = Math.Min(t, Math.Max(0, s.Tc)), used = first * s.Session.Mode1.Alpha * s.Session.Mode1.Max; if (t > first) used += (t - first) * s.Session.Mode2.Alpha * s.Session.Mode2.Max; return s.Mass - used; }
        private static double[,] NormalizedA(CandidateSpec s) { double[,] a = new double[6, 6]; for (int i = 0; i < 3; ++i) { a[i, i + 3] = 1; for (int j = 0; j < 3; ++j) { a[i + 3, j] = s.Scale.Time * s.Scale.Time * s.Session.Frame.Ap[i, j]; a[i + 3, j + 3] = s.Scale.Time * s.Session.Frame.Av[i, j]; } } return a; }
        private static double[,] NormalizedB() { double[,] b = new double[6, 3]; for (int i = 0; i < 3; ++i) b[i + 3, i] = 1; return b; }
        private static double[] NormalizedC(CandidateSpec s) { Vec3 g = s.Session.Frame.G0 / s.Scale.Acceleration; return new[] { 0.0, 0.0, 0.0, g.X, g.Y, g.Z }; }
    }
}
