"""Migration checks plus reserved identifiers introduced by this change."""
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[3]
SCRIPTS = ['Script/boot/atm_check.ks','Script/uentry.ks', 'Script/lib/atm_utils.ks', 'Script/lib/edllib/uentry_core.ks',
           'Script/lib/edllib/gui_utils.ks', 'Script/Falcon9_lib/f9utility.ks']
reserved = set()
fence = chr(96) * 3
for block in re.findall(fence + r'text\s*(.*?)' + fence, (ROOT / 'AGENTS.md').read_text(encoding='utf-8'), re.S):
    reserved.update(block.upper().split())
reserved.update('LOADDISTANCE SENSORS SUN MOHO EVE GILLY KERBIN MUN MINMUS DUNA IKE DRES JOOL LAYTHE VALL TYLO BOP POL EELOO EARTH MOON MERCURY VENUS MARS JUPITER SATURN URANUS NEPTUNE PLUTO SET TO IS LOCAL GLOBAL PARAMETER FUNCTION IF ELSE UNTIL FOR FROM RETURN LOCK UNLOCK ON OFF TRUE FALSE AND OR NOT'.split())
reserved.update(f'AG{i}' for i in range(11,251))
for rel in SCRIPTS:
    text = (ROOT / rel).read_text(encoding='utf-8-sig')
    assert not re.search(r':(?:INITATMMODEL|GETDENSITYEST|GETALTEST)\b', text, re.I), rel
    original = subprocess.run(['git','show',f'HEAD:{rel}'], cwd=ROOT, capture_output=True)
    old = original.stdout.decode('utf-8-sig') if original.returncode == 0 else ''
    def names(code):
        code = re.sub(r'//[^\n]*', '', code)
        result = set(re.findall(r'\b(?:function|(?:declare\s+)?(?:local|global)(?:\s+lock)?|lock|for)\s+([a-z_]\w*)', code, re.I))
        for clause in re.findall(r'\bparameter\s+([^.]*)\.', code, re.I):
            result.update(re.findall(r'(?:^|,)\s*([a-z_]\w*)', clause, re.I))
        return {n.upper() for n in result}
    introduced = names(text) - names(old)
    assert not introduced & reserved, f'{rel}: reserved names {introduced & reserved}'
    assert not re.search(r'CLOBBERBUILTINS', text, re.I), rel
for kind in ('AFS','LTR'):
    core = (ROOT / f'src/kOS-{kind}/kOS-{kind}/{kind}.cs').read_text(encoding='utf-8-sig')
    addon = (ROOT / f'src/kOS-{kind}/kOS-{kind}/{kind}Addon.cs').read_text(encoding='utf-8-sig')
    for obsolete in ('AtmAltSamples','AtmTempSamples','AtmLogDensitySamples','GetLogDensityEst','InitAtmModel'):
        assert obsolete not in core + addon, f'{kind}: {obsolete}'
    assert 'Atmosphere.EvaluatePosition(' in core
    assert addon.index('AtmosphereSnapshotValue.ForPrediction(') < addon.index('Task.Run(')
    assert 'PredictTrajectory(t, state, argsSnapshot' in addon
for rel in ('ManagedMath.cs','AtmosphereSnapshot.cs'):
    code = (ROOT / 'src/kOS-ATM' / rel).read_text(encoding='utf-8')
    assert not re.search(r'UnityEngine|CelestialBody|FloatCurve|AnimationCurve|Planetarium|Transform|DllImport', code), rel
print('Integration checks passed: no legacy atmosphere tables/APIs, snapshot before workers, managed-only kernel, no newly introduced reserved KerboScript identifiers.')

core = (ROOT / 'Script/lib/edllib/uentry_core.ks').read_text(encoding='utf-8')
for name in ('entry_initialize_guidance', 'entry_step_guidance'):
    scope = core.split('function ' + name + ' {', 1)[1].split('\nfunction ', 1)[0]
    assert 'local atmosphere_context to lexicon(' in scope, name
    assert scope.index('local atmosphere_context') < scope.index(', atmosphere_context)'), name
capture = (ROOT / 'src/kOS-ATM/AtmosphereCapture.cs').read_text(encoding='utf-8')
assert 'body.GetWorldSurfacePosition(0,0,0)' in capture.replace(' ', '')
assert 'body.GetWorldSurfacePosition(0,90,0)' in capture.replace(' ', '')
assert 'body.GetRelSurfaceNVector(' not in capture
print('Epoch scope and body-specific geographic orientation checks passed.')
