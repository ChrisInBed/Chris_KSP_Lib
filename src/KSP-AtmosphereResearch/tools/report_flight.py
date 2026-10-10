"""Reproducible analysis of an AtmosphereResearch flight; no plugin files are changed."""
import argparse, base64, hashlib, html, json, re
from pathlib import Path
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

LABELS={'stock_thermal_now':'Native thermal', 'body_altitude_baseline':'Altitude only', 'flightglobals_position_baseline':'FlightGlobals position', 'far_registered':'FAR registered', 'trajectories_position':'Trajectories position', 'mechjeb_private_diagnostic':'MechJeb diagnostic'}
COLORS={'stock_thermal_now':'#087f8c','body_altitude_baseline':'#ca6f1e','trajectories_position':'#6554a4','mechjeb_private_diagnostic':'#c44569'}
REPRESENTATIVES=['stock_thermal_now','body_altitude_baseline','trajectories_position','mechjeb_private_diagnostic']
plt.rcParams.update({'font.family':'DejaVu Sans','font.size':10,'axes.spines.top':False,'axes.spines.right':False,'axes.grid':True,'grid.alpha':.18,'axes.titleweight':'bold','figure.facecolor':'white','savefig.facecolor':'white'})

def truth(series): return series.astype(str).str.lower().eq('true')
def finite(series): return np.isfinite(series)
def curve_keys(cfg,name):
    block=re.search(r'(?m)^'+re.escape(name)+r'\s*\{([^}]+)\}',cfg).group(1)
    return np.array([[float(a) for a in line.split()[2:]] for line in block.splitlines() if 'key =' in line])
def curve(cfg,name,x):
    k=curve_keys(cfg,name);x=np.asarray(x,dtype=np.float32).astype(float)
    i=np.clip(np.searchsorted(k[:,0],x,side='right')-1,0,len(k)-2);a=k[i];b=k[i+1];h=b[:,0]-a[:,0];t=np.clip((x-a[:,0])/h,0,1)
    return (2*t**3-3*t**2+1)*a[:,1]+(t**3-2*t**2+t)*h*a[:,3]+(-2*t**3+3*t**2)*b[:,1]+(t**3-t**2)*h*b[:,2]
def metrics(g):
    out={'n':len(g)}
    for field,ref in [('density_kg_m3','reference_density_kg_m3'),('temperature_k','reference_temperature_k'),('pressure_pa','reference_pressure_pa')]:
        e=g[field]-g[ref]
        for name,value in [('bias',e.mean()),('mae',e.abs().mean()),('rmse',np.sqrt((e**2).mean())),('max_abs',e.abs().max())]:out[field+'_'+name]=float(value)
    e=(g.density_kg_m3/g.reference_density_kg_m3-1)*100
    out.update(density_mae_percent=float(e.abs().mean()),density_max_abs_percent=float(e.abs().max()),density_bias_percent=float(e.mean()))
    return out

def main(session):
    session=Path(session)
    if session.name != '20261009T130829047Z_c5d8bd2e':
        raise ValueError('This report narrative is specific to the first flight; use analyze.py for other sessions.')
    out=session/'analysis';figdir=out/'figures';figdir.mkdir(parents=True,exist_ok=True)
    df=pd.read_csv(session/'samples.csv');cfg=(session/'1_body.cfg').read_text();env=(session/'environment.txt').read_text()
    assert len(df)==len(df.drop_duplicates(['sample_id','record_kind','probe_id','candidate']))
    assert df.schema_version.eq(1).all()
    v=df[df.record_kind.eq('vehicle')].copy();u=v[v.candidate.eq('stock_thermal_now')].sort_values('sample_id').copy()
    assert u.ut_s.is_monotonic_increasing and u.realtime_s.is_monotonic_increasing
    assert v.groupby('sample_id').candidate.nunique().eq(6).all()
    t0=u.ut_s.iloc[0];u['minutes']=(u.ut_s-t0)/60;u['real_minutes']=(u.realtime_s-u.realtime_s.iloc[0])/60
    vacuum=~truth(u.in_atmosphere);first_vac=u.loc[vacuum,'sample_id'].min();last_vac=u.loc[vacuum,'sample_id'].max()
    u['phase']=np.where(u.sample_id<first_vac,'Ascent',np.where(u.sample_id<=last_vac,'Suborbital coast','Reentry'))
    u.loc[u.situation.eq('PRELAUNCH'),'phase']='Prelaunch';u.loc[u.situation.eq('SPLASHED'),'phase']='After splashdown'
    v=v.merge(u[['sample_id','phase','minutes']],on='sample_id',validate='many_to_one')
    valid=truth(v.in_atmosphere)&v.status.eq('ok')&(v.reference_density_kg_m3>=1e-8)&(v.reference_temperature_k>0)&(v.reference_pressure_pa>0)&np.isfinite(v[['pressure_pa','temperature_k','density_kg_m3']]).all(axis=1)
    strict=valid&truth(v.reference_coherent)
    strict_ids=set(v.loc[strict,'sample_id'])
    assert v[strict].groupby('sample_id').candidate.nunique().eq(6).all()
    strict_metrics=pd.DataFrame([dict(candidate=c,**metrics(g)) for c,g in v[strict].groupby('candidate')]);strict_metrics.to_csv(out/'strict_metrics.csv',index=False)
    phase_metrics=pd.DataFrame([dict(phase=p,candidate=c,**metrics(g)) for (p,c),g in v[valid].groupby(['phase','candidate'])]);phase_metrics.to_csv(out/'phase_metrics_unaligned.csv',index=False)
    status=df.groupby(['record_kind','candidate','status']).size().reset_index(name='rows');status.to_csv(out/'status_counts.csv',index=False)
    probes=df[df.record_kind.eq('probe')].copy();probes.groupby(['probe_id','candidate','status']).size().reset_index(name='rows').to_csv(out/'probe_status.csv',index=False)
    gaps=u.assign(gap_ut_s=u.ut_s.diff(),gap_real_s=u.realtime_s.diff());gaps=gaps[gaps.gap_ut_s>30][['sample_id','minutes','altitude_m','gap_ut_s','gap_real_s']];gaps.to_csv(out/'sampling_gaps.csv',index=False)
    reference_ok=truth(u.reference_coherent)&truth(u.in_atmosphere)&(u.reference_density_kg_m3>=1e-8)
    air_finite=truth(u.in_atmosphere)&(u.reference_density_kg_m3>=1e-8)&finite(u.fi_altitude_m)
    aligned=u[air_finite].copy()
    aligned['aligned_temperature_k']=curve(cfg,'atmosphereTemperatureCurve',aligned.fi_altitude_m)+curve(cfg,'atmosphereTemperatureSunMultCurve',aligned.fi_altitude_m)*aligned.offset_k
    molar=float(re.search(r'(?m)^atmosphereMolarMass = (.+)$',cfg).group(1));gas=float(re.search(r'(?m)^idealGasConstant = (.+)$',cfg).group(1))
    aligned['aligned_density_kg_m3']=aligned.reference_pressure_pa*molar/gas/aligned.aligned_temperature_k
    aligned['aligned_density_error_percent']=(aligned.aligned_density_kg_m3/aligned.reference_density_kg_m3-1)*100
    aligned['pressure_geometry_error_percent']=(curve(cfg,'atmospherePressureCurve',aligned.altitude_m)/curve(cfg,'atmospherePressureCurve',aligned.fi_altitude_m)-1)*100
    aligned['pressure_actual_error_percent']=(aligned.pressure_pa/aligned.reference_pressure_pa-1)*100
    aligned.to_csv(out/'alignment_diagnostic.csv',index=False)
    alignstats=pd.DataFrame([{'phase':p,'n':len(g),'temperature_mae_k':float(abs(g.aligned_temperature_k-g.reference_temperature_k).mean()),'temperature_max_abs_k':float(abs(g.aligned_temperature_k-g.reference_temperature_k).max()),'density_mae_percent':float(abs(g.aligned_density_error_percent).mean()),'density_max_abs_percent':float(abs(g.aligned_density_error_percent).max())} for p,g in aligned.groupby('phase')]);alignstats.to_csv(out/'alignment_metrics.csv',index=False)
    spatial=probes[probes.probe_id.isin(['longitude_plus_90','longitude_plus_180','opposite_latitude'])].merge(v[['sample_id','candidate','temperature_k','density_kg_m3']].rename(columns={'temperature_k':'vehicle_candidate_T','density_kg_m3':'vehicle_candidate_rho'}),on=['sample_id','candidate'])
    spatial=spatial[spatial.status.eq('ok')&(spatial.vehicle_candidate_rho>1e-8)].copy();spatial['density_change_percent']=(spatial.density_kg_m3/spatial.vehicle_candidate_rho-1)*100
    spatial['temperature_change_k']=spatial.temperature_k-spatial.vehicle_candidate_T
    spatial_stats=spatial.groupby(['probe_id','candidate']).agg(n=('status','size'),density_change_max_abs_percent=('density_change_percent',lambda s:abs(s).max()),temperature_change_max_abs_k=('temperature_change_k',lambda s:abs(s).max())).reset_index();spatial_stats.to_csv(out/'spatial_probe_metrics.csv',index=False)
    figures=[]
    def save(fig,name,caption):
        fig.savefig(figdir/(name+'.png'),dpi=180,bbox_inches='tight');fig.savefig(figdir/(name+'.svg'),bbox_inches='tight');plt.close(fig);figures.append((name,caption))
    def line(ax,d,column,**kwargs):
        y=d[column].copy();y.loc[d.ut_s.diff()>30]=np.nan;ax.plot(d.minutes,y,**kwargs)
    entry=u.loc[u.sample_id==last_vac+1,'minutes'].iloc[0];exit_time=u.loc[u.sample_id==first_vac,'minutes'].iloc[0]
    fig,axes=plt.subplots(4,1,figsize=(11.4,10.4),sharex=True,layout='constrained')
    line(axes[0],u.assign(height_km=u.altitude_m/1000),'height_km',color='#173b56',lw=1.5);axes[0].axhline(140,color='#8395a7',ls='--',label='Earth atmosphere: 140 km');axes[0].scatter(u.loc[vacuum,'minutes'],u.loc[vacuum,'altitude_m']/1000,s=3,color='#8395a7');axes[0].set_ylabel('Altitude (km)');axes[0].legend(loc='upper right');axes[0].set_title('Flight 1 | ascent, suborbital coast and reentry',loc='left')
    apex=u.loc[u.altitude_m.idxmax()];axes[0].annotate(f'Recorded maximum: {apex.altitude_m/1000:.1f} km',(apex.minutes,apex.altitude_m/1000),xytext=(apex.minutes+3,220),arrowprops={'arrowstyle':'->','color':'#173b56'},fontsize=9)
    line(axes[1],u,'sun_height_deg',color='#d78b2b',lw=1.3);axes[1].axhline(0,color='#6b7785',lw=.8);axes[1].set_ylabel('Solar elevation (deg)')
    line(axes[2],u,'latitude_deg',color='#4e7b52',lw=1.3);axes[2].set_ylabel('Latitude (deg)')
    thermal=u.copy();thermal.loc[vacuum,['reference_temperature_k','external_temperature_k']]=np.nan;line(axes[3],thermal,'reference_temperature_k',color='#087f8c',label='Ambient gas (in atmosphere)',lw=1.5);line(axes[3],thermal,'external_temperature_k',color='#c44569',label='External / shock-heated (in atmosphere)',lw=1);axes[3].set_yscale('log');axes[3].set_ylabel('Temperature (K)');axes[3].legend(loc='upper right');axes[3].set_xlabel('Elapsed game time (minutes)')
    for ax in axes:
        ax.axvspan(exit_time,entry,color='#dfe6ed',alpha=.35);ax.axvline(entry,color='#8395a7',ls=':',lw=.8)
    save(fig,'01_flight_overview','Gray band is the above-atmosphere coast. Lines break at logged UT gaps over 30 seconds; isolated coast points are shown. The recorded maximum is not proof of the true apex between skipped samples. Temperatures are shown only in atmosphere; ambient and external temperature differ sharply during heating.')
    table=strict_metrics.set_index('candidate').loc[list(LABELS)]
    fig,axes=plt.subplots(1,2,figsize=(11.4,4.6),layout='constrained');yy=np.arange(len(table))
    for ax,column,title in [(axes[0],'density_mae_percent','Mean absolute density error (%)'),(axes[1],'density_max_abs_percent','Maximum absolute density error (%)')]:
        vals=table[column].to_numpy();ax.barh(yy,vals,color=[COLORS.get(c,'#8b98a7') for c in table.index],height=.66);ax.set_xscale('log');ax.set_yticks(yy,[LABELS[c] for c in table.index]);ax.invert_yaxis();ax.set_xlabel(title);ax.set_xlim(.003,15)
        for y,value in zip(yy,vals):ax.text(value*1.10,y,f'{value:.5g}',va='center',fontsize=9)
    fig.suptitle(f'Same {len(strict_ids):,} coherent nighttime reentry samples | reference density >= 1e-8 kg/m3',fontsize=12,fontweight='bold')
    save(fig,'02_candidate_comparison','All six methods use the same sample IDs. Logarithmic axes reveal the native method residual. FAR, FlightGlobals position and body altitude give effectively identical results in this flight.')
    fig,axes=plt.subplots(2,1,figsize=(11.4,7),sharex=True,layout='constrained')
    for c in REPRESENTATIVES:
        d=v[strict&v.candidate.eq(c)].copy();d['rho_pct']=(d.density_kg_m3/d.reference_density_kg_m3-1)*100
        axes[0].plot(d.minutes,d.rho_pct,label=LABELS[c],color=COLORS[c],lw=1.3 if c!='mechjeb_private_diagnostic' else .9,ls='--' if c=='mechjeb_private_diagnostic' else '-')
        axes[1].plot(d.minutes,d.temperature_error_k,color=COLORS[c],lw=1.2,ls='--' if c=='mechjeb_private_diagnostic' else '-')
    axes[0].set_ylabel('Signed density error (%)');axes[1].set_ylabel('Signed ambient error (K)');axes[1].set_xlabel('Elapsed game time (minutes)');axes[0].legend(ncol=2,loc='lower left');axes[0].set_title('Model differences during the ranked reentry interval',loc='left');
    for ax in axes:ax.axhline(0,color='#6b7785',lw=.8)
    save(fig,'03_reentry_errors','Negative density error means underprediction. MechJeb and Trajectories almost overlap. The altitude-only group changes sign as the loaded altitude multiplier changes sign; its largest underprediction occurs near the end of reentry.')
    fig,axes=plt.subplots(1,2,figsize=(11.4,5.4),layout='constrained')
    for c in ['stock_thermal_now','body_altitude_baseline','trajectories_position']:
        d=v[strict&v.candidate.eq(c)];e=(d.density_kg_m3/d.reference_density_kg_m3-1)*100;axes[0].scatter(e,d.altitude_m/1000,s=5,alpha=.55,color=COLORS[c],label=LABELS[c])
    grid=np.linspace(0,139999,1500);axes[1].plot(curve(cfg,'atmosphereTemperatureSunMultCurve',grid),grid/1000,color='#173b56');axes[1].axvline(0,color='#8395a7',lw=.8);axes[0].axvline(0,color='#8395a7',lw=.8);axes[0].set_xlabel('Signed density error (%)');axes[0].set_ylabel('Altitude (km)');axes[0].legend(loc='upper right');axes[0].set_title('Reentry error by altitude',loc='left');axes[1].set_xlabel('Configured thermal offset multiplier');axes[1].set_ylabel('Altitude (km)');axes[1].set_title('Captured Earth curve',loc='left');axes[0].set_ylim(0,140);axes[1].set_ylim(0,140)
    save(fig,'04_altitude_and_curve','The multiplier is dimensionless and can be negative. This shows why adding a fixed temperature or density correction cannot replace the loaded body curves. The scatter is one trajectory, so altitude, latitude and local sun angle are confounded.')
    fig,axes=plt.subplots(3,1,figsize=(11.4,9),sharex=True,layout='constrained')
    delta=u.altitude_m-u.fi_altitude_m;line(axes[0],u.assign(altitude_difference=delta),'altitude_difference',color='#173b56',lw=1);axes[0].axhline(1,color='#ca6f1e',ls='--',lw=.8);axes[0].axhline(-1,color='#ca6f1e',ls='--',lw=.8);axes[0].set_ylabel('Query - integrator\naltitude (m)');axes[0].set_title('Reference geometry explains most native residual',loc='left')
    raw=u[(u.reference_density_kg_m3>=1e-8)&truth(u.in_atmosphere)].copy();line(axes[1],raw.assign(native_error_percent=raw.density_relative_error*100),'native_error_percent',color='#ca6f1e',label='Original native query',lw=1);line(axes[1],aligned,'aligned_density_error_percent',color='#087f8c',label='Offline aligned diagnostic',lw=1);axes[1].set_ylabel('Native density error (%)');axes[1].legend(loc='lower right')
    line(axes[2],aligned,'pressure_actual_error_percent',color='#ca6f1e',label='Observed pressure error',lw=1.4);line(axes[2],aligned,'pressure_geometry_error_percent',color='#173b56',label='Snapshot curve at the two altitudes',ls='--',lw=.9);axes[2].set_ylabel('Pressure error (%)');axes[2].set_xlabel('Elapsed game time (minutes)');axes[2].legend(loc='lower right')
    for ax in axes:ax.axhline(0,color='#8395a7',lw=.7)
    save(fig,'05_reference_alignment','The diagnostic uses captured pressure, captured curves evaluated at FI altitude, and the independently queried native offset. It diagnoses alignment; it is not another prediction API or an independent accuracy test. The exact source of the location difference was not logged.')
    fig,axes=plt.subplots(1,2,figsize=(11.4,5),layout='constrained')
    for c in ['stock_thermal_now','body_altitude_baseline','trajectories_position']:
        d=spatial[spatial.candidate.eq(c)&spatial.probe_id.eq('longitude_plus_180')].merge(u[['sample_id','minutes']],on='sample_id');axes[0].scatter(d.minutes,d.density_change_percent,s=23,color=COLORS[c],label=LABELS[c],alpha=.8)
    axes[0].set_xlabel('Elapsed game time (minutes)');axes[0].set_ylabel('Density change at longitude +180 (%)');axes[0].set_title('Same body, latitude and altitude',loc='left');axes[0].legend(loc='lower left');axes[0].axhline(0,color='#8395a7',lw=.8)
    pole=probes[probes.probe_id.isin(['north_pole','south_pole'])&truth(probes.in_atmosphere)];fail=pole.groupby(['candidate','probe_id']).status.apply(lambda x:int(x.eq('invalid').sum())).unstack().reindex(list(LABELS));y=np.arange(len(fail));axes[1].barh(y-.18,fail.north_pole,height=.34,label='North pole',color='#c44569');axes[1].barh(y+.18,fail.south_pole,height=.34,label='South pole',color='#d78b2b');axes[1].set_yticks(y,[LABELS[c] for c in fail.index]);axes[1].invert_yaxis();axes[1].set_xlim(0,60);axes[1].set_xlabel('Invalid results out of 52 in-atmosphere probes');axes[1].set_title('Polar robustness',loc='left');axes[1].legend(loc='lower right')
    save(fig,'06_spatial_probes','Probe locations have no live reference. Left: change within each candidate, not prediction error; altitude-only methods are spatially invariant. Right: both spatial helpers fail every north-pole atmospheric probe; native thermal has no invalid probe.')
    fig,axes=plt.subplots(1,2,figsize=(11.4,4.5),layout='constrained');counts=[len(u),len(strict_ids),int(vacuum.sum()),int((truth(u.in_atmosphere)&(u.reference_density_kg_m3<1e-8)).sum()),int((truth(u.in_atmosphere)&(u.reference_density_kg_m3>=1e-8)&~truth(u.reference_coherent)).sum())];names=['Vehicle snapshots','Ranked reentry','Vacuum excluded','Thin air excluded','Alignment / missing FI excluded'];axes[0].barh(names,counts,color=['#173b56','#087f8c','#8395a7','#d78b2b','#c44569']);axes[0].invert_yaxis();axes[0].set_xlabel('Snapshots');axes[0].set_title('Coverage and exclusions',loc='left');
    for y,n in enumerate(counts):axes[0].text(n+35,y,f'{n:,}',va='center',fontsize=9)
    axes[0].set_xlim(0,3800);width=.35;parts=[]
    for phase in ['Prelaunch','Ascent','Suborbital coast','Reentry','After splashdown']:
        z=u[u.phase.eq(phase)];parts.append((phase,len(z),int(z.sample_id.isin(strict_ids).sum())))
    x=np.arange(len(parts));axes[1].bar(x-width/2,[z[1] for z in parts],width,color='#8395a7',label='Logged');axes[1].bar(x+width/2,[z[2] for z in parts],width,color='#087f8c',label='Ranked');axes[1].set_xticks(x,[z[0].replace(' ','\n') for z in parts],fontsize=9);axes[1].set_ylabel('Snapshots');axes[1].set_title('The strict ranking covers reentry only',loc='left');axes[1].legend()
    save(fig,'07_data_quality','The exclusions form a disjoint partition: 310 vacuum + 184 thin-air + 687 sufficient-density but unaligned/missing-FI + 2,032 ranked = 3,213. Counts are snapshots, not independent experiments.')
    stats={'session':session.name,'inputs_sha256':{f:hashlib.sha256((session/f).read_bytes()).hexdigest() for f in ['samples.csv','environment.txt','1_body.cfg']},'csv_rows':len(df),'vehicle_snapshots':len(u),'probe_rows':len(probes),'strict_snapshots':len(strict_ids),'wall_minutes':float(u.real_minutes.iloc[-1]),'game_minutes':float(u.minutes.iloc[-1]),'sampled_max_altitude_km':float(u.altitude_m.max()/1000),'all_latitude_range':u.latitude_deg.agg(['min','max']).to_dict(),'strict_ranges':u[reference_ok][['latitude_deg','sun_height_deg','altitude_m']].agg(['min','max']).to_dict(),'strict_metrics':strict_metrics.to_dict('records'),'alignment_metrics':alignstats.to_dict('records'),'phase_counts':u.phase.value_counts().to_dict(),'part_density_spread_max':float((u.max_part_density_kg_m3-u.min_part_density_kg_m3).max()),'native_offset_max_abs_difference_k':float(abs(aligned.offset_k-aligned.fi_offset_k).max()),'pressure_geometry_reconstruction_rmse_percentage_points':float(np.sqrt(np.mean((aligned.pressure_geometry_error_percent-aligned.pressure_actual_error_percent)**2)))}
    (out/'metrics.json').write_text(json.dumps(stats,indent=2,allow_nan=False),encoding='utf-8')
    u.to_csv(out/'vehicle_reference.csv',index=False)
    ranking=table[['n','density_mae_percent','density_max_abs_percent','temperature_k_mae','temperature_k_max_abs']].copy();ranking.index=[LABELS[c] for c in ranking.index];ranking.columns=['N','Density MAE (%)','Max absolute density error (%)','Temperature MAE (K)','Max absolute temperature error (K)'];ranking.to_csv(out/'ranking.csv')
    # Report body is added below; plots are standalone PNG/SVG and embedded in HTML.
    build_report(out,stats,ranking,phase_metrics,alignstats,figures,env,entry,exit_time)
    print(json.dumps({'output':str(out),'rows':len(df),'strict_samples':len(strict_ids),'figures':len(figures),'native_density_mae_percent':stats['strict_metrics'][4]['density_mae_percent']},indent=2))


def build_report(out,stats,ranking,phase_metrics,alignstats,figures,env,entry,exit_time):
    def fmt(value):
        return f'{value:,}' if isinstance(value,(int,np.integer)) else f'{value:.6g}'
    def mdtable(frame):
        columns=list(frame.columns);rows=['| Method | '+' | '.join(columns)+' |','|---|'+'---|'*len(columns)]
        for name,row in frame.iterrows():rows.append('| '+str(name)+' | '+' | '.join(fmt(x) for x in row)+' |')
        return '\n'.join(rows)
    sections=[]
    def add(title,text):sections.append((title,text.strip()))
    add('Decision supported by this flight',f'''The native thermal candidate is the leading implementation for the next validation round. On the same {stats['strict_snapshots']:,} coherent nighttime reentry snapshots, its mean absolute density error was **0.00660916%**, with a maximum of **0.0114304%**. The altitude-only methods averaged **1.80208%**, with a maximum of **7.01877%**. Trajectories and MechJeb averaged about **0.8008%**, with maxima near **4.1434%**.

This is a strong result for the tested Earth configuration and nighttime reentry. It does **not** yet validate daytime ascent, other seasons, other bodies or future-UT trajectory sampling. All strictly ranked snapshots are nighttime reentry. Keep kOS-AFS and kOS-LTR unchanged until those gaps are covered.

The native candidate means the project's current-time temperature path through CelestialBody.GetAtmoThermalStats and GetFullTemperature, with body pressure and the body's gas density conversion. It is not the altitude-only FlightGlobals position overload in this comparison.''')
    add('Flight and installed environment',f'''Session: {stats['session']}. Vehicle: X-20-Titan3C. Recorded phases include prelaunch, ascent, suborbital coast, reentry and splashdown.

There are **{stats['vehicle_snapshots']:,} vehicle snapshots**, six candidates per snapshot, and **{stats['probe_rows']:,} probe rows**: **{stats['csv_rows']:,} CSV rows** in total. The recorded interval spans **{stats['game_minutes']:.2f} game minutes** over **{stats['wall_minutes']:.2f} real minutes**. The highest sampled altitude is **{stats['sampled_max_altitude_km']:.3f} km**; gaps in coast sampling prevent claiming the true apex. The atmospheric boundary is 140 km. First sampled exit occurs at {exit_time:.3f} elapsed game minutes; first sampled return at {entry:.3f} minutes.

Environment evidence (loaded assembly versions, which may differ from mod release labels): KSP 1.12.5, RSS Earth, FAR 0.16.1.2, Trajectories 2.4.5.4, MechJeb 2.15.0.0, Kopernicus 1.0.247, ModularFlightIntegrator 1.0, RealHeat 5.1 and RealismOverhaul 0.12.8.1. FAR reports IsCustom=False. The captured Earth body is the standard CelestialBody type. See the original environment.txt and 1_body.cfg for the complete snapshot.

The input CSV is approximately **13.66 MiB**; this flight's observed data rate is about **29.9 MB per real hour**, including probe rows. Generated report files are separate from game logging. Three UT gaps exceed 30 seconds: approximately 1,932.5, 318.9 and 502.2 seconds. Diagrams do not join across these gaps.''')
    add('Reference and comparison method','''The live gas reference is vessel static pressure, ambient atmospheric temperature and atmospheric density, checked against FlightIntegrator fields. External or shock temperature is not ambient temperature: external temperature peaked near 6,079 K in this flight. Root, minimum and maximum recorded part density agree with vessel density throughout the log.

The strict comparison requires an in-atmosphere, finite, successful candidate; positive reference pressure and temperature; reference density at least 1e-8 kg/m3; and the logger's reference_coherent flag. That flag also requires query altitude to agree with FlightIntegrator altitude within 1 m. All six methods are compared on identical sample IDs.

Of 3,213 snapshots, 310 are vacuum, 184 are in-air but below the density threshold, and 687 have sufficient density but fail alignment or lack FlightIntegrator data. The remaining **2,032** enter the strict ranking. All are reentry snapshots with solar elevation from **-68.728 to -22.927 degrees**, altitude from **3.72 m to 127.531 km**, and latitude from **-6.487 to 51.452 degrees**.

858 snapshots fail the coherence flag overall: 797 exceed the altitude tolerance and 61 lack FlightIntegrator data. On all 3,152 snapshots with FlightIntegrator data, the captured vessel and integrator pressure, ambient temperature and density agree exactly. Thus the main reference issue is geometry, not disagreement between gas fields. These are correlated samples from one flight; the statistics are descriptive and do not establish confidence intervals across independent flights.

Density error is 100*(candidate/reference - 1). Mean absolute error and maximum absolute error use that percentage. Temperature errors are in kelvin; pressure errors are in pascals.''')
    add('Strict nighttime reentry results',mdtable(ranking)+'''

FAR registered, FlightGlobals position and body altitude results are effectively identical here. Their mean density bias is -1.32975%, versus -0.00607953% for native thermal. Native thermal has about 273 times smaller mean absolute density error than the altitude-only group and about 121 times smaller than the two legacy spatial helpers.

Every candidate has the same pressure calculation in these vehicle rows, with mean absolute pressure error 0.232626 Pa. Temperature handling explains the differences between candidate density results. The native residual still includes the allowed altitude mismatch of up to 1 m; it is not a measured numerical floor for the API.''')
    p=phase_metrics[phase_metrics.candidate.isin(['stock_thermal_now','body_altitude_baseline','trajectories_position','mechjeb_private_diagnostic']) & phase_metrics.phase.isin(['Prelaunch','Ascent'])].copy()
    p.index=[phase+' / '+LABELS[c] for phase,c in zip(p.phase,p.candidate)]
    p=p[['n','density_mae_percent','density_max_abs_percent','temperature_k_mae']];p.columns=['N','Density MAE (%)','Max absolute density error (%)','Temperature MAE (K)']
    add('Ascent evidence and geometry diagnostic',mdtable(p)+'''

These rows deliberately retain the altitude mismatch and therefore do not provide a fair independent accuracy ranking. The maximum query-minus-integrator altitude difference is **21.4516 m**, already present at prelaunch. The raw native ascent density error reaches **0.245333%**. The logger did not capture both location vectors or enough update-order evidence to prove why they differ.

An offline diagnostic evaluates the captured temperature curves at FlightIntegrator altitude while retaining the native candidate's independently queried thermal offset. Density then uses the **observed reference pressure**, captured molar mass and gas constant. This is a reference-assisted reconstruction, not a deployable candidate or independent validation. Hermite curve evaluation is an approximation to Unity's FloatCurve evaluation.

For 582 ascent rows with a usable integrator altitude, this reconstruction reduces temperature MAE to **0.0000242 K** and density MAE to **0.0000100%**. On 2,032 reentry rows, the corresponding values are **0.00000902 K** and **0.00000391%**. The original native offset and integrator offset differ by at most **0.00385050 K**. The captured pressure curve evaluated at the two altitudes reproduces the observed relative pressure discrepancy with RMSE about **0.00000438 percentage points**.

Together these observations support reference geometry as the dominant source of the native residual. The next logger revision should record both query and integrator sampling points and compare models at the same point before repeating ascent and daytime validation.''')
    add('Spatial probes and API robustness','''The 57 scheduled probe sets test boundary and spatial behavior, not accuracy against measured atmosphere at those locations. There are 52 atmospheric and five vacuum north-pole probes, and the same counts at the south pole.

Native thermal and both stock baselines return valid output for every logged vehicle and probe query. FAR produces 449 invalid density results: 310 vehicle vacuum rows and 139 vacuum probe rows. Its vacuum gas outputs are zero pressure and zero temperature, leading to NaN in this adapter's density conversion. A final API should explicitly return vacuum density zero rather than divide by zero; this is an adapter/API-contract issue, not evidence of an atmospheric density error in FAR.

Trajectories has 62 invalid probe rows and MechJeb has 64, all at the poles. Both fail **52/52 atmospheric north-pole queries**. Trajectories also fails 10/52 atmospheric south-pole queries; MechJeb fails 12/52. Neither fails at the actual vehicle positions. No unavailable adapter or exception status was logged. MechJeb is a private-method diagnostic, not a stable public API contract.

At identical body, latitude, altitude and time, changing longitude by 90 degrees changes native density by as much as **3.58132%**; a 180-degree change reaches **3.74076%**. Corresponding temperature changes reach **10.6067 K** and **10.2078 K**. The altitude-only group has zero spatial response; the two spatial helpers respond similarly to native but still disagree with live reentry reference. These probes demonstrate candidate sensitivity, not that native matches an unobserved atmosphere elsewhere.

The opposite-latitude probes show essentially zero change in this configuration. The solar axial component changes only from about -0.390656 to -0.390564 during this flight, so seasonal behavior has not been tested. The captured orbital eccentricity temperature curve is zero. Avoid interpreting this trajectory as an isolated experiment measuring the sun-height effect: altitude, latitude and time change together.''')
    add('Recommended next validation','''1. Fix reference-point alignment and add explicit query/integrator positions to the logger. Keep ambient, external and shock temperatures clearly distinct.
2. Repeat atmospheric ascent and reentry in daylight, and collect nighttime ascent at comparable latitude and altitude. Include a slow near-ground segment to limit geometry error.
3. Validate native spatial queries against live samples near both poles. Add a different season and, if multi-body support is required, another atmosphere-bearing body.
4. Verify future-UT solar geometry separately before using the API for trajectory prediction; this candidate's live-temperature validation is at current UT. Include longitude evolution with body rotation.
5. Preserve altitude-only, Trajectories and MechJeb as comparison controls. Define vacuum, negative-altitude and atmosphere-boundary behavior explicitly for the final API.

No model replacement inside kOS-AFS or kOS-LTR is made by this analysis. The evidence supports prioritizing native thermal, while the validation matrix remains incomplete.''')
    add('Reproduction and artifacts','''This report script reproduces this specific first flight; its narrative is session-specific. For other flights, use analyze.py until the report narrative is updated. Run from the repository root after installing Python packages numpy, pandas and matplotlib:

python src/KSP-AtmosphereResearch/tools/report_flight.py src/KSP-AtmosphereResearch/artifacts/Logs/20261009T130829047Z_c5d8bd2e

The analysis directory contains report.md, the self-contained report.html, seven PNG/SVG figure pairs, strict_metrics.csv, ranking.csv, phase_metrics_unaligned.csv, alignment_metrics.csv, alignment_diagnostic.csv, spatial_probe_metrics.csv, probe_status.csv, status_counts.csv, sampling_gaps.csv, vehicle_reference.csv and metrics.json. The pre-existing summary.csv and regimes.csv come from the project's simpler analyzer. Original input files are left intact; their SHA-256 hashes are recorded in metrics.json.

The plots and metrics are computed from local supplied flight data and the captured body curves. Mod/source behavior discussed here is limited to this installed environment and the project's implemented adapters.''')
    md=['# KSP Atmosphere Research — first flight','', 'Generated from session '+stats['session']+'.','']
    for title,body in sections:md.extend(['## '+title,'',body,''])
    md.extend(['## Diagrams',''])
    for name,caption in figures:md.extend(['![Diagram](figures/'+name+'.png)','',caption,''])
    (out/'report.md').write_text('\n'.join(md),encoding='utf-8')
    def render(body):
        chunks=[]
        for para in body.split('\n\n'):
            if para.startswith('|'):
                lines=para.splitlines();headers=[s.strip() for s in lines[0].strip('|').split('|')];rows=[[s.strip() for s in x.strip('|').split('|')] for x in lines[2:]]
                chunks.append('<div class="tablewrap"><table><thead><tr>'+''.join('<th>'+html.escape(s)+'</th>' for s in headers)+'</tr></thead><tbody>'+''.join('<tr>'+''.join('<td>'+html.escape(s)+'</td>' for s in row)+'</tr>' for row in rows)+'</tbody></table></div>')
            else:
                text=html.escape(para);text=re.sub(r'\*\*(.+?)\*\*',r'<strong>\1</strong>',text);chunks.append('<p>'+text.replace('\n','<br>')+'</p>')
        return ''.join(chunks)
    css='body{font:16px/1.6 system-ui,Segoe UI,sans-serif;color:#223247;background:#edf2f6;margin:0}main{max-width:1120px;margin:32px auto;background:white;padding:44px 52px;border-radius:12px}h1{font-size:32px;line-height:1.2;color:#173b56}h2{margin-top:38px;color:#173b56;font-size:23px}p{max-width:1000px}header p{color:#52677b}.pill{display:inline-block;background:#e5f3f3;color:#08636c;padding:4px 12px;border-radius:20px;font-weight:600}.tablewrap{overflow-x:auto}table{border-collapse:collapse;width:100%;font-size:13px}th,td{padding:10px 8px;border-bottom:1px solid #dfe6ed;text-align:right}th:first-child,td:first-child{text-align:left}th{background:#edf4f7}figure{margin:28px 0 38px}figure img{width:100%;height:auto}figcaption{font-size:14px;color:#52677b}a{color:#087f8c}footer{border-top:1px solid #dfe6ed;margin-top:40px;padding-top:15px;font-size:13px;color:#52677b}@media(max-width:720px){main{margin:0;padding:22px}h1{font-size:27px}}@media print{body{background:white}main{margin:0;padding:0;max-width:none}figure{break-inside:avoid}h2{break-after:avoid}thead{display:table-header-group}a{color:inherit}}'
    content=['<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>KSP atmosphere research — first flight</title><style>'+css+'</style></head><body><main><header><span class="pill">Flight 1 · Earth · RSS / RO / FAR</span><h1>KSP atmosphere model validation</h1><p>'+html.escape(stats['session'])+' · ascent, suborbital coast and reentry</p></header>']
    for title,body in sections:content.append('<section><h2>'+html.escape(title)+'</h2>'+render(body)+'</section>')
    content.append('<section><h2>Diagrams</h2>')
    for name,caption in figures:
        encoded=base64.b64encode((out/'figures'/(name+'.png')).read_bytes()).decode('ascii');content.append('<figure><img alt="'+html.escape(name)+'" src="data:image/png;base64,'+encoded+'"><figcaption>'+html.escape(caption)+'</figcaption></figure>')
    content.append('</section><footer>Standalone report: all diagrams are embedded. Raw files and machine-readable metrics remain alongside this report.</footer></main></body></html>')
    (out/'report.html').write_text(''.join(content),encoding='utf-8')

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('session',type=Path);main(parser.parse_args().session)
