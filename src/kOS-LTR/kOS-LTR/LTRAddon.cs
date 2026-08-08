using FerramAerospaceResearch;
using KSP.Localization;
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;
using kOS.Safe.Exceptions;
using kOS.Suffixed;
using LTR;
using System;
using System.Collections.Concurrent;
using System.Threading;
using System.Threading.Tasks;
using Unity.Mathematics;
using UnityEngine;

namespace kOS.AddOns.LTRAddon
{
    [kOSAddon("LTR")]
    [kOS.Safe.Utilities.KOSNomenclature("LTRAddon")]
    public class Addon : Suffixed.Addon
    {
        private static readonly ConcurrentDictionary<int, TaskRecord> Tasks
            = new ConcurrentDictionary<int, TaskRecord>();
        private static int NextTaskId;

        private class TaskRecord
        {
            public Task WorkerTask;
            public Lexicon Result;
            public Exception Exception;
            public volatile bool IsCompleted;
        }

        private readonly SimAtmTrajArgs simArgs = new SimAtmTrajArgs();

        public Addon(SharedObjects shared) : base(shared)
        {
            InitializeSuffixes();
        }

        private void InitializeSuffixes()
        {
            // Get-only values: kept in the same order as kOS-AFS.
            AddSuffix(new[] { "AOA" }, new Suffix<ScalarDoubleValue>(GetAOA, "Angle of attack of current vessel"));
            AddSuffix(new[] { "AOS" }, new Suffix<ScalarDoubleValue>(GetAOS, "Sideslip of current vessel"));
            AddSuffix(new[] { "BANK" }, new Suffix<ScalarDoubleValue>(GetBank, "Bank of current vessel"));
            AddSuffix(new[] { "REFAREA" }, new Suffix<ScalarDoubleValue>(GetRefArea, "Reference area of current vessel"));
            AddSuffix(new[] { "CD" }, new Suffix<ScalarDoubleValue>(GetCd, "Current drag coefficient"));
            AddSuffix(new[] { "CL" }, new Suffix<ScalarDoubleValue>(GetCl, "Current lift coefficient"));
            AddSuffix(new[] { "HeatFlux" }, new Suffix<ScalarDoubleValue>(GetHeatFlux, "Current heat flux"));
            AddSuffix(new[] { "GeeForce" }, new Suffix<ScalarDoubleValue>(GetGeeForce, "Current acceleration"));
            AddSuffix(new[] { "DynamicPressure" }, new Suffix<ScalarDoubleValue>(GetDynamicPressure, "Current dynamic pressure"));
            AddSuffix(new[] { "Density" }, new Suffix<ScalarDoubleValue>(GetDensity, "Current air density"));
            AddSuffix(new[] { "Language" }, new Suffix<StringValue>(GetLanguage, "Game language"));

            // Celestial-body parameters.
            AddSuffix(new[] { "mu" }, new SetSuffix<ScalarDoubleValue>(GetMu, SetMu, "Gravity parameter"));
            AddSuffix(new[] { "R" }, new SetSuffix<ScalarDoubleValue>(GetR, SetR, "Body radius"));
            AddSuffix(new[] { "molar_mass" }, new SetSuffix<ScalarDoubleValue>(GetMolarMass, SetMolarMass, "Atmospheric molar mass"));
            AddSuffix(new[] { "atm_height" }, new SetSuffix<ScalarDoubleValue>(GetAtmHeight, SetAtmHeight, "Atmosphere height"));
            AddSuffix(new[] { "bodySpin" }, new SetSuffix<Vector>(GetBodySpin, SetBodySpin, "Body angular-velocity vector"));
            AddSuffix(new[] { "AtmAltSamples" }, new SetSuffix<ListValue>(GetAtmAltSamples, SetAtmAltSamples, "Atmosphere altitude samples"));
            AddSuffix(new[] { "AtmLogDensitySamples" }, new SetSuffix<ListValue>(GetAtmLogDensitySamples, SetAtmLogDensitySamples, "Atmosphere log-density samples"));
            AddSuffix(new[] { "AtmTempSamples" }, new SetSuffix<ListValue>(GetAtmTempSamples, SetAtmTempSamples, "Atmosphere temperature samples"));

            // Vessel and aerodynamic-model parameters.
            AddSuffix(new[] { "mass" }, new SetSuffix<ScalarDoubleValue>(GetMass, SetMass, "Vehicle mass in metric tons"));
            AddSuffix(new[] { "area" }, new SetSuffix<ScalarDoubleValue>(GetArea, SetArea, "Reference area"));
            AddSuffix(new[] { "rotation" }, new SetSuffix<Direction>(GetRotation, SetRotation, "Vehicle reference rotation"));
            AddSuffix(new[] { "AOAReversal" }, new SetSuffix<BooleanValue>(GetAOAReversal, SetAOAReversal, "AOA sign reversal"));
            AddSuffix(new[] { "CtrlSpeedSamples" }, new SetSuffix<ListValue>(GetCtrlSpeedSamples, SetCtrlSpeedSamples, "Speed samples for AOA profile"));
            AddSuffix(new[] { "CtrlAOASamples" }, new SetSuffix<ListValue>(GetCtrlAOASamples, SetCtrlAOASamples, "AOA samples in degrees"));
            AddSuffix(new[] { "AeroSpeedSamples" }, new SetSuffix<ListValue>(GetAeroSpeedSamples, SetAeroSpeedSamples, "Aerodynamic speed samples"));
            AddSuffix(new[] { "AeroLogDensitySamples" }, new SetSuffix<ListValue>(GetAeroLogDensitySamples, SetAeroLogDensitySamples, "Aerodynamic log-density samples"));
            AddSuffix(new[] { "SetAeroDsFromAlt" }, new OneArgsSuffix<ListValue>(SetAeroDsFromAlt, "Set aerodynamic density samples from altitudes"));
            AddSuffix(new[] { "AeroCdSamples" }, new SetSuffix<ListValue>(GetAeroCdSamples, SetAeroCdSamples, "Drag-coefficient matrix"));
            AddSuffix(new[] { "AeroClSamples" }, new SetSuffix<ListValue>(GetAeroClSamples, SetAeroClSamples, "Lift-coefficient matrix"));

            // Target and predictor parameters.
            AddSuffix(new[] { "target_altitude" }, new SetSuffix<ScalarDoubleValue>(GetTargetAltitude, SetTargetAltitude, "Impact altitude above sea level"));
            AddSuffix(new[] { "RTarget" }, new SetSuffix<Vector>(GetRTarget, SetRTarget, "Body-centered target position"));
            AddSuffix(new[] { "predict_min_step" }, new SetSuffix<ScalarDoubleValue>(GetPredictMinStep, SetPredictMinStep, "Predictor minimum step"));
            AddSuffix(new[] { "predict_max_step" }, new SetSuffix<ScalarDoubleValue>(GetPredictMaxStep, SetPredictMaxStep, "Predictor maximum step"));
            AddSuffix(new[] { "predict_tmax" }, new SetSuffix<ScalarDoubleValue>(GetPredictTMax, SetPredictTMax, "Predictor maximum duration"));

            // Synchronous operations.
            AddSuffix(new[] { "GetAOACmd" }, new OneArgsSuffix<Lexicon, Structure>(GetAOACmd, "Interpolate the speed-AOA profile from a speed or state"));
            AddSuffix(new[] { "GetState" }, new NoArgsSuffix<Lexicon>(GetState, "Get the current body-centered state"));
            AddSuffix(new[] { "GetFARAeroCoefs" }, new OneArgsSuffix<Lexicon, Lexicon>(GetFARAeroCoefs, "Sample FAR aerodynamic coefficients"));
            AddSuffix(new[] { "GetFARAeroCoefsEst" }, new OneArgsSuffix<Lexicon, Lexicon>(GetFARAeroCoefsEst, "Interpolate aerodynamic coefficients"));
            AddSuffix(new[] { "GetDensityAt" }, new OneArgsSuffix<ScalarValue, ScalarValue>(GetDensityAt, "Get stock atmospheric density"));
            AddSuffix(new[] { "GetDensityEst" }, new OneArgsSuffix<ScalarValue, ScalarValue>(GetDensityEst, "Interpolate atmospheric density"));
            AddSuffix(new[] { "GetAltEst" }, new OneArgsSuffix<ScalarValue, ScalarValue>(GetAltEst, "Estimate altitude from density"));
            AddSuffix(new[] { "InitAtmModel" }, new NoArgsVoidSuffix(InitAtmModel, "Initialize the atmospheric model"));
            AddSuffix(new[] { "DirectionToAngleAxis" }, new OneArgsSuffix<Vector, Direction>(DirectionToAngleAxis, "Convert a direction to an angle-axis vector"));

            // Asynchronous simulation and task management.
            AddSuffix(new[] { "AsyncSimAtmTraj" }, new OneArgsSuffix<ScalarValue, Lexicon>(StartSimAtmTraj, "Start an atmospheric trajectory prediction"));
            AddSuffix(new[] { "CheckTask" }, new OneArgsSuffix<BooleanValue, ScalarValue>(CheckTask, "Check whether a prediction has finished"));
            AddSuffix(new[] { "GetTaskResult" }, new OneArgsSuffix<Lexicon, ScalarValue>(GetTaskResult, "Retrieve and remove a prediction result"));
        }

        private ScalarDoubleValue GetAOA()
        {
            double value = LTRCore.GetFARAOA(shared.Vessel, shared.Vessel.srf_velocity, simArgs.rotation, simArgs.AOAReversal);
            return new ScalarDoubleValue(LTRCore.GetSafeDouble(value * 180 / Math.PI));
        }

        private ScalarDoubleValue GetAOS()
        {
            double value = LTRCore.GetFARAOS(shared.Vessel, shared.Vessel.srf_velocity, simArgs.rotation);
            return new ScalarDoubleValue(LTRCore.GetSafeDouble(value * 180 / Math.PI));
        }

        private ScalarDoubleValue GetBank()
        {
            double value = LTRCore.GetFARBank(shared.Vessel, simArgs.rotation);
            return new ScalarDoubleValue(LTRCore.GetSafeDouble(value * 180 / Math.PI));
        }

        private ScalarDoubleValue GetRefArea() { return new ScalarDoubleValue(LTRCore.GetSafeDouble(FARAPI.VesselRefArea(shared.Vessel))); }
        private ScalarDoubleValue GetCd() { return new ScalarDoubleValue(LTRCore.GetSafeDouble(FARAPI.VesselDragCoeff(shared.Vessel))); }
        private ScalarDoubleValue GetCl() { return new ScalarDoubleValue(LTRCore.GetSafeDouble(FARAPI.VesselLiftCoeff(shared.Vessel))); }
        private ScalarDoubleValue GetHeatFlux()
        {
            double value = 9.4369e-5 * Math.Pow(shared.Vessel.srf_velocity.magnitude, 3.15) * Math.Sqrt(shared.Vessel.atmDensity);
            return new ScalarDoubleValue(LTRCore.GetSafeDouble(value));
        }
        private ScalarDoubleValue GetGeeForce() { return new ScalarDoubleValue(LTRCore.GetSafeDouble(shared.Vessel.geeForce)); }
        private ScalarDoubleValue GetDynamicPressure() { return new ScalarDoubleValue(LTRCore.GetSafeDouble(shared.Vessel.dynamicPressurekPa * 1000)); }
        private ScalarDoubleValue GetDensity() { return new ScalarDoubleValue(LTRCore.GetSafeDouble(shared.Vessel.atmDensity)); }
        private StringValue GetLanguage() { return new StringValue(Localizer.CurrentLanguage); }

        private ScalarDoubleValue GetMu() { return new ScalarDoubleValue(simArgs.mu); }
        private void SetMu(ScalarDoubleValue value) { simArgs.mu = value.GetDoubleValue(); }
        private ScalarDoubleValue GetR() { return new ScalarDoubleValue(simArgs.R); }
        private void SetR(ScalarDoubleValue value) { simArgs.R = value.GetDoubleValue(); }
        private ScalarDoubleValue GetMolarMass() { return new ScalarDoubleValue(simArgs.molarMass); }
        private void SetMolarMass(ScalarDoubleValue value) { simArgs.molarMass = value.GetDoubleValue(); }
        private ScalarDoubleValue GetAtmHeight() { return new ScalarDoubleValue(simArgs.atmHeight); }
        private void SetAtmHeight(ScalarDoubleValue value) { simArgs.atmHeight = value.GetDoubleValue(); }
        private Vector GetBodySpin() { return Double3ToVector(simArgs.bodySpin); }
        private void SetBodySpin(Vector value) { simArgs.bodySpin = VectorToDouble3(value); }

        private ScalarDoubleValue GetMass() { return new ScalarDoubleValue(simArgs.mass * 1e-3); }
        private void SetMass(ScalarDoubleValue value) { simArgs.mass = value.GetDoubleValue() * 1e3; }
        private ScalarDoubleValue GetArea() { return new ScalarDoubleValue(simArgs.area); }
        private void SetArea(ScalarDoubleValue value) { simArgs.area = value.GetDoubleValue(); }
        private Direction GetRotation() { return new Direction(simArgs.rotation); }
        private void SetRotation(Direction value) { simArgs.rotation = value.Rotation; }
        private BooleanValue GetAOAReversal() { return simArgs.AOAReversal ? BooleanValue.True : BooleanValue.False; }
        private void SetAOAReversal(BooleanValue value) { simArgs.AOAReversal = value.Value; }

        private ScalarDoubleValue GetTargetAltitude() { return new ScalarDoubleValue(simArgs.targetAltitude); }
        private void SetTargetAltitude(ScalarDoubleValue value) { simArgs.targetAltitude = value.GetDoubleValue(); }
        private Vector GetRTarget() { return Double3ToVector(simArgs.RTarget); }
        private void SetRTarget(Vector value) { simArgs.RTarget = VectorToDouble3(value); }
        private ScalarDoubleValue GetPredictMinStep() { return new ScalarDoubleValue(simArgs.predictMinStep); }
        private void SetPredictMinStep(ScalarDoubleValue value) { simArgs.predictMinStep = value.GetDoubleValue(); }
        private ScalarDoubleValue GetPredictMaxStep() { return new ScalarDoubleValue(simArgs.predictMaxStep); }
        private void SetPredictMaxStep(ScalarDoubleValue value) { simArgs.predictMaxStep = value.GetDoubleValue(); }
        private ScalarDoubleValue GetPredictTMax() { return new ScalarDoubleValue(simArgs.predictTMax); }
        private void SetPredictTMax(ScalarDoubleValue value) { simArgs.predictTMax = value.GetDoubleValue(); }

        private ListValue GetAtmAltSamples() { return ListFromDoubleArray(simArgs.AtmAltSamples); }
        private void SetAtmAltSamples(ListValue value) { simArgs.AtmAltSamples = ExtractDoubleArray(value, "AtmAltSamples"); }
        private ListValue GetAtmLogDensitySamples() { return ListFromDoubleArray(simArgs.AtmLogDensitySamples); }
        private void SetAtmLogDensitySamples(ListValue value) { simArgs.AtmLogDensitySamples = ExtractDoubleArray(value, "AtmLogDensitySamples"); }
        private ListValue GetAtmTempSamples() { return ListFromDoubleArray(simArgs.AtmTempSamples); }
        private void SetAtmTempSamples(ListValue value) { simArgs.AtmTempSamples = ExtractDoubleArray(value, "AtmTempSamples"); }
        private ListValue GetCtrlSpeedSamples() { return ListFromDoubleArray(simArgs.CtrlSpeedSamples); }
        private void SetCtrlSpeedSamples(ListValue value) { simArgs.CtrlSpeedSamples = ExtractDoubleArray(value, "CtrlSpeedSamples"); }
        private ListValue GetAeroSpeedSamples() { return ListFromDoubleArray(simArgs.AeroSpeedSamples); }
        private void SetAeroSpeedSamples(ListValue value) { simArgs.AeroSpeedSamples = ExtractDoubleArray(value, "AeroSpeedSamples"); }
        private ListValue GetAeroLogDensitySamples() { return ListFromDoubleArray(simArgs.AeroLogDensitySamples); }
        private void SetAeroLogDensitySamples(ListValue value) { simArgs.AeroLogDensitySamples = ExtractDoubleArray(value, "AeroLogDensitySamples"); }
        private ListValue GetAeroCdSamples() { return ListFromDoubleArray2D(simArgs.AeroCdSamples); }
        private void SetAeroCdSamples(ListValue value) { simArgs.AeroCdSamples = ExtractDoubleArray2D(value, "AeroCdSamples"); }
        private ListValue GetAeroClSamples() { return ListFromDoubleArray2D(simArgs.AeroClSamples); }
        private void SetAeroClSamples(ListValue value) { simArgs.AeroClSamples = ExtractDoubleArray2D(value, "AeroClSamples"); }

        private ListValue GetCtrlAOASamples()
        {
            var result = new ListValue();
            foreach (double aoa in simArgs.CtrlAOASamples)
                result.Add(new ScalarDoubleValue(aoa * 180 / Math.PI));
            return result;
        }

        private void SetCtrlAOASamples(ListValue value)
        {
            double[] result = ExtractDoubleArray(value, "CtrlAOASamples");
            for (int i = 0; i < result.Length; ++i)
                result[i] *= Math.PI / 180;
            simArgs.CtrlAOASamples = result;
        }

        private void SetAeroDsFromAlt(ListValue value)
        {
            double[] altitudes = ExtractDoubleArray(value, "aerodynamic altitude samples");
            var densities = new double[altitudes.Length];
            for (int i = 0; i < altitudes.Length; ++i)
                densities[i] = Math.Log(Math.Max(double.Epsilon, LTRCore.GetDensityAt(shared.Vessel, altitudes[i])));
            simArgs.AeroLogDensitySamples = densities;
        }

        private Lexicon GetAOACmd(Structure argument)
        {
            PhyState state;
            if (argument is ScalarValue speed)
            {
                state = new PhyState(double3.zero, new double3(speed.GetDoubleValue(), 0, 0));
            }
            else if (argument is Lexicon args)
            {
                state = RequirePhyState(args);
            }
            else
            {
                throw new KOSException("GetAOACmd expects a speed or a state lexicon");
            }
            double command = LTRCore.GetAOACommand(state, simArgs);
            var result = new Lexicon();
            result.Add(new StringValue("AOA"), new ScalarDoubleValue(command * 180 / Math.PI));
            return result;
        }

        private Lexicon GetState()
        {
            PhyState state = LTRCore.GetPhyState(shared.Vessel);
            var result = new Lexicon();
            result.Add(new StringValue("vecR"), Double3ToVector(state.vecR));
            result.Add(new StringValue("vecV"), Double3ToVector(state.vecV));
            return result;
        }

        private Lexicon GetFARAeroCoefs(Lexicon args)
        {
            double altitude = RequireDoubleArg(args, "altitude");
            double speed = RequireDoubleArg(args, "speed");
            double aoa = RequireDoubleArg(args, "AOA") * Math.PI / 180;
            LTRCore.GetFARAeroCoefs(shared.Vessel, altitude, aoa, speed, out double cd, out double cl, simArgs.rotation, simArgs.AOAReversal);
            return AeroLexicon(cd, cl);
        }

        private Lexicon GetFARAeroCoefsEst(Lexicon args)
        {
            double altitude = RequireDoubleArg(args, "altitude");
            double speed = RequireDoubleArg(args, "speed");
            double logDensity = LTRCore.GetLogDensityEst(simArgs, altitude);
            LTRCore.GetAeroCoefficients(simArgs, speed, logDensity, out double cd, out double cl);
            return AeroLexicon(cd, cl);
        }

        private static Lexicon AeroLexicon(double cd, double cl)
        {
            var result = new Lexicon();
            result.Add(new StringValue("Cd"), new ScalarDoubleValue(LTRCore.GetSafeDouble(cd)));
            result.Add(new StringValue("Cl"), new ScalarDoubleValue(LTRCore.GetSafeDouble(cl)));
            return result;
        }

        private ScalarValue GetDensityAt(ScalarValue altitude)
        {
            return ScalarValue.Create(LTRCore.GetSafeDouble(LTRCore.GetDensityAt(shared.Vessel, altitude.GetDoubleValue())));
        }
        private ScalarValue GetDensityEst(ScalarValue altitude)
        {
            return ScalarValue.Create(LTRCore.GetSafeDouble(LTRCore.GetDensityEst(simArgs, altitude.GetDoubleValue())));
        }
        private ScalarValue GetAltEst(ScalarValue density)
        {
            return ScalarValue.Create(LTRCore.GetSafeDouble(LTRCore.GetHeightEst(simArgs, density.GetDoubleValue())));
        }
        private void InitAtmModel() { LTRCore.InitAtmModel(shared.Vessel, simArgs); }

        private Vector DirectionToAngleAxis(Direction direction)
        {
            direction.Rotation.ToAngleAxis(out float angle, out Vector3 axis);
            if (angle > 180)
            {
                angle = 360 - angle;
                axis = -axis;
            }
            Vector result = new Vector(axis * (angle * Mathf.Deg2Rad));
            return IsFinite(result.X) && IsFinite(result.Y) && IsFinite(result.Z) ? result : Vector.Zero;
        }

        private ScalarValue StartSimAtmTraj(Lexicon args)
        {
            if (args == null) throw new KOSException("Arguments lexicon must not be null.");
            double t;
            PhyState state;
            try
            {
                t = RequireDoubleArg(args, "t");
                state = RequirePhyState(args);
            }
            catch (Exception exception)
            {
                throw new KOSException("Argument error: " + exception.Message);
            }

            int id = Interlocked.Increment(ref NextTaskId);
            var record = new TaskRecord { Result = new Lexicon() };
            SimAtmTrajArgs argsSnapshot = simArgs.Clone();
            record.WorkerTask = Task.Run(() =>
            {
                try
                {
                    PredictResult prediction = LTRCore.PredictTrajectory(t, state, argsSnapshot);
                    record.Result.Add(new StringValue("ok"), BooleanValue.True);
                    record.Result.Add(new StringValue("t"), new ScalarDoubleValue(prediction.t));
                    record.Result.Add(new StringValue("finalVecR"), Double3ToVector(prediction.finalState.vecR));
                    record.Result.Add(new StringValue("finalVecV"), Double3ToVector(prediction.finalState.vecV));
                    record.Result.Add(new StringValue("status"), new StringValue(prediction.status.ToString()));
                    record.Result.Add(new StringValue("nsteps"), new ScalarDoubleValue(prediction.nsteps));
                    record.Result.Add(new StringValue("msg"), new StringValue("Simulation ended"));
                }
                catch (Exception exception)
                {
                    record.Exception = exception;
                    record.Result.Add(new StringValue("ok"), BooleanValue.False);
                    record.Result.Add(new StringValue("status"), new StringValue("FAILED"));
                    record.Result.Add(new StringValue("msg"), new StringValue(exception.Message));
                }
                finally
                {
                    record.IsCompleted = true;
                }
            });
            Tasks[id] = record;
            return ScalarValue.Create(id);
        }

        private BooleanValue CheckTask(ScalarValue handle)
        {
            int id = HandleToInt(handle);
            if (!Tasks.TryGetValue(id, out TaskRecord record))
                throw new KOSException("No task with handle " + id + " exists");
            return record.IsCompleted ? BooleanValue.True : BooleanValue.False;
        }

        private Lexicon GetTaskResult(ScalarValue handle)
        {
            int id = HandleToInt(handle);
            if (!Tasks.TryGetValue(id, out TaskRecord record))
                throw new KOSException("No task with handle " + id + " exists");
            if (!record.IsCompleted)
                throw new KOSException("Task " + id + " has not completed yet");
            Tasks.TryRemove(id, out _);
            return record.Result;
        }

        private static int HandleToInt(ScalarValue handle)
        {
            try { return Convert.ToInt32(handle); }
            catch { throw new KOSException("Invalid task handle type"); }
        }

        public override BooleanValue Available() { return BooleanValue.True; }

        private PhyState RequirePhyState(Lexicon args)
        {
            return new PhyState(RequiredVectorArg(args, "vecR"), RequiredVectorArg(args, "vecV"));
        }

        private static double RequireDoubleArg(Lexicon args, string name)
        {
            if (!args.TryGetValue(new StringValue(name), out Structure value))
                throw new KOSException("Argument '" + name + "' is required");
            if (!(value is ScalarValue scalar))
                throw new KOSException("Argument '" + name + "' must be a number");
            double result = scalar.GetDoubleValue();
            if (!IsFinite(result)) throw new KOSException("Argument '" + name + "' must be finite");
            return result;
        }

        private static double3 RequiredVectorArg(Lexicon args, string name)
        {
            if (!args.TryGetValue(new StringValue(name), out Structure value))
                throw new KOSException("Argument '" + name + "' is required");
            if (!(value is Vector vector))
                throw new KOSException("Argument '" + name + "' must be a Vector");
            return VectorToDouble3(vector);
        }

        private static ListValue ListFromDoubleArray(double[] values)
        {
            var result = new ListValue();
            if (values != null)
                foreach (double value in values) result.Add(new ScalarDoubleValue(value));
            return result;
        }

        private static double[] ExtractDoubleArray(ListValue list, string name)
        {
            if (list == null) return new double[0];
            var result = new double[list.Count];
            for (int i = 0; i < list.Count; ++i)
            {
                if (!(list[i] is ScalarValue scalar))
                    throw new KOSException("All elements of '" + name + "' must be numbers");
                result[i] = scalar.GetDoubleValue();
                if (!IsFinite(result[i]))
                    throw new KOSException("All elements of '" + name + "' must be finite");
            }
            return result;
        }

        private static ListValue ListFromDoubleArray2D(double[,] values)
        {
            var result = new ListValue();
            if (values == null) return result;
            for (int i = 0; i < values.GetLength(0); ++i)
            {
                var row = new ListValue();
                for (int j = 0; j < values.GetLength(1); ++j)
                    row.Add(new ScalarDoubleValue(values[i, j]));
                result.Add(row);
            }
            return result;
        }

        private static double[,] ExtractDoubleArray2D(ListValue list, string name)
        {
            if (list == null || list.Count == 0) return null;
            if (!(list[0] is ListValue firstRow))
                throw new KOSException("All elements of '" + name + "' must be lists");
            var result = new double[list.Count, firstRow.Count];
            for (int i = 0; i < list.Count; ++i)
            {
                if (!(list[i] is ListValue row) || row.Count != firstRow.Count)
                    throw new KOSException("All rows of '" + name + "' must have the same length");
                for (int j = 0; j < row.Count; ++j)
                {
                    if (!(row[j] is ScalarValue scalar))
                        throw new KOSException("All elements of '" + name + "' must be numbers");
                    result[i, j] = scalar.GetDoubleValue();
                    if (!IsFinite(result[i, j]))
                        throw new KOSException("All elements of '" + name + "' must be finite");
                }
            }
            return result;
        }

        private static Vector Double3ToVector(double3 value)
        {
            return new Vector(
                IsFinite(value.x) ? value.x : 0,
                IsFinite(value.y) ? value.y : 0,
                IsFinite(value.z) ? value.z : 0);
        }

        private static double3 VectorToDouble3(Vector value)
        {
            return new double3(value.X, value.Y, value.Z);
        }

        private static bool IsFinite(double value)
        {
            return !double.IsNaN(value) && !double.IsInfinity(value);
        }
    }
}
