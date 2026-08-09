using FerramAerospaceResearch;
using System;
using System.Collections.Generic;
using Unity.Mathematics;
using UnityEngine;

namespace LTR
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
        public double[] CtrlSpeedSamples, CtrlAOASamples;
        public double[] AeroSpeedSamples, AeroLogDensitySamples;
        public double[,] AeroCdSamples, AeroClSamples;

        // Target parameters
        public double targetAltitude;
        public double3 RTarget;

        // Guidance parameters
        public double predictMinStep, predictMaxStep, predictTMax;

        public SimAtmTrajArgs()
        {
            mu = 3.98589e14;
            R = 6.371e6;
            molarMass = 0.02897;
            atmHeight = 140e3;
            bodySpin = double3.zero;
            AtmAltSamples = new[] { 0.0, 140e3 };
            AtmTempSamples = new[] { 296.0, 220.0 };
            AtmLogDensitySamples = new[] { Math.Log(1.2250), Math.Log(1.2250) - 140.0 / 8.5 };

            mass = 6000;
            area = 12;
            rotation = Quaternion.identity;
            AOAReversal = false;
            CtrlSpeedSamples = new[] { 0.0, 8000.0 };
            CtrlAOASamples = new[] { 0.0, 0.0 };
            AeroSpeedSamples = new[] { 3000.0 };
            AeroLogDensitySamples = new[] { -0.5 };
            AeroCdSamples = new[,] { { 1.5 } };
            AeroClSamples = new[,] { { 0.0 } };

            targetAltitude = 0;
            RTarget = new double3(R, 0, 0);
            predictMinStep = 0.001;
            predictMaxStep = 0.5;
            predictTMax = 1200;
        }

        public SimAtmTrajArgs Clone()
        {
            return new SimAtmTrajArgs
            {
                mu = mu,
                R = R,
                molarMass = molarMass,
                atmHeight = atmHeight,
                bodySpin = bodySpin,
                AtmAltSamples = AtmAltSamples == null ? null : (double[])AtmAltSamples.Clone(),
                AtmTempSamples = AtmTempSamples == null ? null : (double[])AtmTempSamples.Clone(),
                AtmLogDensitySamples = AtmLogDensitySamples == null ? null : (double[])AtmLogDensitySamples.Clone(),
                mass = mass,
                area = area,
                rotation = rotation,
                AOAReversal = AOAReversal,
                CtrlSpeedSamples = CtrlSpeedSamples == null ? null : (double[])CtrlSpeedSamples.Clone(),
                CtrlAOASamples = CtrlAOASamples == null ? null : (double[])CtrlAOASamples.Clone(),
                AeroSpeedSamples = AeroSpeedSamples == null ? null : (double[])AeroSpeedSamples.Clone(),
                AeroLogDensitySamples = AeroLogDensitySamples == null ? null : (double[])AeroLogDensitySamples.Clone(),
                AeroCdSamples = AeroCdSamples == null ? null : (double[,])AeroCdSamples.Clone(),
                AeroClSamples = AeroClSamples == null ? null : (double[,])AeroClSamples.Clone(),
                targetAltitude = targetAltitude,
                RTarget = RTarget,
                predictMinStep = predictMinStep,
                predictMaxStep = predictMaxStep,
                predictTMax = predictTMax
            };
        }
    }

    internal struct PhyState
    {
        public double3 vecR;
        public double3 vecV;

        public PhyState(double3 vecR, double3 vecV)
        {
            this.vecR = vecR;
            this.vecV = vecV;
        }

        public double r => math.length(vecR);
        public double v => math.length(vecV);

        public static PhyState operator +(PhyState a, PhyState b)
        {
            return new PhyState(a.vecR + b.vecR, a.vecV + b.vecV);
        }

        public static PhyState operator *(double scalar, PhyState state)
        {
            return new PhyState(scalar * state.vecR, scalar * state.vecV);
        }

        public static PhyState operator *(PhyState state, double scalar)
        {
            return scalar * state;
        }
    }

    internal enum PredictStatus
    {
        COMPLETED,
        TIMEOUT,
        FAILED,
        OVERSHOOT
    }

    internal class PredictResult
    {
        public int nsteps;
        public double t;
        public PhyState finalState;
        public PredictStatus status;
    }

    internal class LTRCore
    {
        private const double AbsVTol = 1e-6;
        private const double RelVTol = 1e-6;
        private const double StepSafety = 0.9;
        private const double MinScale = 0.2;
        private const double MaxScale = 5.0;
        private const double AltitudeTolerance = 0.01;
        private const double GasConstant = 8.314462618;

        // Fehlberg 4(5) constants. Their layout intentionally matches kOS-AFS.
        private const double C04 = 25.0 / 216.0, C05 = 16.0 / 135.0;
        private const double S1 = 1.0 / 4.0, Beta10 = 1.0 / 4.0, C14 = 0.0, C15 = 0.0;
        private const double S2 = 3.0 / 8.0, Beta20 = 3.0 / 32.0, Beta21 = 9.0 / 32.0, C24 = 1408.0 / 2565.0, C25 = 6656.0 / 12825.0;
        private const double S3 = 12.0 / 13.0, Beta30 = 1932.0 / 2197.0, Beta31 = -7200.0 / 2197.0, Beta32 = 7296.0 / 2197.0, C34 = 2197.0 / 4104.0, C35 = 28561.0 / 56430.0;
        private const double S4 = 1.0, Beta40 = 439.0 / 216.0, Beta41 = -8.0, Beta42 = 3680.0 / 513.0, Beta43 = -845.0 / 4104.0, C44 = -1.0 / 5.0, C45 = -9.0 / 50.0;
        private const double S5 = 1.0 / 2.0, Beta50 = -8.0 / 27.0, Beta51 = 2.0, Beta52 = -3544.0 / 2565.0, Beta53 = 1859.0 / 4104.0, Beta54 = -11.0 / 40.0, C54 = 0.0, C55 = 2.0 / 55.0;

        internal class Context
        {
            public double AOA, density, Cd, Cl, drag, lift;
        }

        public static double GetAOACommand(PhyState state, SimAtmTrajArgs args)
        {
            int idx = FindUpperBound(args.CtrlSpeedSamples, state.v);
            if (idx == 0) return args.CtrlAOASamples[0];
            if (idx == args.CtrlSpeedSamples.Length) return args.CtrlAOASamples[args.CtrlAOASamples.Length - 1];

            double t = (state.v - args.CtrlSpeedSamples[idx - 1])
                / (args.CtrlSpeedSamples[idx] - args.CtrlSpeedSamples[idx - 1]);
            return args.CtrlAOASamples[idx - 1]
                + t * (args.CtrlAOASamples[idx] - args.CtrlAOASamples[idx - 1]);
        }

        public static PhyState GetPhyState(Vessel vessel)
        {
            Vector3d vecR = vessel.CoMD - vessel.mainBody.position;
            Vector3d vecV = vessel.srf_velocity;
            return new PhyState(Vector3dToDouble3(vecR), Vector3dToDouble3(vecV));
        }

        public static PredictResult PredictTrajectory(double t, PhyState state, SimAtmTrajArgs args)
        {
            ValidateSimulationArgs(args);
            double targetRadius = args.R + args.targetAltitude;
            double initialError = state.r - targetRadius;
            if (!IsFinite(state) || state.r < 1.0)
                return MakeResult(0, t, state, PredictStatus.FAILED);
            if (initialError < -AltitudeTolerance)
                return MakeResult(0, t, state, PredictStatus.OVERSHOOT);
            if (Math.Abs(initialError) <= AltitudeTolerance && math.dot(state.vecR, state.vecV) <= 0)
                return MakeResult(0, t, state, PredictStatus.COMPLETED);

            int nsteps = 0;
            double tmax = t + args.predictTMax;
            double tstep = args.predictMaxStep;
            double told = t;
            PhyState stateOld = state;
            Rk45StepResult stepResult = default(Rk45StepResult);

            while (t < tmax)
            {
                ++nsteps;
                tstep = Math.Min(tstep, tmax - t);
                stepResult = RK45Step(t, state, tstep, args, null);
                int rejectedSteps = 0;
                while (!stepResult.isValid && rejectedSteps < 50)
                {
                    tstep = stepResult.newStep;
                    stepResult = RK45Step(t, state, tstep, args, null);
                    ++rejectedSteps;
                }
                if (!stepResult.isValid || !IsFinite(stepResult.nextState))
                    return MakeResult(nsteps, t, state, PredictStatus.FAILED);

                told = t;
                stateOld = state;
                t = stepResult.t;
                state = stepResult.nextState;
                tstep = stepResult.newStep;

                if (state.r <= targetRadius) break;
            }

            if (state.r > targetRadius)
                return MakeResult(nsteps, t, state, PredictStatus.TIMEOUT);

            // Newton iteration within the last accepted RKF45 step finds the
            // target-altitude crossing without forcing all integration steps small.
            double lowerTime = told;
            double upperTime = t;
            PhyState rootState = state;
            double rootTime = t;
            for (int iteration = 0; iteration < 24; ++iteration)
            {
                double error = rootState.r - targetRadius;
                if (Math.Abs(error) <= AltitudeTolerance) break;

                double radialVelocity = math.dot(rootState.vecV, math.normalizesafe(rootState.vecR));
                double candidate;
                if (Math.Abs(radialVelocity) > 1e-9)
                    candidate = rootTime - error / radialVelocity;
                else
                    candidate = 0.5 * (lowerTime + upperTime);
                candidate = Clamp(candidate, lowerTime, upperTime);
                if (candidate <= lowerTime + 1e-9 || candidate >= upperTime - 1e-9)
                    candidate = 0.5 * (lowerTime + upperTime);

                Rk45StepResult rootStep = RK45Step(told, stateOld, candidate - told, args, null);
                rootTime = candidate;
                rootState = rootStep.nextState;
                if (rootState.r > targetRadius) lowerTime = candidate;
                else upperTime = candidate;
            }

            return MakeResult(nsteps, rootTime, rootState, PredictStatus.COMPLETED);
        }

        private static PredictResult MakeResult(
            int nsteps,
            double t,
            PhyState state,
            PredictStatus status)
        {
            return new PredictResult
            {
                nsteps = nsteps,
                t = t,
                finalState = state,
                status = status
            };
        }

        private static void ValidateSimulationArgs(SimAtmTrajArgs args)
        {
            if (args.mass <= 0 || args.area < 0)
                throw new ArgumentException("Vehicle mass must be positive and reference area must not be negative.");
            if (args.mu <= 0 || args.R <= 0)
                throw new ArgumentException("Celestial-body mu and radius must be positive.");
            ValidateSamples(args.CtrlSpeedSamples, "CtrlSpeedSamples");
            if (args.CtrlAOASamples == null || args.CtrlAOASamples.Length != args.CtrlSpeedSamples.Length)
                throw new ArgumentException("CtrlAOASamples must have the same length as CtrlSpeedSamples.");
            ValidateSamples(args.AeroSpeedSamples, "AeroSpeedSamples");
            ValidateMonotonicSamples(args.AeroLogDensitySamples, "AeroLogDensitySamples");
            ValidateMatrix(args.AeroCdSamples, args.AeroSpeedSamples.Length, args.AeroLogDensitySamples.Length, "AeroCdSamples");
            ValidateMatrix(args.AeroClSamples, args.AeroSpeedSamples.Length, args.AeroLogDensitySamples.Length, "AeroClSamples");
            ValidateSamples(args.AtmAltSamples, "AtmAltSamples");
            if (args.AtmTempSamples == null || args.AtmTempSamples.Length != args.AtmAltSamples.Length
                || args.AtmLogDensitySamples == null || args.AtmLogDensitySamples.Length != args.AtmAltSamples.Length)
                throw new ArgumentException("Atmosphere sample arrays must have matching lengths.");
            if (args.predictMinStep < 0 || args.predictMaxStep <= 0 || args.predictMinStep > args.predictMaxStep)
                throw new ArgumentException("Predictor step limits are invalid.");
            if (args.predictTMax <= 0)
                throw new ArgumentException("predict_tmax must be positive.");
        }

        private static void ValidateSamples(double[] samples, string name)
        {
            if (samples == null || samples.Length == 0)
                throw new ArgumentException(name + " must not be empty.");
            for (int i = 1; i < samples.Length; ++i)
                if (samples[i] <= samples[i - 1])
                    throw new ArgumentException(name + " must be strictly increasing.");
        }

        private static void ValidateMonotonicSamples(double[] samples, string name)
        {
            if (samples == null || samples.Length == 0)
                throw new ArgumentException(name + " must not be empty.");
            if (samples.Length == 1) return;
            bool ascending = samples[1] > samples[0];
            for (int i = 1; i < samples.Length; ++i)
            {
                if ((ascending && samples[i] <= samples[i - 1])
                    || (!ascending && samples[i] >= samples[i - 1]))
                    throw new ArgumentException(name + " must be strictly monotonic.");
            }
        }

        private static void ValidateMatrix(double[,] matrix, int rows, int columns, string name)
        {
            if (matrix == null || matrix.GetLength(0) != rows || matrix.GetLength(1) != columns)
                throw new ArgumentException(name + " dimensions must match the aerodynamic sample axes.");
        }

        public static void GetAeroCoefficients(
            SimAtmTrajArgs args,
            double speed,
            double logDensity,
            out double Cd,
            out double Cl)
        {
            int nV = args.AeroSpeedSamples.Length;
            int nD = args.AeroLogDensitySamples.Length;
            int idxV = FindUpperBound(args.AeroSpeedSamples, speed);
            IComparer<double> densityComparer = null;
            if (nD > 1 && args.AeroLogDensitySamples[nD - 1] < args.AeroLogDensitySamples[0])
                densityComparer = Comparer<double>.Create((a, b) => b.CompareTo(a));
            int idxD = FindUpperBound(args.AeroLogDensitySamples, logDensity, densityComparer);

            int v0 = Math.Max(0, idxV - 1);
            int v1 = Math.Min(nV - 1, idxV);
            int d0 = Math.Max(0, idxD - 1);
            int d1 = Math.Min(nD - 1, idxD);
            double tv = v0 == v1 ? 0 : (speed - args.AeroSpeedSamples[v0]) / (args.AeroSpeedSamples[v1] - args.AeroSpeedSamples[v0]);
            double td = d0 == d1 ? 0 : (logDensity - args.AeroLogDensitySamples[d0]) / (args.AeroLogDensitySamples[d1] - args.AeroLogDensitySamples[d0]);
            tv = Clamp(tv, 0, 1);
            td = Clamp(td, 0, 1);

            Cd = Bilinear(args.AeroCdSamples, v0, v1, d0, d1, tv, td);
            Cl = Bilinear(args.AeroClSamples, v0, v1, d0, d1, tv, td);
        }

        private static double Bilinear(double[,] values, int x0, int x1, int y0, int y1, double tx, double ty)
        {
            double low = values[x0, y0] + tx * (values[x1, y0] - values[x0, y0]);
            double high = values[x0, y1] + tx * (values[x1, y1] - values[x0, y1]);
            return low + ty * (high - low);
        }

        private static PhyStateDerivative ComputeDerivatives(
            double t,
            PhyState state,
            SimAtmTrajArgs args,
            Context context)
        {
            if (context == null) context = new Context();
            double r = state.r;
            double speed = state.v;
            double3 localUp = math.normalizesafe(state.vecR);
            double3 gravity = -(args.mu / (r * r)) * localUp;
            double3 drag = double3.zero;
            double3 lift = double3.zero;

            context.AOA = GetAOACommand(state, args);
            context.density = GetDensityEst(args, r - args.R);
            double logDensity = Math.Log(Math.Max(context.density, double.Epsilon));
            GetAeroCoefficients(args, speed, logDensity, out context.Cd, out context.Cl);
            double aeroAcceleration = 0.5 * context.density * speed * speed * args.area / args.mass;
            context.drag = aeroAcceleration * context.Cd;
            context.lift = aeroAcceleration * context.Cl;

            if (speed > 1e-6)
            {
                double3 windForward = state.vecV / speed;
                double3 windRight = math.cross(localUp, windForward);
                if (math.lengthsq(windRight) < 1e-16)
                    windRight = math.normalizesafe(math.cross(math.forward(), windForward));
                else
                    windRight = math.normalize(windRight);
                double3 windUp = math.normalizesafe(math.cross(windForward, windRight));
                drag = -context.drag * windForward;
                lift = context.lift * windUp; // Bank = 0 by definition in LTR.
            }

            double3 coriolis = -2 * math.cross(args.bodySpin, state.vecV);
            double3 centrifugal = -math.cross(args.bodySpin, math.cross(args.bodySpin, state.vecR));
            return new PhyStateDerivative(state.vecV, gravity + drag + lift + coriolis + centrifugal);
        }

        private struct Rk45StepResult
        {
            public double t, newStep, errorV;
            public PhyState nextState;
            public bool isValid;
        }

        private static Rk45StepResult RK45Step(
            double t,
            PhyState state,
            double step,
            SimAtmTrajArgs args,
            Context context)
        {
            if (step <= 0)
                return new Rk45StepResult { t = t, newStep = args.predictMinStep, nextState = state, errorV = 0, isValid = true };

            PhyStateDerivative k0 = ComputeDerivatives(t, state, args, context);
            PhyStateDerivative k1 = ComputeDerivatives(t + S1 * step, state + step * Beta10 * k0, args, null);
            PhyStateDerivative k2 = ComputeDerivatives(t + S2 * step, state + step * (Beta20 * k0 + Beta21 * k1), args, null);
            PhyStateDerivative k3 = ComputeDerivatives(t + S3 * step, state + step * (Beta30 * k0 + Beta31 * k1 + Beta32 * k2), args, null);
            PhyStateDerivative k4 = ComputeDerivatives(t + S4 * step, state + step * (Beta40 * k0 + Beta41 * k1 + Beta42 * k2 + Beta43 * k3), args, null);
            PhyStateDerivative k5 = ComputeDerivatives(t + S5 * step, state + step * (Beta50 * k0 + Beta51 * k1 + Beta52 * k2 + Beta53 * k3 + Beta54 * k4), args, null);

            PhyState y4 = state + step * (C04 * k0 + C14 * k1 + C24 * k2 + C34 * k3 + C44 * k4 + C54 * k5);
            PhyState y5 = state + step * (C05 * k0 + C15 * k1 + C25 * k2 + C35 * k3 + C45 * k4 + C55 * k5);
            double errorV = math.length(y5.vecV - y4.vecV)
                / (AbsVTol + RelVTol * Math.Max(1.0, math.length(y5.vecV)));
            double scale = errorV > 0 ? StepSafety * Math.Pow(errorV, -0.2) : MaxScale;
            double minStep = Math.Max(1e-6, args.predictMinStep);
            double newStep = Clamp(scale, MinScale, MaxScale) * step;
            bool isValid = errorV <= 1.0 || step <= minStep;
            newStep = Clamp(newStep, minStep, args.predictMaxStep);
            return new Rk45StepResult
            {
                t = t + step,
                newStep = newStep,
                nextState = y5,
                errorV = errorV,
                isValid = isValid
            };
        }

        private static int FindUpperBound(double[] xs, double x, IComparer<double> comparer = null)
        {
            int idx = Array.BinarySearch(xs, x, comparer);
            return idx >= 0 ? idx + 1 : ~idx;
        }

        private static double Clamp(double value, double min, double max)
        {
            return Math.Max(min, Math.Min(max, value));
        }

        private static bool IsFinite(PhyState state)
        {
            return IsFinite(state.vecR.x) && IsFinite(state.vecR.y) && IsFinite(state.vecR.z)
                && IsFinite(state.vecV.x) && IsFinite(state.vecV.y) && IsFinite(state.vecV.z);
        }

        private static bool IsFinite(double value)
        {
            return !double.IsNaN(value) && !double.IsInfinity(value);
        }

        public static float SignedAngle(Vector3 from, Vector3 to, Vector3 axis)
        {
            Vector3 cross = Vector3.Cross(from, to);
            float angle = Mathf.Atan2(cross.magnitude, Vector3.Dot(from, to));
            return Vector3.Dot(axis, cross) < 0 ? -angle : angle;
        }

        public static double GetFARAOA(Vessel vessel, Vector3d velocity, Quaternion rotation, bool reversal)
        {
            Quaternion facing = vessel.ReferenceTransform.rotation * Quaternion.Euler(-90, 0, 0) * rotation;
            Vector3 forward = facing * Vector3.forward;
            Vector3 down = facing * (-Vector3.up);
            Vector3 projected = forward * Vector3.Dot(forward, velocity) + down * Vector3.Dot(down, velocity);
            double aoa = Math.Asin(Vector3.Dot(projected.normalized, down));
            if (double.IsNaN(aoa)) aoa = 0;
            return reversal ? -aoa : aoa;
        }

        public static double GetFARAOS(Vessel vessel, Vector3d velocity, Quaternion rotation)
        {
            Quaternion facing = vessel.ReferenceTransform.rotation * Quaternion.Euler(-90, 0, 0) * rotation;
            Vector3 forward = facing * Vector3.forward;
            Vector3 right = facing * Vector3.right;
            Vector3 projected = forward * Vector3.Dot(forward, velocity) + right * Vector3.Dot(right, velocity);
            double aos = Math.Asin(Vector3.Dot(projected.normalized, right));
            return double.IsNaN(aos) ? 0 : aos;
        }

        public static double GetFARBank(Vessel vessel, Quaternion rotation)
        {
            Quaternion facing = vessel.ReferenceTransform.rotation * Quaternion.Euler(-90, 0, 0) * rotation;
            Vector3 localUp = (vessel.transform.position - vessel.mainBody.transform.position).normalized;
            Vector3 windForward = vessel.srf_velocity.normalized;
            Vector3 windRight = Vector3.Cross(localUp, windForward).normalized;
            Vector3 windUp = Vector3.Cross(windForward, windRight).normalized;
            Vector3 bankVector = facing * Vector3.up;
            bankVector -= Vector3.Dot(bankVector, windForward) * windForward;
            return SignedAngle(windUp, bankVector.normalized, -windForward);
        }

        public static void GetFARAeroCoefs(
            Vessel vessel,
            double altitude,
            double AOA,
            double speed,
            out double Cd,
            out double Cl,
            Quaternion rotation,
            bool reversal)
        {
            if (reversal) AOA = -AOA;
            double scaleHeight = GetScaleHeightAt(vessel, 0);
            altitude = Math.Min(altitude, Math.Max(0, vessel.mainBody.atmosphereDepth - scaleHeight));
            speed = Math.Max(0.1, speed);
            Quaternion facing = vessel.ReferenceTransform.rotation * Quaternion.Euler(-90, 0, 0) * rotation;
            Vector3 unitV = facing * Quaternion.Euler((float)(AOA * 180.0 / Math.PI), 0, 0) * Vector3.forward;
            Vector3 unitL = facing * Quaternion.Euler((float)(AOA * 180.0 / Math.PI - 90), 0, 0) * Vector3.forward;
            FARAPI.CalculateVesselAeroForces(vessel, out Vector3 force, out _, unitV * (float)speed, altitude);
            double factor = 0.5 * GetDensityAt(vessel, altitude) * speed * speed * FARAPI.VesselRefArea(vessel) * 1e-3;
            if (factor <= double.Epsilon)
            {
                Cd = 0;
                Cl = 0;
                return;
            }
            Cd = -Vector3.Dot(force, unitV) / factor;
            Cl = Vector3.Dot(force, unitL) / factor;
        }

        public static double GetPressureAt(Vessel vessel, double altitude)
        {
            return vessel.mainBody.GetPressure(altitude) * 1e3;
        }

        public static double GetTemperatureAt(Vessel vessel, double altitude)
        {
            return vessel.mainBody.GetTemperature(altitude);
        }

        public static double GetDensityAt(Vessel vessel, double altitude)
        {
            if (altitude > vessel.mainBody.atmosphereDepth || !vessel.mainBody.atmosphere) return 0;
            double temperature = Math.Max(1e-3, GetTemperatureAt(vessel, altitude));
            return GetPressureAt(vessel, altitude) * vessel.mainBody.atmosphereMolarMass
                / (GasConstant * temperature);
        }

        public static double GetScaleHeightAt(Vessel vessel, double altitude)
        {
            double radius = altitude + vessel.mainBody.Radius;
            double gravity = vessel.mainBody.gravParameter / (radius * radius);
            return GasConstant * Math.Max(1e-3, GetTemperatureAt(vessel, altitude))
                / (Math.Max(1e-9, vessel.mainBody.atmosphereMolarMass) * gravity);
        }

        public static void InitAtmModel(Vessel vessel, SimAtmTrajArgs args)
        {
            args.R = vessel.mainBody.Radius;
            args.mu = vessel.mainBody.gravParameter;
            args.molarMass = vessel.mainBody.atmosphereMolarMass;
            args.atmHeight = vessel.mainBody.atmosphereDepth;
            args.bodySpin = Vector3dToDouble3(vessel.mainBody.angularVelocity);
            if (!vessel.mainBody.atmosphere || args.atmHeight <= 0)
            {
                args.AtmAltSamples = new[] { 0.0 };
                args.AtmTempSamples = new[] { 1.0 };
                args.AtmLogDensitySamples = new[] { Math.Log(double.Epsilon) };
                return;
            }

            const int sampleCount = 129;
            var altitudes = new double[sampleCount];
            var temperatures = new double[sampleCount];
            var logDensities = new double[sampleCount];
            double altitudeStep = Math.Max(0, args.atmHeight - 1000) / (sampleCount - 1);
            for (int i = 0; i < sampleCount; ++i)
            {
                altitudes[i] = i * altitudeStep;
                temperatures[i] = Math.Max(1e-3, GetTemperatureAt(vessel, altitudes[i]));
                logDensities[i] = Math.Log(Math.Max(double.Epsilon, GetDensityAt(vessel, altitudes[i])));
            }
            args.AtmAltSamples = altitudes;
            args.AtmTempSamples = temperatures;
            args.AtmLogDensitySamples = logDensities;
        }

        public static double GetTemperatureEst(SimAtmTrajArgs args, double altitude)
        {
            return InterpolateClamped(args.AtmAltSamples, args.AtmTempSamples, altitude);
        }

        public static double GetLogDensityEst(SimAtmTrajArgs args, double altitude)
        {
            int idx = FindUpperBound(args.AtmAltSamples, altitude);
            if (idx == 0)
            {
                double scaleHeight = GetScaleHeightEst(args, args.AtmAltSamples[0], args.AtmTempSamples[0]);
                return args.AtmLogDensitySamples[0] - (altitude - args.AtmAltSamples[0]) / scaleHeight;
            }
            if (idx == args.AtmAltSamples.Length)
            {
                int last = args.AtmAltSamples.Length - 1;
                double scaleHeight = GetScaleHeightEst(args, args.AtmAltSamples[last], args.AtmTempSamples[last]);
                return args.AtmLogDensitySamples[last] - (altitude - args.AtmAltSamples[last]) / scaleHeight;
            }
            double t = (altitude - args.AtmAltSamples[idx - 1])
                / (args.AtmAltSamples[idx] - args.AtmAltSamples[idx - 1]);
            return args.AtmLogDensitySamples[idx - 1]
                + t * (args.AtmLogDensitySamples[idx] - args.AtmLogDensitySamples[idx - 1]);
        }

        public static double GetDensityEst(SimAtmTrajArgs args, double altitude)
        {
            if (altitude > args.atmHeight) return 0;
            return Math.Exp(GetLogDensityEst(args, altitude));
        }

        public static double GetHeightEst(SimAtmTrajArgs args, double density)
        {
            if (double.IsNaN(density) || double.IsInfinity(density) || density <= 0) return args.atmHeight;
            double logDensity = Math.Log(density);
            int idx = FindUpperBound(
                args.AtmLogDensitySamples,
                logDensity,
                Comparer<double>.Create((a, b) => b.CompareTo(a)));
            if (idx == 0)
            {
                double scaleHeight = GetScaleHeightEst(args, args.AtmAltSamples[0], args.AtmTempSamples[0]);
                return args.AtmAltSamples[0] - scaleHeight * (logDensity - args.AtmLogDensitySamples[0]);
            }
            if (idx == args.AtmLogDensitySamples.Length)
            {
                int last = args.AtmLogDensitySamples.Length - 1;
                double scaleHeight = GetScaleHeightEst(args, args.AtmAltSamples[last], args.AtmTempSamples[last]);
                return args.AtmAltSamples[last] - scaleHeight * (logDensity - args.AtmLogDensitySamples[last]);
            }
            double t = (logDensity - args.AtmLogDensitySamples[idx - 1])
                / (args.AtmLogDensitySamples[idx] - args.AtmLogDensitySamples[idx - 1]);
            return args.AtmAltSamples[idx - 1]
                + t * (args.AtmAltSamples[idx] - args.AtmAltSamples[idx - 1]);
        }

        public static double GetScaleHeightEst(SimAtmTrajArgs args, double altitude, double? temperature = null)
        {
            double temp = temperature ?? GetTemperatureEst(args, altitude);
            double radius = altitude + args.R;
            double gravity = args.mu / (radius * radius);
            return GasConstant * temp / (Math.Max(1e-9, args.molarMass) * gravity);
        }

        private static double InterpolateClamped(double[] xs, double[] ys, double x)
        {
            int idx = FindUpperBound(xs, x);
            if (idx == 0) return ys[0];
            if (idx == xs.Length) return ys[ys.Length - 1];
            double t = (x - xs[idx - 1]) / (xs[idx] - xs[idx - 1]);
            return ys[idx - 1] + t * (ys[idx] - ys[idx - 1]);
        }

        public static double GetSafeDouble(double value)
        {
            return double.IsNaN(value) || double.IsInfinity(value) ? 0 : value;
        }

        public static double3 Vector3dToDouble3(Vector3d value)
        {
            return new double3(value.x, value.y, value.z);
        }
    }
}
