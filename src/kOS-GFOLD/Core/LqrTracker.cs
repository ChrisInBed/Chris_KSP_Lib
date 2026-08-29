using System;
using System.Collections.Generic;

namespace KOSGFOLD.Core
{
    internal static class LqrTracker
    {
        internal static double[,] ComputePhysicalBodyGain(FrameModel frame, Normalizer scale, double dt, double lambda, double beta)
        {
            double[,] a = NormalizedA(frame, scale), b = InputMatrix(), q = new double[6, 6], r = new double[3, 3];
            for (int i = 0; i < 3; ++i) { q[i, i] = 1; q[i + 3, i + 3] = beta; r[i, i] = lambda; }
            DiscreteStep step = LtiDiscretizer.Compute(a, b, new double[6], dt / scale.Time);
            double[,] bd = Dense.Add(step.G0, step.G1), kn = SolveDare(step.Phi, bd, q, r);
            double[,] kl = new double[3, 6];
            for (int i = 0; i < 3; ++i) for (int j = 0; j < 3; ++j)
            {
                kl[i, j] = scale.Acceleration * kn[i, j] / scale.Length;
                kl[i, j + 3] = scale.Acceleration * kn[i, j + 3] / scale.Velocity;
            }
            double[,] result = new double[3, 6];
            for (int j = 0; j < 6; ++j)
            {
                Vec3 bodyError = j < 3 ? Basis(j) : Basis(j - 3), localError = frame.ToLocalVector(bodyError);
                int offset = j < 3 ? 0 : 3;
                Vec3 localControl = new Vec3(RowDot(kl, 0, offset, localError), RowDot(kl, 1, offset, localError), RowDot(kl, 2, offset, localError));
                Vec3 bodyControl = frame.ToBodyVector(localControl); result[0, j] = bodyControl.X; result[1, j] = bodyControl.Y; result[2, j] = bodyControl.Z;
            }
            EnsureFinite(result, "physical LQR gain"); return result;
        }

        internal static ReferenceState Sample(FrameModel frame, PlannerResult reference, double time)
        {
            if (reference == null || !reference.Ok || reference.Trajectory == null || reference.Trajectory.Count < 2) throw new ArgumentException("reference must be a successful result with at least two trajectory nodes");
            List<TrajectoryPoint> tr = reference.Trajectory; double tolerance = 1e-8 * Math.Max(1, Math.Abs(time));
            if (time < tr[0].Time - tolerance || time > tr[tr.Count - 1].Time + tolerance) throw new ArgumentOutOfRangeException("time", "time must lie within the reference trajectory");
            ValidateTrajectory(tr);
            if (Math.Abs(time - tr[tr.Count - 1].Time) <= tolerance) return AtNode(tr[tr.Count - 1], tr[tr.Count - 1].ControlBefore);
            for (int i = 0; i < tr.Count - 1; ++i)
            {
                if (Math.Abs(time - tr[i].Time) <= tolerance) return AtNode(tr[i], tr[i].ControlAfter);
                if (time < tr[i + 1].Time - tolerance)
                {
                    double h = tr[i + 1].Time - tr[i].Time, tau = time - tr[i].Time, f = tau / h;
                    Vec3 u0 = frame.ToLocalVector(tr[i].ControlAfter), u1 = frame.ToLocalVector(tr[i + 1].ControlBefore), ut = u0 * (1 - f) + u1 * f;
                    double[,] a = PhysicalA(frame), b = InputMatrix(); double[] c = { 0, 0, 0, frame.G0.X, frame.G0.Y, frame.G0.Z };
                    DiscreteStep d = LtiDiscretizer.Compute(a, b, c, tau); Vec3 p0 = frame.ToLocalPosition(tr[i].Position), v0 = frame.ToLocalVector(tr[i].Velocity);
                    double[] x0 = { p0.X, p0.Y, p0.Z, v0.X, v0.Y, v0.Z };
                    double[] x = Dense.Mul(d.Phi, x0), a0 = Dense.Mul(d.G0, u0.ToArray()), a1 = Dense.Mul(d.G1, ut.ToArray());
                    for (int k = 0; k < 6; ++k) x[k] += a0[k] + a1[k] + d.Gamma[k];
                    Vec3 p = new Vec3(x[0], x[1], x[2]), v = new Vec3(x[3], x[4], x[5]);
                    return new ReferenceState { Time = time, Control = frame.ToBodyVector(ut), Position = frame.ToBodyPosition(p), Velocity = frame.ToBodyVector(v) };
                }
            }
            throw new InvalidOperationException("Unable to locate reference interval");
        }

        internal static double[,] SolveDare(double[,] a, double[,] b, double[,] q, double[,] r)
        {
            double[,] p = Dense.Copy(q), next = null;
            for (int iteration = 0; iteration < 100000; ++iteration)
            {
                double[,] k = Gain(a, b, p, r), closed = Dense.Sub(a, Dense.Mul(b, k));
                next = Dense.Add(q, Dense.Mul(Transpose(a), Dense.Mul(p, closed))); Symmetrize(next);
                double delta = MaxAbs(Dense.Sub(next, p)), size = MaxAbs(next); p = next;
                if (delta <= 1e-12 * (1 + size))
                {
                    double[,] gain = Gain(a, b, p, r), residual = Dense.Sub(Dense.Add(q, Dense.Mul(Transpose(a), Dense.Mul(p, Dense.Sub(a, Dense.Mul(b, gain))))), p);
                    if (MaxAbs(residual) > 1e-9 * (1 + MaxAbs(p))) throw new InvalidOperationException("Discrete Riccati residual is too large");
                    EnsureFinite(gain, "LQR gain"); return gain;
                }
            }
            throw new InvalidOperationException("Discrete Riccati iteration did not converge");
        }

        private static double[,] Gain(double[,] a, double[,] b, double[,] p, double[,] r)
        {
            double[,] bt = Transpose(b), btp = Dense.Mul(bt, p), s = Dense.Add(r, Dense.Mul(btp, b)); return Dense.Solve(s, Dense.Mul(btp, a));
        }
        private static double[,] NormalizedA(FrameModel frame, Normalizer scale)
        {
            double[,] a = new double[6, 6]; for (int i = 0; i < 3; ++i) { a[i, i + 3] = 1; for (int j = 0; j < 3; ++j) { a[i + 3, j] = scale.Time * scale.Time * frame.Ap[i, j]; a[i + 3, j + 3] = scale.Time * frame.Av[i, j]; } } return a;
        }
        private static double[,] PhysicalA(FrameModel frame)
        {
            double[,] a = new double[6, 6]; for (int i = 0; i < 3; ++i) { a[i, i + 3] = 1; for (int j = 0; j < 3; ++j) { a[i + 3, j] = frame.Ap[i, j]; a[i + 3, j + 3] = frame.Av[i, j]; } } return a;
        }
        private static double[,] InputMatrix() { double[,] b = new double[6, 3]; for (int i = 0; i < 3; ++i) b[i + 3, i] = 1; return b; }
        private static ReferenceState AtNode(TrajectoryPoint p, Vec3 control) { return new ReferenceState { Time = p.Time, Control = control, Position = p.Position, Velocity = p.Velocity }; }
        private static void ValidateTrajectory(List<TrajectoryPoint> tr)
        {
            for (int i = 0; i < tr.Count; ++i) { TrajectoryPoint p = tr[i]; if (!Vec3.Finite(p.Time) || !p.Position.IsFinite || !p.Velocity.IsFinite || !p.ControlBefore.IsFinite || !p.ControlAfter.IsFinite) throw new ArgumentException("reference trajectory contains non-finite values"); if (i > 0 && !(p.Time > tr[i - 1].Time)) throw new ArgumentException("reference trajectory times must be strictly increasing"); }
        }
        private static Vec3 Basis(int i) { return i == 0 ? new Vec3(1, 0, 0) : (i == 1 ? new Vec3(0, 1, 0) : new Vec3(0, 0, 1)); }
        private static double RowDot(double[,] a, int row, int offset, Vec3 x) { return a[row, offset] * x.X + a[row, offset + 1] * x.Y + a[row, offset + 2] * x.Z; }
        private static double[,] Transpose(double[,] a) { double[,] r = new double[a.GetLength(1), a.GetLength(0)]; for (int i = 0; i < a.GetLength(0); ++i) for (int j = 0; j < a.GetLength(1); ++j) r[j, i] = a[i, j]; return r; }
        private static void Symmetrize(double[,] a) { for (int i = 0; i < a.GetLength(0); ++i) for (int j = i + 1; j < a.GetLength(1); ++j) { double x = 0.5 * (a[i, j] + a[j, i]); a[i, j] = x; a[j, i] = x; } }
        private static double MaxAbs(double[,] a) { double m = 0; for (int i = 0; i < a.GetLength(0); ++i) for (int j = 0; j < a.GetLength(1); ++j) m = Math.Max(m, Math.Abs(a[i, j])); return m; }
        private static void EnsureFinite(double[,] a, string name) { for (int i = 0; i < a.GetLength(0); ++i) for (int j = 0; j < a.GetLength(1); ++j) if (!Vec3.Finite(a[i, j])) throw new InvalidOperationException(name + " contains non-finite values"); }
    }
}
