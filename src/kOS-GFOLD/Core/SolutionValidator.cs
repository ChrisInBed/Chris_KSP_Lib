using System;
using System.Collections.Generic;

namespace KOSGFOLD.Core
{
    internal static class SolutionValidator
    {
        internal static PlannerResult BuildAndValidate(ConicProblem model, double[] x, double landingError)
        {
            CandidateSpec s = model.Spec; InitializeRequest cfg = s.Session.Config; Normalizer z = s.Scale; List<TrajectoryPoint> trajectory = new List<TrajectoryPoint>(); Vec3[] localP = new Vec3[model.Nodes], localV = new Vec3[model.Nodes], localU = new Vec3[model.Nodes]; double[] mass = new double[model.Nodes], sigma = new double[model.Nodes];
            for (int k = 0; k < model.Nodes; ++k)
            {
                localP[k] = z.PositionOut(new Vec3(x[model.State(k, 0)], x[model.State(k, 1)], x[model.State(k, 2)])); localV[k] = z.VelocityOut(new Vec3(x[model.State(k, 3)], x[model.State(k, 4)], x[model.State(k, 5)])); mass[k] = s.Mass * Math.Exp(x[model.State(k, 6)]);
                int interval = k < model.Intervals ? k : model.Intervals - 1, side = k < model.Intervals ? 0 : 1; localU[k] = z.AccelOut(new Vec3(x[model.Control(interval, side, 0)], x[model.Control(interval, side, 1)], x[model.Control(interval, side, 2)])); sigma[k] = x[model.Control(interval, side, 3)] * z.Acceleration;
                int beforeInterval = k == 0 ? 0 : k - 1, beforeSide = k == 0 ? 0 : 1, afterInterval = k == model.Nodes - 1 ? model.Intervals - 1 : k, afterSide = k == model.Nodes - 1 ? 1 : 0;
                Vec3 before = z.AccelOut(new Vec3(x[model.Control(beforeInterval, beforeSide, 0)], x[model.Control(beforeInterval, beforeSide, 1)], x[model.Control(beforeInterval, beforeSide, 2)]));
                Vec3 after = z.AccelOut(new Vec3(x[model.Control(afterInterval, afterSide, 0)], x[model.Control(afterInterval, afterSide, 1)], x[model.Control(afterInterval, afterSide, 2)]));
                trajectory.Add(new TrajectoryPoint { Time = s.Epoch + model.Mesh.Times[k], Position = s.Session.Frame.ToBodyPosition(localP[k]), Velocity = s.Session.Frame.ToBodyVector(localV[k]), Thrust = s.Session.Frame.ToBodyVector(localU[k] * mass[k]), Mass = mass[k], ControlBefore = s.Session.Frame.ToBodyVector(before), ControlAfter = s.Session.Frame.ToBodyVector(after) });
            }
            string violation = CheckNodes(s, model, localP, localV, localU, sigma, mass); if (violation != null) return PlannerResult.Failure(PlannerStatus.ValidationFailed, violation, s.Epoch);
            violation = CheckExactPropagation(s, model, localP, localV, x); if (violation != null) return PlannerResult.Failure(PlannerStatus.ValidationFailed, violation, s.Epoch);
            return new PlannerResult { Ok = true, Status = PlannerStatus.Solved, Message = "Validated trajectory", Epoch = s.Epoch, Tf = s.Tf, Te = s.EntryOnly ? 0 : (cfg.PitDepth == 0 ? s.Tf : s.Te), LandingError = landingError, FuelUsed = s.Mass - mass[model.Nodes - 1], Trajectory = trajectory, SolverVector = x };
        }

        private static string CheckNodes(CandidateSpec s, ConicProblem model, Vec3[] p, Vec3[] v, Vec3[] u, double[] sigma, double[] mass)
        {
            InitializeRequest c = s.Session.Config; double rs = c.PitRadius - c.WallBuffer, tolP = Math.Max(0.02, 1e-5 * s.Scale.Length), tolV = Math.Max(0.01, 1e-5 * s.Scale.Velocity);
            for (int k = 0; k < model.Nodes; ++k)
            {
                if (!p[k].IsFinite || !v[k].IsFinite || !u[k].IsFinite || !Vec3.Finite(mass[k])) return "Non-finite trajectory value"; if (k > 0 && mass[k] > mass[k - 1] + 1e-7) return "Mass increases along trajectory"; if (mass[k] < s.Session.DryMass - 1e-6) return "Dry-mass constraint violated";
                double gap = Math.Abs(u[k].Norm - sigma[k]); if (gap > Math.Max(1e-4, 5e-3 * Math.Max(sigma[k], 1e-6))) return "Lossless thrust relaxation gap is excessive";
                EngineMode engine = model.Mesh.Times[k] < s.Tc ? s.Session.Mode1 : s.Session.Mode2; double physicalThrust = mass[k] * u[k].Norm, thrustTol = Math.Max(1e-4, 1e-5 * engine.Max); if (physicalThrust < engine.Min - thrustTol || physicalThrust > engine.Max + thrustTol) return "Original physical thrust bound violated";
                double t = model.Mesh.Times[k], tiltLimit = IsEntry(s, t) ? c.EntryTilt : c.DescentTilt; if (s.Tf - t <= c.TerminalTiltWindow + 1e-8) tiltLimit = Math.Min(tiltLimit, c.TerminalTilt); if (u[k].Norm > 1e-9 && u[k].Y / u[k].Norm < Math.Cos(tiltLimit * Math.PI / 180) - 1e-5) return "Tilt constraint violated";
                bool entry = IsEntry(s, t); double vmax = entry ? c.EntryMaxSpeed : c.DescentMaxSpeed; if (v[k].Norm > vmax + tolV) return "Speed constraint violated";
                if (!entry) { if (p[k].Y < -tolP) return "Descent altitude constraint violated"; double rhs = Math.Tan(c.DescentGlideSlope * Math.PI / 180) * (Math.Sqrt(p[k].X * p[k].X + p[k].Z * p[k].Z) - rs); if (p[k].Y + tolP < rhs) return "Descent glide-slope constraint violated"; }
                else { double radius = Math.Sqrt(p[k].X * p[k].X + p[k].Z * p[k].Z); if (radius > rs + tolP || p[k].Y < -c.PitDepth - tolP || p[k].Y > tolP || v[k].Y > tolV) return "Pit-entry constraint violated"; if (c.EntryGlideSlope > 0 && p[k].Y + c.PitDepth + tolP < Math.Tan(c.EntryGlideSlope * Math.PI / 180) * radius) return "Entry glide-slope constraint violated"; }
            }
            return null;
        }

        private static string CheckExactPropagation(CandidateSpec s, ConicProblem model, Vec3[] expectedP, Vec3[] expectedV, double[] x)
        {
            Vec3 rb = s.Position, vb = s.Velocity; double maxP = 0, maxV = 0;
            for (int k = 0; k < model.Intervals; ++k)
            {
                double dt = model.Mesh.Times[k + 1] - model.Mesh.Times[k]; Vec3 u0 = s.Scale.AccelOut(new Vec3(x[model.Control(k, 0, 0)], x[model.Control(k, 0, 1)], x[model.Control(k, 0, 2)])), u1 = s.Scale.AccelOut(new Vec3(x[model.Control(k, 1, 0)], x[model.Control(k, 1, 1)], x[model.Control(k, 1, 2)])); int steps = Math.Max(4, Math.Min(40, (int)Math.Ceiling(dt / 0.2))); double h = dt / steps;
                for (int j = 0; j < steps; ++j) { double f0 = (double)j / steps, f1 = (j + 0.5) / steps, f2 = (double)(j + 1) / steps; StepRk4(s.Session.Frame, ref rb, ref vb, s.Session.Frame.ToBodyVector(u0 * (1 - f0) + u1 * f0), s.Session.Frame.ToBodyVector(u0 * (1 - f1) + u1 * f1), s.Session.Frame.ToBodyVector(u0 * (1 - f2) + u1 * f2), h); }
                Vec3 ep = s.Session.Frame.ToBodyPosition(expectedP[k + 1]), ev = s.Session.Frame.ToBodyVector(expectedV[k + 1]); maxP = Math.Max(maxP, (rb - ep).Norm); maxV = Math.Max(maxV, (vb - ev).Norm);
            }
            double posTol = Math.Max(0.5, 0.005 * s.Scale.Length), velTol = Math.Max(0.05, 0.005 * s.Scale.Velocity); if (maxP > posTol || maxV > velTol) return string.Format("Exact-gravity mismatch too large (position {0:F3} m, velocity {1:F3} m/s)", maxP, maxV); return null;
        }

        private static void StepRk4(FrameModel frame, ref Vec3 r, ref Vec3 v, Vec3 u0, Vec3 um, Vec3 u1, double h)
        {
            Vec3 k1r = v, k1v = frame.ExactAcceleration(r, v, u0); Vec3 k2r = v + k1v * (h / 2), k2v = frame.ExactAcceleration(r + k1r * (h / 2), v + k1v * (h / 2), um); Vec3 k3r = v + k2v * (h / 2), k3v = frame.ExactAcceleration(r + k2r * (h / 2), v + k2v * (h / 2), um); Vec3 k4r = v + k3v * h, k4v = frame.ExactAcceleration(r + k3r * h, v + k3v * h, u1); r += (k1r + 2 * k2r + 2 * k3r + k4r) * (h / 6); v += (k1v + 2 * k2v + 2 * k3v + k4v) * (h / 6);
        }
        private static bool IsEntry(CandidateSpec s, double t) { return s.EntryOnly || (s.Session.Config.PitDepth > 0 && t >= s.Te - 1e-8); }
    }
}
