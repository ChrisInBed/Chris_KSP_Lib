using System;

namespace KOSGFOLD.Core
{
    internal sealed class FrameModel
    {
        internal readonly Vec3 Reference, East, Up, North, Omega; internal readonly double Mu; internal readonly double[,] Ap = new double[3, 3], Av = new double[3, 3]; internal readonly Vec3 G0;
        internal FrameModel(Vec3 reference, Vec3 omega, double mu)
        {
            Reference = reference; Omega = omega; Mu = mu; Up = reference.Normalized();
            Vec3 east = Vec3.Cross(omega, Up); if (east.Norm < 1e-10) { Vec3 seed = Math.Abs(Up.X) <= Math.Abs(Up.Y) && Math.Abs(Up.X) <= Math.Abs(Up.Z) ? new Vec3(1, 0, 0) : (Math.Abs(Up.Y) <= Math.Abs(Up.Z) ? new Vec3(0, 1, 0) : new Vec3(0, 0, 1)); east = Vec3.Cross(seed, Up); }
            East = east.Normalized(); North = Vec3.Cross(Up, East).Normalized();
            double r = reference.Norm, q = mu / (r * r * r); double[,] j = new double[3, 3]; double[] n = Up.ToArray(); for (int i = 0; i < 3; ++i) for (int k = 0; k < 3; ++k) j[i, k] = q * (3 * n[i] * n[k] - (i == k ? 1 : 0));
            double[,] om = Skew(omega), om2 = Dense.Mul(om, om), rlb = RotationRows(), rbl = Transpose(rlb); double[,] apl = Dense.Mul(Dense.Mul(rlb, Dense.Sub(j, om2)), rbl), avl = Dense.Scale(Dense.Mul(Dense.Mul(rlb, om), rbl), -2);
            Array.Copy(apl, Ap, apl.Length); Array.Copy(avl, Av, avl.Length);
            Vec3 gravity = reference * (-mu / (r * r * r)); Vec3 centrifugal = FromArray(Dense.Mul(om2, reference.ToArray())) * -1; G0 = ToLocalVector(gravity + centrifugal);
        }
        internal Vec3 ToLocalPosition(Vec3 body) { return ToLocalVector(body - Reference); }
        internal Vec3 ToLocalVector(Vec3 body) { return new Vec3(Vec3.Dot(East, body), Vec3.Dot(Up, body), Vec3.Dot(North, body)); }
        internal Vec3 ToBodyPosition(Vec3 local) { return Reference + ToBodyVector(local); }
        internal Vec3 ToBodyVector(Vec3 local) { return East * local.X + Up * local.Y + North * local.Z; }
        internal Vec3 ExactAcceleration(Vec3 bodyPosition, Vec3 bodyVelocity, Vec3 bodyAcceleration)
        {
            double r = bodyPosition.Norm; Vec3 gravity = bodyPosition * (-Mu / (r * r * r)); return gravity - 2 * Vec3.Cross(Omega, bodyVelocity) - Vec3.Cross(Omega, Vec3.Cross(Omega, bodyPosition)) + bodyAcceleration;
        }
        private double[,] RotationRows() { return new[,] { { East.X, East.Y, East.Z }, { Up.X, Up.Y, Up.Z }, { North.X, North.Y, North.Z } }; }
        private static double[,] Transpose(double[,] a) { double[,] r = new double[a.GetLength(1), a.GetLength(0)]; for (int i = 0; i < a.GetLength(0); ++i) for (int j = 0; j < a.GetLength(1); ++j) r[j, i] = a[i, j]; return r; }
        private static double[,] Skew(Vec3 w) { return new[,] { { 0.0, -w.Z, w.Y }, { w.Z, 0.0, -w.X }, { -w.Y, w.X, 0.0 } }; }
        private static Vec3 FromArray(double[] x) { return new Vec3(x[0], x[1], x[2]); }
    }
}
