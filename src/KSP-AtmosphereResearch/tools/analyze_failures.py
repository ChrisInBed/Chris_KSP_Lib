"""Explain installed legacy helpers using same-location candidate differences.
Run: python tools/analyze_failures.py <flight session>
No live-reference ranking is changed by this diagnostic regression.
"""
import json
from pathlib import Path
import re
import sys
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

session = Path(sys.argv[1])
config = (session / '1_body.cfg').read_text(encoding='utf-8-sig')
def curve(name, x):
    block = re.search(r'(?m)^' + re.escape(name) + r'\s*\{([^}]*)\}', config).group(1)
    keys = np.array([[float(v) for v in line.split()] for line in re.findall(r'key\s*=\s*([^\r\n]+)', block)], dtype=np.float32)
    x = np.asarray(x, dtype=np.float32)
    idx = np.searchsorted(keys[:,0], x, side='right') - 1
    lo = np.clip(idx, 0, len(keys)-2); a, b = keys[lo].astype(float), keys[lo+1].astype(float)
    h = b[:,0]-a[:,0]; t = (x.astype(float)-a[:,0])/h
    y = ((2*t**3-3*t**2+1)*a[:,1] + (t**3-2*t**2+t)*h*a[:,3]
         + (-2*t**3+3*t**2)*b[:,1] + (t**3-t**2)*h*b[:,2]).astype(np.float32)
    y = np.where(x <= keys[0,0], keys[0,1], np.where(x >= keys[-1,0], keys[-1,1], y))
    return y.astype(float)

raw = pd.read_csv(session / 'samples.csv', float_precision='round_trip')
raw = raw[(raw.record_kind == 'vehicle') & (raw.status == 'ok') & (raw.altitude_m < 140000)]
native = raw[raw.candidate == 'stock_thermal_now'].set_index('sample_id')
metrics = {}
fig, axes = plt.subplots(1, 2, figsize=(11,4.5), constrained_layout=True)
for ax, candidate in zip(axes, ['trajectories_position', 'mechjeb_private_diagnostic']):
    old = raw[raw.candidate == candidate].set_index('sample_id')
    data = native.join(old[['temperature_k', 'density_kg_m3']], rsuffix='_legacy', how='inner')
    data = data[(data.density_kg_m3 > 1e-6) & (data.density_kg_m3_legacy > 0)]
    solar = curve('atmosphereTemperatureSunMultCurve', data.altitude_m)
    lat = curve('axialTemperatureSunMultCurve', data.latitude_deg.abs())
    legacy_axial = curve('axialTemperatureSunMultCurve', data.sun_axial_dot)
    actual = (data.temperature_k_legacy-data.temperature_k).to_numpy()
    predictor = -solar*lat
    adjusted = actual-solar*legacy_axial
    bias = float(predictor @ adjusted / (predictor @ predictor))
    fitted = predictor*bias+solar*legacy_axial
    residual = actual-fitted
    rho_from_temp = data.temperature_k / data.temperature_k_legacy - 1
    rho_actual = data.density_kg_m3_legacy / data.density_kg_m3 - 1
    metric = dict(samples=len(data), fitted_native_seasonal_bias_k=bias,
        temperature_difference_mae_k=float(np.abs(actual).mean()),
        seasonal_model_residual_mae_k=float(np.abs(residual).mean()),
        seasonal_model_residual_max_k=float(np.abs(residual).max()),
        unexplained_squared_error_fraction=float(residual @ residual / (actual @ actual)),
        density_temperature_identity_max_absolute=float(np.abs(rho_from_temp-rho_actual).max()),
        solar_axis_dot_min=float(data.sun_axial_dot.min()), solar_axis_dot_max=float(data.sun_axial_dot.max()))
    metrics[candidate] = metric
    ax.scatter(fitted, actual, s=7, alpha=.4, color='#266a91')
    bounds = [min(fitted.min(),actual.min()), max(fitted.max(),actual.max())]
    ax.plot(bounds,bounds,color='#bd473c',linewidth=1.5)
    ax.set_title(('Trajectories' if candidate.startswith('trajectories') else 'MechJeb2') + '\nSeasonal-term mismatch')
    ax.set_xlabel('Difference explained by obsolete seasonal term (K)')
    ax.set_ylabel('Helper minus native temperature (K)')
    ax.grid(alpha=.2)
    ax.text(.04,.94,f'N={len(data)}\nFitted native seasonal bias: {bias:.5f} K\nResidual MAE: {np.abs(residual).mean():.6f} K',transform=ax.transAxes,va='top',fontsize=9)
    pd.DataFrame({'sample_id':data.index,'ut_s':data.ut_s,'latitude_deg':data.latitude_deg,'altitude_m':data.altitude_m,
        'observed_difference_k':actual,'seasonal_term_difference_k':fitted,'residual_k':residual}).to_csv(session/'analysis'/f'{candidate}_seasonal_diagnostic.csv',index=False)
fig.suptitle('First flight: same-position comparisons isolate the legacy thermal equation\nOne fitted seasonal bias; this flight does not validate a full seasonal cycle',fontsize=12)
for suffix in ['png','svg']:
    fig.savefig(session/'analysis'/f'08_legacy_seasonal_failure.{suffix}',dpi=180)
(session/'analysis'/'failure_diagnostics.json').write_text(json.dumps(metrics,indent=2),encoding='utf-8')
print(json.dumps(metrics,indent=2))
