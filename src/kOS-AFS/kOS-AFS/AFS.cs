using FerramAerospaceResearch;
using System;
using System.Collections.Generic;
using Unity.Burst;
using Unity.Mathematics;
using UnityEngine;

namespace AFS
{    
    internal class SimAtmTrajArgs
    {
        public double mu, R, mass, molarMass, area, atmHeight, bank_max;
        public double[] CtrlSpeedSamples, CtrlAOAsamples;
        public double[] AeroSpeedSamples, AeroAltSamples;
        public double[,] AeroCdSamples, AeroClSamples;
        public double[] AtmAltSamples, AltTempSamples, AtmLogDensitySamples;
        public double k_QEGC, k_C, t_reg, Qdot_max, acc_max, dynp_max;
        public double L_min, target_energy;
        public double predict_max_step, predict_min_step, predict_tmax;
        public double predict_traj_dSqrtE, predict_traj_dH;
        public SimAtmTrajArgs()
        {
            // initialize defaults (CEV configuration)
            mu = 3.98589e14;  // Earth
            R = 6.371e6;
            molarMass = 0.02897;
            mass = 6000;
            area = 12;
            atmHeight = 140e3;
            bank_max = 40.0 *Math.PI/180.0;
            CtrlSpeedSamples = new double[] { 600, 8000 };
            CtrlAOAsamples = new double[] { 15.0*Math.PI/180.0, 15.0*Math.PI/180.0 };
            AeroSpeedSamples = new double[] { 3000 };
            AeroAltSamples = new double[] { 40e3 };
            AeroClSamples = new double[,] { { 0.3 } };
            AeroCdSamples = new double[,] { { 1.5 } };
            AtmAltSamples = new double[] { 0e3, 140e3 };
            AltTempSamples = new double[] { 296.0, 220.0 };
            AtmLogDensitySamples = new double[] { Math.Log(1.2250), Math.Log(1.2250) - 140.0 / 8.5 };
            k_QEGC = 1.0;
            k_C = 5.0;
            t_reg = 90;
            Qdot_max = 5e6;
            acc_max = 3 * 9.81;
            dynp_max = 15e3;
            L_min = 0.5;
            target_energy = AFSCore.GetSpecificEnergy(mu, R+10e3, 300);
            predict_min_step = 0;
            predict_max_step = 1;
            predict_tmax = 3600;
            predict_traj_dSqrtE = 300.0;
            predict_traj_dH = 10e3;

            AFSCore.InitAtmModel(this);
            mass = FlightGlobals.ActiveVessel.GetTotalMass() * 1000;
            area = FARAPI.ActiveVesselRefArea();
        }
    }
    internal class BankPlanArgs
    {
        public double bank_i, bank_f, energy_i, energy_f;
        public BankPlanArgs()
        {
            // initialize defaults (CEV configuration)
            bank_i = 20.0 * Math.PI / 180.0;
            bank_f = 10.0 * Math.PI / 180.0;
            energy_i = AFSCore.GetSpecificEnergy(3.98589e14, 6.371e6 + 140e3, 8000);
            energy_f = AFSCore.GetSpecificEnergy(3.98589e14, 6.371e6 + 10e3, 300);
        }
        public BankPlanArgs(double bank_i, double bank_f, double energy_i, double energy_f)
        {
            this.bank_i = bank_i;
            this.bank_f = bank_f;
            this.energy_i = energy_i;
            this.energy_f = energy_f;
        }
    }
    internal struct PhyState
    {
        public double4 values;

        public double r => values[0];
        public double theta => values[1];
        public double v => values[2];
        public double gamma => values[3];

        // Initialize defaults (CEV configuration)
        public static PhyState Default => new PhyState(
            (6371 + 140) * 1e3,
            0,
            8000,
            -5.0 * Math.PI / 180.0
        );

        public PhyState(double r, double theta, double v, double gamma)
        {
            values = new double4(r, theta, v, gamma);
        }

        public PhyState(double4 newValues)
        {
            values = newValues;
        }
    }
    internal class PhyTraj
    {
        public double[] Eseq;
        public PhyState[] states;
        public double[] AOAseq;
        public double[] Bankseq;
    }
    internal enum PredictStatus
    {
        COMPLETED, TIMEOUT, FAILED, OVERSHOOT
    }
    internal class PredictResult
    {
        public int nsteps;
        public double t;
        public PhyState finalState;
        public PhyTraj traj;
        public PredictStatus status;
        public double maxQdot, maxQdotTime;
        public double maxAcc, maxAccTime;
        public double maxDynP, maxDynPTime;
    }
    internal class AFSCore
    {
        // RKF45 parameterss
        private const double HeatFluxCoefficient = 9.4369e-5;
        private const double AbsVTol = 0;
        private const double RelVTol = 1e-6;
        private const double StepSafety = 0.9;
        private const double MinScale = 0.2;
        private const double MaxScale = 5.0;
        // RKF45 constants
        private const double C04=25.0/216.0, C05=16.0/135.0;
        private const double S1=1.0/4.0, Beta10=1.0/4.0, C14=0.0, C15=0.0;
        private const double S2=3.0/8.0, Beta20=3.0/32.0, Beta21=9.0/32.0, C24=1408.0/2565.0, C25=6656.0/12825.0;
        private const double S3=12.0/13.0, Beta30=1932.0/2197.0, Beta31=-7200.0/2197.0, Beta32=7296.0/2197.0, C34=2197.0/4104.0, C35=28561.0/56430.0;
        private const double S4=1.0, Beta40=439.0/216.0, Beta41=-8.0, Beta42=3680.0/513.0, Beta43=-845.0/4104.0, C44=-1.0/5.0, C45=-9.0/50.0;
        private const double S5=1.0/2.0, Beta50=-8.0/27.0, Beta51=2.0, Beta52=-3544.0/2565.0, Beta53=1859.0/4104.0, Beta54=-11.0/40.0, C54=0.0, C55=2.0/55.0;
        // Simulation constants
        private const double ENERGY_ERR_TOL = 1;
        // Atmospheric model constants
        private const double GAS_CONSTANT = 8.314462618; // J/(mol·K)

        public class Context {
            public double G, L, D, Qdot, acc, dynp;
        }
        public static double GetBankCommand(PhyState state, SimAtmTrajArgs args, BankPlanArgs bargs, Context context)
        {
            double r = state.r;
            double v = SafeValue(Math.Abs(state.v));
            double gamma = state.gamma;
            double erg = GetSpecificEnergy(args.mu, r, v);

            double energy = GetSpecificEnergy(args.mu, r, v);
            double bankBase = bargs.bank_f + (bargs.bank_i - bargs.bank_f) * (energy - bargs.energy_f) / (bargs.energy_i - bargs.energy_f);
            double G = args.mu / r / r;

            double rho = GetDensityEst(args, r - args.R);
            double aeroCoef = 0.5 * rho * v * v * args.area / args.mass;
            GetAeroCoefficients(args, v, r - args.atmHeight, out double Cd, out double Cl);
            double D = aeroCoef * Cd;
            double L = aeroCoef * Cl;

            if (context != null)
            {
                context.G = G;
                context.L = L;
                context.D = D;
            }

            double Bank;
            if (L > args.L_min)
            {
                double hs = GetScaleHeightEst(args, r - args.R);
                // QEGC correction
                double hdot = v * Math.Sin(gamma);
                double hdotQEGC = -2.0 * G / SafeValue(v/hs * Math.Cos(bankBase)) * (Cd / SafeValue(Cl));
                // Constraints correction
                double Qdot = HeatFluxCoefficient * Math.Pow(v, 3.15) * Math.Sqrt(rho);
                double v2 = v * v;
                double denomQdot = Math.Max(0.5 / hs + 3.15 * G / v2, 1e-6);
                double hdotQdot = -(args.Qdot_max / Math.Max(Qdot, 1e-6) - 1.0 + 3.15 * D * args.t_reg / v) / denomQdot / args.t_reg;

                double a = Math.Sqrt(L * L + D * D);
                double denomAcc = Math.Max(1.0 / hs + 2.0 * G / v2, 1e-6);
                double hdotAcc = -(args.acc_max / Math.Max(a, 1e-6) - 1.0 + 2.0 * D * args.t_reg / v) / denomAcc / args.t_reg;

                double q = rho * v * v / 2.0;
                double hdotDynP = -(args.dynp_max / Math.Max(q, 1e-6) - 1.0 + 2.0 * D * args.t_reg / v) / denomAcc / args.t_reg;

                double hdotC = Math.Max(Math.Max(hdot, hdotQdot), Math.Max(hdotAcc, hdotDynP));
                double vNorm = hs / 10;
                double cosArg = Math.Cos(bankBase) - args.k_QEGC / vNorm * (hdot - hdotQEGC) - args.k_C / vNorm * (hdot - hdotC);
                cosArg = Clamp(cosArg, Math.Cos(args.bank_max), 1.0);
                Bank = Math.Acos(cosArg);

                if (context != null)
                {
                    context.Qdot = Qdot;
                    context.acc = a;
                    context.dynp = q;
                }
            }
            else
            {
                Bank = Clamp(bankBase, 0.0, args.bank_max);

                if (context != null)
                {
                    context.Qdot = 0;
                    context.acc = 0;
                    context.dynp = 0;
                }
            }

            return Bank;
        }

        public static double GetAOACommand(PhyState state, SimAtmTrajArgs args)
        {
            double v = state.v;
            // Interpolate for AOA command
            int idx = FindUpperBound(args.CtrlSpeedSamples, v);
            if (idx == 0) return args.CtrlAOAsamples[0];
            else if (idx == args.CtrlSpeedSamples.Length) return args.CtrlAOAsamples[args.CtrlAOAsamples.Length - 1];
            else
            {
                double t = (v - args.CtrlSpeedSamples[idx - 1]) / (args.CtrlSpeedSamples[idx] - args.CtrlSpeedSamples[idx - 1]);
                return args.CtrlAOAsamples[idx - 1] + t * (args.CtrlAOAsamples[idx] - args.CtrlAOAsamples[idx - 1]);
            }
        }

        public static PredictResult PredictTrajectory(double t, PhyState state, SimAtmTrajArgs args, BankPlanArgs bargs)
        {
            int nsteps = 0;
            double E = GetSpecificEnergy(args.mu, state.r, state.v);
            double Eold = E;
            double Rold = state.r;
            double tmax = t + args.predict_tmax;
            double told = t;
            List<double> Eseq = new List<double>(); Eseq.Add(E);
            List<PhyState> stateSeq = new List<PhyState>(); stateSeq.Add(state);
            List<double> AOAseq = new List<double>();
            List<double> Bankseq = new List<double>();
            double AOA = GetAOACommand(state, args);
            double Bank = GetBankCommand(state, args, bargs, null);
            AOAseq.Add(AOA);
            Bankseq.Add(Bank);

            PhyState stateold = state;
            double maxQdot=-1, maxQdotTime=-1;
            double maxAcc=-1, maxAccTime=-1;
            double maxDynP=-1, maxDynPTime=-1;
            double tstep = args.predict_max_step;
            Rk45StepResult result;
            while (t < tmax)
            {
                ++nsteps;
                result = RK45Step(t, state, tstep, args, bargs);
                while (!result.isValid)
                {
                    result = RK45Step(t, state, result.newStep, args, bargs);
                }
                if (result.Qdot > maxQdot)
                {
                    maxQdot = result.Qdot;
                    maxQdotTime = t;
                }
                if (result.acc > maxAcc)
                {
                    maxAcc = result.acc;
                    maxAccTime = t;
                }
                if (result.dynp > maxDynP)
                {
                    maxDynP = result.dynp;
                    maxDynPTime = t;
                }
                tstep = result.newStep;
                told = t; stateold = state;
                t = result.t; state = result.nextState;
                E = GetSpecificEnergy(args.mu, state.r, state.v);
                if (E < args.target_energy) break;
                if (Math.Abs(Math.Sqrt(E-args.target_energy) - Math.Sqrt(Eold-args.target_energy)) > args.predict_traj_dSqrtE || Math.Abs(state.r - Rold) > args.predict_traj_dH)
                {
                    Eseq.Add(E);
                    stateSeq.Add(state);
                    AOA = GetAOACommand(state, args);
                    Bank = GetBankCommand(state, args, bargs, null);
                    AOAseq.Add(AOA);
                    Bankseq.Add(Bank);
                    Eold = E;
                    Rold = state.r;
                }
            }
            if (t >= tmax)
            {
                // Reaches maximum time
                return new PredictResult
                {
                    nsteps = nsteps,
                    t = t, finalState = state,
                    traj = new PhyTraj { Eseq = Eseq.ToArray(), states = stateSeq.ToArray(), AOAseq = AOAseq.ToArray(), Bankseq = Bankseq.ToArray() },
                    status = PredictStatus.TIMEOUT,
                    maxQdot = maxQdot, maxQdotTime = maxQdotTime,
                    maxAcc = maxAcc, maxAccTime = maxAccTime,
                    maxDynP = maxDynP, maxDynPTime = maxDynPTime
                };
            }
            // Reaches terminal energy condition, Newton-Raphson method to find the root
            int numiter = 0;
            while (numiter < 40)
            {
                double r = state.r;
                double v = state.v;
				double Err = GetSpecificEnergy(args.mu, r, v) - args.target_energy;
                if (Math.Abs(Err) < ENERGY_ERR_TOL) break;

				double G = args.mu / (r * r);
				double rho = GetDensityEst(args, r - args.R);
				double aeroCoef = 0.5 * rho * v * v * args.area / args.mass;
				GetAeroCoefficients(args, v, r - args.atmHeight, out double Cd, out _);
				double D = aeroCoef * Cd;

                double rdot = v * Math.Sin(state.gamma);
                double vdot = -D - G * Math.Sin(state.gamma);
                double Edot = args.mu / r / r * rdot + v * vdot;

                t -= Err / Edot;
                result = RK45Step(told, stateold, t - told, args, bargs);
                state = result.nextState;

                ++numiter;
            }
            E = GetSpecificEnergy(args.mu, state.r, state.v);
            if (E < Eold)
            {
                Eseq.Add(E);
                stateSeq.Add(state);
                AOA = GetAOACommand(state, args);
                Bank = GetBankCommand(state, args, bargs, null);
                AOAseq.Add(AOA);
                Bankseq.Add(Bank);
            }
            return new PredictResult
            {
                nsteps = nsteps,
                t = t, finalState = state,
                traj = new PhyTraj { Eseq = Eseq.ToArray(), states = stateSeq.ToArray(), AOAseq = AOAseq.ToArray(), Bankseq = Bankseq.ToArray() },
                status = PredictStatus.COMPLETED,
                maxQdot = maxQdot, maxQdotTime = maxQdotTime,
				maxAcc = maxAcc, maxAccTime = maxAccTime,
				maxDynP = maxDynP, maxDynPTime = maxDynPTime
			};
        }

        public static double GetSpecificEnergy(double mu, double r, double v)
        {
            return -mu / r + 0.5 * v * v;
        }

        private static void GetAeroCoefficients(SimAtmTrajArgs args, double speed, double altitude, out double Cd, out double Cl)
        {
            // Bilinear interpolation for aerodynamic coefficients
            int nV = args.AeroSpeedSamples.Length;
            int nH = args.AeroAltSamples.Length;
            int idxV = FindUpperBound(args.AeroSpeedSamples, speed);
            int idxH = FindUpperBound(args.AeroAltSamples, altitude);
            double w00, w01, w10, w11;
            if (idxV == 0) { w00 = 0; w01 = 0; w10 = 1; w11 = 1; }
            else if (idxV == nV) { w00 = 1; w01 = 1; w10 = 0; w11 = 0; }
            else
            {
                double tV = (speed - args.AeroSpeedSamples[idxV - 1]) / (args.AeroSpeedSamples[idxV] - args.AeroSpeedSamples[idxV - 1]);
                w00 = 1 - tV; w10 = tV;
                w01 = 1 - tV; w11 = tV;
            }
            if (idxH == 0) { w00 = 0; w10 = 0; }
            else if (idxH == nH) { w01 = 0; w11 = 0; }
            else
            {
                double tH = (altitude - args.AeroAltSamples[idxH - 1]) / (args.AeroAltSamples[idxH] - args.AeroAltSamples[idxH - 1]);
                w00 *= (1 - tH); w01 *= tH;
                w10 *= (1 - tH); w11 *= tH;
            }
            int x0 = Math.Max(0, idxV - 1), x1 = Math.Min(nV - 1, idxV);
            int y0 = Math.Max(0, idxH - 1), y1 = Math.Min(nH - 1, idxH);
            Cd = w00 * args.AeroCdSamples[x0, y0] + w01 * args.AeroCdSamples[x0, y1] + w10 * args.AeroCdSamples[x1, y0] + w11 * args.AeroCdSamples[x1, y1];
            Cl = w00 * args.AeroClSamples[x0, y0] + w01 * args.AeroClSamples[x0, y1] + w10 * args.AeroClSamples[x1, y0] + w11 * args.AeroClSamples[x1, y1];
            return;
        }

        private static int FindUpperBound(double[] xs, double x)
        {
            if (xs == null || xs.Length == 0) return 0;
            // Assume xs is sorted: binary search
            int idx = Array.BinarySearch(xs, x);
            if (idx >= 0) ++idx;
            else idx = ~idx;
            return idx;
        }

        private static double SafeValue(double value, double minAbs = 1e-6)
        {
            if (double.IsNaN(value) || double.IsInfinity(value))
            {
                return minAbs;
            }
            if (Math.Abs(value) < minAbs)
            {
                return value >= 0 ? minAbs : -minAbs;
            }
            return value;
        }

        private class PhyStateDerivative
		{
            public PhyStateDerivative(double rdot, double thetadot, double vdot, double gammadot)
            {
                values = new double4(rdot, thetadot, vdot, gammadot);
            }
            public double4 values;
            public double rdot { get => values[0]; }
            public double thetadot { get => values[1]; }
            public double vdot { get => values[2]; }
            public double gammadot { get => values[3]; }
		}

        private static PhyStateDerivative ComputeDerivatives(double t, PhyState state, SimAtmTrajArgs args, BankPlanArgs bargs, Context context)
        {
            double r = state.r;
            //double theta = state.theta;
            double v = state.v;
            double gamma = state.gamma;

            if (context == null)
            {
                context = new Context();
            }

            double bank = GetBankCommand(state, args, bargs, context);
            double safeR = SafeValue(r);
            double safeV = SafeValue(v);

            double rdot = v * Math.Sin(gamma);
            double thetadot = v * Math.Cos(gamma) / safeR;
            double vdot = -context.D - context.G * Math.Sin(gamma);
            double gammadot = (context.L * Math.Cos(bank) - (context.G - v * v / safeR) * Math.Cos(gamma)) / safeV;

            return new PhyStateDerivative(rdot, thetadot, vdot, gammadot);
        }

        private struct Rk45StepResult
        {
            public double t, newStep;
            public PhyState nextState;
            public double errorV;
            public bool isValid;
            public double Qdot, acc, dynp;
        }

        [BurstCompile]
        private static Rk45StepResult RK45Step(double t, PhyState state, double tstep, SimAtmTrajArgs args, BankPlanArgs bargs)
        {
            Context context = new Context();
            PhyStateDerivative k0 = ComputeDerivatives(t, state, args, bargs, context);
            PhyStateDerivative k1 = ComputeDerivatives(t+S1*tstep, new PhyState(state.values+Beta10*k0.values), args, bargs, null);
            PhyStateDerivative k2 = ComputeDerivatives(t+S2*tstep, new PhyState(state.values+Beta20*k0.values+Beta21*k1.values), args, bargs, null);
            PhyStateDerivative k3 = ComputeDerivatives(t+S3*tstep, new PhyState(state.values+Beta30*k0.values+Beta31*k1.values+Beta32*k2.values), args, bargs, null);
            PhyStateDerivative k4 = ComputeDerivatives(t+S4*tstep, new PhyState(state.values+Beta40*k0.values+Beta41*k1.values+Beta42*k2.values+Beta43*k3.values), args, bargs, null);
            PhyStateDerivative k5 = ComputeDerivatives(t+S5*tstep, new PhyState(state.values+Beta50*k0.values+Beta51*k1.values+Beta52*k2.values+Beta53*k3.values+Beta54*k4.values), args, bargs, null);

            PhyState y4 = new PhyState(state.values+tstep*(C04*k0.values+C14*k1.values+C24*k2.values+C34*k3.values+C44*k4.values+C54*k5.values));
            PhyState y5 = new PhyState(state.values+tstep*(C05*k0.values+C15*k1.values+C25*k2.values+C35*k3.values+C45*k4.values+C55*k5.values));
            double errorV = Math.Abs((y4.v-y5.v)/(AbsVTol+RelVTol*Math.Abs(y5.v)));
            double newStep = Clamp(StepSafety * Math.Pow(errorV, -0.2), MinScale, MaxScale) * tstep;
            bool isValid = (errorV <= 1.0) || (newStep <= args.predict_min_step);  // If new step size is too small, we just accept the result.
            newStep = Clamp(newStep, args.predict_min_step, args.predict_max_step);
            return new Rk45StepResult { t = t + tstep, newStep = newStep, nextState = y5, errorV = errorV, isValid = isValid, Qdot = context.Qdot, acc = context.acc, dynp = context.dynp };
        }

        private static double Clamp(double value, double min, double max)
        {
            return Math.Max(min, Math.Min(max, value));
        }

        public static void GetFARAeroCoefs(double altitude, double AOA, double speed, out double Cd, out double Cl)
        {
            double atmHeight = FlightGlobals.ActiveVessel.mainBody.atmosphereDepth;
            double hs = GetScaleHeightAt(0);
            double area = FARAPI.ActiveVesselRefArea();
            if (altitude > atmHeight - hs) altitude = atmHeight - hs;
            Vessel vessel = FlightGlobals.ActiveVessel;
            Quaternion facing = vessel.ReferenceTransform.rotation * Quaternion.Euler(-90, 0, 0);
            Vector3 unitV = facing * Quaternion.Euler((float)(AOA * 180.0 / Math.PI), 0, 0) * Vector3.forward;
            Vector3 unitL = facing * Quaternion.Euler((float)(AOA * 180.0 / Math.PI - 90), 0, 0) * Vector3.forward;
            FARAPI.CalculateVesselAeroForces(vessel, out Vector3 forceVec, out _, unitV * (float)speed, altitude);
            double _factor = 0.5 * GetDensityAt(altitude) * speed * speed * area * 1e-3;
            Cd = -Vector3.Dot(forceVec, unitV) / _factor;
            Cl = Vector3.Dot(forceVec, unitL) / _factor;
            //Debug.Log($"[kOS-AFS] altitude={altitude * 1e-3:F2}km; AOA={AOA * 180 / Math.PI:F2}d; V={speed * 1e-3:F3}km/s; Cd={Cd:F3}; Cl={Cl:F3}");
            return;
        }

        public static double GetPressureAt(double altitude) { return FlightGlobals.ActiveVessel.mainBody.GetPressure(altitude) * 1e3; }
        public static double GetTemperatureAt(double altitude) { return FlightGlobals.ActiveVessel.mainBody.GetTemperature(altitude); }
        public static double GetDensityAt(double altitude)
        {
            if (altitude > FlightGlobals.ActiveVessel.mainBody.atmosphereDepth) return 0;
            double P = GetPressureAt(altitude);
            double T = GetTemperatureAt(altitude);
            if (T < 1e-3) T = 1e-3;
            double MW = FlightGlobals.ActiveVessel.mainBody.atmosphereMolarMass;
            return P * MW / (GAS_CONSTANT * T);
        }
        public static double GetScaleHeightAt(double altitude)
        {
            double r = altitude + FlightGlobals.ActiveVessel.mainBody.Radius;
            double g = FlightGlobals.ActiveVessel.mainBody.gravParameter / r / r;
            double T = GetTemperatureAt(altitude);
            double MW = FlightGlobals.ActiveVessel.mainBody.atmosphereMolarMass;
            return (GAS_CONSTANT * T)/(MW * g);
        }

        public static void InitAtmModel(SimAtmTrajArgs args)
        {
            // Set basic parameters
            args.R = FlightGlobals.ActiveVessel.mainBody.Radius;
            args.mu = FlightGlobals.ActiveVessel.mainBody.gravParameter;
            args.molarMass = FlightGlobals.ActiveVessel.mainBody.atmosphereMolarMass;
            args.atmHeight = FlightGlobals.ActiveVessel.mainBody.atmosphereDepth;
            // Sampling altitude, get density and temperatures
            const int nSamples = 21;
            double[] altSamples = new double[nSamples];
            double[] tempSamples = new double[nSamples];
            double[] logDensitySamples = new double[nSamples];
            double dAlt = (args.atmHeight - 1000) / (nSamples - 1);
            double P, T, D;
            for (int i = 0; i < nSamples; ++i)
            {
                altSamples[i] = i * dAlt;
                T = GetTemperatureAt(altSamples[i]);
                P = GetPressureAt(altSamples[i]);
                D = P * args.molarMass / (GAS_CONSTANT * T);
                tempSamples[i] = T;
                logDensitySamples[i] = Math.Log(D);
            }
            args.AtmAltSamples = altSamples;
            args.AltTempSamples = tempSamples;
            args.AtmLogDensitySamples = logDensitySamples;
        }

        public static double GetTemperatureEst(SimAtmTrajArgs args, double altitude)
        {
            int idx = FindUpperBound(args.AtmAltSamples, altitude);
            if (idx == 0)
            {
                return args.AltTempSamples[0];
            }
            else if (idx == args.AtmAltSamples.Length)
            {
                return args.AltTempSamples[args.AltTempSamples.Length - 1];
            }
            else
            {
                double t = (altitude - args.AtmAltSamples[idx - 1]) / (args.AtmAltSamples[idx] - args.AtmAltSamples[idx - 1]);
                return args.AltTempSamples[idx - 1] + t * (args.AltTempSamples[idx] - args.AltTempSamples[idx - 1]);
            }
        }

        public static double GetDensityEst(SimAtmTrajArgs args, double altitude)
        {
            if (altitude > args.atmHeight) return 0;
            int idx = FindUpperBound(args.AtmAltSamples, altitude);
            if (idx == 0)
            {
                double hs = GetScaleHeightEst(args, Math.Exp(args.AtmLogDensitySamples[0]), args.AltTempSamples[0]);
                return Math.Exp(args.AtmLogDensitySamples[0] - (args.AtmAltSamples[0] - altitude) / hs);
            }
            else if (idx == args.AtmAltSamples.Length)
            {
                double hs = GetScaleHeightEst(args, Math.Exp(args.AtmLogDensitySamples[args.AtmAltSamples.Length - 1]), args.AltTempSamples[args.AtmAltSamples.Length - 1]);
                return Math.Exp(args.AtmLogDensitySamples[args.AtmAltSamples.Length - 1] - (args.AtmAltSamples[args.AtmAltSamples.Length - 1] - altitude) / hs);
            }
            else
            {
                double t = (altitude - args.AtmAltSamples[idx - 1]) / (args.AtmAltSamples[idx] - args.AtmAltSamples[idx - 1]);
                return Math.Exp(args.AtmLogDensitySamples[idx - 1] + t * (args.AtmLogDensitySamples[idx] - args.AtmLogDensitySamples[idx - 1]));
            }
        }

        public static double GetScaleHeightEst(SimAtmTrajArgs args, double altitude, double? temperature = null)
        {
            if (temperature == null) temperature = GetTemperatureEst(args, altitude);
            double r = altitude + args.R;
            double g = args.mu / (r * r);
            return GAS_CONSTANT * (double)temperature / (args.molarMass * g);
        }
    }
}
