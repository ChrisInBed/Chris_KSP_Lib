using System;
using System.Linq;
using System.Collections.Generic;
using Unity.Burst;
using Unity.Mathematics;

namespace AFS
{    
    internal class SimAtmTrajArgs
    {
        public double mu, R, rho0, hs, mass, area, atmHeight, bank_max;
        public double[] Energysamples, Cdsamples, Clsamples, AOAsamples;
        public double k_QEGC, k_C, t_reg, Qdot_max, acc_max, dynp_max;
        public double L_min, target_energy;
        public double predict_max_step, predict_min_step, predict_tmax;
        public double predict_traj_dSqrtE;
        public SimAtmTrajArgs()
        {
            // initialize defaults (CEV configuration)
            mu = 3.98589e14;  // Earth
            R = 6.371e6;
            rho0 = 1.225;
            hs = 8500;
            mass = 6000;
            area = 12;
            atmHeight = 140e3;
            bank_max = 40.0 *Math.PI/180.0;
            Energysamples = new double[] { AFSCore.GetSpecificEnergy(mu, R+23e3, 600), AFSCore.GetSpecificEnergy(mu, R+140e3, 8000) };
            Cdsamples = new double[] { 1.28, 1.28 };
            Clsamples = new double[] { 0.39, 0.39 };
            AOAsamples = new double[] { 15.0*Math.PI/180.0, 15.0*Math.PI/180.0 };
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


		public class Context {
            public double G, L, D, Qdot, acc, dynp;
        }
        public static void GetAOABankCommand(PhyState state, SimAtmTrajArgs args, BankPlanArgs bargs, Context context, out double AOA, out double Bank)
        {
            double r = state.r;
            double v = SafeValue(Math.Abs(state.v));
            double gamma = state.gamma;
            double erg = GetSpecificEnergy(args.mu, r, v);

            // Interpolate for AOA command
            int idx = FindUpperBound(args.Energysamples, erg);
            if (idx == 0) AOA = args.AOAsamples[0];
            else if (idx == args.Energysamples.Length) AOA = args.AOAsamples[args.AOAsamples.Length - 1];
            else
            {
                double t = (v - args.Energysamples[idx - 1]) / (args.Energysamples[idx] - args.Energysamples[idx - 1]);
                AOA = args.AOAsamples[idx - 1] + t * (args.AOAsamples[idx] - args.AOAsamples[idx - 1]);
            }

            double energy = GetSpecificEnergy(args.mu, r, v);
            double bankBase = bargs.bank_f + (bargs.bank_i - bargs.bank_f) * (energy - bargs.energy_f) / (bargs.energy_i - bargs.energy_f);
            double G = args.mu / r / r;

            double rho = ComputeDensity(r, args);
            double aeroCoef = 0.5 * rho * v * v * args.area / args.mass;
            GetAeroCoefficients(args, v, out double Cd, out double Cl);
            double D = aeroCoef * Cd;
            double L = aeroCoef * Cl;

            context.G = G;
            context.L = L;
            context.D = D;

            if (L > args.L_min)
            {
                // QEGC correction
                double hdot = v * Math.Sin(gamma);
                double hdotQEGC = -2.0 * G / SafeValue(v/args.hs * Math.Cos(bankBase)) * (Cd / SafeValue(Cl));
                // Constraints correction
                double Qdot = HeatFluxCoefficient * Math.Pow(v, 3.15) * Math.Sqrt(rho);
                double v2 = v * v;
                double denomQdot = Math.Max(0.5 / args.hs + 3.15 * G / v2, 1e-6);
                double hdotQdot = -(args.Qdot_max / Math.Max(Qdot, 1e-6) - 1.0 + 3.15 * D * args.t_reg / v) / denomQdot / args.t_reg;

                double a = Math.Sqrt(L * L + D * D);
                double denomAcc = Math.Max(1.0 / args.hs + 2.0 * G / v2, 1e-6);
                double hdotAcc = -(args.acc_max / Math.Max(a, 1e-6) - 1.0 + 2.0 * D * args.t_reg / v) / denomAcc / args.t_reg;

                double q = rho * v * v / 2.0;
                double hdotDynP = -(args.dynp_max / Math.Max(q, 1e-6) - 1.0 + 2.0 * D * args.t_reg / v) / denomAcc / args.t_reg;

                double hdotC = Math.Max(Math.Max(hdot, hdotQdot), Math.Max(hdotAcc, hdotDynP));
                double vNorm = args.hs / 10;
                double cosArg = Math.Cos(bankBase) - args.k_QEGC / vNorm * (hdot - hdotQEGC) - args.k_C / vNorm * (hdot - hdotC);
                cosArg = Clamp(cosArg, Math.Cos(args.bank_max), 1.0);
                Bank = Math.Acos(cosArg);

                context.Qdot = Qdot;
                context.acc = a;
                context.dynp = q;
            }
            else
            {
                Bank = Clamp(bankBase, 0.0, args.bank_max);

                context.Qdot = 0;
                context.acc = 0;
                context.dynp = 0;
            }

            return;
        }

        public static PredictResult PredictTrajectory(double t, PhyState state, SimAtmTrajArgs args, BankPlanArgs bargs)
        {
            int nsteps = 0;
            double E = GetSpecificEnergy(args.mu, state.r, state.v);
            double Eold = E;
            double tmax = t + args.predict_tmax;
            double told = t;
            List<double> Eseq = new List<double>(); Eseq.Add(E);
            List<PhyState> stateSeq = new List<PhyState>(); stateSeq.Add(state);

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
                if (Math.Abs(Math.Sqrt(E-args.target_energy) - Math.Sqrt(Eold-args.target_energy)) > args.predict_traj_dSqrtE)
                {
                    Eseq.Add(E);
                    stateSeq.Add(state);
                    Eold = E;
                }
            }
            if (t >= tmax)
            {
                // Reaches maximum time
                return new PredictResult
                {
                    nsteps = nsteps,
                    t = t, finalState = state, status = PredictStatus.TIMEOUT,
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
				double rho = ComputeDensity(r, args);
				double aeroCoef = 0.5 * rho * v * v * args.area / args.mass;
				GetAeroCoefficients(args, v, out double Cd, out _);
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
            }
            PhyTraj traj = new PhyTraj();
            traj.Eseq = Eseq.ToArray();

            return new PredictResult
            {
                nsteps = nsteps,
                t = t, finalState = state, status = PredictStatus.COMPLETED,
				maxQdot = maxQdot, maxQdotTime = maxQdotTime,
				maxAcc = maxAcc, maxAccTime = maxAccTime,
				maxDynP = maxDynP, maxDynPTime = maxDynPTime
			};
        }

        public static double GetSpecificEnergy(double mu, double r, double v)
        {
            return -mu / r + 0.5 * v * v;
        }

        private static double ComputeDensity(double r, SimAtmTrajArgs args)
        {
            return args.rho0 * Math.Exp(-(r - args.R) / args.hs);
        }

        private static void GetAeroCoefficients(SimAtmTrajArgs args, double energy, out double Cd, out double Cl)
        {
            int idx = FindUpperBound(args.Energysamples, energy);
            if (idx == 0)
            {
                Cd = args.Cdsamples[0];
                Cl = args.Clsamples[0];
                return;
            }
            if (idx == args.Energysamples.Length)
            {
                Cd = args.Cdsamples[args.Cdsamples.Length - 1];
                Cl = args.Clsamples[args.Clsamples.Length - 1];
                return;
            }
            double t = (energy - args.Energysamples[idx - 1]) / (args.Energysamples[idx] - args.Energysamples[idx - 1]);
            Cd = args.Cdsamples[idx - 1] + t * (args.Cdsamples[idx] - args.Cdsamples[idx - 1]);
            Cl = args.Clsamples[idx - 1] + t * (args.Clsamples[idx] - args.Clsamples[idx - 1]);
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

			GetAOABankCommand(state, args, bargs, context, out _, out double bank);
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
    }
}
