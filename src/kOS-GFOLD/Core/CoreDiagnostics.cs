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
            alglib.minqpstate state; alglib.minqpcreate(3, out state); alglib.minqpsetlinearterm(state, new[] { -1.0, 0.0, 0.0 }); alglib.minqpsetbc(state, new[] { double.NegativeInfinity, 0.0, 1.0 }, new[] { double.PositiveInfinity, 0.0, 1.0 }); alglib.minqpaddsoccprimitive(state, 0, 2, 2, false); alglib.minqpsetalgosparsegenipm(state, 1e-9); alglib.minqpoptimize(state); double[] x; alglib.minqpreport report; alglib.minqpresults(state, out x, out report); Assert(report.terminationtype > 0 && Math.Abs(x[0] - 1) < 1e-6, "ALGLIB SOC smoke test");
        }
        private static bool Contains(double[] xs, double x) { foreach (double v in xs) if (Math.Abs(v - x) < 1e-10) return true; return false; }
        private static void Assert(bool condition, string name) { if (!condition) throw new InvalidOperationException("Core diagnostic failed: " + name); }
    }
}
