using System;
using System.Collections.Generic;

namespace KOSGFOLD.Core
{
    internal sealed class SolverOutcome
    {
        internal bool Success; internal bool Infeasible; internal int Termination; internal double[] X; internal string Message;
    }
    internal static class AlglibSocpSolver
    {
        internal static SolverOutcome Solve(ConicProblem problem, double[] startingPoint)
        {
            try
            {
                alglib.minqpstate state; alglib.minqpcreate(problem.Variables, out state); double[] cost = new double[problem.Variables]; foreach (KeyValuePair<int, double> kv in problem.Objective) cost[kv.Key] = kv.Value; alglib.minqpsetlinearterm(state, cost);
                int rows = problem.Linear.Count; alglib.sparsematrix matrix; alglib.sparsecreate(rows, problem.Variables, out matrix); double[] lo = new double[rows], hi = new double[rows];
                for (int i = 0; i < rows; ++i) { LinearConstraint row = problem.Linear[i]; foreach (KeyValuePair<int, double> kv in row.Expr.Terms) alglib.sparseset(matrix, i, kv.Key, kv.Value); lo[i] = row.Lower - row.Expr.Constant; hi[i] = row.Upper - row.Expr.Constant; }
                alglib.sparseconverttocrs(matrix); alglib.minqpsetlc2(state, matrix, lo, hi, rows);
                foreach (ConeConstraint cone in problem.Cones) alglib.minqpaddsoccprimitive(state, cone.RadialStart, cone.RadialEnd, cone.Axis, false);
                double[] scale = new double[problem.Variables]; for (int i = 0; i < scale.Length; ++i) scale[i] = 1; alglib.minqpsetscale(state, scale); if (startingPoint != null && startingPoint.Length == problem.Variables) alglib.minqpsetstartingpoint(state, startingPoint);
                alglib.minqpsetalgosparsegenipm(state, 1e-8); alglib.minqpoptimize(state); double[] x; alglib.minqpreport report; alglib.minqpresults(state, out x, out report);
                bool finite = x != null && x.Length == problem.Variables; if (finite) foreach (double v in x) if (!Vec3.Finite(v)) { finite = false; break; }
                return new SolverOutcome { Success = report.terminationtype > 0 && finite, Infeasible = report.terminationtype == -3, Termination = report.terminationtype, X = x, Message = "ALGLIB termination " + report.terminationtype };
            }
            catch (Exception ex) { return new SolverOutcome { Success = false, Message = ex.GetType().Name + ": " + ex.Message }; }
        }
    }
}
