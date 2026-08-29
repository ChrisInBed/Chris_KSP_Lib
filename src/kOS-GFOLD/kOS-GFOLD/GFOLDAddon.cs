using System;
using System.Collections.Concurrent;
using System.Threading;
using System.Threading.Tasks;
using KOSGFOLD.Core;
using kOS.Safe;
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;
using kOS.Safe.Exceptions;
using kOS.Safe.Utilities;
using kOS.Suffixed;

namespace kOS.AddOns.GFOLDAddon
{
    [kOSAddon("GFOLD")]
    [KOSNomenclature("GFOLDAddon")]
    public sealed class Addon : Suffixed.Addon
    {
        private sealed class TaskRecord { internal Task<PlannerResult> Task; }
        private static readonly Planner CorePlanner = new Planner();
        private static readonly ConcurrentDictionary<int, TaskRecord> Tasks = new ConcurrentDictionary<int, TaskRecord>();
        private static readonly ConcurrentDictionary<int, byte> AsyncSessions = new ConcurrentDictionary<int, byte>();
        private static int nextTask;

        public Addon(SharedObjects shared) : base(shared)
        {
            AddSuffix(new[] { "Initialize" }, new OneArgsSuffix<Lexicon, Lexicon>(Initialize, "Synchronously compute an initial GFOLD trajectory"));
            AddSuffix(new[] { "AsyncInitialize" }, new OneArgsSuffix<ScalarValue, Lexicon>(AsyncInitialize, "Start an initial GFOLD solve and return a task handle"));
            AddSuffix(new[] { "Update" }, new OneArgsSuffix<Lexicon, Lexicon>(Update, "Synchronously replan a GFOLD trajectory"));
            AddSuffix(new[] { "AsyncUpdate" }, new OneArgsSuffix<ScalarValue, Lexicon>(AsyncUpdate, "Start a GFOLD replan and return a task handle"));
            AddSuffix(new[] { "GetRefState" }, new OneArgsSuffix<Lexicon, Lexicon>(GetRefState, "Analytically sample a solved GFOLD reference trajectory"));
            AddSuffix(new[] { "CheckTask" }, new OneArgsSuffix<BooleanValue, ScalarValue>(CheckTask, "Test whether a GFOLD task is complete"));
            AddSuffix(new[] { "GetTaskResult" }, new OneArgsSuffix<Lexicon, ScalarValue>(GetTaskResult, "Retrieve and remove a completed GFOLD task"));
        }

        private Lexicon Initialize(Lexicon args) { InitializeRequest request = ParseInitialize(args); InputValidation.Validate(request); return ToLexicon(CorePlanner.Initialize(request)); }
        private Lexicon Update(Lexicon args) { UpdateRequest request = ParseUpdate(args); InputValidation.ValidateUpdate(request); return ToLexicon(CorePlanner.Update(request)); }
        private Lexicon GetRefState(Lexicon args)
        {
            try { PlannerResult reference = ParseReference(Required(args, "reference")); ReferenceState state = CorePlanner.GetRefState(reference, D(args, "time")); Lexicon d = new Lexicon(); Add(d, "time", ScalarValue.Create(state.Time)); Add(d, "control", Vector(state.Control)); Add(d, "position", Vector(state.Position)); Add(d, "velocity", Vector(state.Velocity)); return d; }
            catch (KOSException) { throw; } catch (Exception ex) { throw new KOSException(ex.Message); }
        }
        private ScalarValue AsyncInitialize(Lexicon args)
        {
            InitializeRequest request = ParseInitialize(args); InputValidation.Validate(request); int handle = Interlocked.Increment(ref nextTask); TaskRecord record = new TaskRecord(); record.Task = Task.Run(delegate { return SafeInitialize(request); }); Tasks[handle] = record; return ScalarValue.Create(handle);
        }
        private ScalarValue AsyncUpdate(Lexicon args)
        {
            UpdateRequest request = ParseUpdate(args); InputValidation.ValidateUpdate(request); if (!AsyncSessions.TryAdd(request.Session, 0)) throw new KOSException("An asynchronous solve is already active for session " + request.Session); int handle = Interlocked.Increment(ref nextTask); TaskRecord record = new TaskRecord(); record.Task = Task.Run(delegate { try { return SafeUpdate(request); } finally { byte ignored; AsyncSessions.TryRemove(request.Session, out ignored); } }); Tasks[handle] = record; return ScalarValue.Create(handle);
        }
        private static PlannerResult SafeInitialize(InitializeRequest r) { try { return CorePlanner.Initialize(r); } catch (Exception ex) { return PlannerResult.Failure(PlannerStatus.NumericalFailure, ex.Message, r.StateTime); } }
        private static PlannerResult SafeUpdate(UpdateRequest r) { try { return CorePlanner.Update(r); } catch (Exception ex) { PlannerResult f = PlannerResult.Failure(PlannerStatus.NumericalFailure, ex.Message, r.StateTime); f.Session = r.Session; return f; } }
        private BooleanValue CheckTask(ScalarValue value) { int handle = Handle(value); TaskRecord record; if (!Tasks.TryGetValue(handle, out record)) throw new KOSException("No task with handle " + handle + " exists"); return record.Task.IsCompleted ? BooleanValue.True : BooleanValue.False; }
        private Lexicon GetTaskResult(ScalarValue value)
        {
            int handle = Handle(value); TaskRecord record; if (!Tasks.TryGetValue(handle, out record)) throw new KOSException("No task with handle " + handle + " exists"); if (!record.Task.IsCompleted) throw new KOSException("Task " + handle + " has not completed yet"); Tasks.TryRemove(handle, out record); return ToLexicon(record.Task.GetAwaiter().GetResult());
        }
        private static int Handle(ScalarValue value) { double d = value.GetDoubleValue(); if (!Vec3.Finite(d) || Math.Abs(d - Math.Round(d)) > 1e-9) throw new KOSException("Task handle must be an integer"); return Convert.ToInt32(d); }

        private static InitializeRequest ParseInitialize(Lexicon a)
        {
            return new InitializeRequest { StateTime = D(a, "stateTime"), Position = V(a, "position"), Velocity = V(a, "velocity"), Mass = D(a, "mass"), Mu = D(a, "mu"), BodyRadius = D(a, "bodyRadius"), BodySpin = V(a, "bodySpin"), TargetPosition = V(a, "targetPosition"), TargetVelocity = V(a, "targetVelocity"), PitCenter = V(a, "pitCenter"), FuelMass = D(a, "fuelMass"), ThrustMin1 = D(a, "thrustMin1"), ThrustMax1 = D(a, "thrustMax1"), Isp1 = D(a, "isp1"), ThrustMin2 = D(a, "thrustMin2"), ThrustMax2 = D(a, "thrustMax2"), Isp2 = D(a, "isp2"), EngineSwitchTime = D(a, "engineSwitchTime"), DescentMaxSpeed = D(a, "descentMaxSpeed"), DescentTilt = D(a, "descentTilt"), DescentGlideSlope = D(a, "descentGlideSlope"), EntryMaxSpeed = D(a, "entryMaxSpeed"), EntryTilt = D(a, "entryTilt"), EntryGlideSlope = D(a, "entryGlideSlope"), TerminalTilt = D(a, "terminalTilt"), TerminalTiltWindow = D(a, "terminalTiltWindow"), PitRadius = D(a, "pitRadius"), WallBuffer = D(a, "wallBuffer"), PitDepth = D(a, "pitDepth"), Nodes = OI(a, "nodes", 20), MaxSearchEvaluations = OI(a, "maxSearchEvaluations", 20), TfMin = OD(a, "tfMin"), TfMax = OD(a, "tfMax"), LqrDt = D(a, "lqrDt"), LqrLambda = ODValue(a, "lqrLambda", 0.5), LqrBeta = ODValue(a, "lqrBeta", 1.0) };
        }
        private static UpdateRequest ParseUpdate(Lexicon a)
        {
            Structure raw = Required(a, "previous"); Lexicon previousLex = raw as Lexicon; if (previousLex == null) throw new KOSException("Argument 'previous' must be a Lexicon"); PlannerResult previous = new PlannerResult { Ok = B(previousLex, "ok"), Session = I(previousLex, "session"), Epoch = D(previousLex, "epoch"), Tf = D(previousLex, "tf"), Te = D(previousLex, "te"), Status = PlannerStatus.Solved };
            return new UpdateRequest { Session = I(a, "session"), StateTime = D(a, "stateTime"), Position = V(a, "position"), Velocity = V(a, "velocity"), Mass = D(a, "mass"), Previous = previous, MaxSearchEvaluations = OIValue(a, "maxSearchEvaluations") };
        }
        private static PlannerResult ParseReference(Structure raw)
        {
            Lexicon d = raw as Lexicon; if (d == null) throw new KOSException("Argument 'reference' must be a Lexicon"); ListValue list = Required(d, "trajectory") as ListValue; if (list == null) throw new KOSException("reference.trajectory must be a List");
            PlannerResult r = new PlannerResult { Ok = B(d, "ok"), Session = I(d, "session"), Epoch = D(d, "epoch"), Tf = D(d, "tf"), Te = D(d, "te"), Status = PlannerStatus.Solved, Trajectory = new System.Collections.Generic.List<TrajectoryPoint>() };
            for (int i = 0; i < list.Count; ++i) { Lexicon q = list[i] as Lexicon; if (q == null) throw new KOSException("reference trajectory elements must be Lexicons"); r.Trajectory.Add(new TrajectoryPoint { Time = D(q, "time"), Position = V(q, "position"), Velocity = V(q, "velocity"), Thrust = V(q, "thrust"), Mass = D(q, "mass"), ControlBefore = V(q, "controlBefore"), ControlAfter = V(q, "controlAfter") }); } return r;
        }
        private static Structure Required(Lexicon a, string name) { Structure v; if (!a.TryGetValue(new StringValue(name), out v)) throw new KOSException("Argument '" + name + "' is required"); return v; }
        private static double D(Lexicon a, string name) { ScalarValue s = Required(a, name) as ScalarValue; if (s == null) throw new KOSException("Argument '" + name + "' must be a Scalar"); double d = s.GetDoubleValue(); if (!Vec3.Finite(d)) throw new KOSException("Argument '" + name + "' must be finite"); return d; }
        private static int I(Lexicon a, string name) { double d = D(a, name); if (Math.Abs(d - Math.Round(d)) > 1e-9) throw new KOSException("Argument '" + name + "' must be an integer"); return Convert.ToInt32(d); }
        private static int OI(Lexicon a, string name, int fallback) { Structure ignored; return a.TryGetValue(new StringValue(name), out ignored) ? I(a, name) : fallback; }
        private static int? OIValue(Lexicon a, string name) { Structure ignored; return a.TryGetValue(new StringValue(name), out ignored) ? (int?)I(a, name) : null; }
        private static double? OD(Lexicon a, string name) { Structure ignored; return a.TryGetValue(new StringValue(name), out ignored) ? (double?)D(a, name) : null; }
        private static double ODValue(Lexicon a, string name, double fallback) { Structure ignored; return a.TryGetValue(new StringValue(name), out ignored) ? D(a, name) : fallback; }
        private static Vec3 V(Lexicon a, string name) { Vector v = Required(a, name) as Vector; if (v == null) throw new KOSException("Argument '" + name + "' must be a Vector"); return new Vec3(v.X, v.Y, v.Z); }
        private static bool B(Lexicon a, string name) { BooleanValue v = Required(a, name) as BooleanValue; if (v == null) throw new KOSException("Argument '" + name + "' must be Boolean"); return v.Value; }

        private static Lexicon ToLexicon(PlannerResult r)
        {
            Lexicon d = new Lexicon(); Add(d, "ok", r.Ok ? BooleanValue.True : BooleanValue.False); Add(d, "status", new StringValue(r.StatusText)); Add(d, "message", new StringValue(r.Message ?? "")); Add(d, "session", ScalarValue.Create(r.Session)); Add(d, "epoch", ScalarValue.Create(r.Epoch)); Add(d, "solveTime", ScalarValue.Create(r.SolveTime)); Add(d, "landingError", ScalarValue.Create(r.LandingError)); Add(d, "fuelUsed", ScalarValue.Create(r.FuelUsed)); Add(d, "searchEvaluations", ScalarValue.Create(r.SearchEvaluations));
            if (r.Ok) { Add(d, "tf", ScalarValue.Create(r.Tf)); Add(d, "te", ScalarValue.Create(r.Te)); Add(d, "K", Matrix(r.K)); ListValue trajectory = new ListValue(); foreach (TrajectoryPoint p in r.Trajectory) { Lexicon q = new Lexicon(); Add(q, "time", ScalarValue.Create(p.Time)); Add(q, "position", Vector(p.Position)); Add(q, "velocity", Vector(p.Velocity)); Add(q, "thrust", Vector(p.Thrust)); Add(q, "mass", ScalarValue.Create(p.Mass)); Add(q, "controlBefore", Vector(p.ControlBefore)); Add(q, "controlAfter", Vector(p.ControlAfter)); trajectory.Add(q); } Add(d, "trajectory", trajectory); } return d;
        }
        private static ListValue Matrix(double[,] matrix) { ListValue rows = new ListValue(); for (int i = 0; i < matrix.GetLength(0); ++i) { ListValue row = new ListValue(); for (int j = 0; j < matrix.GetLength(1); ++j) row.Add(ScalarValue.Create(matrix[i, j])); rows.Add(row); } return rows; }
        private static Vector Vector(Vec3 v) { return new Vector(v.X, v.Y, v.Z); }
        private static void Add(Lexicon d, string key, Structure value) { d.Add(new StringValue(key), value); }
        public override BooleanValue Available() { return BooleanValue.True; }
    }
}
