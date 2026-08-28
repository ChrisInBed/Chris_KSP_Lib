using System;
using System.Collections;
using System.Collections.Generic;
using KOSGFOLD.Core;

namespace KOSGFOLD.Cli
{
    internal static class JsonAdapter
    {
        internal static Dictionary<string, object> Object(object value) { Dictionary<string, object> d = value as Dictionary<string, object>; if (d == null) throw new ArgumentException("Expected a JSON object"); return d; }
        internal static object[] Array(object value) { object[] a = value as object[]; if (a != null) return a; ArrayList l = value as ArrayList; if (l != null) return l.ToArray(); throw new ArgumentException("Expected a JSON array"); }
        internal static object Required(Dictionary<string, object> d, string name) { object v; if (!d.TryGetValue(name, out v)) throw new ArgumentException("Missing field '" + name + "'"); return v; }
        private static double D(Dictionary<string, object> d, string n) { return Convert.ToDouble(Required(d, n)); }
        private static int I(Dictionary<string, object> d, string n, int fallback) { object v; return d.TryGetValue(n, out v) ? Convert.ToInt32(v) : fallback; }
        private static double? OD(Dictionary<string, object> d, string n) { object v; return d.TryGetValue(n, out v) && v != null ? (double?)Convert.ToDouble(v) : null; }
        private static Vec3 V(Dictionary<string, object> d, string n) { object[] a = Array(Required(d, n)); if (a.Length != 3) throw new ArgumentException(n + " must contain three values"); return new Vec3(Convert.ToDouble(a[0]), Convert.ToDouble(a[1]), Convert.ToDouble(a[2])); }
        internal static InitializeRequest ParseInitialize(Dictionary<string, object> d)
        {
            return new InitializeRequest { StateTime = D(d, "stateTime"), Position = V(d, "position"), Velocity = V(d, "velocity"), Mass = D(d, "mass"), Mu = D(d, "mu"), BodyRadius = D(d, "bodyRadius"), BodySpin = V(d, "bodySpin"), TargetPosition = V(d, "targetPosition"), TargetVelocity = V(d, "targetVelocity"), PitCenter = V(d, "pitCenter"), FuelMass = D(d, "fuelMass"), ThrustMin1 = D(d, "thrustMin1"), ThrustMax1 = D(d, "thrustMax1"), Isp1 = D(d, "isp1"), ThrustMin2 = D(d, "thrustMin2"), ThrustMax2 = D(d, "thrustMax2"), Isp2 = D(d, "isp2"), EngineSwitchTime = D(d, "engineSwitchTime"), DescentMaxSpeed = D(d, "descentMaxSpeed"), DescentTilt = D(d, "descentTilt"), DescentGlideSlope = D(d, "descentGlideSlope"), EntryMaxSpeed = D(d, "entryMaxSpeed"), EntryTilt = D(d, "entryTilt"), EntryGlideSlope = D(d, "entryGlideSlope"), TerminalTilt = D(d, "terminalTilt"), TerminalTiltWindow = D(d, "terminalTiltWindow"), PitRadius = D(d, "pitRadius"), WallBuffer = D(d, "wallBuffer"), PitDepth = D(d, "pitDepth"), Nodes = I(d, "nodes", 20), MaxSearchEvaluations = I(d, "maxSearchEvaluations", 20), TfMin = OD(d, "tfMin"), TfMax = OD(d, "tfMax") };
        }
        internal static UpdateRequest ParseUpdate(Dictionary<string, object> d, PlannerResult previous) { object v; return new UpdateRequest { Session = previous.Session, Previous = previous, StateTime = D(d, "stateTime"), Position = V(d, "position"), Velocity = V(d, "velocity"), Mass = D(d, "mass"), MaxSearchEvaluations = d.TryGetValue("maxSearchEvaluations", out v) ? (int?)Convert.ToInt32(v) : null }; }
        internal static Dictionary<string, object> Result(PlannerResult r)
        {
            Dictionary<string, object> d = new Dictionary<string, object> { { "ok", r.Ok }, { "status", r.StatusText }, { "message", r.Message ?? "" }, { "session", r.Session }, { "epoch", r.Epoch }, { "solveTime", r.SolveTime }, { "landingError", r.LandingError }, { "fuelUsed", r.FuelUsed }, { "searchEvaluations", r.SearchEvaluations } };
            if (r.Ok) { d["tf"] = r.Tf; d["te"] = r.Te; List<object> traj = new List<object>(); foreach (TrajectoryPoint q in r.Trajectory) traj.Add(new Dictionary<string, object> { { "time", q.Time }, { "position", q.Position.ToArray() }, { "velocity", q.Velocity.ToArray() }, { "thrust", q.Thrust.ToArray() }, { "mass", q.Mass } }); d["trajectory"] = traj; } return d;
        }
    }
}
