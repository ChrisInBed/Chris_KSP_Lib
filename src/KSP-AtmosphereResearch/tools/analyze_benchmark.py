"""Summarize native benchmark CSVs using only the Python standard library."""
import argparse,csv,math,statistics
from collections import defaultdict
from pathlib import Path

def num(row,key,default=math.nan):
    try:return float(row[key])
    except (ValueError,KeyError):return default

def summarize_timings(rows):
    groups=defaultdict(list)
    for row in rows:groups[(row['mode'],int(row['workers']))].append(row)
    result=[]
    for (mode,workers),group in sorted(groups.items()):
        good=[r for r in group if not r['error'] and num(r,'calls')>0 and num(r,'elapsed_ms')>0]
        calls=sum(num(r,'calls',0) for r in good);ms=sum(num(r,'elapsed_ms',0) for r in good)
        per_call=[num(r,'ns_per_call') for r in good]
        allocated=[r for r in good if num(r,'allocated_bytes')>=0]
        result.append(dict(mode=mode,workers=workers,batches=len(group),errors=sum(bool(r['error']) for r in group),calls=int(calls),weighted_ns_per_call=ms*1e6/calls if calls else math.nan,median_ns_per_call=statistics.median(per_call) if per_call else math.nan,max_ns_per_call=max(per_call,default=math.nan),bytes_per_call=sum(num(r,'allocated_bytes') for r in allocated)/sum(num(r,'calls') for r in allocated) if allocated else math.nan,determinism_mismatches=sum(int(num(r,'determinism_mismatches',0)) for r in group),max_density_relative_difference=max((num(r,'max_density_relative_difference',0) for r in group),default=0),max_temperature_difference_k=max((num(r,'max_temperature_difference_k',0) for r in group),default=0)))
    return result

def summarize_parity(rows):
    groups=defaultdict(list)
    for r in rows:groups[r['mode']].append(r)
    result=[]
    for mode,group in sorted(groups.items()):
        air=[r for r in group if num(r,'native_temperature_k')>0]
        ranked=[r for r in air if num(r,'native_density_kg_m3')>=1e-8 and math.isfinite(num(r,'density_relative_error'))]
        density=[abs(num(r,'density_relative_error'))*100 for r in ranked]
        temperature=[abs(num(r,'temperature_error_k')) for r in air]
        pressure=[abs(num(r,'pressure_error_pa')) for r in air]
        maximum=lambda values:max(values,default=math.nan) if all(math.isfinite(x) for x in values) else math.inf
        result.append(dict(mode=mode,rows=len(group),invalid=sum(r['status']!='finite' for r in group),air_rows=len(air),ranked_density_rows=len(ranked),density_mae_percent=statistics.mean(density) if density else math.nan,density_max_abs_percent=maximum(density),temperature_max_abs_k=maximum(temperature),pressure_max_abs_pa=maximum(pressure),vacuum_nonzero=sum(num(r,'native_pressure_pa')==0 and num(r,'native_temperature_k')==0 and (num(r,'snapshot_pressure_pa')!=0 or num(r,'snapshot_density_kg_m3')!=0) for r in group)))
    return result

def write_csv(path,rows):
    if not rows:return
    with path.open('w',newline='',encoding='utf-8') as f:
        writer=csv.DictWriter(f,fieldnames=list(rows[0]));writer.writeheader();writer.writerows(rows)

def main(folder):
    folder=Path(folder);out=folder/'analysis';out.mkdir(exist_ok=True)
    with (folder/'timings.csv').open(newline='',encoding='utf-8-sig') as f:timings=list(csv.DictReader(f))
    with (folder/'parity.csv').open(newline='',encoding='utf-8-sig') as f:parity=list(csv.DictReader(f))
    ts=summarize_timings(timings);ps=summarize_parity(parity)
    write_csv(out/'timing_summary.csv',ts);write_csv(out/'parity_summary.csv',ps)
    complete=(folder/'completion.txt').read_text(encoding='utf-8-sig') if (folder/'completion.txt').exists() else 'Missing completion.txt'
    lines=['# Native thermal benchmark analysis','',folder.name,'','Completion: '+complete.splitlines()[0],'','## Measured costs','','| Mode | Workers | Batches | ns/call (weighted) | Bytes/call | Cost / 100,000 calls (ms) | Errors | Determinism mismatches |','|---|---:|---:|---:|---:|---:|---:|---:|']
    for r in ts:
        lines.append(f"| {r['mode']} | {r['workers']} | {r['batches']} | {r['weighted_ns_per_call']:.3f} | {r['bytes_per_call']:.3f} | {r['weighted_ns_per_call']*.1:.3f} | {r['errors']} | {r['determinism_mismatches']} |")
    lines+=['','Main worker-count 0 means the main thread. Group-wall rows measure aggregate throughput, including correctness sweeps, post-timing checksum checks, gate release, scheduling and frame-bound completion polling. Individual worker rows measure each kernel loop; summing their durations is not group wall time. Cost per 100,000 calls is a linear query-cost projection, not an integrated trajectory result. Allocation NaN means the runtime counter is unavailable; counters include harness bookkeeping. GC deltas in the raw CSV are process-wide.','','## Same-frame API parity','','| Frozen variant | Valid density comparisons | Density MAE (%) | Max density error (%) | Max atmospheric temperature error (K) | Max pressure error (Pa) | Invalid | Nonzero vacuum |','|---|---:|---:|---:|---:|---:|---:|---:|']
    for r in ps:lines.append(f"| {r['mode']} | {r['ranked_density_rows']} | {r['density_mae_percent']:.8g} | {r['density_max_abs_percent']:.8g} | {r['temperature_max_abs_k']:.8g} | {r['pressure_max_abs_pa']:.8g} | {r['invalid']} | {r['vacuum_nonzero']} |")
    for r in ps:
        checks=r['invalid']==0 and r['vacuum_nonzero']==0 and r['ranked_density_rows']>0 and r['density_max_abs_percent']<=.01 and r['temperature_max_abs_k']<=.02
        lines+=['',r['mode']+': '+('meets' if checks else 'does not meet')+' the provisional 0.01% density / 0.02 K temperature parity gates.']
    lines+=['','## Observed concurrency','','Full native GetAtmoThermalStats is excluded from workers because it reads live Unity transforms internally. Stress-test success cannot override that API restriction.']
    for mode in ['copied_native_curves','managed_hermite']:
        observed=[r for r in ts if r['mode']==mode and r['workers']>0]
        if not observed:lines+=['',mode+': no worker data; consult environment.txt for a skipped capability or interrupted run.'];continue
        passed=all(r['errors']==0 and r['determinism_mismatches']==0 and r['calls']>0 for r in observed)
        coverage=sorted({r['workers'] for r in observed})
        lines+=['',mode+': '+('no exception or deterministic mismatch observed' if passed else 'exceptions, missing calls or deterministic mismatches observed')+'; tested worker counts '+str(coverage)+'.']
        if coverage!=[1,2,4] or any(r['batches']!=r['workers']*5 for r in observed) or not complete.startswith('Complete\n'):lines+=['','**This run is incomplete; do not use it as a completed concurrency validation.**']
    frames=folder/'frames.csv'
    if frames.exists():
        lines+=['','## Observed frame times','','| Stage | Frames | Median (ms) | p95 (ms) | Maximum (ms) |','|---|---:|---:|---:|---:|']
        with frames.open(newline='',encoding='utf-8-sig') as f:
            for r in csv.DictReader(f):lines.append(f"| {r['stage']} | {r['frames']} | {num(r,'p50_ms'):.3f} | {num(r,'p95_ms'):.3f} | {num(r,'max_ms'):.3f} |")
    lines+=['','Frame changes include normal game variability and any concurrent UEntry work. Private snapshots freeze the ephemeris; this run does not validate future-UT rotation or season evolution. Use repeated baseline/active-flight runs before deciding whether query cost fits the integrator budget.','']
    (out/'report.md').write_text('\n'.join(lines),encoding='utf-8');print('Reports: '+str(out))

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('folder',type=Path);main(parser.parse_args().folder)
