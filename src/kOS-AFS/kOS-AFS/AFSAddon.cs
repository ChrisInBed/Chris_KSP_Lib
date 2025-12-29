using AFS;
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;
using kOS.Safe.Exceptions;
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;

namespace kOS.AddOns.AFSAddon
{
    [kOSAddon("AFS")]
    [Safe.Utilities.KOSNomenclature("AFSAddon")]
    public class Addon : Suffixed.Addon
    {
        // Simple in-addon task registry.
        // Note: kept static so tasks remain valid across Addon instances that may be created for different CPUs.
        private static readonly ConcurrentDictionary<int, TaskRecord> Tasks = new ConcurrentDictionary<int, TaskRecord>();
        private static int NextTaskId = 0;

        private class TaskRecord
        {
            public Task WorkerTask;
            public Lexicon Result;
            public Exception Exception;
            public volatile bool IsCompleted;
        }
        
        public Addon(SharedObjects shared) : base(shared)
        {
            InitializeSuffixes();
        }

        private void InitializeSuffixes()
        {
            // Get&Set args (scalars)
            AddSuffix(new string[] { "mu" }, new SetSuffix<ScalarDoubleValue>(GetMu, SetMu, "Gravity constant of central celestral"));
            AddSuffix(new string[] { "R" }, new SetSuffix<ScalarDoubleValue>(GetR, SetR, "Planet radius"));
            AddSuffix(new string[] { "rho0" }, new SetSuffix<ScalarDoubleValue>(GetRho0, SetRho0, "Atmospheric density at reference"));
            AddSuffix(new string[] { "hs" }, new SetSuffix<ScalarDoubleValue>(GetHs, SetHs, "Scale height"));
            AddSuffix(new string[] { "mass" }, new SetSuffix<ScalarDoubleValue>(GetMass, SetMass, "Vehicle mass"));
            AddSuffix(new string[] { "area" }, new SetSuffix<ScalarDoubleValue>(GetArea, SetArea, "Reference area"));
            AddSuffix(new string[] { "bank_max" }, new SetSuffix<ScalarDoubleValue>(GetBankMax, SetBankMax, "Max bank angle"));
            AddSuffix(new string[] { "k_QEGC" }, new SetSuffix<ScalarDoubleValue>(GetK_QEGC, SetK_QEGC, "Heat flux gain constant"));
            AddSuffix(new string[] { "k_C" }, new SetSuffix<ScalarDoubleValue>(GetK_C, SetK_C, "Constraint gain constant"));
            AddSuffix(new string[] { "t_reg" }, new SetSuffix<ScalarDoubleValue>(GetTReg, SetTReg, "Regulation timescale"));
            AddSuffix(new string[] { "Qdot_max" }, new SetSuffix<ScalarDoubleValue>(GetQdotMax, SetQdotMax, "Max heat flux"));
            AddSuffix(new string[] { "acc_max" }, new SetSuffix<ScalarDoubleValue>(GetAccMax, SetAccMax, "Max acceleration"));
            AddSuffix(new string[] { "dynp_max" }, new SetSuffix<ScalarDoubleValue>(GetDynpMax, SetDynpMax, "Max dynamic pressure"));
            AddSuffix(new string[] { "L_min" }, new SetSuffix<ScalarDoubleValue>(GetLMin, SetLMin, "Minimum lift"));
            AddSuffix(new string[] { "target_energy" }, new SetSuffix<ScalarDoubleValue>(GetTargetEnergy, SetTargetEnergy, "Target energy"));
            AddSuffix(new string[] { "predict_min_step" }, new SetSuffix<ScalarDoubleValue>(GetPredictMinStep, SetPredictMinStep, "Predictor min step size"));
            AddSuffix(new string[] { "predict_max_step" }, new SetSuffix<ScalarDoubleValue>(GetPredictMaxStep, SetPredictMaxStep, "Predictor max step size"));
            AddSuffix(new string[] { "predict_tmax" }, new SetSuffix<ScalarDoubleValue>(GetPredictTMax, SetPredictTMax, "Predictor max time"));

            // Arrays (as List)
            AddSuffix(new string[] { "speedsamples" }, new SetSuffix<ListValue>(GetSpeedsamples, SetSpeedsamples, "Speed samples"));
            AddSuffix(new string[] { "Cdsamples" }, new SetSuffix<ListValue>(GetCdsamples, SetCdsamples, "Drag coefficient samples"));
            AddSuffix(new string[] { "Clsamples" }, new SetSuffix<ListValue>(GetClsamples, SetClsamples, "Lift coefficient samples"));

            // Sync operations
            AddSuffix(new string[] { "GetBankCmd" }, new OneArgsSuffix<ScalarDoubleValue, Lexicon>(GetBankCmd, "Takes y4 state and guidance parameters, output bank command"));

            // Async operations
            AddSuffix(new string[] { "AsyncSimAtmTraj" }, new OneArgsSuffix<ScalarValue, Lexicon>(StartSimAtmTraj, "Start a background atmosphere flight simulation; returns integer handle"));

            // Task management
            AddSuffix(new string[] { "CheckTask" }, new OneArgsSuffix<BooleanValue, ScalarValue>(CheckTask, "Check whether task (handle) has finished successfully"));
            AddSuffix(new string[] { "GetTaskResult" }, new OneArgsSuffix<Lexicon, ScalarValue>(GetTaskResult, "Retrieve Vector result of completed task (handle)"));
        }

        private SimAtmTrajArgs simArgs = new SimAtmTrajArgs();

        private ScalarDoubleValue GetMu() { return new ScalarDoubleValue(simArgs.mu); }
        private void SetMu(ScalarDoubleValue val) { simArgs.mu = val.GetDoubleValue(); }

        private ScalarDoubleValue GetR() { return new ScalarDoubleValue(simArgs.R); }
        private void SetR(ScalarDoubleValue val) { simArgs.R = val.GetDoubleValue(); }

        private ScalarDoubleValue GetRho0() { return new ScalarDoubleValue(simArgs.rho0); }
        private void SetRho0(ScalarDoubleValue val) { simArgs.rho0 = val.GetDoubleValue(); }

        private ScalarDoubleValue GetHs() { return new ScalarDoubleValue(simArgs.hs); }
        private void SetHs(ScalarDoubleValue val) { simArgs.hs = val.GetDoubleValue(); }

        private ScalarDoubleValue GetMass() { return new ScalarDoubleValue(simArgs.mass * 1e-3); }
        private void SetMass(ScalarDoubleValue val) { simArgs.mass = val.GetDoubleValue() * 1e3; }

        private ScalarDoubleValue GetArea() { return new ScalarDoubleValue(simArgs.area); }
        private void SetArea(ScalarDoubleValue val) { simArgs.area = val.GetDoubleValue(); }

        private ScalarDoubleValue GetBankMax() { return new ScalarDoubleValue(simArgs.bank_max /Math.PI*180); }
        private void SetBankMax(ScalarDoubleValue val) { simArgs.bank_max = val.GetDoubleValue() /180.0*Math.PI; }

        private ScalarDoubleValue GetK_QEGC() { return new ScalarDoubleValue(simArgs.k_QEGC); }
        private void SetK_QEGC(ScalarDoubleValue val) { simArgs.k_QEGC = val.GetDoubleValue(); }

        private ScalarDoubleValue GetK_C() { return new ScalarDoubleValue(simArgs.k_C); }
        private void SetK_C(ScalarDoubleValue val) { simArgs.k_C = val.GetDoubleValue(); }

        private ScalarDoubleValue GetTReg() { return new ScalarDoubleValue(simArgs.t_reg); }
        private void SetTReg(ScalarDoubleValue val) { simArgs.t_reg = val.GetDoubleValue(); }

        private ScalarDoubleValue GetQdotMax() { return new ScalarDoubleValue(simArgs.Qdot_max); }
        private void SetQdotMax(ScalarDoubleValue val) { simArgs.Qdot_max = val.GetDoubleValue(); }

        private ScalarDoubleValue GetAccMax() { return new ScalarDoubleValue(simArgs.acc_max); }
        private void SetAccMax(ScalarDoubleValue val) { simArgs.acc_max = val.GetDoubleValue(); }

        private ScalarDoubleValue GetDynpMax() { return new ScalarDoubleValue(simArgs.dynp_max); }
        private void SetDynpMax(ScalarDoubleValue val) { simArgs.dynp_max = val.GetDoubleValue(); }

        private ScalarDoubleValue GetLMin() { return new ScalarDoubleValue(simArgs.L_min); }
        private void SetLMin(ScalarDoubleValue val) { simArgs.L_min = val.GetDoubleValue(); }

        private ScalarDoubleValue GetTargetEnergy() { return new ScalarDoubleValue(simArgs.target_energy); }
        private void SetTargetEnergy(ScalarDoubleValue val) { simArgs.target_energy = val.GetDoubleValue(); }

        private ScalarDoubleValue GetPredictMinStep() { return new ScalarDoubleValue(simArgs.predict_min_step); }
        private void SetPredictMinStep(ScalarDoubleValue val) { simArgs.predict_min_step = val.GetDoubleValue(); }

        private ScalarDoubleValue GetPredictMaxStep() { return new ScalarDoubleValue(simArgs.predict_max_step); }
        private void SetPredictMaxStep(ScalarDoubleValue val) { simArgs.predict_max_step = val.GetDoubleValue(); }

        private ScalarDoubleValue GetPredictTMax() { return new ScalarDoubleValue(simArgs.predict_tmax); }
        private void SetPredictTMax(ScalarDoubleValue val) { simArgs.predict_tmax = val.GetDoubleValue(); }

        private ListValue ListFromDoubleArray(double[] arr)
        {
            var list = new ListValue();
            if (arr != null)
                foreach (var d in arr)
                    list.Add(new ScalarDoubleValue(d));
            return list;
        }
        private double[] ExtractDoubleArray(ListValue list, string name)
        {
            if (list == null) return new double[0];
            var result = new double[list.Count];
            for (int i = 0; i < list.Count; i++)
            {
                var item = list[i];
                if (!(item is ScalarValue scalar))
                    throw new KOSException($"All elements of '{name}' must be Scalar numbers");
                double d = scalar.GetDoubleValue();
                if (double.IsNaN(d) || double.IsInfinity(d))
                    throw new KOSException($"All elements of '{name}' must be finite numbers");
                result[i] = d;
            }
            return result;
        }
        private PhyState RequirePhyState(Lexicon args, string key = "y4")
        {
            double[] _y4 = RequireDoubleArrayArg(args, "y4");
            if (!(_y4.Length == 4))
                throw new KOSException($"Argument y4 must be a List of 4 numbers");
            PhyState state = new PhyState(
                _y4[0],
                _y4[1] / 180 * Math.PI,
                _y4[2],
                _y4[3] / 180 * Math.PI
            );
            return state;
        }
        private BankPlanArgs RequireBankArgs(Lexicon args)
        {
            BankPlanArgs bargs = new BankPlanArgs(
                RequireDoubleArg(args, "bank_i") / 180 * Math.PI,
                RequireDoubleArg(args, "bank_f") / 180 * Math.PI,
                RequireDoubleArg(args, "energy_i"),
                RequireDoubleArg(args, "energy_f")
            );
            return bargs;
        }
        private ListValue GetSpeedsamples() { return ListFromDoubleArray(simArgs.speedsamples); }
        private void SetSpeedsamples(ListValue val) { simArgs.speedsamples = ExtractDoubleArray(val, "speedsamples"); }

        private ListValue GetCdsamples() { return ListFromDoubleArray(simArgs.Cdsamples); }
        private void SetCdsamples(ListValue val) { simArgs.Cdsamples = ExtractDoubleArray(val, "Cdsamples"); }

        private ListValue GetClsamples() { return ListFromDoubleArray(simArgs.Clsamples); }
        private void SetClsamples(ListValue val) { simArgs.Clsamples = ExtractDoubleArray(val, "Clsamples"); }

        private ScalarDoubleValue GetBankCmd(Lexicon args)
        {
            PhyState state = RequirePhyState(args, "y4");
            BankPlanArgs bargs = RequireBankArgs(args);
            AFSCore.Context context = new AFSCore.Context();
            double bankCmd = AFSCore.GetBankCommand(state, simArgs, bargs, context) * 180 / Math.PI;
            return new ScalarDoubleValue(bankCmd);
        }

        private ScalarValue StartSimAtmTraj(Lexicon args)
        {
            int id = Interlocked.Increment(ref NextTaskId);
            TaskRecord record = new TaskRecord();
            record.Result = new Lexicon();
            if (args == null) throw new KOSException("Arguments lexicon must not be null.");

            double t;
            PhyState state;
            BankPlanArgs bargs;
            try
            {
                t = RequireDoubleArg(args, "t");
                state = RequirePhyState(args, "y4");
                bargs = RequireBankArgs(args);
            }
            catch (Exception ex)
            {
                throw new KOSException($"Argument error: {ex.Message}");
            }

            record.WorkerTask = Task.Run(() =>
            {
                try
                {
                    PredictResult simResult = AFSCore.PredictTrajectory(t, state, simArgs, bargs);

                    // Parse results
                    record.Result.Add(new StringValue("ok"), BooleanValue.True);
                    record.Result.Add(new StringValue("t"), new ScalarDoubleValue(simResult.t));
                    record.Result.Add(new StringValue("finalState"), new ListValue()
                    {
                        new ScalarDoubleValue(simResult.finalState.r),
                        new ScalarDoubleValue(simResult.finalState.theta*180/Math.PI),
                        new ScalarDoubleValue(simResult.finalState.v),
                        new ScalarDoubleValue(simResult.finalState.gamma*180/Math.PI)
                    });
                    switch (simResult.status)
                    {
                        case PredictStatus.COMPLETED:
                            record.Result.Add(new StringValue("status"), new StringValue("COMPLETED"));
                            break;
                        case PredictStatus.TIMEOUT:
                            record.Result.Add(new StringValue("status"), new StringValue("TIMEOUT"));
                            break;
                        case PredictStatus.FAILED:
                            record.Result.Add(new StringValue("status"), new StringValue("FAILED"));
                            break;
                        case PredictStatus.OVERSHOOT:
                            record.Result.Add(new StringValue("status"), new StringValue("OVERSHOOT"));
                            break;
                        default:
                            record.Result.Add(new StringValue("status"), new StringValue("UNKNOWN"));
                            break;
                    }
                    record.Result.Add(new StringValue("nsteps"), new ScalarDoubleValue(simResult.nsteps));
                    record.Result.Add(new StringValue("maxQdot"), new ScalarDoubleValue(simResult.maxQdot));
                    record.Result.Add(new StringValue("maxQdotTime"), new ScalarDoubleValue(simResult.maxQdotTime));
                    record.Result.Add(new StringValue("maxAcc"), new ScalarDoubleValue(simResult.maxAcc));
                    record.Result.Add(new StringValue("maxAccTime"), new ScalarDoubleValue(simResult.maxAccTime));
                    record.Result.Add(new StringValue("maxDynP"), new ScalarDoubleValue(simResult.maxDynP));
                    record.Result.Add(new StringValue("maxDynPTime"), new ScalarDoubleValue(simResult.maxDynPTime));
                    record.Result.Add(new StringValue("msg"), new StringValue("Simulation ended"));
                }
                catch (Exception ex)
                {
                    record.Exception = ex;
                    record.Result.Add(new StringValue("ok"), BooleanValue.False);
                    record.Result.Add(new StringValue("msg"), new StringValue(ex.Message));
                }
                finally
                {
                    record.IsCompleted = true;
                }
            });

            Tasks[id] = record;
            return ScalarValue.Create(id);
        }

        // Returns true when the task finished.
        private BooleanValue CheckTask(ScalarValue handle)
        {
            int id;
            try
            {
                id = Convert.ToInt32(handle);
            }
            catch
            {
                throw new KOSException("Invalid task handle type");
            }

            if (!Tasks.TryGetValue(id, out var record))
                throw new KOSException($"No task with handle {id} exists");

            return record.IsCompleted ? BooleanValue.True : BooleanValue.False;
        }

        // Returns the Vector result for a finished task.
        private Lexicon GetTaskResult(ScalarValue handle)
        {
            int id;
            try
            {
                id = Convert.ToInt32(handle);
            }
            catch
            {
                throw new KOSException("Invalid task handle type");
            }

            if (!Tasks.TryGetValue(id, out var record))
                throw new KOSException($"No task with handle {id} exists");

            if (!record.IsCompleted)
                throw new KOSException($"Task {id} has not completed yet");

            //if (record.Exception != null)
            //    throw new KOSException($"Task {id} failed: {record.Exception.Message}");

            // Optionally remove completed tasks to free memory:
            Tasks.TryRemove(id, out _);

            // Return the computed result
            return record.Result;
        }

        public override BooleanValue Available()
        {
            return true;
        }

        // Helper: fetch a required ScalarValue from lexicon and convert to double.
        private static double RequireDoubleArg(Lexicon args, string name)
        {
            if (!args.TryGetValue(new StringValue(name), out var val))
                throw new KOSException($"Argument '{name}' is required");
            if (!(val is ScalarValue scalar))
                throw new KOSException($"Argument '{name}' must be a number (Scalar)");
            double d = scalar.GetDoubleValue();
            if (double.IsNaN(d) || double.IsInfinity(d))
                throw new KOSException($"Argument '{name}' must be a finite number");
            return d;
        }

        // Helper: fetch a required List of ScalarValue from lexicon and convert to double[].
        private static double[] RequireDoubleArrayArg(Lexicon args, string name)
        {
            if (!args.TryGetValue(new StringValue(name), out var val))
                throw new KOSException($"Argument '{name}' is required");
            if (!(val is ListValue list))
                throw new KOSException($"Argument '{name}' must be a List of numbers");

            var result = new List<double>();
            foreach (var item in list)
            {
                if (!(item is ScalarValue scalar))
                    throw new KOSException($"All elements of '{name}' must be numbers (Scalar)");
                double d = scalar.GetDoubleValue();
                if (double.IsNaN(d) || double.IsInfinity(d))
                    throw new KOSException($"All elements of '{name}' must be finite numbers");
                result.Add(d);
            }

            if (result.Count == 0)
                throw new KOSException($"Argument '{name}' must not be empty");

            return result.ToArray();
        }
    }

}