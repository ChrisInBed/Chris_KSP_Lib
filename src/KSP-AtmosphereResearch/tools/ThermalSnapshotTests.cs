// Standalone analytic checks. Unity native behavior is verified separately inside KSP.
using System;
using System.Threading.Tasks;
using KSPAtmosphereResearch;
using UnityEngine;
class ThermalSnapshotTests
{
    static void Near(double a,double b,double tolerance,string name) { if(Math.Abs(a-b)>tolerance)throw new Exception(name+": "+a+" != "+b); }
    static void Assert(bool value,string name) { if(!value)throw new Exception(name); }
    static void Main()
    {
        FloatCurve quadratic=new FloatCurve(new Keyframe(0,0,0,0),new Keyframe(2,4,4,4));
        CopiedCurve copy=new CopiedCurve(quadratic);
        Near(copy.Evaluate(.5f,true),.25,1e-7,"Hermite reproduces quadratic");
        Near(copy.Evaluate(1.5f,true),2.25,1e-7,"non-unit segment");
        Near(copy.Evaluate(-1,true),0,0,"lower clamp");Near(copy.Evaluate(3,true),4,0,"upper clamp");
        quadratic.Curve.keys=new[] {new Keyframe(0,99,0,0)};
        Near(copy.Evaluate(.5f,true),.25,1e-7,"copy unaffected by source replacement");
        CopiedCurve step=new CopiedCurve(new FloatCurve(new Keyframe(0,2,0,float.PositiveInfinity),new Keyframe(1,5,float.PositiveInfinity,0)));
        Near(step.Evaluate(.75f,true),2,0,"step tangent");Near(step.Evaluate(1,true),5,0,"step endpoint");
        Keyframe weighted=new Keyframe(0,1,0,0);weighted.weightedMode=WeightedMode.Both;
        Assert(!new CopiedCurve(new FloatCurve(weighted)).ManagedSupported,"weighted rejection");
        FloatCurve looping=new FloatCurve(new Keyframe(0,1,0,0));looping.Curve.preWrapMode=WrapMode.Loop;
        Assert(!new CopiedCurve(looping).ManagedSupported,"loop rejection");
        CelestialBody body=new CelestialBody();ThermalSnapshot model=ThermalSnapshot.Capture(body);
        ThermalInput equator=new ThermalInput {Latitude=0,Longitude=0,Altitude=0,Up=new Vector3d(1,0,0)};
        ThermalValue value=model.Evaluate(equator,true);
        // Equator, sun overhead, 45 degree lag: normalized solar = (1+cos(45))/2.
        double expectedOffset=10+20*(1+Math.Cos(Math.PI/4))/2+3*2;
        Near(value.Offset,expectedOffset,3e-6,"solar, latitude and axial composition");
        Near(value.PressurePa,100000,0,"kPa to Pa");Near(value.TemperatureK,300+.5*expectedOffset,3e-6,"temperature composition");
        Near(value.Density,100000*.0289644/(8.31447*value.TemperatureK),1e-12,"ideal gas units");
        ThermalValue pole=model.Evaluate(new ThermalInput {Altitude=0,Up=new Vector3d(0,1,0)},true);
        Near(pole.Offset,26-10*(float)(body.Radius/Math.Sqrt(1e16+body.Radius*body.Radius)),1e-6,"guarded polar normalization with finite sun distance");
        ThermalValue vacuum=model.Evaluate(new ThermalInput {Altitude=140000,Up=new Vector3d(1,0,0)},true);
        Near(vacuum.Density,0,0,"exact atmosphere boundary");Near(vacuum.PressurePa,0,0,"vacuum pressure");
        Near(model.Evaluate(new ThermalInput {Altitude=-100,Up=new Vector3d(1,0,0)},true).PressurePa,100000,0,"below-sea-level clamp");
        double checksum=value.Density+value.TemperatureK+value.Offset;
        Parallel.For(0,100000,i=> { ThermalValue x=model.Evaluate(equator,true);Assert(x.Density+x.TemperatureK+x.Offset==checksum,"parallel immutable result"); });
        Console.WriteLine("Thermal snapshot tests passed: analytic Hermite, copy isolation, boundary/step behavior, unsupported curve rejection, solar/polar/season composition, gas units and 100,000 parallel evaluations.");
    }
}
namespace UnityEngine
{
    public enum WeightedMode { None=0, Both=3 }
    public enum WrapMode { Default=0, Clamp=1, Loop=2, PingPong=4, ClampForever=8 }
    public struct Keyframe { public float time,value,inTangent,outTangent;public WeightedMode weightedMode;public Keyframe(float t,float v,float a,float b) {time=t;value=v;inTangent=a;outTangent=b;weightedMode=WeightedMode.None;} }
    public class AnimationCurve
    {
        private Keyframe[] data;public Keyframe[] keys { get{return (Keyframe[])data.Clone();}set{data=(Keyframe[])value.Clone();} }
        public WrapMode preWrapMode,postWrapMode;
        public AnimationCurve(params Keyframe[] k) { keys=k; }
        public float Evaluate(float t) { throw new NotSupportedException("Native curve evaluation requires KSP"); }
    }
    public struct Vector3
    {
        public float x,y,z;public Vector3(float a,float b,float c) {x=a;y=b;z=c;}
        public static float Dot(Vector3 a,Vector3 b) {return a.x*b.x+a.y*b.y+a.z*b.z;}
    }
    public struct Quaternion
    {
        private double angle;public static Quaternion AngleAxis(float degrees,Vector3 axis) { return new Quaternion {angle=degrees*Math.PI/180}; }
        public static Vector3 operator *(Quaternion q,Vector3 v) {return new Vector3((float)(Math.Cos(q.angle)*v.x+Math.Sin(q.angle)*v.z),v.y,(float)(-Math.Sin(q.angle)*v.x+Math.Cos(q.angle)*v.z));}
    }
    public class Transform {public Vector3 position=new Vector3(100000000,0,0),up=new Vector3(0,1,0);}
    public class GameObject {public Transform transform=new Transform();}
    public static class Mathf {public static float Sign(float x) {return x>=0?1:-1;}}
}
public struct Vector3d
{
    public double x,y,z;public Vector3d(double a,double b,double c) {x=a;y=b;z=c;}
    public double magnitude {get{return Math.Sqrt(x*x+y*y+z*z);}}
    public static Vector3d operator -(Vector3d a,Vector3d b) {return new Vector3d(a.x-b.x,a.y-b.y,a.z-b.z);}
    public static Vector3d operator *(Vector3d a,double b) {return new Vector3d(a.x*b,a.y*b,a.z*b);}
    public static Vector3d operator /(Vector3d a,double b) {return new Vector3d(a.x/b,a.y/b,a.z/b);}
    public static implicit operator Vector3d(Vector3 a) {return new Vector3d(a.x,a.y,a.z);}
    public static explicit operator Vector3(Vector3d a) {return new Vector3((float)a.x,(float)a.y,(float)a.z);}
}
public class FloatCurve
{
    public AnimationCurve Curve;public FloatCurve(params Keyframe[] keys) {Curve=new AnimationCurve(keys);}
    public static FloatCurve Constant(float value) {return new FloatCurve(new Keyframe(0,value,0,0),new Keyframe(200000,value,0,0));}
}
public class Orbit {public double trueAnomaly,eccentricity,radius,PeR,ApR;}
public class CelestialBody
{
    public bool atmosphere=true,atmosphereUsePressureCurve=true,atmosphereUseTemperatureCurve=true,atmospherePressureCurveIsNormalized,atmosphereTemperatureCurveIsNormalized;
    public double atmosphereDepth=140000,Radius=6371000,atmosphereMolarMass=.0289644,atmospherePressureSeaLevel=100,atmosphereTemperatureSeaLevel=300,atmosphereTemperatureLapseRate,atmosphereGasMassLapseRate,rotationPeriod=86400;
    public FloatCurve atmospherePressureCurve=FloatCurve.Constant(100),atmosphereTemperatureCurve=FloatCurve.Constant(300),atmosphereTemperatureSunMultCurve=FloatCurve.Constant(.5f),latitudeTemperatureBiasCurve=FloatCurve.Constant(10),latitudeTemperatureSunMultCurve=FloatCurve.Constant(20),axialTemperatureSunBiasCurve=FloatCurve.Constant(3),axialTemperatureSunMultCurve=FloatCurve.Constant(2),eccentricityTemperatureBiasCurve=FloatCurve.Constant(0);
    public Transform bodyTransform=new Transform();public GameObject scaledBody=new GameObject();public Vector3d position;
    public Orbit orbit=new Orbit();public static CelestialBody GetBodyReferencing(CelestialBody body,CelestialBody sun) {return body;}
}
public class Planetarium {public static Planetarium fetch=new Planetarium();public CelestialBody Sun=new CelestialBody();public static double GetUniversalTime() {return 0;} }
public static class PhysicsGlobals {public static double IdealGasConstant=8.31447,SpaceTemperature=4;}
public static class ScaledSpace {public static float InverseScaleFactor=1;public static Vector3d LocalToScaledSpace(Vector3d p) {return p;} }
