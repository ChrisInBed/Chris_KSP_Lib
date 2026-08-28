using System;

namespace KOSGFOLD.Core
{
    internal sealed class Normalizer
    {
        internal readonly double Length, Acceleration, Time, Velocity, Mass;
        internal Normalizer(Vec3 p0, Vec3 pf, Vec3 v0, double pitRadius, double pitDepth, Vec3 g0, double maxThrust, double mass)
        { Mass = mass; Length = Math.Max(1.0, Math.Max((p0 - pf).Norm, Math.Max(pitRadius, pitDepth))); Acceleration = Math.Max(1e-3, Math.Max(g0.Norm, Math.Max(maxThrust / mass, v0.Norm2 / Length))); Time = Math.Sqrt(Length / Acceleration); Velocity = Math.Sqrt(Length * Acceleration); }
        internal Vec3 PositionIn(Vec3 p) { return p / Length; } internal Vec3 PositionOut(Vec3 p) { return p * Length; }
        internal Vec3 VelocityIn(Vec3 v) { return v / Velocity; } internal Vec3 VelocityOut(Vec3 v) { return v * Velocity; }
        internal Vec3 AccelIn(Vec3 a) { return a / Acceleration; } internal Vec3 AccelOut(Vec3 a) { return a * Acceleration; }
        internal double TimeIn(double t) { return t / Time; } internal double TimeOut(double t) { return t * Time; }
    }
}
