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
using UnityEngine;
using kOS.Suffixed;
using Unity.Mathematics;

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
            AddSuffix(new string[] { "BANK" }, new Suffix<ScalarDoubleValue>(GetBank, "Bank of current vessel"));
            AddSuffix(new string[] { "REFAREA" }, new Suffix<ScalarDoubleValue>(GetRefArea, "reference area of current vessel"));
            AddSuffix(new string[] { "CD" }, new Suffix<ScalarDoubleValue>(GetCd, "current drag coefficient of the current vessel"));
            AddSuffix(new string[] { "CL" }, new Suffix<ScalarDoubleValue>(GetCl, "current lift coefficient of the current vessel"));
            AddSuffix(new string[] { "HeatFlux" }, new Suffix<ScalarDoubleValue>(GetHeatFlux, "current heat flux of the current vessel"));
            AddSuffix(new string[] { "GeeForce" }, new Suffix<ScalarDoubleValue>(GetGeeForce, "current acceleration of the current vessel"));
            AddSuffix(new string[] { "DynamicPressure" }, new Suffix<ScalarDoubleValue>(GetDynamicPressure, "current dynamic pressure of the current vessel"));
            AddSuffix(new string[] { "Density" }, new Suffix<ScalarDoubleValue>(GetDensity, "current air density of the current vessel"));

            // Celestial body parameters
            AddSuffix(new string[] { "mu" }, new SetSuffix<ScalarDoubleValue>(GetMu, SetMu, "Gravity constant of central celestral"));
            AddSuffix(new string[] { "R" }, new SetSuffix<ScalarDoubleValue>(GetR, SetR, "Planet radius"));
            AddSuffix(new string[] { "molar_mass" }, new SetSuffix<ScalarDoubleValue>(GetMolarMass, SetMolarMass, "Atmospheric average molar mass"));
            AddSuffix(new string[] { "atm_height" }, new SetSuffix<ScalarDoubleValue>(GetAtmHeight, SetAtmHeight, "Height of the ceiling of the atmosphere"));
            AddSuffix(new string[] { "bodySpin" }, new SetSuffix<Vector>(GetBodySpin, SetBodySpin, "The spin angular vector of the central body"));
            AddSuffix(new string[] { "AtmAltSamples" }, new SetSuffix<ListValue>(GetAtmAltSamples, SetAtmAltSamples, "Altitude samples (For density profile)"));
            AddSuffix(new string[] { "AtmLogDensitySamples" }, new SetSuffix<ListValue>(GetAtmLogDensitySamples, SetAtmLogDensitySamples, "Log Density samples"));
            AddSuffix(new string[] { "AtmTempSamples" }, new SetSuffix<ListValue>(GetAtmTempSamples, SetAtmTempSamples, "Temperature samples"));

            // Vessel parameters
            AddSuffix(new string[] { "mass" }, new SetSuffix<ScalarDoubleValue>(GetMass, SetMass, "Vehicle mass"));
            AddSuffix(new string[] { "area" }, new SetSuffix<ScalarDoubleValue>(GetArea, SetArea, "Reference area"));
            AddSuffix(new string[] { "rotation" }, new SetSuffix<Direction>(GetRotation, SetRotation, "Rotation of the vessel"));
            AddSuffix(new string[] { "AOAReversal" }, new SetSuffix<BooleanValue>(GetAOAReversal, SetAOAReversal, "The sign of AOA angle, false mean positive, true mean negative"));
            AddSuffix(new string[] { "CtrlSpeedSamples" }, new SetSuffix<ListValue>(GetCtrlSpeedSamples, SetCtrlSpeedSamples, "Speed samples (For AOA profile)"));
            AddSuffix(new string[] { "CtrlAOAsamples" }, new SetSuffix<ListValue>(GetCtrlAOASamples, SetCtrlAOASamples, "AOA samples"));
            AddSuffix(new string[] { "AeroSpeedSamples" }, new SetSuffix<ListValue>(GetAeroSpeedSamples, SetAeroSpeedSamples, "Speed samples (For aerodynamic profile"));
            AddSuffix(new string[] { "AeroLogDensitySamples" }, new SetSuffix<ListValue>(GetAeroLogDensitySamples, SetAeroLogDensitySamples, "Log density samples (For aerodynamic profile"));
            AddSuffix(new string[] { "SetAeroDsFromAlt" }, new OneArgsSuffix<ListValue>(SetAeroDsFromAlt, "Set AeroLogDensitySamples from altitudes"));
            AddSuffix(new string[] { "AeroCdSamples" }, new SetSuffix<ListValue>(GetAeroCdSamples, SetAeroCdSamples, "2D matrix of drag coefficient samples"));
            AddSuffix(new string[] { "AeroClSamples" }, new SetSuffix<ListValue>(GetAeroClSamples, SetAeroClSamples, "2D matrix of lift coefficient samples"));

            // Target parameters
            AddSuffix(new string[] { "target_energy" }, new SetSuffix<ScalarDoubleValue>(GetTargetEnergy, SetTargetEnergy, "Target energy"));
            AddSuffix(new string[] { "RTarget" }, new SetSuffix<Vector>(GetRTarget, SetRTarget, "Position of target"));

            // Guidance parameters
            AddSuffix(new string[] { "L_min" }, new SetSuffix<ScalarDoubleValue>(GetLMin, SetLMin, "Minimum lift"));
            AddSuffix(new string[] { "k_QEGC" }, new SetSuffix<ScalarDoubleValue>(GetK_QEGC, SetK_QEGC, "Heat flux gain constant"));
            AddSuffix(new string[] { "k_C" }, new SetSuffix<ScalarDoubleValue>(GetK_C, SetK_C, "Constraint gain constant"));
            AddSuffix(new string[] { "t_lag" }, new SetSuffix<ScalarDoubleValue>(GetTLag, SetTLag, "Constraint prediction time"));
            AddSuffix(new string[] { "Qdot_max" }, new SetSuffix<ScalarDoubleValue>(GetQdotMax, SetQdotMax, "Max heat flux"));
            AddSuffix(new string[] { "acc_max" }, new SetSuffix<ScalarDoubleValue>(GetAccMax, SetAccMax, "Max acceleration"));
            AddSuffix(new string[] { "dynp_max" }, new SetSuffix<ScalarDoubleValue>(GetDynpMax, SetDynpMax, "Max dynamic pressure"));
            AddSuffix(new string[] { "bank_max" }, new SetSuffix<ScalarDoubleValue>(GetBankMax, SetBankMax, "Max bank angle"));
            AddSuffix(new string[] { "heading_tol" }, new SetSuffix<ScalarDoubleValue>(GetHeadingTol, SetHeadingTol, "Heading error tolerance"));
            AddSuffix(new string[] { "bank_reversal" }, new SetSuffix<BooleanValue>(GetBankReversal, SetBankReversal, "Bank reversal"));
            AddSuffix(new string[] { "predict_min_step" }, new SetSuffix<ScalarDoubleValue>(GetPredictMinStep, SetPredictMinStep, "Predictor min step size"));
            AddSuffix(new string[] { "predict_max_step" }, new SetSuffix<ScalarDoubleValue>(GetPredictMaxStep, SetPredictMaxStep, "Predictor max step size"));
            AddSuffix(new string[] { "predict_tmax" }, new SetSuffix<ScalarDoubleValue>(GetPredictTMax, SetPredictTMax, "Predictor max time"));
            AddSuffix(new string[] { "predict_traj_dSqrtE" }, new SetSuffix<ScalarDoubleValue>(GetPredictDSqrtE, SetPredictDSqrtE, "Trajector sampling interval in energy in predictor"));
            AddSuffix(new string[] { "predict_traj_dH" }, new SetSuffix<ScalarDoubleValue>(GetPredictDH, SetPredictDH, "Trajector sampling interval in height in predictor"));

            // Sync operations
            AddSuffix(new string[] { "GetBankCmd" }, new OneArgsSuffix<Lexicon, Lexicon>(GetBankCmd, "Takes state and guidance parameters, output Bank command"));
            AddSuffix(new string[] { "GetAOACmd" }, new OneArgsSuffix<Lexicon, Lexicon>(GetAOACmd, "Takes state, output AOA command"));
            AddSuffix(new string[] { "GetState" }, new NoArgsSuffix<Lexicon>(GetState, "Get current state"));
            AddSuffix(new string[] { "GetFARAeroCoefs" }, new OneArgsSuffix<Lexicon, Lexicon>(GetFARAeroCoefs, "Takes altitude, speed and AOA as input, output Cd and Cl"));
            AddSuffix(new string[] { "GetFARAeroCoefsEst" }, new OneArgsSuffix<Lexicon, Lexicon>(GetFARAeroCoefsEst, "Takes altitude, speed and AOA as input, output estimated Cd and Cl"));
            AddSuffix(new string[] { "GetDensityAt" }, new OneArgsSuffix<ScalarValue, ScalarValue>(GetDensityAt, "Takes altitude as input, output air density in kg/m3"));
            AddSuffix(new string[] { "GetDensityEst" }, new OneArgsSuffix<ScalarValue, ScalarValue>(GetDensityEst, "Takes altitude as input, output estimated air density in kg/m3"));
            AddSuffix(new string[] { "GetAltEst" }, new OneArgsSuffix<ScalarValue, ScalarValue>(GetAltEst, "Takes density as input, output estimated altitude in m"));
            AddSuffix(new string[] { "InitAtmModel" }, new NoArgsVoidSuffix(InitAtmModel, "Initialize atmosphere model for current body"));
            AddSuffix(new string[] { "DirectionToAngleAxis" }, new OneArgsSuffix<Vector, Direction>(DirectionToAngleAxis, "Takes direction as input, output its angle axis form, where the magnitude of the vector is in radian unit"));
            AddSuffix(new string[] { "GetHeadingErr" }, new OneArgsSuffix<ScalarValue, Lexicon>(GetHeadingErr, "Takes vecR, vecV and vecRtgt as input, output heading error in (-180, 180)"));

            // Async operations
            AddSuffix(new string[] { "AsyncSimAtmTraj" }, new OneArgsSuffix<ScalarValue, Lexicon>(StartSimAtmTraj, "Start a background atmosphere flight simulation; returns integer handle"));

            // Task management
            AddSuffix(new string[] { "CheckTask" }, new OneArgsSuffix<BooleanValue, ScalarValue>(CheckTask, "Check whether task (handle) has finished successfully"));
            AddSuffix(new string[] { "GetTaskResult" }, new OneArgsSuffix<Lexicon, ScalarValue>(GetTaskResult, "Retrieve Vector result of completed task (handle)"));
        }

        private SimAtmTrajArgs simArgs = new SimAtmTrajArgs();

        //private ScalarDoubleValue GetAOA() { return new ScalarDoubleValue(FARAPI.ActiveVesselAoA()); }
        private ScalarDoubleValue GetAOA() { return new ScalarDoubleValue(AFSCore.GetSafeDouble(AFSCore.GetFARAOA(FlightGlobals.ActiveVessel.srf_velocity, simArgs.rotation, simArgs.AOAReversal) * 180 / Math.PI)); }
        //private ScalarDoubleValue GetAOS() { return new ScalarDoubleValue(FARAPI.ActiveVesselSideslip()); }
        private ScalarDoubleValue GetAOS() { return new ScalarDoubleValue(AFSCore.GetSafeDouble(AFSCore.GetFARAOS(FlightGlobals.ActiveVessel.srf_velocity, simArgs.rotation) * 180 / Math.PI)); }
        private ScalarDoubleValue GetBank() { return new ScalarDoubleValue(AFSCore.GetSafeDouble(AFSCore.GetFARBank(simArgs.rotation) * 180 / Math.PI)); }
        private ScalarDoubleValue GetRefArea() { return new ScalarDoubleValue(AFSCore.GetSafeDouble(FARAPI.ActiveVesselRefArea())); }
        private ScalarDoubleValue GetCd() { return new ScalarDoubleValue(AFSCore.GetSafeDouble(FARAPI.ActiveVesselDragCoeff())); }
        private ScalarDoubleValue GetCl() { return new ScalarDoubleValue(AFSCore.GetSafeDouble(FARAPI.ActiveVesselLiftCoeff())); }
        private ScalarDoubleValue GetHeatFlux()
        {
            double rho = FlightGlobals.ActiveVessel.atmDensity;
            double v = FlightGlobals.ActiveVessel.srf_velocity.magnitude;
            return new ScalarDoubleValue(AFSCore.GetSafeDouble(AFSCore.HeatFluxCoefficient * Math.Pow(v, 3.15) * Math.Sqrt(rho)));
        }

        private ScalarDoubleValue GetGeeForce()
        {
            return new ScalarDoubleValue(AFSCore.GetSafeDouble(FlightGlobals.ActiveVessel.geeForce));
        }

        private ScalarDoubleValue GetDynamicPressure()
        {
            return new ScalarDoubleValue(AFSCore.GetSafeDouble(FlightGlobals.ActiveVessel.dynamicPressurekPa * 1000.0));
        }

        private ScalarDoubleValue GetDensity()
        {
            return new ScalarDoubleValue(AFSCore.GetSafeDouble(FlightGlobals.ActiveVessel.atmDensity));
        }

        private Vector DirectionToAngleAxis(Direction q)
        {
            q.Rotation.ToAngleAxis(out float angle, out Vector3 axis);
            if (angle > 180f)
            {
                angle = 360f - angle;
                axis = -axis;
            }
            Vector resVec = new Vector(axis * (angle * Mathf.Deg2Rad));
            if (Double.IsFinite(resVec.X) && Double.IsFinite(resVec.Y) && Double.IsFinite(resVec.Z))
                return resVec;
            else
                return Vector.Zero;
        }

        private ScalarValue GetHeadingErr(Lexicon args)
        {
            double3 vecR = RequiredVectorArg(args, "vecR");
            double3 vecV = RequiredVectorArg(args, "vecV");
            double3 vecRtgt = RequiredVectorArg(args, "vecRtgt");
            double headingErr = AFSCore.GetHeadingErr(vecR, vecV, vecRtgt);
            headingErr = math.degrees(headingErr);
            if (!Double.IsFinite(headingErr)) return ScalarValue.Create(0d);
            return ScalarValue.Create(headingErr);
        }

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

        private Direction GetRotation() { return new Direction(simArgs.rotation); }
        private void SetRotation(Direction q) { simArgs.rotation = q.Rotation; }

        private BooleanValue GetAOAReversal() { return simArgs.AOAReversal ? BooleanValue.True : BooleanValue.False; }
        private void SetAOAReversal(BooleanValue val) { simArgs.AOAReversal = val.Value; }

        private ScalarDoubleValue GetAtmHeight() { return new ScalarDoubleValue(simArgs.atmHeight); }
        private void SetAtmHeight(ScalarDoubleValue val) { simArgs.atmHeight = val.GetDoubleValue(); }

        private Vector GetBodySpin() { return Double3ToVector(simArgs.bodySpin); }
        private void SetBodySpin(Vector val) { simArgs.bodySpin = VectorToDouble3(val); }

        private ScalarDoubleValue GetBankMax() { return new ScalarDoubleValue(simArgs.bank_max / Math.PI * 180); }
        private void SetBankMax(ScalarDoubleValue val) { simArgs.bank_max = val.GetDoubleValue() / 180.0 * Math.PI; }

        private ScalarDoubleValue GetHeadingTol() { return new ScalarDoubleValue(simArgs.heading_tol / Math.PI * 180); }
        private void SetHeadingTol(ScalarDoubleValue val) { simArgs.heading_tol = val.GetDoubleValue() / 180.0 * Math.PI; }

        private BooleanValue GetBankReversal() { return new BooleanValue(simArgs.bank_reversal); }
        private void SetBankReversal(BooleanValue val) { simArgs.bank_reversal = val.Value; }

        private ScalarDoubleValue GetK_QEGC() { return new ScalarDoubleValue(simArgs.k_QEGC); }
        private void SetK_QEGC(ScalarDoubleValue val) { simArgs.k_QEGC = val.GetDoubleValue(); }

        private ScalarDoubleValue GetK_C() { return new ScalarDoubleValue(simArgs.k_C); }
        private void SetK_C(ScalarDoubleValue val) { simArgs.k_C = val.GetDoubleValue(); }

        private ScalarDoubleValue GetTLag() { return new ScalarDoubleValue(simArgs.t_lag); }
        private void SetTLag(ScalarDoubleValue val) { simArgs.t_lag = val.GetDoubleValue(); }

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

        private Vector GetRTarget() { return Double3ToVector(simArgs.Rtarget); }
        private void SetRTarget(Vector val) { simArgs.Rtarget = VectorToDouble3(val); }

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

        private PhyState RequirePhyState(Lexicon args)
        {
            double3 vecR = RequiredVectorArg(args, "vecR");
            double3 vecV = RequiredVectorArg(args, "vecV");
            return new PhyState(vecR, vecV);
        }
        private BankPlanArgs RequireBankArgs(Lexicon args)
        {
            BankPlanArgs bargs = new BankPlanArgs(
                RequireDoubleArg(args, "bank_i") / 180 * Math.PI,
                RequireDoubleArg(args, "bank_f") / 180 * Math.PI,
                RequireDoubleArg(args, "energy_i"),
                RequireDoubleArg(args, "energy_f"),
                simArgs.bank_reversal
            );
            return bargs;
        }

        private ListValue GetAeroSpeedSamples() { return ListFromDoubleArray(simArgs.AeroSpeedSamples); }
        private void SetAeroSpeedSamples(ListValue val) { simArgs.AeroSpeedSamples = ExtractDoubleArray(val, "AeroSpeedSamples"); }

        private ListValue GetAeroLogDensitySamples() { return ListFromDoubleArray(simArgs.AeroLogDensitySamples); }
        private void SetAeroLogDensitySamples(ListValue val) { simArgs.AeroLogDensitySamples = ExtractDoubleArray(val, "AeroLogDensitySamples"); }

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

        private void SetAeroDsFromAlt(ListValue val)
        {
            double[] altSamples = ExtractDoubleArray(val, "alt samples");
            for (int i = 0; i < altSamples.Length; ++i)
            {
                double density = AFSCore.GetDensityAt(altSamples[i]);
                altSamples[i] = density > Double.Epsilon ? Math.Log(density) : Double.MinValue * 0.5;
            }
            simArgs.AeroLogDensitySamples = altSamples;
        }

        private ListValue GetAtmTempSamples() { return ListFromDoubleArray(simArgs.AtmTempSamples); }
        private void SetAtmTempSamples(ListValue val) { simArgs.AtmTempSamples = ExtractDoubleArray(val, "temperaturesamples"); }

        private Lexicon GetBankCmd(Lexicon args)
        {
            PhyState state = RequirePhyState(args);
            BankPlanArgs bargs = RequireBankArgs(args);
            AFSCore.Context context = new AFSCore.Context();
            double BankCmd = AFSCore.GetBankCommand(state, simArgs, bargs, context);
            Lexicon result = new Lexicon();
            result.Add(new StringValue("Bank"), new ScalarDoubleValue(BankCmd / Math.PI * 180));
            return result;
        }

        private Lexicon GetAOACmd(Lexicon args)
        {
            PhyState state = RequirePhyState(args);
            double AOACmd = AFSCore.GetAOACommand(state, simArgs);
            Lexicon result = new Lexicon();
            result.Add(new StringValue("AOA"), new ScalarDoubleValue(AOACmd / Math.PI * 180));
            return result;
        }

        private Lexicon GetState()
        {
            PhyState state = AFSCore.GetPhyState();
            Lexicon result = new Lexicon();
            result.Add(new StringValue("vecR"), Double3ToVector(state.vecR));
            result.Add(new StringValue("vecV"), Double3ToVector(state.vecV));
            return result;
        }

        private Lexicon GetFARAeroCoefs(Lexicon args)
        {
            double altitude = RequireDoubleArg(args, "altitude");
            double speed = RequireDoubleArg(args, "speed");
            double AOA = RequireDoubleArg(args, "AOA") / 180 * Math.PI;
            AFSCore.GetFARAeroCoefs(altitude, AOA, speed, out double Cd, out double Cl, simArgs.rotation, simArgs.AOAReversal);
            Lexicon result = new Lexicon();
            result.Add(new StringValue("Cd"), new ScalarDoubleValue(Cd));
            result.Add(new StringValue("Cl"), new ScalarDoubleValue(Cl));
            return result;
        }

        private Lexicon GetFARAeroCoefsEst(Lexicon args)
        {
            double altitude = RequireDoubleArg(args, "altitude");
            double logRho = AFSCore.GetLogDensityEst(simArgs, altitude);
            double speed = RequireDoubleArg(args, "speed");
            AFSCore.GetAeroCoefficients(simArgs, speed, logRho, out double Cd, out double Cl);
            Lexicon result = new Lexicon();
            result.Add(new StringValue("Cd"), new ScalarDoubleValue(Cd));
            result.Add(new StringValue("Cl"), new ScalarDoubleValue(Cl));
            return result;
        }

        private ScalarValue GetDensityAt(ScalarValue altitude)
        {
            return ScalarValue.Create(AFSCore.GetSafeDouble(AFSCore.GetDensityAt(altitude.GetDoubleValue())));
        }

        private ScalarValue GetDensityEst(ScalarValue altitude)
        {
            return ScalarValue.Create(AFSCore.GetSafeDouble(AFSCore.GetDensityEst(simArgs, altitude.GetDoubleValue())));
        }

        private ScalarValue GetAltEst(ScalarValue density)
        {
            return ScalarValue.Create(AFSCore.GetSafeDouble(AFSCore.GetHeightEst(simArgs, density.GetDoubleValue())));
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
                state = RequirePhyState(args);
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
                    record.Result.Add(new StringValue("finalVecR"), Double3ToVector(simResult.finalState.vecR));
                    record.Result.Add(new StringValue("finalVecV"), Double3ToVector(simResult.finalState.vecV));
                    ListValue<ScalarDoubleValue> trajE = new ListValue<ScalarDoubleValue>();
                    ListValue<ScalarDoubleValue> trajAOA = new ListValue<ScalarDoubleValue>();
                    ListValue<ScalarDoubleValue> trajBank = new ListValue<ScalarDoubleValue>();
                    ListValue<Vector> trajVecR = new ListValue<Vector>();
                    ListValue<Vector> trajVecV = new ListValue<Vector>();
                    for (int i = 0; i < simResult.traj.Eseq.Length; ++i)
                    {
                        trajE.Add(new ScalarDoubleValue(simResult.traj.Eseq[i]));
                        trajAOA.Add(new ScalarDoubleValue(simResult.traj.AOAseq[i] * 180 / Math.PI));
                        trajBank.Add(new ScalarDoubleValue(simResult.traj.Bankseq[i] * 180 / Math.PI));
                        trajVecR.Add(Double3ToVector(simResult.traj.states[i].vecR));
                        trajVecV.Add(Double3ToVector(simResult.traj.states[i].vecV));
                    }
                    record.Result.Add(new StringValue("trajE"), trajE);
                    record.Result.Add(new StringValue("trajAOA"), trajAOA);
                    record.Result.Add(new StringValue("trajBank"), trajBank);
                    record.Result.Add(new StringValue("trajVecR"), trajVecR);
                    record.Result.Add(new StringValue("trajVecV"), trajVecV);
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

        private static double3 RequiredVectorArg(Lexicon args, string name)
        {
            if (!args.TryGetValue(new StringValue(name), out var val))
                throw new KOSException($"Argument '{name}' is required");
            if (!(val is Vector vec))
                throw new KOSException($"Argument '{name}' must be a Vector");
            return VectorToDouble3(vec);
        }

        private static Vector Double3ToVector(double3 d3)
        {
            Vector v = new Vector(
                Double.IsFinite(d3.x) ? d3.x : 0.0,
                Double.IsFinite(d3.y) ? d3.y : 0.0,
                Double.IsFinite(d3.z) ? d3.z : 0.0
            );
            return v;
        }

        private static double3 VectorToDouble3(Vector v)
        {
            double3 d3 = new double3(v.X, v.Y, v.Z);
            return d3;
        }
    }
}