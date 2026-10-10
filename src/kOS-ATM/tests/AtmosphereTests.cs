using System;
using System.Threading.Tasks;
using System.Diagnostics;
using KOSAtmosphere;

internal static class AtmosphereTests
{
    internal static void Assert(bool value,string name) {if(!value)throw new Exception(name);}
    internal static void Near(double a,double b,double tolerance,string name) {Assert(AtmosphereVector.Finite(a)&&AtmosphereVector.Finite(b)&&Math.Abs(a-b)<=tolerance,name+": "+a+" != "+b);}
    internal static void Throws(Action action,string name) {try {action();}catch(ArgumentException){return;}catch(NotSupportedException){return;}throw new Exception("Missing rejection: "+name);}
    internal static HermiteCurve Constant(float value) {return new HermiteCurve(new[] {new CurveKey(0,value,0,0)});}
    internal static SnapshotData Fixture(bool air=true)
    {
        return new SnapshotData {
            BodyName="Fixture",Epoch=12345,HasAir=air,Depth=100000,Radius=1000000,Mu=9.8e12,Molar=.0289644,Gas=8.31447,Space=4,
            PressureSea=100,TempSea=300,UsePressure=true,UseTemp=true,PressureNormalized=false,TempNormalized=false,
            Pressure=Constant(100),Temperature=Constant(300),SunMult=Constant(1),LatBias=Constant(10),LatMult=Constant(80),AxialBias=Constant(3),AxialMult=Constant(2),EccBias=Constant(0),
            Axis=new AtmosphereVector(0,1,0),North=new AtmosphereVector(0,1,0),Spin=new AtmosphereVector(0,2*Math.PI/600,0),ColumnUp=new AtmosphereVector(1,0,0),
            ZeroLongitude=new AtmosphereVector(1,0,0),EastLongitude=new AtmosphereVector(0,0,1),SunFromCenter=new AtmosphereVector(1e8,0,0),InverseScale=1,
            Lag=new FloatRotation(0,(float)Math.Sin(Math.PI/8),0,(float)Math.Cos(Math.PI/8)),Anomaly=0,EccFraction=double.NaN
        };
    }
    private static void Main()
    {
        CurveKey[] source={new CurveKey(0,0,0,0),new CurveKey(2,4,4,4)};
        var curve=new HermiteCurve(source);source[0]=new CurveKey(0,999,0,0);
        Near(curve.Evaluate(.5f),.25,1e-7,"Hermite/copy independence");Near(curve.Evaluate(1.5f),2.25,1e-7,"non-unit interval");
        Near(curve.Evaluate(-1),0,0,"lower clamp");Near(curve.Evaluate(3),4,0,"upper clamp");
        var step=new HermiteCurve(new[] {new CurveKey(0,2,0,float.PositiveInfinity),new CurveKey(1,5,float.PositiveInfinity,0)});
        Near(step.Evaluate(.7f),2,0,"step segment");Near(step.Evaluate(1),5,0,"step endpoint");
        Throws(()=>new HermiteCurve(new[] {new CurveKey(0,float.NaN,0,0)}),"invalid curve");
        var fixture=Fixture();var model=new AtmosphereSnapshot(fixture);
        fixture.TempSea=999;fixture.LatMult=Constant(0);
        var noon=model.EvaluateGeographic(0,0,0,model.EpochUT);
        Near(noon.PressurePa,100000,0,"Pa conversion");
        Near(noon.TemperatureK,300+16+80*(1+Math.Cos(Math.PI/4))/2,1e-5,"native solar and seasonal composition");
        Near(noon.Density,noon.PressurePa*.0289644/(8.31447*noon.TemperatureK),1e-12,"gas units");
        Near(model.EvaluatePosition(model.BodyRadius,0,0,0).TemperatureK,noon.TemperatureK,0,"position/geographic epoch");
        Near(model.EvaluateGeographic(0,360,0,model.EpochUT).TemperatureK,noon.TemperatureK,0,"longitude wrap");
        var night=model.EvaluateGeographic(0,180,0,model.EpochUT);
        Assert(night.Density>noon.Density,"longitude changes density");
        Near(model.EvaluateGeographic(0,0,0,model.EpochUT+300).TemperatureK,night.TemperatureK,1e-5,"future rotation");
        Near(model.EvaluatePosition(model.BodyRadius,0,0,300).TemperatureK,night.TemperatureK,1e-5,"rotating trajectory frame");
        foreach(double lat in new[] {-90.0,90.0}) Assert(AtmosphereVector.Finite(model.EvaluateGeographic(lat,0,0,model.EpochUT).Density),"pole finite");
        foreach(double altitude in new[] {model.AtmosphereDepth,model.AtmosphereDepth+1})Near(model.EvaluateColumn(altitude).Density,0,0,"exact cutoff");
        Assert(model.EvaluateColumn(-100).Density>0,"below sea level");
        Throws(()=>model.EvaluateColumn(-model.BodyRadius),"body center");Throws(()=>model.EvaluateColumn(double.NaN),"NaN altitude");
        Throws(()=>model.EvaluateGeographic(91,0,0,model.EpochUT),"latitude");Throws(()=>model.EvaluatePosition(0,0,0,0),"zero position");
        Near(new AtmosphereSnapshot(Fixture(false)).EvaluateColumn(0).TemperatureK,0,0,"airless body");
        var inverseFixture=Fixture();inverseFixture.LatMult=Constant(0);inverseFixture.Pressure=new HermiteCurve(new[] {new CurveKey(0,100,-.001f,-.001f),new CurveKey(100000,0,-.001f,-.001f)});
        var inverse=new AtmosphereSnapshot(inverseFixture);
        Near(inverse.AltitudeForDensity(inverse.EvaluateColumn(25000).Density),25000,.02,"column inversion");Near(inverse.AltitudeForDensity(0),100000,0,"inverse vacuum");
        var normalizedFixture=Fixture();normalizedFixture.PressureNormalized=true;normalizedFixture.TempNormalized=true;normalizedFixture.Pressure=Constant(.25f);normalizedFixture.Temperature=Constant(.25f);normalizedFixture.SunMult=Constant(0);
        var normalized=new AtmosphereSnapshot(normalizedFixture).EvaluateColumn(1000);
        Near(normalized.PressurePa,25000,0,"normalized pressure");Near(normalized.TemperatureK,78,0,"normalized temperature");
        normalizedFixture.UsePressure=false;normalizedFixture.UseTemp=false;normalizedFixture.Lapse=.001;normalizedFixture.GasLapse=5;
        var analytic=new AtmosphereSnapshot(normalizedFixture).EvaluateColumn(1000);
        Near(analytic.TemperatureK,299,1e-12,"analytic lapse");Near(analytic.PressurePa,100000*Math.Pow(1-1.0/300,5),1e-8,"analytic pressure");
        var tiltedFixture=Fixture();double tilt=.4;
        tiltedFixture.Axis=tiltedFixture.North=new AtmosphereVector(0,Math.Cos(tilt),Math.Sin(tilt));
        tiltedFixture.EastLongitude=new AtmosphereVector(0,-Math.Sin(tilt),Math.Cos(tilt));
        tiltedFixture.Spin=new AtmosphereVector(0,0,0);
        var tilted=new AtmosphereSnapshot(tiltedFixture);
        Near(tilted.EvaluateGeographic(90,0,0,tilted.EpochUT).TemperatureK,tilted.EvaluatePosition(tiltedFixture.North.X*tilted.BodyRadius,tiltedFixture.North.Y*tilted.BodyRadius,tiltedFixture.North.Z*tilted.BodyRadius,0).TemperatureK,1e-6,"tilted-body geographic basis");
        TestOrbits();
        var ephemerisFixture=Fixture();var orbit=new EllipticOrbit(1e8,.2,Math.PI,10000,new AtmosphereVector(1,0,0),new AtmosphereVector(0,0,1));
        ephemerisFixture.SeasonOrbit=orbit;ephemerisFixture.OrbitTerms=new[] {new OrbitTerm(orbit,-1)};ephemerisFixture.Anomaly=Math.PI;ephemerisFixture.Spin=new AtmosphereVector(0,0,0);
        ephemerisFixture.EccFraction=1;ephemerisFixture.EccSpan=4e7;ephemerisFixture.EccBias=new HermiteCurve(new[] {new CurveKey(0,0,10,10),new CurveKey(1,10,10,10)});
        var moving=new AtmosphereSnapshot(ephemerisFixture);
        Assert(Math.Abs(moving.EvaluateColumn(0).TemperatureK-moving.EvaluatePosition(moving.BodyRadius,0,0,2000).TemperatureK)>1,"orbital solar and eccentricity evolution");
        var expected=new double[1024];for(int i=0;i<expected.Length;i++)expected[i]=moving.EvaluateGeographic(i%179-89,i%360-180,i%50000,moving.EpochUT+i).Density;
        Parallel.For(0,1000000,i=> {int j=i%expected.Length;Near(moving.EvaluateGeographic(j%179-89,j%360-180,j%50000,moving.EpochUT+j).Density,expected[j],0,"concurrent future queries");});
        double checksum=0;var watch=Stopwatch.StartNew();for(int i=0;i<100000;i++)checksum+=moving.EvaluatePosition(moving.BodyRadius+10000,0,0,i%3600).Density;watch.Stop();
        Console.WriteLine("Managed tests passed: curves, units, gas branches, poles, vacuum, immutable copy, inverse column, rotation, Kepler, future geometry, 1,000,000 concurrent queries.");
        Console.WriteLine("Standalone .NET future-query cost (not a KSP benchmark): "+(watch.Elapsed.TotalMilliseconds*1000/100000).ToString("F3")+" us/query; checksum="+checksum);
    }
    private static void TestOrbits()
    {
        foreach(double e in new[] {0.0,.2,.9,.9999})
        {
            var orbit=new EllipticOrbit(1000,e,0,100,new AtmosphereVector(1,0,0),new AtmosphereVector(0,0,1));
            Near(orbit.Position(0).X,1000*(1-e),1e-9,"periapsis");Near(orbit.Position(50).X,-1000*(1+e),1e-9,"apoapsis");
            Near((orbit.Position(17)-orbit.Position(117)).Length,0,1e-8,"periodic orbit");
            Near((orbit.Position(-83)-orbit.Position(17)).Length,0,1e-8,"negative UT");
            for(int i=1;i<100;i++)
            {
                double anomaly=orbit.TrueAnomaly(i),radius=orbit.Radius(i);
                Near(radius,1000*(1-e*e)/(1+e*Math.Cos(anomaly)),1e-5,"orbit geometry");
            }
        }
    }
}
