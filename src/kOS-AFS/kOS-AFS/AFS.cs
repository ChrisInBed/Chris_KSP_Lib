using FerramAerospaceResearch;
using System;
using System.Collections.Generic;
using System.Security.Cryptography;
using Unity.Burst;
using Unity.Mathematics;
using UnityEngine;

namespace AFS
{    
    using PhyStateDerivative = PhyState;
    internal class SimAtmTrajArgs
    {
        // Celestial body parameters
        public double mu, R, molarMass, atmHeight;
        public double3 bodySpin;
        public double[] AtmAltSamples, AtmTempSamples, AtmLogDensitySamples;
        // Vessel parameters
        public double mass, area;
        public Quaternion rotation;
        public bool AOAReversal;
        public double[] CtrlSpeedSamples, CtrlAOAsamples;
        public double[] AeroSpeedSamples, AeroLogDensitySamples;
        public double[,] AeroCdSamples, AeroClSamples;
        // Target parameters
        public double target_energy;
        public double3 Rtarget;
        // Guidance parameters
        public double L_min, k_QEGC, k_C, t_lag, Qdot_max, acc_max, dynp_max;
        public double bank_max, heading_tol;
        public bool bank_reversal;
        public double predict_min_step, predict_max_step, predict_tmax;
        public double predict_traj_dSqrtE, predict_traj_dH;
        public SimAtmTrajArgs()
        {
            // Celestial body parameters
            mu = 3.98589e14;  // Earth
            R = 6.371e6;
            molarMass = 0.02897;
            atmHeight = 140e3;
            bodySpin = double3.zero;
            AtmAltSamples = new double[] { 0e3, 140e3 };
            AtmTempSamples = new double[] { 296.0, 220.0 };
            AtmLogDensitySamples = new double[] { Math.Log(1.2250), Math.Log(1.2250) - 140.0 / 8.5 };
            // Vessel parameters
            mass = 6000;
            area = 12;
            rotation = Quaternion.identity;
            AOAReversal = false;
            CtrlSpeedSamples = new double[] { 600, 8000 };
            CtrlAOAsamples = new double[] { 15.0*Math.PI/180.0, 15.0*Math.PI/180.0 };
            AeroSpeedSamples = new double[] { 3000 };
            AeroLogDensitySamples = new double[] { -0.5 };
            AeroClSamples = new double[,] { { 0.3 } };
            AeroCdSamples = new double[,] { { 1.5 } };
            // Target parameters
            target_energy = AFSCore.GetSpecificEnergy(mu, R+10e3, 300);
            Rtarget = new double3(R + 10e3, 0, 0);
            // Guidance parameters
            L_min = 0.5;
            k_QEGC = 1.0;
            k_C = 5.0;
            t_lag = 90;
            Qdot_max = 5e6;
            acc_max = 3 * 9.81;
            dynp_max = 15e3;
            bank_max = 70.0 *Math.PI/180.0;
            heading_tol = 10.0 *Math.PI/180.0;
            bank_reversal = false;
            predict_min_step = 0;
            predict_max_step = 1;
            predict_tmax = 3600;
            predict_traj_dSqrtE = 300.0;
            predict_traj_dH = 10e3;
        }
    }
    internal struct BankPlanArgs
    {
        public double bank_i, bank_f, energy_i, energy_f;
        public bool reversal;
        public static BankPlanArgs Default => new BankPlanArgs(
            20.0 * Math.PI / 180.0,
            10.0 * Math.PI / 180.0,
            AFSCore.GetSpecificEnergy(3.98589e14, 6.371e6 + 140e3, 8000),
            AFSCore.GetSpecificEnergy(3.98589e14, 6.371e6 + 10e3, 300),
            false
        );
        public BankPlanArgs(double bank_i, double bank_f, double energy_i, double energy_f, bool reversal)
        {
            this.bank_i = bank_i;
            this.bank_f = bank_f;
            this.energy_i = energy_i;
            this.energy_f = energy_f;
            this.reversal = reversal;
        }
    }

    [BurstCompile]
    internal struct PhyState
    {
        public double3 vecR;
        public double3 vecV;

        public static PhyState Default => new PhyState(
            double3.zero, double3.zero
        );

        public PhyState(double3 vecR, double3 vecV)
        {
            this.vecR = vecR;
            this.vecV = vecV;
        }

        public double r { get => math.length(vecR); }
        public double phi
        {
            get
            {
                double cosPhi = math.dot(math.normalizesafe(vecR), math.up());
                cosPhi = 0.5*math.PI - math.acos(math.clamp(cosPhi, -1, 1));
                return cosPhi;
            }
        }
        public double theta
        {
            get
            {
                double3 bodyY = new double3(0, 1, 0);
                double3 bodyZ = new double3(0, 0, 1);
                double3 vecR1 = math.normalizesafe(vecR - math.dot(vecR, bodyY) * bodyY);
                double angle = AFSCore.SignedAngle(bodyZ, vecR1, -bodyY);
                if (angle < 0) angle = math.PI * 2 + angle;
                return angle;
            }
        }
        public double v { get => math.length(vecV); }
        public double gamma
        {
            get
            {
                if (v < 1e-6) return 0;
                double vr = math.dot(vecV, math.normalize(vecR));
                return math.asin(math.clamp(vr / v, -1, 1));
            }
        }
        public double psi
        {
            get
            {
                double3 localUp = math.normalizesafe(vecR);
                double3 localForward = vecV - math.dot(vecV, localUp) * localUp;
                double _l = math.length(localForward);
                if (_l < 1e-6) return 0;
                localForward = localForward / _l;
                double3 bodyNorth = new double3(0, 1, 0);
                double3 localNorth = bodyNorth - math.dot(bodyNorth, localUp) * localUp;
                _l = math.length(localNorth);
                if (_l < 1e-6) return math.dot(bodyNorth, localUp) > 0 ? 0 : math.PI;
                localNorth = localNorth / _l;
                return AFSCore.SignedAngle(localNorth, localForward, localUp);
            }
        }

        public static PhyState operator+(PhyState a, PhyState b)
        {
            return new PhyState(a.vecR + b.vecR, a.vecV + b.vecV);
        }
        public static PhyState operator*(double scalar, PhyState state)
        {
            return new PhyState(scalar * state.vecR, scalar * state.vecV);
        }
        public static PhyState operator *(PhyState state, double scalar)
        {
            return new PhyState(scalar * state.vecR, scalar * state.vecV);
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
        public const double HeatFluxCoefficient = 9.4369e-5;
        private const double AbsVTol = 0;
        private const double RelVTol = 1e-6;
        private const double StepSafety = 0.9;
        private const double MinScale = 0.2;
        private const double MaxScale = 5.0;
        // RKF45 constants
        private const double C04 = 25.0 / 216.0, C05 = 16.0 / 135.0;
        private const double S1 = 1.0 / 4.0, Beta10 = 1.0 / 4.0, C14 = 0.0, C15 = 0.0;
        private const double S2 = 3.0 / 8.0, Beta20 = 3.0 / 32.0, Beta21 = 9.0 / 32.0, C24 = 1408.0 / 2565.0, C25 = 6656.0 / 12825.0;
        private const double S3 = 12.0 / 13.0, Beta30 = 1932.0 / 2197.0, Beta31 = -7200.0 / 2197.0, Beta32 = 7296.0 / 2197.0, C34 = 2197.0 / 4104.0, C35 = 28561.0 / 56430.0;
        private const double S4 = 1.0, Beta40 = 439.0 / 216.0, Beta41 = -8.0, Beta42 = 3680.0 / 513.0, Beta43 = -845.0 / 4104.0, C44 = -1.0 / 5.0, C45 = -9.0 / 50.0;
        private const double S5 = 1.0 / 2.0, Beta50 = -8.0 / 27.0, Beta51 = 2.0, Beta52 = -3544.0 / 2565.0, Beta53 = 1859.0 / 4104.0, Beta54 = -11.0 / 40.0, C54 = 0.0, C55 = 2.0 / 55.0;
        // Simulation constants
        private const double ENERGY_ERR_TOL = 1;
        // Atmospheric model constants
        private const double GAS_CONSTANT = 8.314462618; // J/(mol·K)

        public class Context
        {
            public double G, L, D, Qdot, acc, dynp;
            public double bank;
        }
        public static double GetBankCommand(PhyState state, SimAtmTrajArgs args, BankPlanArgs bargs, Context context)
        {
            double r = state.r;
            double v = state.v;
            double gamma = state.gamma;
            double energy = GetSpecificEnergy(args.mu, r, v);
            double bankBase = bargs.bank_f + (bargs.bank_i - bargs.bank_f) * (energy - bargs.energy_f) / (bargs.energy_i - bargs.energy_f);
            double G = args.mu / r / r;

            double logRho = GetLogDensityEst(args, r - args.R);
            double rho = Math.Exp(logRho);
            double aeroCoef = 0.5 * rho * v * v * args.area / args.mass;
            GetAeroCoefficients(args, v, logRho, out double Cd, out double Cl);
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
                double hdotQEGC = -2.0 * G / SafeValue(v / hs * Math.Cos(bankBase)) * (Cd / SafeValue(Cl));
                // Constraints correction
                double Qdot = HeatFluxCoefficient * Math.Pow(v, 3.15) * Math.Sqrt(rho);
                double v2 = v * v;
                double denomQdot = Math.Max(0.5 / hs + 3.15 * G / v2, 1e-6);
                double hdotQdot = -(args.Qdot_max / Math.Max(Qdot, 1e-6) - 1.0 + 3.15 * D * args.t_lag / v) / denomQdot / args.t_lag;

                double a = Math.Sqrt(L * L + D * D);
                double denomAcc = Math.Max(1.0 / hs + 2.0 * G / v2, 1e-6);
                double hdotAcc = -(args.acc_max / Math.Max(a, 1e-6) - 1.0 + 2.0 * D * args.t_lag / v) / denomAcc / args.t_lag;

                double q = rho * v * v / 2.0;
                double hdotDynP = -(args.dynp_max / Math.Max(q, 1e-6) - 1.0 + 2.0 * D * args.t_lag / v) / denomAcc / args.t_lag;

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

            if (bargs.reversal) Bank = -Bank;

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

        public static PhyState GetPhyState()
        {
            Vessel _vessel = FlightGlobals.ActiveVessel;
            Vector3d vecR = _vessel.CurrentPosition() - _vessel.mainBody.position;
            Vector3d vecV = _vessel.srf_velocity;
            return new PhyState(
                new double3(vecR.x, vecR.y, vecR.z),
                new double3(vecV.x, vecV.y, vecV.z)
            );
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
            double maxQdot = -1, maxQdotTime = -1;
            double maxAcc = -1, maxAccTime = -1;
            double maxDynP = -1, maxDynPTime = -1;
            double tstep = args.predict_max_step;
            Rk45StepResult result;
            Context context = new Context();
            while (t < tmax)
            {
                ++nsteps;
                result = RK45Step(t, state, tstep, args, bargs, context);
                while (!result.isValid)
                {
                    result = RK45Step(t, state, result.newStep, args, bargs, null);
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
                if (Math.Abs(Math.Sqrt(E - args.target_energy) - Math.Sqrt(Eold - args.target_energy)) > args.predict_traj_dSqrtE || Math.Abs(state.r - Rold) > args.predict_traj_dH)
                {
                    Eseq.Add(E);
                    stateSeq.Add(state);
                    AOA = GetAOACommand(state, args);
                    AOAseq.Add(AOA);
                    Bankseq.Add(context.bank);
                    Eold = E;
                    Rold = state.r;
                }
                // Bank reversal
                double headingErr = GetHeadingErr(state.vecR, state.vecV, args.Rtarget);
                if (math.abs(headingErr) > args.heading_tol || math.abs(context.bank) < math.radians(0.01))
                    bargs.reversal = headingErr > 0;
            }
            if (t >= tmax)
            {
                // Reaches maximum time
                return new PredictResult
                {
                    nsteps = nsteps,
                    t = t,
                    finalState = state,
                    traj = new PhyTraj { Eseq = Eseq.ToArray(), states = stateSeq.ToArray(), AOAseq = AOAseq.ToArray(), Bankseq = Bankseq.ToArray() },
                    status = PredictStatus.TIMEOUT,
                    maxQdot = maxQdot,
                    maxQdotTime = maxQdotTime,
                    maxAcc = maxAcc,
                    maxAccTime = maxAccTime,
                    maxDynP = maxDynP,
                    maxDynPTime = maxDynPTime
                };
            }
            // Reaches terminal energy condition, Newton-Raphson method to find the root
            int numiter = 0;
            while (numiter < 40)
            {
                double r = state.r;
                double v = state.v;
                double gamma = state.gamma;
                double Err = GetSpecificEnergy(args.mu, r, v) - args.target_energy;
                if (Math.Abs(Err) < ENERGY_ERR_TOL) break;

                double G = args.mu / (r * r);
                double logRho = GetLogDensityEst(args, r - args.R);
                double rho = Math.Exp(logRho);
                double aeroCoef = 0.5 * rho * v * v * args.area / args.mass;
                GetAeroCoefficients(args, v, logRho, out double Cd, out _);
                double D = aeroCoef * Cd;

                double rdot = v * Math.Sin(gamma);
                double vdot = -D - G * Math.Sin(gamma);
                double Edot = args.mu / r / r * rdot + v * vdot;

                t -= Err / Edot;
                result = RK45Step(told, stateold, t - told, args, bargs, context);
                state = result.nextState;

                ++numiter;
            }
            E = GetSpecificEnergy(args.mu, state.r, state.v);
            if (E < Eold)
            {
                Eseq.Add(E);
                stateSeq.Add(state);
                AOA = GetAOACommand(state, args);
                AOAseq.Add(AOA);
                Bankseq.Add(context.bank);
            }
            return new PredictResult
            {
                nsteps = nsteps,
                t = t,
                finalState = state,
                traj = new PhyTraj { Eseq = Eseq.ToArray(), states = stateSeq.ToArray(), AOAseq = AOAseq.ToArray(), Bankseq = Bankseq.ToArray() },
                status = PredictStatus.COMPLETED,
                maxQdot = maxQdot,
                maxQdotTime = maxQdotTime,
                maxAcc = maxAcc,
                maxAccTime = maxAccTime,
                maxDynP = maxDynP,
                maxDynPTime = maxDynPTime
            };
        }

        public static double GetSpecificEnergy(double mu, double r, double v)
        {
            return -mu / r + 0.5 * v * v;
        }

        public static void GetAeroCoefficients(SimAtmTrajArgs args, double speed, double logDensity, out double Cd, out double Cl)
        {
            // Bilinear interpolation for aerodynamic coefficients
            int nV = args.AeroSpeedSamples.Length;
            int nD = args.AeroLogDensitySamples.Length;
            int idxV = FindUpperBound(args.AeroSpeedSamples, speed);
            int idxD = FindUpperBound(args.AeroLogDensitySamples, logDensity);
            double w00, w01, w10, w11;
            if (idxV == 0) { w00 = 0; w01 = 0; w10 = 1; w11 = 1; }
            else if (idxV == nV) { w00 = 1; w01 = 1; w10 = 0; w11 = 0; }
            else
            {
                double tV = (speed - args.AeroSpeedSamples[idxV - 1]) / (args.AeroSpeedSamples[idxV] - args.AeroSpeedSamples[idxV - 1]);
                w00 = 1 - tV; w10 = tV;
                w01 = 1 - tV; w11 = tV;
            }
            if (idxD == 0) { w00 = 0; w10 = 0; }
            else if (idxD == nD) { w01 = 0; w11 = 0; }
            else
            {
                double tD = (logDensity - args.AeroLogDensitySamples[idxD - 1]) / (args.AeroLogDensitySamples[idxD] - args.AeroLogDensitySamples[idxD - 1]);
                w00 *= (1 - tD); w01 *= tD;
                w10 *= (1 - tD); w11 *= tD;
            }
            int x0 = Math.Max(0, idxV - 1), x1 = Math.Min(nV - 1, idxV);
            int y0 = Math.Max(0, idxD - 1), y1 = Math.Min(nD - 1, idxD);
            Cd = w00 * args.AeroCdSamples[x0, y0] + w01 * args.AeroCdSamples[x0, y1] + w10 * args.AeroCdSamples[x1, y0] + w11 * args.AeroCdSamples[x1, y1];
            Cl = w00 * args.AeroClSamples[x0, y0] + w01 * args.AeroClSamples[x0, y1] + w10 * args.AeroClSamples[x1, y0] + w11 * args.AeroClSamples[x1, y1];
            return;
        }

        private static int FindUpperBound(double[] xs, double x, IComparer<double> comparer = null)
        {
            if (xs == null || xs.Length == 0) return 0;
            // Assume xs is sorted: binary search
            int idx = Array.BinarySearch(xs, x, comparer);
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

        [BurstCompile]
        private static PhyStateDerivative ComputeDerivatives(double t, PhyState state, SimAtmTrajArgs args, BankPlanArgs bargs, Context context)
        {
            if (context == null) context = new Context();
            double bank = GetBankCommand(state, args, bargs, context);
            context.bank = bank;
            double3 localUp = math.normalize(state.vecR);
            double3 G = -context.G * localUp;
            double3 D = double3.zero;
            double3 L = double3.zero;
            if (state.v > 1e-6)
            {
                double3 unitWindForward = math.normalize(state.vecV);
                double3 unitWindRight = math.cross(localUp, unitWindForward);
                double _l = math.length(unitWindRight);
                if (_l < 1e-12) unitWindRight = math.normalize(math.cross(math.forward(), unitWindForward));
                else unitWindRight = unitWindRight / _l;
                double3 unitWindUp = math.cross(unitWindForward, unitWindRight);
                D = -context.D * unitWindForward;
                L = context.L * (math.cos(bank) * unitWindUp + math.sin(bank) * unitWindRight);
            }
            double3 COR = -2 * math.cross(args.bodySpin, state.vecV);
            double3 CEN = -math.cross(args.bodySpin, math.cross(args.bodySpin, state.vecR));
            double3 acc = G + D + L + COR + CEN;
            return new PhyStateDerivative(state.vecV, acc);
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
        private static Rk45StepResult RK45Step(double t, PhyState state, double tstep, SimAtmTrajArgs args, BankPlanArgs bargs, Context context)
        {
            if (context == null) context = new Context();
            PhyStateDerivative k0 = ComputeDerivatives(t, state, args, bargs, context);
            PhyStateDerivative k1 = ComputeDerivatives(t + S1 * tstep, state + Beta10 * k0, args, bargs, null);
            PhyStateDerivative k2 = ComputeDerivatives(t + S2 * tstep, state + Beta20 * k0 + Beta21 * k1, args, bargs, null);
            PhyStateDerivative k3 = ComputeDerivatives(t + S3 * tstep, state + Beta30 * k0 + Beta31 * k1 + Beta32 * k2, args, bargs, null);
            PhyStateDerivative k4 = ComputeDerivatives(t + S4 * tstep, state + Beta40 * k0 + Beta41 * k1 + Beta42 * k2 + Beta43 * k3, args, bargs, null);
            PhyStateDerivative k5 = ComputeDerivatives(t + S5 * tstep, state + Beta50 * k0 + Beta51 * k1 + Beta52 * k2 + Beta53 * k3 + Beta54 * k4, args, bargs, null);

            PhyState y4 = state + tstep * (C04 * k0 + C14 * k1 + C24 * k2 + C34 * k3 + C44 * k4 + C54 * k5);
            PhyState y5 = state + tstep * (C05 * k0 + C15 * k1 + C25 * k2 + C35 * k3 + C45 * k4 + C55 * k5);
            double errorV = Math.Abs((y4.v - y5.v) / (AbsVTol + RelVTol * Math.Abs(y5.v)));
            double newStep = Clamp(StepSafety * Math.Pow(errorV, -0.2), MinScale, MaxScale) * tstep;
            bool isValid = (errorV <= 1.0) || (newStep <= args.predict_min_step);  // If new step size is too small, we just accept the result.
            newStep = Clamp(newStep, args.predict_min_step, args.predict_max_step);
            return new Rk45StepResult { t = t + tstep, newStep = newStep, nextState = y5, errorV = errorV, isValid = isValid, Qdot = context.Qdot, acc = context.acc, dynp = context.dynp };
        }

        private static double Clamp(double value, double min, double max)
        {
            return Math.Max(min, Math.Min(max, value));
        }

        public static float SignedAngle(Vector3 from, Vector3 to, Vector3 axis)
        {
            Vector3 cross = Vector3.Cross(from, to);
            float dot = Vector3.Dot(from, to);
            float angle = Mathf.Atan2(cross.magnitude, dot);
            if (Vector3.Dot(axis, cross) < 0.0f)
                angle = -angle;
            return angle;
        }

        [BurstCompile]
        public static double SignedAngle(double3 from, double3 to, double3 axis)
        {
            double3 cross = math.cross(from, to);
            double dot = math.dot(from, to);
            double angle = math.atan2(math.length(cross), dot);
            if (math.dot(axis, cross) < 0.0)
                angle = -angle;
            return angle;
        }

        [BurstCompile]
        public static double GetHeadingErr(double3 vecR, double3 vecV, double3 vecRtgt)
        {
            if (math.length(vecV) < 1e-6) return 0;
            double3 unitV = math.normalize(vecV);
            double3 unitR = math.normalize(vecR);
            double3 unitH = math.cross(unitR, unitV);
            double _l = math.length(unitH);
            if (_l < 1e-8) return 0;
            unitH = unitH / _l;
            double3 unitRtgt = math.normalize(vecRtgt);
            double3 unitHRef = math.cross(unitR, unitRtgt);
            _l = math.length(unitHRef);
            if (_l < 1e-8) return 0;
            unitHRef = unitHRef / _l;
            // If the target is faraway behind, flip the reference heading vector
            // To track a major arc rather than the minor arc
            if (math.dot(unitR, unitRtgt) < 0.94 && math.dot(unitHRef, unitH) < 0) unitHRef = -unitHRef;

            return SignedAngle(unitHRef, unitH, unitR);
        }

        public static double GetFARAOA(Vector3d vel, Quaternion rot, bool AOAReversal)
        {
            Quaternion facing = FlightGlobals.ActiveVessel.ReferenceTransform.rotation * Quaternion.Euler(-90, 0, 0) * rot;
            Vector3 forward = facing * Vector3.forward;
            Vector3 down = facing * (-Vector3.up);
            //Vector3 right = facing * Vector3.right;
            //velocity vector projected onto a plane that divides the airplane into left and right halves
            Vector3 tmpVec = forward * Vector3.Dot(forward, vel) + down * Vector3.Dot(down, vel);
            double AOA = Math.Asin(Vector3.Dot(tmpVec.normalized, down));
            if (double.IsNaN(AOA)) AOA = 0;
            return AOAReversal ? -AOA : AOA;
        }

        public static double GetFARAOS(Vector3d vel, Quaternion rot)
        {
            Quaternion facing = FlightGlobals.ActiveVessel.ReferenceTransform.rotation * Quaternion.Euler(-90, 0, 0) * rot;
            Vector3 forward = facing * Vector3.forward;
            //Vector3 down = facing * (-Vector3.up);
            Vector3 right = facing * Vector3.right;
            //velocity vector projected onto the vehicle-horizontal plane
            Vector3 tmpVec = forward * Vector3.Dot(forward, vel) + right * Vector3.Dot(right, vel);
            double AOS = Math.Asin(Vector3.Dot(tmpVec.normalized, right));
            if (double.IsNaN(AOS)) AOS = 0;
            return AOS;
        }

        public static double GetFARRoll(Quaternion rot)
        {
            Vessel _vessel = FlightGlobals.ActiveVessel;
            Quaternion facing = _vessel.ReferenceTransform.rotation * Quaternion.Euler(-90, 0, 0) * rot;
            Vector3 forward = facing * Vector3.forward;
            //Vector3 down = facing * (-Vector3.up);
            Vector3 right = facing * Vector3.right;
            Vector3 localUp = (_vessel.transform.position - _vessel.mainBody.transform.position).normalized;
            double Roll = SignedAngle(Vector3.Cross(localUp, forward).normalized, right, -forward);
            return Roll;
        }

        public static double GetFARBank(Quaternion rot)
        {
            Vessel _vessel = FlightGlobals.ActiveVessel;
            Quaternion facing = _vessel.ReferenceTransform.rotation * Quaternion.Euler(-90, 0, 0) * rot;
            Vector3 localUp = (_vessel.transform.position - _vessel.mainBody.transform.position).normalized;
            Vector3 windForward = _vessel.srf_velocity.normalized;
            Vector3 windRight = Vector3.Cross(localUp, windForward).normalized;
            Vector3 windUp = Vector3.Cross(windForward, windRight).normalized;
            Vector3 bankVec = facing * Vector3.up;
            bankVec = bankVec - Vector3.Dot(bankVec, windForward) * windForward;
            double Bank = SignedAngle(windUp, bankVec.normalized, -windForward);
            return Bank;
        }

        public static void GetFARAeroCoefs(double altitude, double AOA, double speed, out double Cd, out double Cl, Quaternion rot, bool AOAReversal)
        {
            if (AOAReversal) AOA = -AOA;
            if (rot == null) rot = Quaternion.identity;
            double atmHeight = FlightGlobals.ActiveVessel.mainBody.atmosphereDepth;
            double hs = GetScaleHeightAt(0);
            double area = FARAPI.ActiveVesselRefArea();
            if (altitude > atmHeight - hs) altitude = atmHeight - hs;
            Vessel vessel = FlightGlobals.ActiveVessel;
            Quaternion facing = vessel.ReferenceTransform.rotation * Quaternion.Euler(-90, 0, 0) * rot;
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
            return (GAS_CONSTANT * T) / (MW * g);
        }

        public static void InitAtmModel(SimAtmTrajArgs args)
        {
            // Set basic parameters
            args.R = FlightGlobals.ActiveVessel.mainBody.Radius;
            args.mu = FlightGlobals.ActiveVessel.mainBody.gravParameter;
            args.molarMass = FlightGlobals.ActiveVessel.mainBody.atmosphereMolarMass;
            args.atmHeight = FlightGlobals.ActiveVessel.mainBody.atmosphereDepth;
            args.bodySpin = Vector3dToDouble3(FlightGlobals.ActiveVessel.mainBody.angularVelocity);
            // Sampling altitude, get density and temperatures
            const int nSamples = 129;
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
            args.AtmTempSamples = tempSamples;
            args.AtmLogDensitySamples = logDensitySamples;
        }

        public static double GetTemperatureEst(SimAtmTrajArgs args, double altitude)
        {
            int idx = FindUpperBound(args.AtmAltSamples, altitude);
            if (idx == 0)
            {
                return args.AtmTempSamples[0];
            }
            else if (idx == args.AtmAltSamples.Length)
            {
                return args.AtmTempSamples[args.AtmTempSamples.Length - 1];
            }
            else
            {
                double t = (altitude - args.AtmAltSamples[idx - 1]) / (args.AtmAltSamples[idx] - args.AtmAltSamples[idx - 1]);
                return args.AtmTempSamples[idx - 1] + t * (args.AtmTempSamples[idx] - args.AtmTempSamples[idx - 1]);
            }
        }

        public static double GetLogDensityEst(SimAtmTrajArgs args, double altitude)
        {
            int idx = FindUpperBound(args.AtmAltSamples, altitude);
            if (idx == 0)
            {
                double hs = GetScaleHeightEst(args, args.AtmAltSamples[0], args.AtmTempSamples[0]);
                return args.AtmLogDensitySamples[0] - (altitude - args.AtmAltSamples[0]) / hs;
            }
            else if (idx == args.AtmAltSamples.Length)
            {
                double hs = GetScaleHeightEst(args, args.AtmAltSamples[args.AtmAltSamples.Length - 1], args.AtmTempSamples[args.AtmAltSamples.Length - 1]);
                return args.AtmLogDensitySamples[args.AtmAltSamples.Length - 1] - (altitude - args.AtmAltSamples[args.AtmAltSamples.Length - 1]) / hs;
            }
            else
            {
                double t = (altitude - args.AtmAltSamples[idx - 1]) / (args.AtmAltSamples[idx] - args.AtmAltSamples[idx - 1]);
                return args.AtmLogDensitySamples[idx - 1] + t * (args.AtmLogDensitySamples[idx] - args.AtmLogDensitySamples[idx - 1]);
            }
        }

        public static double GetDensityEst(SimAtmTrajArgs args, double altitude)
        {
            if (altitude > args.atmHeight) return 0;
            return Math.Exp(GetLogDensityEst(args, altitude));
        }

        public static double GetHeightEst(SimAtmTrajArgs args, double density)
        {
            if ((!Double.IsFinite(density)) || (density <= 0)) return args.atmHeight;
            // Find the altitude that corresponds to the given density via interpolation
            double logD = Math.Log(density);
            int idx = FindUpperBound(args.AtmLogDensitySamples, logD, Comparer<double>.Create((a, b) => b.CompareTo(a)));
            if (idx == 0)
            {
                double hs = GetScaleHeightEst(args, args.AtmAltSamples[0], args.AtmTempSamples[0]);
                return args.AtmAltSamples[0] - hs * (logD - args.AtmLogDensitySamples[0]);
            }
            else if (idx == args.AtmLogDensitySamples.Length)
            {
                double hs = GetScaleHeightEst(args, args.AtmAltSamples[args.AtmAltSamples.Length - 1], args.AtmTempSamples[args.AtmAltSamples.Length - 1]);
                return args.AtmAltSamples[args.AtmAltSamples.Length - 1] - hs * (logD -args.AtmLogDensitySamples[args.AtmAltSamples.Length - 1]);
            }
            else
            {
                double t = (logD - args.AtmLogDensitySamples[idx - 1]) / (args.AtmLogDensitySamples[idx] - args.AtmLogDensitySamples[idx - 1]);
                return args.AtmAltSamples[idx - 1] + t * (args.AtmAltSamples[idx] - args.AtmAltSamples[idx - 1]);
            }
        }

        public static double GetScaleHeightEst(SimAtmTrajArgs args, double altitude, double? temperature = null)
        {
            if (temperature == null) temperature = GetTemperatureEst(args, altitude);
            double r = altitude + args.R;
            double g = args.mu / (r * r);
            return GAS_CONSTANT * (double)temperature / (args.molarMass * g);
        }

        public static double GetSafeDouble(double value)
        {
            return Double.IsFinite(value) ? value : 0.0;
        }

        public static Vector3d Double3ToVector3d(double3 v)
        {
            return new Vector3d(v.x, v.y, v.z);
        }

        public static double3 Vector3dToDouble3(Vector3d v)
        {
            return new double3(v.x, v.y, v.z);
        }
    }
}
