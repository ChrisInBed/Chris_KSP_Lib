using System;
using System.Threading.Tasks;
using KOSAtmosphere;
using Unity.Mathematics;

internal static class PredictorTests
{
    private static void Main()
    {
        var dayFixture=AtmosphereTests.Fixture();dayFixture.Spin=new AtmosphereVector(0,0,0);
        var nightFixture=AtmosphereTests.Fixture();nightFixture.Spin=new AtmosphereVector(0,0,0);nightFixture.SunFromCenter=new AtmosphereVector(-1e8,0,0);
        var day=new AtmosphereSnapshot(dayFixture);var night=new AtmosphereSnapshot(nightFixture);
        var state=new LTR.PhyState(new double3(day.BodyRadius+500,0,0),new double3(-80,0,400));
        var args=new LTR.SimAtmTrajArgs {Atmosphere=day,R=day.BodyRadius,mu=9.8e12,predictTMax=60,predictMaxStep=.1,predictMinStep=.001};
        var light=LTR.LTRCore.PredictTrajectory(0,state,args);
        args.Atmosphere=night;var dark=LTR.LTRCore.PredictTrajectory(0,state,args);
        AtmosphereTests.Assert(light.status==LTR.PredictStatus.COMPLETED&&dark.status==LTR.PredictStatus.COMPLETED,"LTR impact completes");
        AtmosphereTests.Assert(Math.Abs(light.finalState.vecR.z-dark.finalState.vecR.z)>.1,"LTR reacts to temperature/density geometry");
        NearImpact(light.finalState.vecR,day.BodyRadius);NearImpact(dark.finalState.vecR,day.BodyRadius);
        var afsState=new AFS.PhyState(state.vecR,state.vecV);
        var afsArgs=new AFS.SimAtmTrajArgs {Atmosphere=day,R=day.BodyRadius,mu=9.8e12,predict_tmax=60,predict_max_step=.1,predict_min_step=.001};
        double initial=AFS.AFSCore.GetSpecificEnergy(afsArgs.mu,afsState.r,afsState.v);
        afsArgs.target_energy=initial-5000;
        var plan=new AFS.BankPlanArgs(0,0,initial,afsArgs.target_energy,false);
        var first=AFS.AFSCore.PredictTrajectory(0,afsState,afsArgs,plan);
        afsArgs.Atmosphere=night;var second=AFS.AFSCore.PredictTrajectory(0,afsState,afsArgs,plan);
        AtmosphereTests.Assert(first.status==AFS.PredictStatus.COMPLETED&&second.status==AFS.PredictStatus.COMPLETED,"AFS energy crossing completes");
        AtmosphereTests.Assert(Math.Abs(first.t-second.t)>.0001,"AFS reacts to solar density");
        var clone=afsArgs.Clone();afsArgs.AeroCdSamples[0,0]=99;afsArgs.CtrlSpeedSamples[0]=-99;
        AtmosphereTests.Near(clone.AeroCdSamples[0,0],1.5,0,"AFS matrix clone isolation");AtmosphereTests.Near(clone.CtrlSpeedSamples[0],600,0,"AFS axis clone isolation");
        var ltrClone=args.Clone();args.AeroCdSamples[0,0]=99;
        AtmosphereTests.Near(ltrClone.AeroCdSamples[0,0],1.5,0,"LTR clone isolation");
        Parallel.For(0,32,i=> {
            var result=LTR.LTRCore.PredictTrajectory(0,state,ltrClone);
            AtmosphereTests.Near(result.t,dark.t,0,"parallel LTR determinism");
            var afsResult=AFS.AFSCore.PredictTrajectory(0,afsState,clone,plan);
            AtmosphereTests.Near(afsResult.t,second.t,0,"parallel AFS determinism");
        });
        // A chained prediction must retain the original snapshot and elapsed t.
        ltrClone.targetAltitude=250;var intermediate=LTR.LTRCore.PredictTrajectory(0,state,ltrClone);
        ltrClone.targetAltitude=0;var chained=LTR.LTRCore.PredictTrajectory(intermediate.t,intermediate.finalState,ltrClone);
        AtmosphereTests.Near(chained.t,dark.t,.002,"LTR chain time");
        AtmosphereTests.Near((chained.finalState.vecR-dark.finalState.vecR).x,0,.02,"LTR chain impact");
        Console.WriteLine("Predictor tests passed: AFS/LTR solar-density response, terminal crossings, immutable configuration copies, 32 concurrent predictions and chained LTR time.");
    }
    private static void NearImpact(double3 position,double radius) {AtmosphereTests.Near(math.length(position),radius,.011,"impact radius");}
}
// Any main-thread capture from a trajectory worker is a test failure.
namespace KOSAtmosphere
{
    public static class AtmosphereCapture
    {
        public static AtmosphereSnapshot Capture(Vessel vessel) {throw new InvalidOperationException("Worker tried to capture live game state");}
    }
}
