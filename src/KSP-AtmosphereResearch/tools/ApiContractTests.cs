// Lightweight contract harness. Does not emulate KSP's atmospheric curves or prove flight accuracy.
using System;
using KSPAtmosphereResearch;
namespace UnityEngine
{
    public class Object { }
    public struct Vector3
    {
        public double x, y, z;
        public Vector3(double a, double b, double c) { x=a; y=b; z=c; }
    }
}
public struct Vector3d
{
    public double x,y,z;
    public Vector3d(double a,double b,double c) { x=a;y=b;z=c; }
    public double magnitude { get { return Math.Sqrt(x*x+y*y+z*z); } }
    public static implicit operator Vector3d(UnityEngine.Vector3 v) { return new Vector3d(v.x,v.y,v.z); }
    public static explicit operator UnityEngine.Vector3(Vector3d v) { return new UnityEngine.Vector3(v.x,v.y,v.z); }
    public static Vector3d operator -(Vector3d a, Vector3d b) { return new Vector3d(a.x-b.x,a.y-b.y,a.z-b.z); }
    public static Vector3d operator /(Vector3d a,double b) { return new Vector3d(a.x/b,a.y/b,a.z/b); }
    public static double Dot(Vector3d a,Vector3d b) { return a.x*b.x+a.y*b.y+a.z*b.z; }
}
public class DummyTransform { public Vector3d position = new Vector3d(1000,0,0); }
public class DummyObject { public DummyTransform transform = new DummyTransform(); }
public class CelestialBody
{
    public bool atmosphere=true; public double atmosphereDepth=100, Radius=1000;
    public DummyObject scaledBody = new DummyObject();
    public Vector3d GetWorldSurfacePosition(double lat,double lon,double alt) { return new Vector3d(lat,lon,alt); }
    public double GetPressure(double alt) { return alt < atmosphereDepth && atmosphere ? 2 : 0; }
    public double GetTemperature(double alt) { return alt < atmosphereDepth && atmosphere ? 200 : 0; }
    public double GetFullTemperature(double alt,double offset) { return GetTemperature(alt)+3*offset; }
    public void GetAtmoThermalStats(bool flux,CelestialBody sun,Vector3d ray,double dot,Vector3d up,double alt,
        out double offset,out double emissive,out double albedo)
    {
        if(flux || Math.Abs(ray.magnitude-1)>1e-10) throw new Exception("Wrong native thermal inputs");
        offset=10; emissive=albedo=0;
    }
}
public class Planetarium
{
    public static Planetarium fetch=new Planetarium(); public CelestialBody Sun=new CelestialBody();
    public static double GetUniversalTime() { return 123; }
}
public static class ScaledSpace { public static Vector3d LocalToScaledSpace(Vector3d pos) { return pos; } }
public static class FlightGlobals
{
    public static Vector3d getUpAxis(CelestialBody body,Vector3d pos) { return new Vector3d(1,0,0); }
    public static double getStaticPressure(Vector3d pos,CelestialBody body) { return body.GetPressure(pos.z); }
    public static double getExternalTemperature(Vector3d pos,CelestialBody body) { return body.GetTemperature(pos.z); }
    public static double getAtmDensity(double pressure,double temp,CelestialBody body) { return pressure == 0 ? 0 : pressure*1000/temp; }
}
class ApiContractTests
{
    static void Equal(double actual,double expected,string name)
    { if(Math.Abs(actual-expected)>1e-10) throw new Exception(name+": "+actual+" != "+expected); }
    static void Invalid(Action action)
    { try { action(); } catch(ArgumentException) { return; } throw new Exception("Invalid input accepted"); }
    static void Main()
    {
        var body=new CelestialBody();
        var query=new AtmosphereQuery(body,30,540,20);
        Equal(query.LongitudeDegrees,-180,"longitude normalization");
        Equal(query.WorldPosition.x,30,"latitude input"); Equal(query.WorldPosition.z,20,"altitude input");
        Equal(query.UniversalTime,123,"current UT");
        var sample=new StockCandidate(true).Sample(query);
        Equal(sample.PressurePa,2000,"kPa to Pa"); Equal(sample.TemperatureK,230,"offset composition");
        Equal(sample.DensityKgM3,2000.0/230,"density uses full ambient temperature");
        Equal(new StockCandidate(false,true).Sample(query).TemperatureK,200,"altitude negative control");
        if(new AtmosphereQuery(body,0,0,100).InAtmosphere) throw new Exception("Atmosphere cutoff");
        if(new StockCandidate(true).Sample(new AtmosphereQuery(body,0,0,101)).Status!="vacuum") throw new Exception("Vacuum status");
        if(AtmosphereSample.Values(query,1,double.NaN,1).Status!="invalid") throw new Exception("Invalid result hidden");
        Invalid(()=>new AtmosphereQuery(body,91,0,0)); Invalid(()=>new AtmosphereQuery(body,0,double.NaN,0));
        Invalid(()=>new AtmosphereQuery(body,0,0,-1000));
        Console.WriteLine("API contract tests passed: coordinates, units, thermal composition, cutoff, invalid inputs/results.");
    }
}
