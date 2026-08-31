using System;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Threading;

namespace KOSGFOLD.Core
{
    public sealed class Planner
    {
        private readonly ConcurrentDictionary<int, PlannerSession> sessions = new ConcurrentDictionary<int, PlannerSession>(); private int nextSession;
        public PlannerResult Initialize(InitializeRequest request)
        {
            Stopwatch watch = Stopwatch.StartNew(); try { InputValidation.Validate(request); FrameModel frame = new FrameModel(request.PitCenter, request.BodySpin, request.Mu); int id = Interlocked.Increment(ref nextSession); PlannerSession session = new PlannerSession(id, request, frame); PlannerResult result = SearchInitial(session, request.StateTime, request.Position, request.Velocity, request.Mass, request.MaxSearchEvaluations, watch); result.SolveTime = watch.Elapsed.TotalSeconds; result.SearchEvaluations = Math.Max(result.SearchEvaluations, 0); if (result.Ok) { result.Session = id; result.K = Dense.Copy(session.Gain); session.LatestEpoch = request.StateTime; session.LandingEpoch = result.Epoch + result.Tf; session.EntryEpoch = result.Epoch + result.Te; session.EventsFrozen = true; sessions[id] = session; } else result.Session = 0; return result; }
            catch (ArgumentException) { throw; } catch (Exception ex) { PlannerResult r = PlannerResult.Failure(PlannerStatus.NumericalFailure, ex.Message, request == null ? 0 : request.StateTime); r.SolveTime = watch.Elapsed.TotalSeconds; return r; }
        }
        public PlannerResult Update(UpdateRequest request)
        {
            Stopwatch watch = Stopwatch.StartNew(); InputValidation.ValidateUpdate(request); PlannerSession session; if (!sessions.TryGetValue(request.Session, out session)) throw new ArgumentException("Unknown planner session " + request.Session); if (request.Previous.Session != request.Session) throw new ArgumentException("previous result belongs to another session");
            lock (session.Gate) { if (session.Active) throw new InvalidOperationException("A solve is already active for this session"); if (Math.Abs(request.Previous.Epoch - session.LatestEpoch) > 1e-6) throw new ArgumentException("previous result is stale"); if (request.StateTime <= session.LatestEpoch) throw new ArgumentException("stateTime must advance beyond the latest successful epoch"); session.Active = true; }
            try { PlannerResult r = SolveFixedUpdate(session, request); r.SolveTime = watch.Elapsed.TotalSeconds; r.Session = session.Id; if (r.Ok) { r.K = Dense.Copy(session.Gain); lock (session.Gate) session.LatestEpoch = request.StateTime; } return r; }
            finally { lock (session.Gate) session.Active = false; }
        }
        public ReferenceState GetRefState(PlannerResult reference, double time)
        {
            if (reference == null || !reference.Ok) throw new ArgumentException("reference must be a successful planner result"); PlannerSession session; if (!sessions.TryGetValue(reference.Session, out session)) throw new ArgumentException("reference belongs to an unknown planner session"); return LqrTracker.Sample(session.Frame, reference, time);
        }
        private PlannerResult SearchInitial(PlannerSession session, double epoch, Vec3 position, Vec3 velocity, double mass, int budget, Stopwatch watch)
        {
            if (mass <= session.DryMass) return PlannerResult.Failure(PlannerStatus.Infeasible, "No usable fuel remains", epoch); Vec3 p0 = session.Frame.ToLocalPosition(position), pf = new Vec3(0, -session.Config.PitDepth, 0); double vmax = Math.Max(session.Config.DescentMaxSpeed, session.Config.EntryMaxSpeed); double derivedMin = Math.Max(0.5, (p0 - pf).Norm / vmax); double tfMin = session.Config.TfMin ?? derivedMin; double maxBurn = MaximumBurnDuration(session, epoch, mass); double tfMax = Math.Min(session.Config.TfMax ?? maxBurn, maxBurn); if (!(tfMax > tfMin)) return PlannerResult.Failure(PlannerStatus.Infeasible, "No valid flight-time interval remains", epoch);
            double tc = session.SwitchEpoch - epoch; bool pit = session.Config.PitDepth > 0;
            Func<double, double, PlannerResult> solve = delegate(double tf, double ratio) { double te = pit ? ratio * tf : tf; return SolveCandidate(session, epoch, position, velocity, mass, tf, te, tc, false); };
            SearchOutcome outcome = TimeSearch.Cold(tfMin, tfMax, pit, budget, watch, solve);
            if (outcome.Best != null) { outcome.Best.SearchEvaluations = outcome.Evaluations; if (outcome.Deadline) outcome.Best.Message += "; search stopped at soft deadline"; return outcome.Best; }
            PlannerStatus status = outcome.Deadline ? PlannerStatus.TimeBudgetExceeded : outcome.LastStatus; PlannerResult fail = PlannerResult.Failure(status, outcome.Deadline ? "No validated candidate before soft deadline" : outcome.LastMessage, epoch, outcome.Evaluations); return fail;
        }
        private PlannerResult SolveFixedUpdate(PlannerSession session, UpdateRequest request)
        {
            double epoch = request.StateTime; if (!session.EventsFrozen) return PlannerResult.Failure(PlannerStatus.NumericalFailure, "Session event epochs were not initialized", epoch);
            if (request.Mass <= session.DryMass) return PlannerResult.Failure(PlannerStatus.Infeasible, "No usable fuel remains", epoch);
            double tolerance = 1e-8 * Math.Max(1, Math.Max(Math.Abs(request.Previous.Tf), Math.Abs(request.Previous.Te)));
            double previousLanding = request.Previous.Epoch + request.Previous.Tf;
            if (Math.Abs(previousLanding - session.LandingEpoch) > tolerance) throw new ArgumentException("previous result does not preserve the session landing epoch");
            bool pit = session.Config.PitDepth > 0;
            if (pit && request.Previous.Te > 0)
            {
                double previousEntry = request.Previous.Epoch + request.Previous.Te;
                if (Math.Abs(previousEntry - session.EntryEpoch) > tolerance) throw new ArgumentException("previous result does not preserve the session entry epoch");
            }
            double tf = session.LandingEpoch - epoch;
            if (!(tf > 1e-9)) return PlannerResult.Failure(PlannerStatus.Infeasible, "The frozen landing epoch has passed", epoch);
            bool entryOnly = pit && epoch >= session.EntryEpoch - tolerance;
            double te = pit ? (entryOnly ? 0 : session.EntryEpoch - epoch) : tf;
            if (pit && !entryOnly && (!(te > 0) || !(te < tf))) return PlannerResult.Failure(PlannerStatus.Infeasible, "Frozen pit-entry epoch is invalid for the remaining flight", epoch);
            double tc = session.SwitchEpoch - epoch;
            PlannerResult result = SolveCandidate(session, epoch, request.Position, request.Velocity, request.Mass, tf, te, tc, entryOnly);
            result.SearchEvaluations = 1;
            return result;
        }
        private PlannerResult SolveCandidate(PlannerSession session, double epoch, Vec3 position, Vec3 velocity, double mass, double tf, double te, double tc, bool entryOnly)
        {
            try
            {
                Vec3 p0 = session.Frame.ToLocalPosition(position), v0 = session.Frame.ToLocalVector(velocity), pf = new Vec3(0, -session.Config.PitDepth, 0); Normalizer scale = new Normalizer(p0, pf, v0, session.Config.PitRadius, session.Config.PitDepth, session.Frame.G0, Math.Max(session.Mode1.Max, session.Mode2.Max), mass); Mesh mesh = MeshBuilder.Build(session.Config.Nodes, tf, tc, session.Config.PitDepth > 0 && !entryOnly ? (double?)te : null); CandidateSpec spec = new CandidateSpec { Session = session, Epoch = epoch, Position = position, Velocity = velocity, Mass = mass, Tf = tf, Te = te, Tc = tc, EntryOnly = entryOnly, Scale = scale, Mesh = mesh };
                ConicProblem p1 = GfoldProblemBuilder.Build(spec, false, 0); SolverOutcome first = AlglibSocpSolver.Solve(p1, null); if (!first.Success) return PlannerResult.Failure(first.Infeasible ? PlannerStatus.Infeasible : PlannerStatus.NumericalFailure, "P1: " + first.Message, epoch); double d = Math.Max(0, first.X[p1.LandingErrorIndex]) * scale.Length, dTol = Math.Max(0.001, 1e-6 * scale.Length) / scale.Length;
                ConicProblem p2 = GfoldProblemBuilder.Build(spec, true, first.X[p1.LandingErrorIndex] + dTol); SolverOutcome second = AlglibSocpSolver.Solve(p2, first.X); if (!second.Success) return PlannerResult.Failure(second.Infeasible ? PlannerStatus.Infeasible : PlannerStatus.NumericalFailure, "P2: " + second.Message, epoch); return SolutionValidator.BuildAndValidate(p2, second.X, d);
            }
            catch (Exception ex) { return PlannerResult.Failure(PlannerStatus.NumericalFailure, "Candidate error: " + ex.Message, epoch); }
        }
        private static double MaximumBurnDuration(PlannerSession s, double epoch, double mass)
        {
            double fuel = mass - s.DryMass, tc = Math.Max(0, s.SwitchEpoch - epoch); if (tc > 0) { double flow1 = s.Mode1.Alpha * s.Mode1.Min, possible = fuel / flow1; if (possible <= tc) return possible; fuel -= tc * flow1; return tc + fuel / (s.Mode2.Alpha * s.Mode2.Min); } return fuel / (s.Mode2.Alpha * s.Mode2.Min);
        }
    }
}
