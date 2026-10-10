using System;
using System.Reflection;
using UnityEngine;

namespace KSPAtmosphereResearch
{
    internal struct ThermalInput
    {
        public double Latitude, Longitude, Altitude;
        public Vector3d Up;
    }
    internal struct ThermalValue
    {
        public double PressurePa, TemperatureK, Density, Offset;
        public ThermalValue(double p, double t, double d, double o) { PressurePa=p; TemperatureK=t; Density=d; Offset=o; }
    }
    // Private copied curves. No CelestialBody, Transform, Orbit or live FloatCurve is retained.
    internal sealed class CopiedCurve
    {
        private readonly AnimationCurve native;
        private readonly Keyframe[] keys;
        public readonly bool ManagedSupported;
        public CopiedCurve(FloatCurve source)
        {
            keys=source.Curve.keys;
            native=new AnimationCurve(keys);
            native.preWrapMode=source.Curve.preWrapMode;
            native.postWrapMode=source.Curve.postWrapMode;
            ManagedSupported=true;
            foreach(Keyframe key in keys) if(key.weightedMode!=WeightedMode.None) ManagedSupported=false;
            if(native.preWrapMode==WrapMode.Loop || native.preWrapMode==WrapMode.PingPong || native.postWrapMode==WrapMode.Loop || native.postWrapMode==WrapMode.PingPong) ManagedSupported=false;
        }
        public float Evaluate(float x, bool managed)
        {
            if(!managed) return native.Evaluate(x);
            if(!ManagedSupported) throw new NotSupportedException("Managed Hermite requires unweighted, clamped curves");
            if(keys.Length==0) return 0;
            if(x<=keys[0].time) return keys[0].value;
            if(x>=keys[keys.Length-1].time) return keys[keys.Length-1].value;
            int lo=0, hi=keys.Length-1;
            while(hi-lo>1) { int m=(lo+hi)/2; if(keys[m].time<=x) lo=m; else hi=m; }
            Keyframe a=keys[lo],b=keys[hi];
            if(float.IsInfinity(a.outTangent)||float.IsInfinity(b.inTangent)) return a.value;
            double h=(double)b.time-a.time,t=((double)x-a.time)/h;
            return (float)((2*t*t*t-3*t*t+1)*a.value+(t*t*t-2*t*t+t)*h*a.outTangent+(-2*t*t*t+3*t*t)*b.value+(t*t*t-t*t)*h*b.inTangent);
        }
        public static bool NativeEvaluateDeclaredThreadSafe()
        {
            foreach(CustomAttributeData a in typeof(AnimationCurve).GetMethod("Evaluate").GetCustomAttributesData())
            {
                if(a.AttributeType.Name=="ThreadSafeAttribute") return true;
                foreach(CustomAttributeNamedArgument n in a.NamedArguments)
                    if(n.MemberName=="IsThreadSafe" && n.TypedValue.Value is bool && (bool)n.TypedValue.Value) return true;
            }
            return false;
        }
    }
    internal sealed class ThermalSnapshot
    {
        private readonly CopiedCurve pressure,temperature,sunMult,latBias,latMult,axialBias,axialMult,eccBias;
        private readonly double depth,radius,molar,gas,space,pressureSea,tempSea,lapse,gasLapse,anomaly,eccFraction,inverseScale;
        private readonly bool hasAir,usePressure,pressureNormalized,useTemp,tempNormalized;
        private readonly Vector3 axis;
        private readonly Quaternion lag;
        private readonly Vector3d sunFromCenter;
        public readonly bool ManagedSupported;
        public readonly double UniversalTime;
        private ThermalSnapshot(CelestialBody body)
        {
            // This constructor MUST run on the Unity main thread.
            CelestialBody sun=Planetarium.fetch.Sun;
            UniversalTime=Planetarium.GetUniversalTime();
            hasAir=body.atmosphere;depth=body.atmosphereDepth;radius=body.Radius;
            molar=body.atmosphereMolarMass;gas=PhysicsGlobals.IdealGasConstant;space=PhysicsGlobals.SpaceTemperature;
            pressureSea=body.atmospherePressureSeaLevel;tempSea=body.atmosphereTemperatureSeaLevel;
            lapse=body.atmosphereTemperatureLapseRate;gasLapse=body.atmosphereGasMassLapseRate;
            usePressure=body.atmosphereUsePressureCurve;pressureNormalized=body.atmospherePressureCurveIsNormalized;
            useTemp=body.atmosphereUseTemperatureCurve;tempNormalized=body.atmosphereTemperatureCurveIsNormalized;
            axis=body.bodyTransform.up;lag=Quaternion.AngleAxis(45*Mathf.Sign((float)body.rotationPeriod),axis);
            sunFromCenter=(Vector3d)sun.scaledBody.transform.position-ScaledSpace.LocalToScaledSpace(body.position);
            inverseScale=ScaledSpace.InverseScaleFactor;
            Orbit orbit=CelestialBody.GetBodyReferencing(body,sun).orbit;
            anomaly=((float)orbit.trueAnomaly*57.29578f+360f)%360f;
            eccFraction=orbit.eccentricity==0?double.NaN:(orbit.radius-orbit.PeR)/(orbit.ApR-orbit.PeR);
            pressure=new CopiedCurve(body.atmospherePressureCurve);temperature=new CopiedCurve(body.atmosphereTemperatureCurve);
            sunMult=new CopiedCurve(body.atmosphereTemperatureSunMultCurve);latBias=new CopiedCurve(body.latitudeTemperatureBiasCurve);
            latMult=new CopiedCurve(body.latitudeTemperatureSunMultCurve);axialBias=new CopiedCurve(body.axialTemperatureSunBiasCurve);
            axialMult=new CopiedCurve(body.axialTemperatureSunMultCurve);eccBias=new CopiedCurve(body.eccentricityTemperatureBiasCurve);
            ManagedSupported=pressure.ManagedSupported&&temperature.ManagedSupported&&sunMult.ManagedSupported&&latBias.ManagedSupported&&latMult.ManagedSupported&&axialBias.ManagedSupported&&axialMult.ManagedSupported&&eccBias.ManagedSupported;
        }
        public static ThermalSnapshot Capture(CelestialBody body) { return new ThermalSnapshot(body); }
        // Kernel: current-ephemeris snapshot + body-relative radial unit vector. No live game state.
        public ThermalValue Evaluate(ThermalInput input, bool managed)
        {
            double h=input.Altitude;
            if(!hasAir || h>=depth) return new ThermalValue(0,0,0,0);
            Vector3d ray=sunFromCenter-input.Up*((radius+h)*inverseScale);
            Vector3 direction=(Vector3)(ray/Math.Max(ray.magnitude,double.Epsilon));
            Vector3 up=(Vector3)input.Up;
            double axisSun=Vector3.Dot(direction,axis),axisUp=Vector3.Dot(axis,up);
            double polar=AcosLikeNative(axisUp),solar=AcosLikeNative(axisSun);
            double max=(1+Math.Cos(solar-polar))*.5,min=(1+Math.Cos(solar+polar))*.5;
            if(polar>Math.PI/2) polar=Math.PI-polar;
            double normalizedSun=(1+Vector3.Dot(direction,lag*up))*.5;
            double range=max-min;double unnormalizedSun=normalizedSun;
            if(range>.001)
            {
                normalizedSun=(normalizedSun-min)/range;
                if(double.IsNaN(normalizedSun)) normalizedSun=unnormalizedSun>.5?1:0;
            }
            else normalizedSun=min+range*.5;
            float latitude=(float)(Math.PI/2-polar)*57.29578f;
            double offset=latBias.Evaluate(latitude,managed)+(double)latMult.Evaluate(latitude,managed)*normalizedSun
                +(double)(axialBias.Evaluate((float)anomaly,managed)*axialMult.Evaluate(latitude,managed))
                +(double.IsNaN(eccFraction)?0:eccBias.Evaluate((float)eccFraction,managed));
            double p;
            if(usePressure) p=pressureNormalized?(float)((float)pressureSea*Clamp01(pressure.Evaluate((float)(h/depth),managed))):pressure.Evaluate((float)h,managed);
            else p=pressureSea*Math.Pow(1-lapse*h/tempSea,gasLapse);
            double t;
            if(useTemp) t=tempNormalized?space+(tempSea-space)*Clamp01(temperature.Evaluate((float)(h/depth),managed)):temperature.Evaluate((float)h,managed);
            else t=tempSea-lapse*h;
            t+=sunMult.Evaluate((float)h,managed)*offset;
            return new ThermalValue(p*1000,t,p<=0||t<=0?0:p*1000*molar/(gas*t),offset);
        }
        private static double Clamp01(double x) { return Math.Max(0,Math.Min(1,x)); }
        private static double AcosLikeNative(double x) { double a=Math.Acos(x);return double.IsNaN(a)?(x<0?Math.PI:0):a; }
    }
}
