using System;
using System.Collections.Generic;

namespace KOSGFOLD.Core
{
    public enum PlannerStatus { Solved, Infeasible, NumericalFailure, ValidationFailed, TimeBudgetExceeded, Cancelled }

    public sealed class InitializeRequest
    {
        public double StateTime; public Vec3 Position; public Vec3 Velocity; public double Mass;
        public double Mu; public double BodyRadius; public Vec3 BodySpin; public Vec3 TargetPosition; public Vec3 TargetVelocity; public Vec3 PitCenter;
        public double FuelMass; public double ThrustMin1; public double ThrustMax1; public double Isp1; public double ThrustMin2; public double ThrustMax2; public double Isp2; public double EngineSwitchTime;
        public double DescentMaxSpeed; public double DescentTilt; public double DescentGlideSlope; public double EntryMaxSpeed; public double EntryTilt; public double EntryGlideSlope;
        public double TerminalTilt; public double TerminalTiltWindow; public double PitRadius; public double WallBuffer; public double PitDepth;
        public int Nodes = 20; public int MaxSearchEvaluations = 20; public double? TfMin; public double? TfMax;
    }

    public sealed class UpdateRequest
    {
        public int Session; public double StateTime; public Vec3 Position; public Vec3 Velocity; public double Mass; public PlannerResult Previous; public int? MaxSearchEvaluations;
    }

    public sealed class TrajectoryPoint
    {
        public double Time; public Vec3 Position; public Vec3 Velocity; public Vec3 Thrust; public double Mass;
    }

    public sealed class PlannerResult
    {
        public bool Ok; public PlannerStatus Status; public string Message; public int Session; public double Epoch; public double SolveTime;
        public double Tf; public double Te; public double LandingError; public double FuelUsed; public int SearchEvaluations; public List<TrajectoryPoint> Trajectory;
        internal double[] SolverVector;
        public string StatusText { get { switch (Status) { case PlannerStatus.Solved: return "SOLVED"; case PlannerStatus.Infeasible: return "INFEASIBLE"; case PlannerStatus.NumericalFailure: return "NUMERICAL_FAILURE"; case PlannerStatus.ValidationFailed: return "VALIDATION_FAILED"; case PlannerStatus.TimeBudgetExceeded: return "TIME_BUDGET_EXCEEDED"; default: return "CANCELLED"; } } }
        internal static PlannerResult Failure(PlannerStatus status, string message, double epoch, int evaluations = 0) { return new PlannerResult { Ok = false, Status = status, Message = message, Epoch = epoch, SearchEvaluations = evaluations, Trajectory = null }; }
    }

    internal sealed class EngineMode
    {
        internal readonly double Min, Max, Alpha;
        internal EngineMode(double min, double max, double isp) { Min = min; Max = max; Alpha = 1.0 / (isp * 9.80665); }
    }

    internal sealed class PlannerSession
    {
        internal readonly int Id; internal readonly InitializeRequest Config; internal readonly FrameModel Frame; internal readonly double DryMass; internal readonly double SwitchEpoch;
        internal readonly EngineMode Mode1, Mode2; internal readonly object Gate = new object(); internal bool Active; internal double LatestEpoch;
        internal PlannerSession(int id, InitializeRequest c, FrameModel frame)
        { Id = id; Config = c; Frame = frame; DryMass = c.Mass - c.FuelMass; SwitchEpoch = c.StateTime + c.EngineSwitchTime; Mode1 = new EngineMode(c.ThrustMin1, c.ThrustMax1, c.Isp1); Mode2 = new EngineMode(c.ThrustMin2, c.ThrustMax2, c.Isp2); LatestEpoch = c.StateTime; }
    }

    internal static class InputValidation
    {
        internal static void Validate(InitializeRequest r)
        {
            if (r == null) throw new ArgumentNullException("request");
            Finite(r.StateTime, "stateTime"); Vector(r.Position, "position"); Vector(r.Velocity, "velocity"); Positive(r.Mass, "mass"); Positive(r.Mu, "mu"); Positive(r.BodyRadius, "bodyRadius"); Vector(r.BodySpin, "bodySpin"); Vector(r.TargetPosition, "targetPosition"); Vector(r.TargetVelocity, "targetVelocity"); Vector(r.PitCenter, "pitCenter");
            Positive(r.FuelMass, "fuelMass"); if (r.FuelMass >= r.Mass) throw new ArgumentException("fuelMass must be less than mass");
            Engine(r.ThrustMin1, r.ThrustMax1, r.Isp1, "1"); Engine(r.ThrustMin2, r.ThrustMax2, r.Isp2, "2"); if (r.EngineSwitchTime < 0) throw new ArgumentException("engineSwitchTime must be non-negative");
            Positive(r.DescentMaxSpeed, "descentMaxSpeed"); Positive(r.EntryMaxSpeed, "entryMaxSpeed"); Angle(r.DescentTilt, "descentTilt", true); Angle(r.EntryTilt, "entryTilt", true); Angle(r.TerminalTilt, "terminalTilt", true); Angle(r.DescentGlideSlope, "descentGlideSlope", false); Angle(r.EntryGlideSlope, "entryGlideSlope", false);
            if (r.TerminalTiltWindow < 0) throw new ArgumentException("terminalTiltWindow must be non-negative"); if (r.PitRadius < 0 || r.WallBuffer < 0 || r.PitDepth < 0) throw new ArgumentException("pit geometry values must be non-negative");
            if (r.PitDepth > 0 && !(r.PitRadius > r.WallBuffer)) throw new ArgumentException("pitRadius must exceed wallBuffer for pit landing"); if (r.PitDepth == 0 && r.WallBuffer > r.PitRadius) throw new ArgumentException("wallBuffer cannot exceed pitRadius");
            if (r.Nodes < 4 || r.Nodes > 200) throw new ArgumentException("nodes must be in [4,200]"); if (r.MaxSearchEvaluations < 1 || r.MaxSearchEvaluations > 200) throw new ArgumentException("maxSearchEvaluations must be in [1,200]");
            if (r.TfMin.HasValue && !(r.TfMin.Value > 0)) throw new ArgumentException("tfMin must be positive"); if (r.TfMax.HasValue && !(r.TfMax.Value > 0)) throw new ArgumentException("tfMax must be positive"); if (r.TfMin.HasValue && r.TfMax.HasValue && r.TfMin.Value >= r.TfMax.Value) throw new ArgumentException("tfMin must be less than tfMax");
            FrameModel f = new FrameModel(r.PitCenter, r.BodySpin, r.Mu); Vec3 target = f.ToLocalPosition(r.TargetPosition); double tol = Math.Max(0.01, 1e-6 * Math.Max(1, Math.Max(r.PitDepth, r.PitRadius)));
            Vec3 expected = new Vec3(0, -r.PitDepth, 0); if ((target - expected).Norm > tol) throw new ArgumentException("targetPosition must be the center of the cylinder floor (local [0,-pitDepth,0])");
        }
        internal static void ValidateUpdate(UpdateRequest r) { if (r == null) throw new ArgumentNullException("request"); if (r.Session <= 0) throw new ArgumentException("session must be positive"); Finite(r.StateTime, "stateTime"); Vector(r.Position, "position"); Vector(r.Velocity, "velocity"); Positive(r.Mass, "mass"); if (r.Previous == null || !r.Previous.Ok) throw new ArgumentException("previous must be a successful planner result"); if (r.MaxSearchEvaluations.HasValue && (r.MaxSearchEvaluations < 1 || r.MaxSearchEvaluations > 200)) throw new ArgumentException("maxSearchEvaluations must be in [1,200]"); }
        private static void Engine(double lo, double hi, double isp, string suffix) { Positive(lo, "thrustMin" + suffix); Positive(hi, "thrustMax" + suffix); if (lo > hi) throw new ArgumentException("minimum thrust cannot exceed maximum thrust"); Positive(isp, "isp" + suffix); }
        private static void Angle(double x, string name, bool allow90) { Finite(x, name); if (x < 0 || (allow90 ? x > 90 : x >= 90)) throw new ArgumentException(name + (allow90 ? " must be in [0,90]" : " must be in [0,90)")); }
        private static void Vector(Vec3 x, string name) { if (!x.IsFinite) throw new ArgumentException(name + " must be finite"); }
        private static void Positive(double x, string name) { Finite(x, name); if (!(x > 0)) throw new ArgumentException(name + " must be positive"); }
        private static void Finite(double x, string name) { if (!Vec3.Finite(x)) throw new ArgumentException(name + " must be finite"); }
    }
}
