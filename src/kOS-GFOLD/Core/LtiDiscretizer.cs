using System;

namespace KOSGFOLD.Core
{
    internal sealed class DiscreteStep
    {
        internal readonly double[,] Phi, G0, G1; internal readonly double[] Gamma;
        internal DiscreteStep(double[,] phi, double[,] g0, double[,] g1, double[] gamma) { Phi = phi; G0 = g0; G1 = g1; Gamma = gamma; }
    }
    internal static class LtiDiscretizer
    {
        // Exponentiate [A B 0 c; 0 0 I 0; 0 0 0 0; 0 0 0 0], where q=(u1-u0)/h.
        internal static DiscreteStep Compute(double[,] a, double[,] b, double[] c, double h)
        {
            int nx = a.GetLength(0), nu = b.GetLength(1), n = nx + 2 * nu + 1; double[,] aug = new double[n, n];
            for (int i = 0; i < nx; ++i) { for (int j = 0; j < nx; ++j) aug[i, j] = a[i, j]; for (int j = 0; j < nu; ++j) aug[i, nx + j] = b[i, j]; aug[i, n - 1] = c[i]; }
            for (int j = 0; j < nu; ++j) aug[nx + j, nx + nu + j] = 1;
            double[,] exp = Dense.Exponential(Dense.Scale(aug, h)), phi = new double[nx, nx], coeffU = new double[nx, nu], coeffQ = new double[nx, nu], g0 = new double[nx, nu], g1 = new double[nx, nu]; double[] gamma = new double[nx];
            for (int i = 0; i < nx; ++i) { for (int j = 0; j < nx; ++j) phi[i, j] = exp[i, j]; for (int j = 0; j < nu; ++j) { coeffU[i, j] = exp[i, nx + j]; coeffQ[i, j] = exp[i, nx + nu + j]; g1[i, j] = coeffQ[i, j] / h; g0[i, j] = coeffU[i, j] - g1[i, j]; } gamma[i] = exp[i, n - 1]; }
            return new DiscreteStep(phi, g0, g1, gamma);
        }
    }
}
