#!/usr/bin/env python3
"""Stage exactly the customer addon, then zip and copy it into the standalone Lab."""
from pathlib import Path
import hashlib
import json
import shutil
import zipfile

root = Path(__file__).resolve().parent.parent
pins = json.loads((root / 'NATIVE-PINS.json').read_text())
stage = root / '.native/package'
addon = stage / 'addons/nuxie'
if stage.exists():
    shutil.rmtree(stage)
shutil.copytree(root / 'addons/nuxie', addon, ignore=shutil.ignore_patterns('.DS_Store', '.godot'))
for name in [f'{base}.{variant}.xcframework' for base in ['NuxieGodotBridge', 'nuxie_godot_plugin'] for variant in ['debug', 'release']]:
    source = root / 'ios-plugin/.build/xcframework' / name
    if not source.is_dir():
        raise SystemExit('Prepare iOS artifacts first: ' + str(source))
    shutil.copytree(source, addon / 'ios' / name, dirs_exist_ok=True)
repo = root / '.native/maven'
if not repo.is_dir():
    raise SystemExit('Prepare the pinned native Android Maven repository first')
shutil.copytree(repo, addon / 'android/maven', dirs_exist_ok=True)
for variant in ['debug', 'release']:
    if not (addon / f'android/bin/{variant}/NuxieGodot-{variant}.aar').is_file():
        raise SystemExit('Build both Android bridge variants before packing')
shutil.copy2(root / 'NATIVE-PINS.json', addon / 'native-pins.json')
notices = addon / 'licenses'
notices.mkdir(exist_ok=True)
for name, source in [('Godot.txt', root / '.native/godot/LICENSE.txt'), ('Godot-COPYRIGHT.txt', root / '.native/godot/COPYRIGHT.txt'), ('Nuxie-Android.txt', root / '.native/android/LICENSE'), ('Nuxie-iOS.txt', root / 'ios-plugin/.build/DerivedData/SourcePackages/checkouts/nuxie-ios/LICENSE')]:
    if not source.is_file():
        raise SystemExit('Missing pinned dependency license: ' + str(source))
    shutil.copy2(source, notices / name)
checksums = {str(p.relative_to(addon)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(addon.rglob('*')) if p.is_file()}
(addon / 'artifact-checksums.json').write_text(json.dumps(checksums, indent=2) + '\n')
output = root / 'dist' / ('nuxie-godot-' + pins['version'] + '.zip')
output.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(stage.rglob('*')):
        if path.is_file():
            archive.write(path, path.relative_to(stage))
example = root / 'examples/sdk-lab/addons'
if example.exists():
    shutil.rmtree(example)
shutil.copytree(stage / 'addons', example)
print('Prepared addon and Lab: ' + str(output))
