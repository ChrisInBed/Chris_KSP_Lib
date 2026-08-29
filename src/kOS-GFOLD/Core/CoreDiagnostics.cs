using System;

namespace KOSGFOLD.Core
{
    public static class CoreDiagnostics
    {
        public static void Run()
        {
            FrameModel polar = new FrameModel(new Vec3(0, 0, 1000), new Vec3(0, 0, 1), 1e6); Assert(Math.Abs(Vec3.Dot(polar.East, polar.Up)) < 1e-12, "polar frame orthogonality"); Assert(Math.Abs(Vec3.Dot(polar.North, polar.Up)) < 1e-12, "polar north orthogonality");
            Mesh mesh = MeshBuilder.Build(20, 30, 10, 20); Assert(mesh.Times.Length == 20, "mesh node count"); Assert(Contains(mesh.Times, 10) && Contains(mesh.Times, 20), "mesh event alignment");
            Mesh coincident = MeshBuilder.Build(20, 30, 15, 15); Assert(coincident.Times.Length == 20 && Contains(coincident.Times, 15), "coincident event alignment");
            double[,] a = new double[1, 1], b = new double[,] { { 1 } }; DiscreteStep step = LtiDiscretizer.Compute(a, b, new[] { 0.0 }, 2); double value = step.G0[0, 0] * 1 + step.G1[0, 0] * 3; Assert(Math.Abs(value - 4) < 1e-11, "FOH integral");
            TestLqr(); TestReferenceSampling();
            alglib.minqpstate state; alglib.minqpcreate(3, out state); alglib.minqpsetlinearterm(state, new[] { -1.0, 0.0, 0.0 }); alglib.minqpsetbc(state, new[] { double.NegativeInfinity, 0.0, 1.0 }, new[] { double.PositiveInfinity, 0.0, 1.0 }); alglib.minqpaddsoccprimitive(state, 0, 2, 2, false); alglib.minqpsetalgosparsegenipm(state, 1e-9); alglib.minqpoptimize(state); double[] x; alglib.minqpreport report; alglib.minqpresults(state, out x, out report); Assert(report.terminationtype > 0 && Math.Abs(x[0] - 1) < 1e-6, "ALGLIB SOC smoke test");
        }
        private static void TestLqr()
        {
            double[,] ac = new double[6, 6], bc = new double[6, 3], q = Dense.Identity(6), r = Dense.Identity(3); for (int i = 0; i < 3; ++i) { ac[i, i + 3] = 1; bc[i + 3, i] = 1; r[i, i] = 0.5; }
            DiscreteStep d = LtiDiscretizer.Compute(ac, bc, new double[6], 0.1); double[,] bd = Dense.Add(d.G0, d.G1), k = LqrTracker.SolveDare(d.Phi, bd, q, r), closed = Dense.Sub(d.Phi, Dense.Mul(bd, k)); double[] x = { 1, -2, 3, 0.5, -0.25, 1 };
            for (int i = 0; i < 500; ++i) x = Dense.Mul(closed, x); double norm = 0; foreach (double v in x) norm += v * v; Assert(Math.Sqrt(norm) < 1e-8, "discrete LQR closed-loop stability");
        }
        private static void TestReferenceSampling()
        {
            FrameModel f = new FrameModel(new Vec3(1, 0, 0), new Vec3(0, 0, 0), 0); Vec3 u0 = new Vec3(1, 2, 0), u1 = new Vec3(3, 4, 0), p1 = new Vec3(10.0 / 3.0, 16.0 / 3.0, 0), v1 = new Vec3(4, 6, 0);
            TrajectoryPoint a = new TrajectoryPoint { Time = 10, Position = f.ToBodyPosition(new Vec3(0, 0, 0)), Velocity = f.ToBodyVector(new Vec3(0, 0, 0)), ControlBefore = f.ToBodyVector(u0), ControlAfter = f.ToBodyVector(u0) };
            TrajectoryPoint b = new TrajectoryPoint { Time = 12, Position = f.ToBodyPosition(p1), Velocity = f.ToBodyVector(v1), ControlBefore = f.ToBodyVector(u1), ControlAfter = f.ToBodyVector(new Vec3(9, 9, 9)) };
            TrajectoryPoint c = new TrajectoryPoint { Time = 13, Position = f.ToBodyPosition(p1), Velocity = f.ToBodyVector(v1), ControlBefore = f.ToBodyVector(new Vec3(8, 8, 8)), ControlAfter = f.ToBodyVector(new Vec3(8, 8, 8)) };
            PlannerResult result = new PlannerResult { Ok = true, Trajectory = new System.Collections.Generic.List<TrajectoryPoint> { a, b, c } }; ReferenceState first = LqrTracker.Sample(f, result, 10), mid = LqrTracker.Sample(f, result, 11), eventState = LqrTracker.Sample(f, result, 12), terminal = LqrTracker.Sample(f, result, 13);
            Vec3 pm = f.ToLocalPosition(mid.Position), vm = f.ToLocalVector(mid.Velocity); Assert((pm - new Vec3(2.0 / 3.0, 7.0 / 6.0, 0)).Norm < 1e-11 && (vm - new Vec3(1.5, 2.5, 0)).Norm < 1e-11, "analytical FOH reference sampling"); Assert((eventState.Control - b.ControlAfter).Norm < 1e-12, "internal right-continuous control semantics"); Assert((terminal.Control - c.ControlBefore).Norm < 1e-12, "terminal incoming control semantics");
            Assert((first.Control - a.ControlAfter).Norm < 1e-12, "initial outgoing control semantics"); AssertThrows(delegate { LqrTracker.Sample(f, result, 9); }, "out-of-range reference rejection");
        }
        private static bool Contains(double[] xs, double x) { foreach (double v in xs) if (Math.Abs(v - x) < 1e-10) return true; return false; }
        private static void Assert(bool condition, string name) { if (!condition) throw new InvalidOperationException("Core diagnostic failed: " + name); }
        private static void AssertThrows(Action action, string name) { try { action(); } catch (ArgumentException) { return; } throw new InvalidOperationException("Core diagnostic failed: " + name); }
    }
}
