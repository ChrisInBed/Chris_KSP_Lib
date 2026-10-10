"""Reproduce the combined 2026-10-09 native thermal benchmark report."""
import argparse,base64,hashlib,html,json,re
from pathlib import Path
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from analyze_benchmark import main as analyze_one

RUNS=[('20261009T144209054Z_c42a2be8','Pad'),('20261009T144534973Z_99b004d7','Pad'),('20261009T144748567Z_4303e9e7','Pad'),('20261009T144928975Z_8ef30933','Ascent'),('20261009T145027143Z_59787571','Ascent'),('20261009T145104172Z_5857ac21','Ascent'),('20261009T145518428Z_5d7af39d','Reentry'),('20261009T145532447Z_af3bccac','Reentry'),('20261009T145538145Z_109e9faa','Reentry'),('20261009T145730936Z_b12075a3','UEntry active')]
COLORS={'Pad':'#527da5','Ascent':'#d58b28','Reentry':'#158c84','UEntry active':'#9b57a0'}
plt.rcParams.update({'font.family':'DejaVu Sans','font.size':10,'axes.spines.top':False,'axes.spines.right':False,'axes.grid':True,'grid.alpha':.18,'axes.titleweight':'bold'})

def main(folder):
    folder=Path(folder);out=folder/'analysis';figdir=out/'figures';figdir.mkdir(parents=True,exist_ok=True)
    tables={k:[] for k in ['timings','parity','frames']};environments=[];hashes={};man=[]
    for i,(name,condition) in enumerate(RUNS,1):
        p=folder/name;analyze_one(p)
        assert (p/'completion.txt').read_text().startswith('Complete\n')
        env=dict(line.split('=',1) for line in (p/'environment.txt').read_text().splitlines() if '=' in line and not line.startswith('assembly='))
        assert env['KSP']=='1.12.5' and env['Unity']=='2019.4.18f1' and env['body']=='Earth'
        assert env['native_curve_declared_thread_safe']=='True' and env['managed_curves_supported']=='True'
        assembly_lines=(p/'environment.txt').read_text().splitlines()
        assert 'assembly=Assembly-CSharp|0.0.0.0|4b449f28-41f8-4227-adfa-ad3149c8fdba' in assembly_lines
        assert 'assembly=UnityEngine.CoreModule|0.0.0.0|12e76cd5-0cc6-4cf1-9e75-9e981cb725af' in assembly_lines
        environments.append(dict(run=i,session=name,condition=condition,**env))
        for f in ['timings.csv','parity.csv','frames.csv','environment.txt','completion.txt']:hashes[name+'/'+f]=hashlib.sha256((p/f).read_bytes()).hexdigest()
        man.append(dict(run=i,session=name,condition=condition,wall_seconds=float((p/'completion.txt').read_text().split('wall_seconds=')[1].splitlines()[0]),input_bytes=sum((p/f).stat().st_size for f in ['timings.csv','parity.csv','frames.csv','environment.txt','completion.txt'])))
        for k in tables:
            d=pd.read_csv(p/(k+'.csv'),float_precision='round_trip');d['run']=i;d['session']=name;d['condition']=condition;tables[k].append(d)
    t,p,f=(pd.concat(tables[k],ignore_index=True) for k in ['timings','parity','frames'])
    assert t.groupby('run').size().eq(156).all() and p.groupby('run').size().eq(920).all()
    assert t.error.fillna('').eq('').all()
    assert t[['mode','workers','repeat','worker','run']].duplicated().sum()==0
    worker=t[t.workers.gt(0)&~t['mode'].str.contains('group_wall')].copy()
    assert worker.groupby(['run','mode','workers']).size().eq(worker.groupby(['run','mode','workers']).workers.first()*5).all()
    assert worker.calls.eq(32768).all() and worker.thread_id.ne(1).all()
    assert worker[['checksum','expected_checksum']].notna().all().all()
    assert (worker.checksum.ne(worker.expected_checksum).astype(int)==worker.timed_checksum_mismatches).all()
    worker['sweep_mismatches']=worker.determinism_mismatches-worker.timed_checksum_mismatches
    assert worker.sweep_mismatches.ge(0).all()
    assert worker.groupby(['run','mode','workers','repeat']).thread_id.nunique().eq(worker.groupby(['run','mode','workers','repeat']).workers.first()).all()
    air=p[p.native_temperature_k.gt(0)].copy()
    rank=air[air.native_density_kg_m3.ge(1e-8)].copy()
    rank['computed_density_error_percent']=(rank.snapshot_density_kg_m3/rank.native_density_kg_m3-1)*100
    assert np.allclose(rank.computed_density_error_percent,rank.density_relative_error*100,atol=1e-11)
    assert np.allclose(air.snapshot_temperature_k-air.native_temperature_k,air.temperature_error_k,atol=1e-10)
    assert p.status.eq('finite').all()
    vacuum=p[p.native_temperature_k.eq(0)&p.native_pressure_pa.eq(0)]
    assert vacuum.snapshot_pressure_pa.eq(0).all() and vacuum.snapshot_density_kg_m3.eq(0).all()
    captures=np.array([float(e['snapshot_capture_ms']) for e in environments])
    t['ns_computed']=t.elapsed_ms*1e6/t.calls
    assert np.allclose(t.ns_computed,t.ns_per_call)
    costs=[]
    for (run,condition,mode,workers),g in t.groupby(['run','condition','mode','workers']):
        costs.append(dict(run=run,condition=condition,mode=mode,workers=workers,calls=int(g.calls.sum()),elapsed_ms=float(g.elapsed_ms.sum()),ns_per_call=float(g.elapsed_ms.sum()*1e6/g.calls.sum())))
    costs=pd.DataFrame(costs)
    performance=costs.groupby(['condition','mode','workers']).ns_per_call.agg(['count','median','min','max']).reset_index()
    concurrency=worker.groupby(['mode','workers']).agg(batches=('calls','size'),calls=('calls','sum'),sweep_queries=('calls',lambda s:len(s)*460),sweep_mismatches=('sweep_mismatches','sum'),checksum_mismatches=('timed_checksum_mismatches','sum'),max_density_relative_difference=('max_density_relative_difference','max'),max_temperature_difference_k=('max_temperature_difference_k','max'),max_pressure_difference_pa=('max_pressure_difference_pa','max')).reset_index()
    parity=[]
    for (run,condition,mode),g in p.groupby(['run','condition','mode']):
        a=air[(air.run==run)&air['mode'].eq(mode)];r=rank[(rank.run==run)&rank['mode'].eq(mode)]
        parity.append(dict(run=run,condition=condition,mode=mode,rows=len(g),air_rows=len(a),density_rows=len(r),density_mae_percent=float(abs(r.computed_density_error_percent).mean()),density_max_percent=float(abs(r.computed_density_error_percent).max()),temperature_max_k=float(abs(a.temperature_error_k).max()),pressure_max_pa=float(abs(a.pressure_error_pa).max()),offset_max_k=float(abs(a.offset_error_k).max())))
    parity=pd.DataFrame(parity)
    worst=rank[rank['mode'].eq('managed_hermite')].loc[rank[rank['mode'].eq('managed_hermite')].computed_density_error_percent.abs().idxmax()]
    for name,data in [('timings_all',t),('parity_all',p),('frames_all',f),('run_costs',costs),('performance_summary',performance),('concurrency_summary',concurrency),('parity_by_run',parity),('runs',pd.DataFrame(man)),('environment_summary',pd.DataFrame(environments))]:data.to_csv(out/(name+'.csv'),index=False)
    figures=[]
    def save(fig,name,caption):
        fig.savefig(figdir/(name+'.png'),dpi=180,bbox_inches='tight');fig.savefig(figdir/(name+'.svg'),bbox_inches='tight');plt.close(fig);figures.append((name,caption))
    labels=[f'P{i}' for i in range(1,4)]+[f'A{i}' for i in range(1,4)]+[f'R{i}' for i in range(1,4)]+['R+UE']
    fig,ax=plt.subplots(figsize=(11.4,5.1),layout='constrained')
    for mode,workers,label,color,shift in [('full_native_main',0,'Full native API (main thread)','#173b56',-.17),('copied_native_curves',1,'Copied Unity curves (one worker only)','#d58b28',0),('managed_hermite',1,'Managed Hermite (one worker)','#158c84',.17)]:
        d=costs[costs['mode'].eq(mode)&costs.workers.eq(workers)].sort_values('run');ax.plot(d.run+shift,d.ns_per_call/1000,'o-',label=label,color=color,lw=1.2)
    ax.set_xticks(range(1,11),labels);ax.set_ylim(0,1.5);ax.set_ylabel('Measured microseconds per query');ax.set_title('Per-run query cost | native-equation snapshot is fast',loc='left');ax.legend(loc='upper right');ax.set_xlabel('Pad / ascent / reentry repeats; final run has UEntry active')
    save(fig,'01_query_cost','Each point is total measured time / total calls within one run. The frozen kernels exclude latitude/longitude-to-world conversion and live API lookups. All workloads include the same query traversal and checksum overhead; about 16% of the deterministic input set is vacuum. The faster copied-native kernel is not accepted for shared concurrent use.')
    fig,axes=plt.subplots(1,2,figsize=(11.4,5),layout='constrained')
    for mode,label,color,shift in [('copied_native_curves','Shared copied Unity curves','#c44569',-.045),('managed_hermite','Managed Hermite','#158c84',.045)]:
        d=worker[worker['mode'].eq(mode)].groupby(['run','workers']).agg(sweep=('sweep_mismatches','sum'),checks=('timed_checksum_mismatches','sum'),n=('calls','size')).reset_index()
        for run,g in d.groupby('run'):
            axes[0].plot(g.workers+shift,g.sweep/(g.n*460)*100,'o-',color=color,alpha=.6,lw=.8,label=label if run==1 else None)
        total=d.groupby('workers').agg(checks=('checks','sum'),n=('n','sum'));axes[1].plot(total.index+shift,total.checks/total.n*100,'o-',color=color,label=label,lw=2)
    axes[0].set_ylabel('Exact mismatch rate in validation sweep (%)');axes[1].set_ylabel('Timed batches with checksum mismatch (%)')
    for ax in axes:ax.set_xticks([1,2,4]);ax.set_xlabel('Concurrent workers');ax.legend(loc='upper left');ax.set_ylim(-3,105 if ax is axes[1] else 36)
    axes[0].set_title('Individual query failures in every multi-worker trial',loc='left');axes[1].set_title('Every 2/4-worker native checksum fails',loc='left')
    save(fig,'02_concurrency_failures','Left: per-run sweeps, 460 queries per batch; the checksum flag is subtracted from the combined mismatch counter. Right: timed-checksum failures across all runs, 0/50 with one native worker, 100/100 with two, 200/200 with four. Managed Hermite has zero sweep and checksum failures. Timed checksum counts are batch failures, not the number of bad timed queries.')
    fig,axes=plt.subplots(1,3,figsize=(11.4,4.7),layout='constrained')
    multi=worker[worker['mode'].eq('copied_native_curves')&worker.workers.gt(1)].groupby(['run','workers']).max(numeric_only=True).reset_index()
    for ax,col,scale,unit,title in [(axes[0],'max_density_relative_difference',100,'Absolute relative density difference (%)','Density'),(axes[1],'max_temperature_difference_k',1,'Absolute temperature difference (K)','Temperature'),(axes[2],'max_pressure_difference_pa',1,'Absolute pressure difference (Pa)','Pressure')]:
        for w,marker in [(2,'o'),(4,'s')]:
            d=multi[multi.workers.eq(w)];ax.scatter(d.run,d[col]*scale,c=[COLORS[RUNS[int(r)-1][1]] for r in d.run],marker=marker,s=36,label=f'{w} workers')
        ax.set_yscale('log');ax.set_xticks(range(1,11),labels,rotation=45,fontsize=8);ax.set_ylabel(unit);ax.set_title(title,loc='left');ax.legend(fontsize=8)
    fig.suptitle('Shared native-curve mismatches are far beyond float rounding',fontweight='bold')
    save(fig,'03_concurrent_error_magnitudes','These are absolute discrepancies against the same frozen variant evaluated on the main thread, not errors against changing live atmosphere. Relative density maxima include thin air, so pressure and temperature are also shown. They are maxima from untimed sweeps; the timed loops are audited by checksum, not logged per query.')
    managed=parity[parity['mode'].eq('managed_hermite')].sort_values('run')
    fig,axes=plt.subplots(1,2,figsize=(11.4,4.8),layout='constrained')
    for ax,col,target,unit,title in [(axes[0],'density_max_percent',.01,'Maximum absolute density error (%)','Native API parity: density'),(axes[1],'temperature_max_k',.02,'Maximum absolute ambient error (K)','Native API parity: temperature')]:
        ax.scatter(managed.run,managed[col],c=[COLORS[c] for c in managed.condition],s=48);ax.axhline(target,color='#8395a7',ls='--',label='Provisional gate');ax.set_yscale('log');ax.set_xticks(range(1,11),labels);ax.set_ylabel(unit);ax.set_title(title,loc='left');ax.legend(loc='upper left')
    save(fig,'04_managed_parity','Same-frame comparison against the full native API at 460 locations per run. Density excludes reference density below 1e-8 kg/m3; temperature uses all atmospheric rows. Copied native curves match the API exactly in the serial parity test, but their concurrent failure remains decisive. Managed Hermite is well inside both gates.')
    fig,axes=plt.subplots(1,2,figsize=(11.4,4.9),layout='constrained')
    for condition in COLORS:
        for run,g in costs[costs.condition.eq(condition)&costs['mode'].eq('managed_hermite')].groupby('run'):
            axes[0].plot(g.workers,g.ns_per_call/1000,'o-',color=COLORS[condition],alpha=.7,lw=1,label=condition if run==next(i for i,(n,c) in enumerate(RUNS,1) if c==condition) else None)
        for run,g in costs[costs.condition.eq(condition)&costs['mode'].eq('managed_hermite_group_wall')].groupby('run'):
            axes[1].plot(g.workers,1000/g.ns_per_call,'o-',color=COLORS[condition],alpha=.7,lw=1)
    axes[0].set_ylabel('Per-worker microseconds / query');axes[1].set_ylabel('Group throughput (million timed queries / second)');axes[0].set_title('Managed kernel: per-worker cost remains stable',loc='left');axes[1].set_title('Complete group wall cost, including audit overhead',loc='left')
    for ax in axes:ax.set_xticks([1,2,4]);ax.set_xlabel('Concurrent workers')
    axes[0].legend(loc='upper left');axes[0].set_ylim(.4,.6)
    save(fig,'05_managed_scaling','Group wall duration includes all five repetitions, untimed sweeps, post-timing checksum verification and main-thread completion polling. Work increases with worker count; this is throughput scaling, not evidence that a single integration becomes four times faster. The tested CPU reports 16 logical processors.')
    valid_frames=f[~f.stage.eq('idle')].copy()
    fig,axes=plt.subplots(1,2,figsize=(11.4,4.7),layout='constrained')
    for stage,label,color,shift in [('idle baseline (logger suspended)','Baseline','#173b56',-.12),('managed_hermite workers=1','Managed: one worker','#158c84',.12)]:
        d=valid_frames[valid_frames.stage.eq(stage)].sort_values('run');axes[0].scatter(d.run+shift,d.p95_ms,label=label,color=color,s=34);axes[1].scatter(d.run+shift,d.frames,label=label,color=color,s=34)
    axes[0].set_ylabel('Logged p95 frame time (ms)');axes[1].set_ylabel('Frames in stage summary');axes[0].set_title('Frame observations require cautious interpretation',loc='left');axes[1].set_title('Worker windows have only 3-4 frame samples',loc='left')
    for ax in axes:ax.set_xticks(range(1,11),labels);ax.legend(loc='upper right')
    save(fig,'06_frame_observations','Baseline windows contain 60 frames; managed-worker windows contain only 3-4. Their p95 is not a reliable tail-latency estimate and cannot prove an FPS effect. Stale rows named idle are excluded: the benchmark retains the previous stage frame buffer and writes it when the next run starts.')
    stats=dict(inputs_sha256=hashes,runs=man,worker_calls=int(worker.calls.sum()),worker_batches=len(worker),parity_rows=len(p),concurrency=concurrency.to_dict('records'),parity_by_run=parity.to_dict('records'),performance=performance.to_dict('records'),snapshot_capture_ms=captures.tolist(),managed_worst_density_row=worst[['run','session','latitude_deg','longitude_deg','altitude_m','computed_density_error_percent','native_density_kg_m3']].to_dict(),warm_capture_median_ms=float(np.median(captures[1:])),native_worker_mismatch_count=int(worker.loc[worker['mode'].eq('copied_native_curves'),'determinism_mismatches'].sum()))
    (out/'metrics.json').write_text(json.dumps(stats,indent=2,allow_nan=False),encoding='utf-8')
    make_report(out,stats,figures,costs,parity,concurrency,valid_frames,environments)
    print(json.dumps({'report':str(out/'report.html'),'figures':len(figures),'managed_max_density_error_percent':managed.density_max_percent.max(),'managed_max_temperature_error_k':managed.temperature_max_k.max(),'native_mismatches':stats['native_worker_mismatch_count']},indent=2))


def make_report(out,stats,figures,costs,parity,concurrency,frames,environments):
    sections=[]
    def add(title,body):sections.append((title,body.strip()))
    managed=parity[parity['mode'].eq('managed_hermite')]
    native=concurrency[concurrency['mode'].eq('copied_native_curves')]
    mdensity=managed.density_max_percent.max();mtemp=managed.temperature_max_k.max();mp=managed.pressure_max_pa.max()
    one=costs[costs['mode'].eq('managed_hermite')&costs.workers.eq(1)]
    ue=one[one.condition.eq('UEntry active')].ns_per_call.iloc[0]
    reentry=one[one.condition.eq('Reentry')].ns_per_call.median()
    pooled=(managed.density_mae_percent*managed.density_rows).sum()/managed.density_rows.sum()
    add('Decision',f'''Select the **native KSP thermal equations evaluated with managed Hermite curves over an immutable main-thread snapshot** for the worker implementation. The full live KSP API remains a main-thread operation. Reject the shared copied-Unity-curve variant for concurrent use in this tested installation.

The managed kernel completed **11,468,800 timed calls** and **161,000 exact-reference sweep queries** with zero deterministic mismatches, zero timed checksum mismatches and zero reported exceptions at 1, 2 and 4 workers across all ten runs. Its worst density discrepancy against the native API was **{mdensity:.8g}%**, and its worst atmospheric temperature discrepancy was **{mtemp:.8g} K**. It therefore passes both provisional parity gates with ample margin.

A one-worker query costs about **{one.ns_per_call.median()/1000:.3f} microseconds** on this machine. The UEntry-active run measures **{ue/1000:.3f} microseconds**, about **{(ue/reentry-1)*100:.2f}%** above the median of the three inactive reentry runs. This single active run does not establish a causal slowdown, but it shows no major cost increase or loss of correctness.

These results give no reason to introduce a coarser spatial or altitude lookup table for performance. Managed Hermite evaluates the loaded native curve keys and preserves the selected atmosphere equations. No change to kOS-AFS/kOS-LTR or altitude alignment is made by this analysis.''')
    add('Coverage and provenance',f'''Ten complete runs: three on the launchpad, three during ascent, three during reentry, and one during reentry with UEntry active. Each contains 156 timing rows and 920 parity rows. Together they provide **{stats['worker_calls']:,} timed worker calls**, 700 worker timing batches and 9,200 native-versus-snapshot parity rows. Each variant has 4,600 parity rows; {int(managed.density_rows.sum()):,} enter its sufficient-density relative-error comparison.

All environments report Earth, CelestialBody, KSP 1.12.5, Unity 2019.4.18f1, benchmark schema/version 1, 16 logical processors, copied-native Evaluate declared thread safe, and managed curves supported. All five repetitions and all worker counts are present in every run; no exception row is present. All worker thread IDs differ from the recorded main-thread ID. Runs take **{min(r['wall_seconds'] for r in stats['runs']):.3f}-{max(r['wall_seconds'] for r in stats['runs']):.3f} seconds**. Total original input size is {sum(r['input_bytes'] for r in stats['runs'])/1048576:.2f} MiB.

Inputs are preserved. SHA-256 hashes of all 50 input files are recorded in metrics.json. The corresponding session reports are in each session's analysis directory. The phase labels come from the user, not inferred from altitude.

The parity set combines a global latitude/longitude grid, exact and near poles, negative altitude, atmospheric curve heights, atmosphere-boundary/vacuum cases and 64 positions around the current vehicle. Main-thread reference and snapshot capture occur without yielding, using the same game ephemeris. Kernel timing receives prepared radial geometry; the full API also pays coordinate conversion and live state lookup costs. About 16% of the deterministic input set is vacuum, so these means are not air-only microbenchmarks.''')
    run_table=['| Run | Condition | Session | Wall seconds |','|---:|---|---|---:|']
    for r in stats['runs']:run_table.append(f"| {r['run']} | {r['condition']} | {r['session']} | {r['wall_seconds']:.3f} |")
    add('Run inventory','\n'.join(run_table))
    conc=['| Variant | Workers | Timed calls | Sweep mismatches / queries | Failed timed checksums / batches |','|---|---:|---:|---:|---:|']
    for r in concurrency.to_dict('records'):
        label='Copied Unity curves' if r['mode']=='copied_native_curves' else 'Managed Hermite'
        conc.append(f"| {label} | {r['workers']} | {r['calls']:,} | {r['sweep_mismatches']:,} / {r['sweep_queries']:,} | {r['checksum_mismatches']:,} / {r['batches']:,} |")
    add('Concurrency failure: shared Unity curves','\n'.join(conc)+f'''

All ten runs fail the shared-native variant with two and four workers. Every multi-worker timed native batch has a checksum mismatch: **300/300**. The combined mismatch field totals **{stats['native_worker_mismatch_count']:,}**, consisting of **7,785 bad sweep queries** plus **300 failed timed checksums**. These categories must not be interpreted as 8,085 bad timed calls: the timed loop logs a checksum per batch, not every result.

This is not a float-rounding tolerance issue. Untimed sweeps record absolute temperature differences up to **{native.max_temperature_difference_k.max():,.3f} K**, pressure differences up to **{native.max_pressure_difference_pa.max()/1e6:.3f} MPa**, and absolute relative density differences up to **{native.max_density_relative_difference.max():.6g}** (dimensionless). Relative density maxima include thin air, but the independent absolute temperature and pressure discrepancies are already disqualifying.

One native worker has no observed mismatch over 1,638,400 timed calls. Serial native-copy parity against KSP has zero recorded pressure, temperature, density or atmospheric-offset difference. Thus the equations and serial copied-curve path are supported; simultaneous sharing is the failing condition.

The loaded DLL and [Unity 2019.4 bindings](https://github.com/Unity-Technologies/UnityCsReference/blob/2019.4/Runtime/Export/Animation/AnimationCurve.bindings.cs) declare AnimationCurve.Evaluate thread safe. That annotation was a candidate-selection signal, not sufficient evidence of safe concurrent evaluation in this KSP runtime. The shared native evaluation path is the leading suspect after inspecting the private read-only managed state, but a direct minimal single-curve reproducer would be needed to isolate the exact engine mechanism. No specific internal cache bug is claimed as proven.

Private native curves per worker or serialization might avoid sharing, but neither option was tested here. The current results do not justify selecting them over the managed implementation.''')
    add('Managed parity and boundaries',f'''Across the {int(managed.density_rows.sum()):,} sufficient-density comparisons, pooled density MAE is **{pooled:.8g}%**, maximum density error is **{mdensity:.8g}%**, maximum atmospheric temperature error is **{mtemp:.8g} K**, and maximum atmospheric pressure error is **{mp:.8g} Pa**. Atmospheric offset difference is at most {managed.offset_max_k.max():.8g} K.

The worst ranked density case occurs in run {int(stats['managed_worst_density_row']['run'])}, latitude {stats['managed_worst_density_row']['latitude_deg']:.6f} degrees, longitude {stats['managed_worst_density_row']['longitude_deg']:.6f} degrees, altitude {stats['managed_worst_density_row']['altitude_m']/1000:.6f} km. It remains well below the 0.01% density gate; all atmospheric temperatures remain below the 0.02 K error gate.

All 9,200 snapshot outputs are flagged finite and nonnegative in the original parity records. Every true vacuum row (at or above 140 km) returns zero pressure and density. At 139,999 m, KSP rounds pressure to zero while managed Hermite returns about 1.10e-11 Pa and density about 7e-17 kg/m3. This is an in-atmosphere boundary-rounding difference, not failed vacuum handling; a relative error against zero is undefined. These rows remain in temperature and absolute-pressure checks. Both exact poles and the below-sea-level and atmospheric boundary cases are covered. Temperature metrics include atmospheric thin air and zero-pressure rows with positive native temperature; relative density ranking excludes reference density below 1e-8 kg/m3.

This measures numerical agreement with the KSP API at the same frozen ephemeris. It does not independently remeasure live gas along the craft, and it should not be combined arithmetically with the first flight's reference-alignment residual. Managed interpolation follows copied unweighted key tangents; tiny rounding differences from Unity are expected. Weighted and looping curves remain explicitly unsupported by this candidate.''')
    costtable=['| Condition | Full API, main (us) | Unity curves, 1 worker (us) | Managed, 1 worker (us) | Managed, 2 workers (us) | Managed, 4 workers (us) |','|---|---:|---:|---:|---:|---:|']
    for condition in COLORS:
        vals=[]
        for mode,w in [('full_native_main',0),('copied_native_curves',1),('managed_hermite',1),('managed_hermite',2),('managed_hermite',4)]:
            z=costs[costs.condition.eq(condition)&costs['mode'].eq(mode)&costs.workers.eq(w)].ns_per_call/1000
            vals.append(f'{z.median():.3f}'+(f' ({z.min():.3f}-{z.max():.3f})' if len(z)>1 else ''))
        costtable.append('| '+condition+' | '+' | '.join(vals)+' |')
    add('Efficiency and projected integration cost','\n'.join(costtable)+f'''

Each value is the median of per-run weighted ns/call; parentheses give the range of the three repeats. Multi-worker entries are per-worker kernel cost, not group throughput. Failed concurrent native timings are not candidates for production and are omitted from this decision table.

Across the ten one-worker managed runs, cost ranges from {one.ns_per_call.min()/1000:.3f} to {one.ns_per_call.max()/1000:.3f} us/query. The measured loop includes delegate dispatch, deterministic index traversal, cancellation checks every 32 calls and a checksum accumulation. The constant-output main-thread control is about 0.026-0.029 us/query for most runs, with one 0.043 us outlier. It is not subtracted from the reported cost.

At a representative **0.48 us/query**, 10,000 calls cost about **4.8 ms**, 100,000 about **48 ms**, and one million about **0.48 s**. Six atmosphere evaluations per attempted RKF45 step contribute approximately **2.9 us per step** before other integration work and retry costs. These are query-cost projections, not measured complete trajectory runtimes. A high iteration count can still make atmosphere a material cost despite its fast per-call time.

Warm snapshot capture ranges from {min(stats['snapshot_capture_ms'][1:])*1000:.1f} to {max(stats['snapshot_capture_ms'][1:])*1000:.1f} us, median {stats['warm_capture_median_ms']*1000:.2f} us. The first observed capture is {stats['snapshot_capture_ms'][0]*1000:.1f} us. Capture is a one-time main-thread setup cost per snapshot, not a per-query cost. It includes eight private Unity curves in this benchmark; a final managed-only object can own just copied keys and scalars.

All environments report allocation_counter_available=False and allocated_bytes=-1. Bytes/query were **not measured**; zero allocation cannot be claimed from these logs. No GC collection is recorded inside any timing batch or valid active frame stage. That observation is not proof of zero allocation.''')
    add('UEntry-active run and frame-time limits',f'''The final run preserves zero managed mismatches and exceptions at every worker count. Its one-worker managed cost is {ue/1000:.6f} us/query, compared with {reentry/1000:.6f} us median for the three earlier reentry runs. Two/four-worker sharing does not destabilize the managed kernel. Active UEntry does not rescue the native shared-curve variant; it still fails at two and four workers.

The UEntry-active baseline has median frame time about 24.8 ms and p95 about 34.24 ms. Managed one-worker p95 is about 31.37 ms, but that stage contains only four frames. This is insufficient to conclude that frame rate improved or that the kernel has no frame impact. Worker windows across runs contain only 2-4 frames; main stages have 19 frames and baselines 60. None of those short worker summaries provides a robust tail-latency measurement.

A benchmark bookkeeping defect was identified: rows named **idle** carry the previous stage's frame buffer into the next run, because Finish does not clear it. Their GC deltas can span the time between runs. These idle rows are retained in frames_all.csv for audit but excluded from figures and conclusions. The 26 per-generation GC deltas in idle rows must not be attributed to benchmark query execution. This does not affect kernel timings, checksum comparisons or same-frame API parity.

Group-wall throughput includes untimed correctness sweeps, post-timing checksum checks, scheduling and completion polling at game-frame boundaries. The kernel loop timings are the useful one-worker cost estimate. All stages run in a fixed order, so cross-stage/condition differences are descriptive observations rather than controlled causal comparisons.''')
    add('Production recommendation and remaining contract','''Use a main-thread capture step for body configuration, loaded curve keys, gas constants and solar/orbit state. Publish a private immutable managed snapshot to the background predictor and evaluate the reconstructed native equations with managed Hermite curves. Multiple predictions can safely read the same private managed arrays under this ownership design; prevent mutation or exposure of those arrays after publication.

Use explicit vacuum behavior and preserve loaded latitude, solar-lag, seasonal and eccentricity terms. Keep the direct native API as a main-thread reference for regression/parity checks. Do not reuse the shared copied-Unity-curve candidate in concurrent predictors merely because its binding declares thread safety.

These benchmarks validate a **current-ephemeris** snapshot with prepared radial geometry. The final predictor must define how its body-fixed/rotating-frame trajectory positions convert into the snapshot's axes as prediction time advances. Body rotation changes sun height during the predicted flight; season and orbital solar direction also evolve over longer horizons. That future-time contract is not exercised by repeatedly querying frozen inputs here. Seasonal accuracy on other dates, other body configurations, runtime overrides and weighted curves remains outside this dataset.

No additional benchmark is needed to reject the shared native-curve variant or to choose the managed kernel for implementation. The next work is production API integration and time/coordinate validation, followed by an end-to-end UEntry prediction check. Altitude/CoM alignment remains unchanged as requested.''')
    add('Reproduction and delivered artifacts','''Run from the repository root with numpy, pandas and matplotlib installed:

python src/KSP-AtmosphereResearch/tools/report_benchmarks.py src/KSP-AtmosphereResearch/artifacts/Logs/Benchmarks

This script targets the ten sessions listed in this report. It regenerates each session's standard-library analysis and the combined analysis directory. Combined artifacts include self-contained report.html, report.md, six PNG/SVG diagram pairs, metrics.json with input hashes, run_costs.csv, performance_summary.csv, concurrency_summary.csv, parity_by_run.csv, runs.csv, environment_summary.csv and complete copied aggregate CSV tables. The source CSVs and original environment/completion files are unchanged.

Assertions check completion, expected batch/worker coverage, distinct worker threads, finite parity and vacuum results, consistent checksums, recomputed error units and timing math. The report records observed failures and does not change the test mod or the flight libraries.''')
    md=['# KSP native thermal benchmark results','', 'Ten runs · Earth · KSP 1.12.5 / Unity 2019.4.18f1','']
    for title,body in sections:md+=['## '+title,'',body,'']
    md+=['## Diagrams','']
    for name,caption in figures:md+=['![Diagram](figures/'+name+'.png)','',caption,'']
    (out/'report.md').write_text('\n'.join(md),encoding='utf-8')
    def inline(text):
        text=html.escape(text);text=re.sub(r'\*\*(.+?)\*\*',r'<strong>\1</strong>',text)
        text=re.sub(r'\[([^]]+)\]\((https://[^)]+)\)',r'<a href="\2">\1</a>',text)
        return text.replace('\n','<br>')
    def render(body):
        result=[]
        for block in body.split('\n\n'):
            if block.startswith('|'):
                rows=block.splitlines();headers=[s.strip() for s in rows[0].strip('|').split('|')];data=[[s.strip() for s in x.strip('|').split('|')] for x in rows[2:]]
                result.append('<div class="tablewrap"><table><thead><tr>'+''.join('<th>'+inline(s)+'</th>' for s in headers)+'</tr></thead><tbody>'+''.join('<tr>'+''.join('<td>'+inline(s)+'</td>' for s in row)+'</tr>' for row in data)+'</tbody></table></div>')
            else:result.append('<p>'+inline(block)+'</p>')
        return ''.join(result)
    css='body{font:16px/1.6 system-ui,Segoe UI,sans-serif;color:#223247;background:#edf2f6;margin:0}main{max-width:1120px;margin:30px auto;background:white;padding:42px 50px;border-radius:12px}h1{font-size:32px;line-height:1.2;color:#173b56}h2{margin-top:38px;color:#173b56;font-size:23px}.badge{display:inline-block;background:#e5f3f3;color:#08636c;padding:4px 12px;border-radius:20px;font-weight:600}.tablewrap{overflow-x:auto}table{border-collapse:collapse;width:100%;font-size:13px}th,td{padding:10px 7px;border-bottom:1px solid #dfe6ed;text-align:right}th:first-child,td:first-child{text-align:left}th{background:#edf4f7}figure{margin:28px 0 38px}figure img{width:100%;height:auto}figcaption{font-size:14px;color:#52677b}a{color:#087f8c}@media(max-width:720px){main{margin:0;padding:22px}h1{font-size:27px}}@media print{body{background:white}main{margin:0;padding:0;max-width:none}figure{break-inside:avoid}h2{break-after:avoid}}'
    chunks=['<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>KSP native thermal benchmark results</title><style>'+css+'</style></head><body><main><header><span class="badge">10 in-game runs · 22.94 million timed worker calls</span><h1>Native atmosphere: performance and concurrency</h1><p>Selected implementation: native equations + managed Hermite curves in an immutable snapshot.</p></header>']
    for title,body in sections:chunks.append('<section><h2>'+html.escape(title)+'</h2>'+render(body)+'</section>')
    chunks.append('<section><h2>Diagrams</h2>')
    for name,caption in figures:
        data=base64.b64encode((out/'figures'/(name+'.png')).read_bytes()).decode();chunks.append('<figure><img alt="'+name+'" src="data:image/png;base64,'+data+'"><figcaption>'+html.escape(caption)+'</figcaption></figure>')
    chunks.append('</section></main></body></html>');(out/'report.html').write_text(''.join(chunks),encoding='utf-8')

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('folder',type=Path);main(parser.parse_args().folder)
