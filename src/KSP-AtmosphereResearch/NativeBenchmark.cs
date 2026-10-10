using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Threading;
using System.Threading.Tasks;
using UnityEngine;

namespace KSPAtmosphereResearch
{
    [KSPAddon(KSPAddon.Startup.Flight, false)]
    public sealed class NativeBenchmark : MonoBehaviour
    {
        public static bool Active { get; private set; }
        private static readonly CultureInfo Inv=CultureInfo.InvariantCulture;
        private static readonly Func<long> Allocated=AllocationCounter();
        private bool visible=true, available=true;
        private string status="Ready. F8 hides/shows this panel.",directory,stage="idle";
        private CancellationTokenSource cancellation;
        private ManualResetEventSlim gate;
        private StreamWriter timing,parity,frames;
        private Stopwatch runClock;
        private int repeats=5,calls=32768;
        private List<double> frameSamples=new List<double>();
        private int[] gcStart=new int[3];
        private bool dropNextFrame;
        private readonly StockCandidate native=new StockCandidate(true);
        private void Start()
        {
            ConfigNode cfg=GameDatabase.Instance.GetConfigNode("KSP_ATMOSPHERE_RESEARCH");
            bool flag;
            if(cfg!=null && bool.TryParse(cfg.GetValue("benchmarkEnabled"),out flag)) available=flag;
            if(!available) { enabled=false; return; }
        }
        private void Update() { if(Active && stage!="idle") { if(dropNextFrame)dropNextFrame=false;else frameSamples.Add(Time.unscaledDeltaTime*1000.0); } }
        private void OnGUI()
        {
            if(!available) return;
            if(Event.current.type==EventType.KeyDown && Event.current.keyCode==KeyCode.F8) { visible=!visible;Event.current.Use(); }
            if(!visible) return;
            GUILayout.BeginArea(new Rect(Math.Max(5,Screen.width-425),90,415,190),GUI.skin.box);
            GUILayout.Label("Atmosphere: native efficiency / thread test");
            GUILayout.Label(status);
            GUI.enabled=!Active;
            if(GUILayout.Button("Run benchmark (~10-30 seconds)")) Begin();
            GUI.enabled=Active;
            if(GUILayout.Button("Cancel")) { if(cancellation!=null) cancellation.Cancel(); }
            GUI.enabled=true;
            GUILayout.EndArea();
        }
        private void Begin()
        {
            try { BeginCore(); }
            catch(Exception error) { CloseFiles();Active=false;status="Cannot start: "+error.Message;if(cancellation!=null)cancellation.Cancel(); }
        }
        private void BeginCore()
        {
            Vessel vessel=FlightGlobals.ActiveVessel;
            if(!FlightGlobals.ready || vessel==null || vessel.mainBody==null || !vessel.mainBody.atmosphere)
            { status="Enter flight around an atmosphere-bearing body first."; return; }
            directory=Path.Combine(KSPUtil.ApplicationRootPath,"Logs","AtmosphereResearch","Benchmarks",
                DateTime.UtcNow.ToString("yyyyMMddTHHmmssfffZ",Inv)+"_"+Guid.NewGuid().ToString("N").Substring(0,8));
            Directory.CreateDirectory(directory);
            cancellation=new CancellationTokenSource();runClock=Stopwatch.StartNew();Active=true;
            timing=new StreamWriter(Path.Combine(directory,"timings.csv"));
            timing.WriteLine("mode,workers,repeat,worker,thread_id,calls,elapsed_ms,ns_per_call,allocated_bytes,gc0,gc1,gc2,checksum,determinism_mismatches,max_density_relative_difference,max_temperature_difference_k,max_pressure_difference_pa,expected_checksum,timed_checksum_mismatches,error");
            parity=new StreamWriter(Path.Combine(directory,"parity.csv"));
            parity.WriteLine("mode,index,latitude_deg,longitude_deg,altitude_m,native_pressure_pa,native_temperature_k,native_density_kg_m3,native_offset_k,snapshot_pressure_pa,snapshot_temperature_k,snapshot_density_kg_m3,snapshot_offset_k,density_relative_error,temperature_error_k,pressure_error_pa,offset_error_k,status");
            frames=new StreamWriter(Path.Combine(directory,"frames.csv"));
            frames.WriteLine("stage,frames,p50_ms,p95_ms,max_ms,gc0,gc1,gc2");
            StartCoroutine(Guarded(Execute(vessel.mainBody,vessel.latitude,vessel.longitude,vessel.altitude)));
        }
        private IEnumerator Guarded(IEnumerator work)
        {
            while(true)
            {
                bool more=false;object next=null;Exception failure=null;
                try { more=work.MoveNext();if(more)next=work.Current; }
                catch(Exception error) { failure=error; }
                if(failure!=null) { Finish("Failed",failure);yield break; }
                if(!more)yield break;
                yield return next;
            }
        }
        private IEnumerator Execute(CelestialBody body,double vehicleLat,double vehicleLon,double vehicleAlt)
        {
            ThermalSnapshot snapshot=null;ThermalInput[] inputs=null;ThermalValue[] reference=null;
            Exception setupError=null;
            try
            {
                inputs=BuildInputs(body,vehicleLat,vehicleLon,vehicleAlt);
                Stopwatch setup=Stopwatch.StartNew();long alloc=Bytes();snapshot=ThermalSnapshot.Capture(body);
                double snapshotMs=setup.Elapsed.TotalMilliseconds;long snapshotAlloc=Bytes()-alloc;
                reference=new ThermalValue[inputs.Length];
                // No yield: capture and native reference have the same game ephemeris and orientation.
                for(int i=0;i<inputs.Length;i++) reference[i]=SampleNative(body,inputs[i]);
                WriteEnvironment(body,snapshot,snapshotMs,snapshotAlloc);
                for(int i=0;i<inputs.Length;i++) WriteParity("copied_native_curves",i,inputs[i],reference[i],snapshot.Evaluate(inputs[i],false));
                if(snapshot.ManagedSupported) for(int i=0;i<inputs.Length;i++) WriteParity("managed_hermite",i,inputs[i],reference[i],snapshot.Evaluate(inputs[i],true));
                parity.Flush();
            }
            catch(Exception e) { setupError=e; }
            if(setupError!=null) { Finish("Setup failed",setupError);yield break; }
            ThermalSnapshot frozen=snapshot;ThermalInput[] points=inputs;
            SetStage("idle baseline (logger suspended)");
            for(int i=0;i<60;i++) { if(Cancelled()) { Finish("Cancelled",null);yield break; } yield return null; }
            List<Func<ThermalInput,ThermalValue>> kernels=new List<Func<ThermalInput,ThermalValue>> { p=>SampleNative(body,p),p=>frozen.Evaluate(p,false) };
            List<string> names=new List<string> {"full_native","copied_native_curves"};
            if(snapshot.ManagedSupported) { kernels.Add(p=>frozen.Evaluate(p,true));names.Add("managed_hermite"); }
            kernels.Add(p=>new ThermalValue(100000,300,1,0));names.Add("harness_control");
            // Bound main-thread work by 256 calls, with a soft 2 ms budget checked every 32 calls.
            for(int k=0;k<kernels.Count;k++)
            {
                Func<ThermalInput,ThermalValue> kernel=kernels[k];
                for(int i=0;i<64;i++) kernel(points[i%points.Length]); // JIT warmup, not timed
                SetStage(names[k]+" main");
                for(int repeat=0;repeat<20;repeat++)
                {
                    if(Cancelled()) { Finish("Cancelled",null);yield break; }
                    Batch result=RunBatch(kernel,points,null,256,repeat,0,cancellation.Token,true);
                    WriteBatch(names[k]+"_main",0,repeat,0,result);yield return null;
                }
            }
            bool unitySafe=CopiedCurve.NativeEvaluateDeclaredThreadSafe();
            for(int mode=0;mode<2;mode++)
            {
                if(mode==0 && !unitySafe) continue;
                if(mode==1 && !snapshot.ManagedSupported) continue;
                bool managed=mode==1;
                Func<ThermalInput,ThermalValue> workerKernel=p=>frozen.Evaluate(p,managed);
                ThermalValue[] deterministic=new ThermalValue[points.Length];
                for(int i=0;i<points.Length;i++) deterministic[i]=workerKernel(points[i]);
                string name=managed?"managed_hermite":"copied_native_curves";
                foreach(int count in new[] {1,2,4})
                {
                    if(Cancelled()) { Finish("Cancelled",null);yield break; }
                    SetStage(name+" workers="+count);
                    gate=new ManualResetEventSlim(false);
                    ManualResetEventSlim startGate=gate;CancellationToken token=cancellation.Token;
                    int ready=0;
                    Task<Batch[]>[] jobs=new Task<Batch[]>[count];
                    for(int worker=0;worker<count;worker++)
                    {
                        int workerIndex=worker;int localRepeats=repeats,localCalls=calls;
                        jobs[worker]=Task.Factory.StartNew(()=>
                        {
                            for(int i=0;i<64;i++) workerKernel(points[(i+workerIndex)%points.Length]);
                            Interlocked.Increment(ref ready);startGate.Wait(token);
                            Batch[] results=new Batch[localRepeats];
                            for(int r=0;r<localRepeats;r++) results[r]=RunBatch(workerKernel,points,deterministic,localCalls,r,workerIndex,token,false);
                            return results;
                        },token,TaskCreationOptions.LongRunning,TaskScheduler.Default);
                    }
                    while(Volatile.Read(ref ready)<count && !AnyFinished(jobs) && !Cancelled()) yield return null;
                    Stopwatch groupClock=Stopwatch.StartNew();startGate.Set();
                    while(!AllFinished(jobs) && !Cancelled()) yield return null;
                    if(Cancelled()) { Finish("Cancelled",null);yield break; }
                    double groupMs=groupClock.Elapsed.TotalMilliseconds;
                    double checksum=0;long total=0;bool errors=false;
                    for(int worker=0;worker<count;worker++)
                    {
                        if(jobs[worker].IsFaulted || jobs[worker].IsCanceled)
                        { errors=true;WriteBatch(name,count,-1,worker,new Batch { Error=jobs[worker].IsCanceled?"cancelled":jobs[worker].Exception.ToString() }); continue; }
                        Batch[] results=jobs[worker].Result;
                        for(int r=0;r<results.Length;r++) { WriteBatch(name,count,r,worker,results[r]);total+=results[r].Calls;checksum+=results[r].Checksum;if(results[r].Error!="") errors=true; }
                    }
                    WriteBatch(name+"_group_wall",count,-1,-1,new Batch { Calls=total,ElapsedMs=groupMs,Checksum=checksum,Allocated=-1,Error=errors?"worker_error":"" });
                    startGate.Dispose();gate=null;
                }
            }
            Finish("Complete",null);
        }
        private static bool AllFinished(Task<Batch[]>[] jobs) { foreach(var job in jobs) if(!job.IsCompleted) return false;return true; }
        private static bool AnyFinished(Task<Batch[]>[] jobs) { foreach(var job in jobs) if(job.IsCompleted) return true;return false; }
        private bool Cancelled() { return cancellation.IsCancellationRequested || runClock.Elapsed.TotalSeconds>60; }
        private static ThermalInput[] BuildInputs(CelestialBody body,double lat,double lon,double alt)
        {
            List<ThermalInput> points=new List<ThermalInput>();
            // Includes poles, night/day, longitude wrap and negative/boundary/vacuum altitudes.
            double[] heights={-100,0,10,1000,10000,30000,60000,90000,body.atmosphereDepth-1,body.atmosphereDepth,body.atmosphereDepth+1};
            foreach(double latitude in new[] {-90.0,-89.99,-60,-30,0,30,60,89.99,90})
                foreach(double longitude in new[] {-180.0,-90,0,90})
                    foreach(double height in heights) points.Add(Input(body,latitude,longitude,height));
            for(int i=0;i<64;i++) points.Add(Input(body,Math.Max(-90,Math.Min(90,lat+(i-32)*.1)),lon+(i-32)*.2,Math.Max(-100,Math.Min(body.atmosphereDepth+1,alt+(i-32)*100))));
            return points.ToArray();
        }
        private static ThermalInput Input(CelestialBody body,double lat,double lon,double alt)
        { return new ThermalInput { Latitude=lat,Longitude=lon,Altitude=alt,Up=FlightGlobals.getUpAxis(body,body.GetWorldSurfacePosition(lat,lon,alt)) }; }
        private ThermalValue SampleNative(CelestialBody body,ThermalInput p)
        {
            AtmosphereSample value=native.Sample(new AtmosphereQuery(body,p.Latitude,p.Longitude,p.Altitude));
            return new ThermalValue(value.PressurePa,value.TemperatureK,value.DensityKgM3,value.TemperatureOffsetK);
        }
        private sealed class Batch
        {
            public long Calls,Allocated=-1,Mismatches;public int ThreadId;
            public double ElapsedMs,Checksum,MaxDensity,MaxTemperature,MaxPressure,ExpectedChecksum=double.NaN;public int TimedChecksumMismatches;public int Gc0,Gc1,Gc2;
            public string Error="";
        }
        private static Batch RunBatch(Func<ThermalInput,ThermalValue> kernel,ThermalInput[] points,ThermalValue[] expected,int calls,int repeat,int worker,CancellationToken token,bool main)
        {
            Batch result=new Batch { ThreadId=Thread.CurrentThread.ManagedThreadId };
            // Validate before timing: rotate traversal orders to expose shared mutable caches.
            try
            {
                if(expected!=null) for(int i=0;i<points.Length;i++)
                {
                    int j=(i*197+worker*47+repeat*31)%points.Length;
                    ThermalValue value=kernel(points[j]),truth=expected[j];
                    if(!Same(value.PressurePa,truth.PressurePa)||!Same(value.TemperatureK,truth.TemperatureK)||!Same(value.Density,truth.Density)||!Same(value.Offset,truth.Offset)) result.Mismatches++;
                    result.MaxTemperature=Math.Max(result.MaxTemperature,Math.Abs(value.TemperatureK-truth.TemperatureK));
                    result.MaxPressure=Math.Max(result.MaxPressure,Math.Abs(value.PressurePa-truth.PressurePa));
                    if(truth.Density>0) result.MaxDensity=Math.Max(result.MaxDensity,Math.Abs(value.Density/truth.Density-1));
                }
                int a=GC.CollectionCount(0),b=GC.CollectionCount(1),c=GC.CollectionCount(2);long allocation=Bytes();
                Stopwatch watch=Stopwatch.StartNew();
                for(int i=0;i<calls;i++)
                {
                    if((i&31)==0) { token.ThrowIfCancellationRequested();if(main && i>0 && watch.Elapsed.TotalMilliseconds>=2) break; }
                    int j=(i*197+worker*47+repeat*31)%points.Length;
                    ThermalValue value=kernel(points[j]);result.Checksum+=value.Density+value.TemperatureK*.0001+value.PressurePa*.0000001;result.Calls++;
                }
                watch.Stop();result.ElapsedMs=watch.Elapsed.TotalMilliseconds;
                result.Allocated=Allocated==null?-1:Bytes()-allocation;
                result.Gc0=GC.CollectionCount(0)-a;result.Gc1=GC.CollectionCount(1)-b;result.Gc2=GC.CollectionCount(2)-c;
                if(expected!=null)
                {
                    double expectedSum=0;
                    for(int i=0;i<result.Calls;i++)
                    {
                        int j=(i*197+worker*47+repeat*31)%points.Length;ThermalValue value=expected[j];
                        expectedSum+=value.Density+value.TemperatureK*.0001+value.PressurePa*.0000001;
                    }
                    result.ExpectedChecksum=expectedSum;
                    if(result.Checksum!=expectedSum) { result.TimedChecksumMismatches=1;result.Mismatches++; }
                }
            }
            catch(Exception error) { result.Error=error.GetType().FullName+": "+error.Message; }
            return result;
        }
        private static bool Same(double a,double b) { return a==b || (double.IsNaN(a)&&double.IsNaN(b)); }
        private static long Bytes() { return Allocated==null?-1:Allocated(); }
        private static Func<long> AllocationCounter()
        {
            MethodInfo method=typeof(GC).GetMethod("GetAllocatedBytesForCurrentThread",BindingFlags.Public|BindingFlags.Static);
            return method==null?null:(Func<long>)Delegate.CreateDelegate(typeof(Func<long>),method);
        }
        private void WriteParity(string mode,int i,ThermalInput p,ThermalValue a,ThermalValue b)
        {
            bool valid=AtmosphereQuery.Finite(b.PressurePa)&&AtmosphereQuery.Finite(b.TemperatureK)&&AtmosphereQuery.Finite(b.Density)&&b.PressurePa>=0&&b.TemperatureK>=0&&b.Density>=0;
            parity.WriteLine(string.Join(",",new[] {mode,N(i),N(p.Latitude),N(p.Longitude),N(p.Altitude),N(a.PressurePa),N(a.TemperatureK),N(a.Density),N(a.Offset),N(b.PressurePa),N(b.TemperatureK),N(b.Density),N(b.Offset),N(a.Density>0?b.Density/a.Density-1:double.NaN),N(b.TemperatureK-a.TemperatureK),N(b.PressurePa-a.PressurePa),N(b.Offset-a.Offset),valid?"finite":"invalid"}));
        }
        private void WriteBatch(string mode,int workers,int repeat,int worker,Batch b)
        {
            timing.WriteLine(string.Join(",",new[] {mode,N(workers),N(repeat),N(worker),N(b.ThreadId),N(b.Calls),N(b.ElapsedMs),N(b.Calls>0?b.ElapsedMs*1e6/b.Calls:double.NaN),N(b.Allocated),N(b.Gc0),N(b.Gc1),N(b.Gc2),N(b.Checksum),N(b.Mismatches),N(b.MaxDensity),N(b.MaxTemperature),N(b.MaxPressure),N(b.ExpectedChecksum),N(b.TimedChecksumMismatches),Csv(b.Error)}));timing.Flush();
        }
        private void SetStage(string next)
        { FlushFrames();stage=next;dropNextFrame=true;status=next+" — running";frameSamples.Clear();for(int i=0;i<3;i++)gcStart[i]=GC.CollectionCount(i); }
        private void FlushFrames()
        {
            if(frames==null||frameSamples.Count==0) return;
            frameSamples.Sort();int n=frameSamples.Count;
            frames.WriteLine(string.Join(",",new[] {stage,N(n),N(frameSamples[(n-1)/2]),N(frameSamples[(int)((n-1)*.95)]),N(frameSamples[n-1]),N(GC.CollectionCount(0)-gcStart[0]),N(GC.CollectionCount(1)-gcStart[1]),N(GC.CollectionCount(2)-gcStart[2])}));frames.Flush();
        }
        private void WriteEnvironment(CelestialBody body,ThermalSnapshot snapshot,double captureMs,long allocated)
        {
            using(StreamWriter writer=new StreamWriter(Path.Combine(directory,"environment.txt")))
            {
                writer.WriteLine("schema_version=1\nbenchmark_version=1\nKSP="+Versioning.GetVersionString()+"\nUnity="+Application.unityVersion);
                writer.WriteLine("body="+body.name+"\nbody_type="+body.GetType().FullName+"\nUT="+N(snapshot.UniversalTime));
                writer.WriteLine("processor_count="+Environment.ProcessorCount+"\nmain_thread="+Thread.CurrentThread.ManagedThreadId+"\nstopwatch_frequency="+Stopwatch.Frequency);
                writer.WriteLine("snapshot_capture_ms="+N(captureMs)+"\nsnapshot_capture_allocated_bytes="+N(Allocated==null?-1:allocated));
                writer.WriteLine("native_curve_declared_thread_safe="+CopiedCurve.NativeEvaluateDeclaredThreadSafe()+"\nmanaged_curves_supported="+snapshot.ManagedSupported+"\nallocation_counter_available="+(Allocated!=null));
                writer.WriteLine("worker_calls_per_repeat="+calls+"\nworker_repeats="+repeats+"\nworker_counts=1,2,4\nraw_native_worker_test=excluded_transform_access\nreference_alignment=unchanged");
                foreach(Assembly assembly in AppDomain.CurrentDomain.GetAssemblies()) writer.WriteLine("assembly="+assembly.GetName().Name+"|"+assembly.GetName().Version+"|"+assembly.ManifestModule.ModuleVersionId);
            }
        }
        private void Finish(string outcome,Exception error)
        {
            FlushFrames();status=outcome+". Logs/AtmosphereResearch/Benchmarks/"+Path.GetFileName(directory);
            if(error!=null) status+=" — "+error.Message;
            File.WriteAllText(Path.Combine(directory,"completion.txt"),outcome+"\nwall_seconds="+N(runClock.Elapsed.TotalSeconds)+"\n"+(error==null?"":error.ToString()));
            CloseFiles();Active=false;stage="idle";
            if(cancellation!=null) cancellation.Cancel();if(gate!=null)gate.Set();
            UnityEngine.Debug.Log("[AtmosphereResearch] Benchmark "+status);
        }
        private void CloseFiles() { if(timing!=null){timing.Dispose();timing=null;}if(parity!=null){parity.Dispose();parity=null;}if(frames!=null){frames.Dispose();frames=null;} }
        private void OnDestroy() { if(cancellation!=null)cancellation.Cancel();if(gate!=null)gate.Set();CloseFiles();Active=false; }
        private static string N(object value) { return value is double?((double)value).ToString("R",Inv):Convert.ToString(value,Inv); }
        private static string Csv(string text) { return "\""+text.Replace("\"","\"\"").Replace("\r"," ").Replace("\n"," ")+"\""; }
    }
}
