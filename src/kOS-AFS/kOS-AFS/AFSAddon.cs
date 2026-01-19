using AFS;
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;
using kOS.Safe.Exceptions;
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using FerramAerospaceResearch;
using System.Linq;

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
            // Get-only args (scalars)
            AddSuffix(new string[] { "AOA" }, new Suffix<ScalarDoubleValue>(GetAOA, "Angle of attack of current vessel"));
            AddSuffix(new string[] { "AOS" }, new Suffix<ScalarDoubleValue>(GetAOS, "Sideslip of current vessel"));
            AddSuffix(new string[] { "REFAREA" }, new Suffix<ScalarDoubleValue>(GetRefArea, "reference area of current vessel"));
            AddSuffix(new string[] { "CD" }, new Suffix<ScalarDoubleValue>(GetCd, "current drag coefficient of the current vessel"));
            AddSuffix(new string[] { "CL" }, new Suffix<ScalarDoubleValue>(GetCl, "current lift coefficient of the current vessel"));

            // Get&Set args (scalars)
            AddSuffix(new string[] { "mu" }, new SetSuffix<ScalarDoubleValue>(GetMu, SetMu, "Gravity constant of central celestral"));
            AddSuffix(new string[] { "R" }, new SetSuffix<ScalarDoubleValue>(GetR, SetR, "Planet radius"));
            AddSuffix(new string[] { "molar_mass" }, new SetSuffix<ScalarDoubleValue>(GetMolarMass, SetMolarMass, "Atmospheric average molar mass"));
            AddSuffix(new string[] { "mass" }, new SetSuffix<ScalarDoubleValue>(GetMass, SetMass, "Vehicle mass"));
            AddSuffix(new string[] { "area" }, new SetSuffix<ScalarDoubleValue>(GetArea, SetArea, "Reference area"));
            AddSuffix(new string[] { "atm_height" }, new SetSuffix<ScalarDoubleValue>(GetAtmHeight, SetAtmHeight, "Height of the ceiling of the atmosphere"));
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
            AddSuffix(new string[] { "predict_traj_dSqrtE" }, new SetSuffix<ScalarDoubleValue>(GetPredictDSqrtE, SetPredictDSqrtE, "Trajector sampling interval in energy in predictor"));
            AddSuffix(new string[] { "predict_traj_dH" }, new SetSuffix<ScalarDoubleValue>(GetPredictDH, SetPredictDH, "Trajector sampling interval in height in predictor"));

            // Arrays (as List)
            // Aerodynamic coefficient profiles
            AddSuffix(new string[] { "AeroSpeedSamples" }, new SetSuffix<ListValue>(GetAeroSpeedSamples, SetAeroSpeedSamples, "Speed samples (For aerodynamic profile"));
            AddSuffix(new string[] { "AeroAltSamples" }, new SetSuffix<ListValue>(GetAeroAltSamples, SetAeroAltSamples, "Altitude samples (For aerodynamic profile"));
            AddSuffix(new string[] { "AeroCdSamples" }, new SetSuffix<ListValue>(GetAeroCdSamples, SetAeroCdSamples, "2D matrix of drag coefficient samples"));
            AddSuffix(new string[] { "AeroClSamples" }, new SetSuffix<ListValue>(GetAeroClSamples, SetAeroClSamples, "2D matrix of lift coefficient samples"));
            // AOA profiles
            AddSuffix(new string[] { "CtrlSpeedSamples" }, new SetSuffix<ListValue>(GetCtrlSpeedSamples, SetCtrlSpeedSamples, "Speed samples (For AOA profile)"));
            AddSuffix(new string[] { "CtrlAOAsamples" }, new SetSuffix<ListValue>(GetCtrlAOASamples, SetCtrlAOASamples, "AOA samples"));
            // Atmosphere density and temperature profile
            AddSuffix(new string[] { "AtmAltSamples" }, new SetSuffix<ListValue>(GetAtmAltSamples, SetAtmAltSamples, "Altitude samples (For density profile)"));
            AddSuffix(new string[] { "AtmLogDensitySamples" }, new SetSuffix<ListValue>(GetAtmLogDensitySamples, SetAtmLogDensitySamples, "Log Density samples"));
            AddSuffix(new string[] { "AtmTempSamples" }, new SetSuffix<ListValue>(GetAtmTempSamples, SetAtmTempSamples, "Temperature samples"));

            // Sync operations
            AddSuffix(new string[] { "GetBankCmd" }, new OneArgsSuffix<Lexicon, Lexicon>(GetBankCmd, "Takes y4 state and guidance parameters, output Bank command"));
            AddSuffix(new string[] { "GetAOACmd" }, new OneArgsSuffix<Lexicon, Lexicon>(GetAOACmd, "Takes y4 state, output AOA command"));
            AddSuffix(new string[] { "GetFARAeroCoefs" }, new OneArgsSuffix<Lexicon, Lexicon>(GetFARAeroCoefs, "Takes altitude, speed and AOA as input, output Cd and Cl"));
            AddSuffix(new string[] { "GetDensityAt" }, new OneArgsSuffix<ScalarValue, ScalarValue>(GetDensityAt, "Takes altitude as input, output air density in kg/m3"));
            AddSuffix(new string[] { "GetDensityEst" }, new OneArgsSuffix<ScalarValue, ScalarValue>(GetDensityEst, "Takes altitude as input, output estimated air density in kg/m3"));
            AddSuffix(new string[] { "InitAtmModel" }, new NoArgsVoidSuffix(InitAtmModel, "Initialize atmosphere model for current body"));

            // Async operations
            AddSuffix(new string[] { "AsyncSimAtmTraj" }, new OneArgsSuffix<ScalarValue, Lexicon>(StartSimAtmTraj, "Start a background atmosphere flight simulation; returns integer handle"));

            // Task management
            AddSuffix(new string[] { "CheckTask" }, new OneArgsSuffix<BooleanValue, ScalarValue>(CheckTask, "Check whether task (handle) has finished successfully"));
            AddSuffix(new string[] { "GetTaskResult" }, new OneArgsSuffix<Lexicon, ScalarValue>(GetTaskResult, "Retrieve Vector result of completed task (handle)"));
        }

        private SimAtmTrajArgs simArgs = new SimAtmTrajArgs();

        private ScalarDoubleValue GetAOA() { return new ScalarDoubleValue(FARAPI.ActiveVesselAoA()); }
        private ScalarDoubleValue GetAOS() { return new ScalarDoubleValue(FARAPI.ActiveVesselSideslip()); }
        private ScalarDoubleValue GetRefArea() { return new ScalarDoubleValue(FARAPI.ActiveVesselRefArea()); }
        private ScalarDoubleValue GetCd() { return new ScalarDoubleValue(FARAPI.ActiveVesselDragCoeff()); }
        private ScalarDoubleValue GetCl() { return new ScalarDoubleValue(FARAPI.ActiveVesselLiftCoeff()); }

        private ScalarDoubleValue GetMu() { return new ScalarDoubleValue(simArgs.mu); }
        private void SetMu(ScalarDoubleValue val) { simArgs.mu = val.GetDoubleValue(); }

        private ScalarDoubleValue GetR() { return new ScalarDoubleValue(simArgs.R); }
        private void SetR(ScalarDoubleValue val) { simArgs.R = val.GetDoubleValue(); }

        private ScalarDoubleValue GetMolarMass() { return new ScalarDoubleValue(simArgs.molarMass); }
        private void SetMolarMass(ScalarDoubleValue val) { simArgs.molarMass = val.GetDoubleValue(); }

        private ScalarDoubleValue GetMass() { return new ScalarDoubleValue(simArgs.mass * 1e-3); }
        private void SetMass(ScalarDoubleValue val) { simArgs.mass = val.GetDoubleValue() * 1e3; }

        private ScalarDoubleValue GetArea() { return new ScalarDoubleValue(simArgs.area); }
        private void SetArea(ScalarDoubleValue val) { simArgs.area = val.GetDoubleValue(); }

        private ScalarDoubleValue GetAtmHeight() { return new ScalarDoubleValue(simArgs.atmHeight); }
        private void SetAtmHeight(ScalarDoubleValue val) { simArgs.atmHeight = val.GetDoubleValue(); }

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

        private ScalarDoubleValue GetPredictDSqrtE() { return new ScalarDoubleValue(simArgs.predict_traj_dSqrtE); }
        private void SetPredictDSqrtE(ScalarDoubleValue val) { simArgs.predict_traj_dSqrtE = val.GetDoubleValue(); }

        private ScalarDoubleValue GetPredictDH() { return new ScalarDoubleValue(simArgs.predict_traj_dH); }
        private void SetPredictDH(ScalarDoubleValue val) { simArgs.predict_traj_dH = val.GetDoubleValue(); }

        private ScalarDoubleValue GetPredictTMax() { return new ScalarDoubleValue(simArgs.predict_tmax); }
        private void SetPredictTMax(ScalarDoubleValue val) { simArgs.predict_tmax = val.GetDoubleValue(); }

        private ListValue ListFromDoubleArray(double[] arr)
        {
            ListValue list = new ListValue();
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

        private ListValue ListFromDoubleArray2D(double[,] arr)
        {
            ListValue list = new ListValue();
            if (arr == null) return list;
            int dim0 = arr.GetLength(0), dim1 = arr.GetLength(1);
            for (int i = 0; i < dim0; i++)
            {
                ListValue sublist = new ListValue();
                for (int j = 0; j < dim1; j++)
                {
                    sublist.Add(new ScalarDoubleValue(arr[i, j]));
                }
                list.Add(sublist);
            }
            return list;
        }

        private double[,] ExtractDoubleArray2D(ListValue list, string name)
        {
            int dim0 = list.Count;
            if (dim0 == 0) return null;
            if (!(list[0] is ListValue sublist0))
                throw new KOSException($"All elements of '{name}' must be List of Scalar numbers");
            int dim1 = sublist0.Count;
            double[,] result = new double[dim0, dim1];
            for (int i = 0; i < dim0; i++)
            {
                if (!(list[i] is ListValue sublist))
                    throw new KOSException($"All elements of '{name}' must be List of Scalar numbers");
                if (sublist.Count != dim1)
                    throw new KOSException($"All sublists of '{name}' must have the same length");
                for (int j = 0; j < dim1; j++)
                {
                    var item = sublist[j];
                    if (!(item is ScalarValue scalar))
                        throw new KOSException($"All elements of sublists of '{name}' must be Scalar numbers");
                    double d = scalar.GetDoubleValue();
                    if (double.IsNaN(d) || double.IsInfinity(d))
                        throw new KOSException($"All elements of sublists of '{name}' must be finite numbers");
                    result[i, j] = d;
                }
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

        private ListValue GetAeroSpeedSamples() { return ListFromDoubleArray(simArgs.AeroSpeedSamples); }
        private void SetAeroSpeedSamples(ListValue val) { simArgs.AeroSpeedSamples = ExtractDoubleArray(val, "AeroSpeedSamples"); }

        private ListValue GetAeroAltSamples() { return ListFromDoubleArray(simArgs.AeroAltSamples); }
        private void SetAeroAltSamples(ListValue val) { simArgs.AeroAltSamples = ExtractDoubleArray(val, "AeroAltSamples"); }

        private ListValue GetAeroCdSamples() { return ListFromDoubleArray2D(simArgs.AeroCdSamples); }
        private void SetAeroCdSamples(ListValue val) { simArgs.AeroCdSamples = ExtractDoubleArray2D(val, "AeroCdSamples"); }

        private ListValue GetAeroClSamples() { return ListFromDoubleArray2D(simArgs.AeroClSamples); }
        private void SetAeroClSamples(ListValue val) { simArgs.AeroClSamples = ExtractDoubleArray2D(val, "AeroClSamples"); }

        private ListValue GetCtrlSpeedSamples() { return ListFromDoubleArray(simArgs.CtrlSpeedSamples); }
        private void SetCtrlSpeedSamples(ListValue val) { simArgs.CtrlSpeedSamples = ExtractDoubleArray(val, "speedsamples"); }

        private ListValue GetCtrlAOASamples()
        {
            ListValue list = new ListValue();
            foreach (double AOA in simArgs.CtrlAOAsamples)
            {
                list.Add(new ScalarDoubleValue(AOA / Math.PI * 180));
            }
            return list;
        }
        private void SetCtrlAOASamples(ListValue val)
        {
            if (val == null)
            {
                simArgs.CtrlAOAsamples = new double[0];
                return;
            }
            double[] result = new double[val.Count];
            for (int i = 0; i < val.Count; i++)
            {
                var item = val[i];
                if (!(item is ScalarValue scalar))
                    throw new KOSException($"All elements of AOAsamples must be Scalar numbers");
                double d = scalar.GetDoubleValue();
                if (double.IsNaN(d) || double.IsInfinity(d))
                    throw new KOSException($"All elements of AOAsamples must be finite numbers");
                result[i] = d / 180.0 * Math.PI;
            }
            simArgs.CtrlAOAsamples = result;
        }

        private ListValue GetAtmAltSamples() { return ListFromDoubleArray(simArgs.AtmAltSamples); }
        private void SetAtmAltSamples(ListValue val) { simArgs.AtmAltSamples = ExtractDoubleArray(val, "altsamples"); }

        private ListValue GetAtmLogDensitySamples() { return ListFromDoubleArray(simArgs.AtmLogDensitySamples); }
        private void SetAtmLogDensitySamples(ListValue val) { simArgs.AtmLogDensitySamples = ExtractDoubleArray(val, "logdensitysamples"); }

        private ListValue GetAtmTempSamples() { return ListFromDoubleArray(simArgs.AltTempSamples); }
        private void SetAtmTempSamples(ListValue val) { simArgs.AltTempSamples = ExtractDoubleArray(val, "temperaturesamples"); }

        private Lexicon GetBankCmd(Lexicon args)
        {
            PhyState state = RequirePhyState(args, "y4");
            BankPlanArgs bargs = RequireBankArgs(args);
            AFSCore.Context context = new AFSCore.Context();
            double BankCmd = AFSCore.GetBankCommand(state, simArgs, bargs, context);
            Lexicon result = new Lexicon();
            result.Add(new StringValue("Bank"), new ScalarDoubleValue(BankCmd / Math.PI * 180));
            return result;
        }

        private Lexicon GetAOACmd(Lexicon args)
        {
            PhyState state = RequirePhyState(args, "y4");
            double AOACmd = AFSCore.GetAOACommand(state, simArgs);
            Lexicon result = new Lexicon();
            result.Add(new StringValue("AOA"), new ScalarDoubleValue(AOACmd / Math.PI * 180));
            return result;
        }

        private Lexicon GetFARAeroCoefs(Lexicon args)
        {
            double altitude = RequireDoubleArg(args, "altitude");
            double speed = RequireDoubleArg(args, "speed");
            double AOA = RequireDoubleArg(args, "AOA") / 180 * Math.PI;
            AFSCore.GetFARAeroCoefs(altitude, AOA, speed, out double Cd, out double Cl);
            Lexicon result = new Lexicon();
            result.Add(new StringValue("Cd"), new ScalarDoubleValue(Cd));
            result.Add(new StringValue("Cl"), new ScalarDoubleValue(Cl));
            return result;
        }

        private ScalarValue GetDensityAt(ScalarValue altitude)
        {
            return ScalarValue.Create(AFSCore.GetDensityAt(altitude.GetDoubleValue()));
        }

        private ScalarValue GetDensityEst(ScalarValue altitude)
        {
            return ScalarValue.Create(AFSCore.GetDensityEst(simArgs, altitude.GetDoubleValue()));
        }

        private void InitAtmModel()
        {
            AFSCore.InitAtmModel(simArgs);
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
                    record.Result.Add(new StringValue("finalState"), new ListValue<ScalarDoubleValue>()
                    {
                        new ScalarDoubleValue(simResult.finalState.r),
                        new ScalarDoubleValue(simResult.finalState.theta*180/Math.PI),
                        new ScalarDoubleValue(simResult.finalState.v),
                        new ScalarDoubleValue(simResult.finalState.gamma*180/Math.PI)
                    });
                    ListValue<ScalarDoubleValue> trajE = new ListValue<ScalarDoubleValue>();
                    ListValue<ScalarDoubleValue> trajR = new ListValue<ScalarDoubleValue>();
                    ListValue<ScalarDoubleValue> trajTheta = new ListValue<ScalarDoubleValue>();
                    ListValue<ScalarDoubleValue> trajV = new ListValue<ScalarDoubleValue>();
                    ListValue<ScalarDoubleValue> trajGamma = new ListValue<ScalarDoubleValue>();
                    ListValue<ScalarDoubleValue> trajAOA = new ListValue<ScalarDoubleValue>();
                    ListValue<ScalarDoubleValue> trajBank = new ListValue<ScalarDoubleValue>();
                    for (int i=0; i<simResult.traj.Eseq.Length; ++i)
                    {
                        trajE.Add(new ScalarDoubleValue(simResult.traj.Eseq[i]));
                        trajR.Add(new ScalarDoubleValue(simResult.traj.states[i].r));
                        trajTheta.Add(new ScalarDoubleValue(simResult.traj.states[i].theta *180/Math.PI));
                        trajV.Add(new ScalarDoubleValue(simResult.traj.states[i].v));
                        trajGamma.Add(new ScalarDoubleValue(simResult.traj.states[i].gamma *180/Math.PI));
                        trajAOA.Add(new ScalarDoubleValue(simResult.traj.AOAseq[i] * 180 / Math.PI));
                        trajBank.Add(new ScalarDoubleValue(simResult.traj.Bankseq[i] * 180 / Math.PI));
                    }
                    record.Result.Add(new StringValue("trajE"), trajE);
                    record.Result.Add(new StringValue("trajR"), trajR);
                    record.Result.Add(new StringValue("trajTheta"), trajTheta);
                    record.Result.Add(new StringValue("trajV"), trajV);
                    record.Result.Add(new StringValue("trajGamma"), trajGamma);
                    record.Result.Add(new StringValue("trajAOA"), trajAOA);
                    record.Result.Add(new StringValue("trajBank"), trajBank);
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