from pathlib import Path
import sys
import zipfile

archive = Path(sys.argv[1])
expected = {
    'GameData/kOS-ATM/Plugins/kOS-ATM.dll',
    'GameData/kOS-AFS/Plugins/kOS-AFS.dll',
    'GameData/kOS-LTR/Plugins/kOS-LTR.dll',
    'INSTALL.md', 'Script/boot/atm_check.ks', 'Script/uentry.ks',
    'Script/lib/atm_utils.ks', 'Script/lib/edllib/uentry_core.ks',
    'Script/lib/edllib/gui_utils.ks', 'Script/Falcon9_lib/f9utility.ks'
}
with zipfile.ZipFile(archive) as z:
    names = {n.replace(chr(92), '/') for n in z.namelist() if not n.endswith('/')}
    assert names == expected, (names - expected, expected - names)
    assert z.testzip() is None
print(f'Package integrity passed: 3 addon DLLs, 6 scripts, installation instructions; {archive.stat().st_size:,} bytes.')
