#!/usr/bin/env python3
"""Readiness: GDScript behavior, Android bridge tests/lint/build, and iOS bridge tests."""
from pathlib import Path
import os
import subprocess
import json
import shutil

root = Path(__file__).resolve().parent.parent
engine = os.environ.get('GODOT_BIN') or str(root / '.native/tools/Godot.app/Contents/MacOS/Godot')
if not Path(engine).is_file():
    engine = shutil.which('godot') or ''
if not engine:
    raise SystemExit('Install the pinned Godot editor or set GODOT_BIN')
pins = json.loads((root / 'NATIVE-PINS.json').read_text())
version = subprocess.check_output([engine, '--version'], text=True).strip()
if not version.startswith(pins['godot'] + '.stable.'):
    raise SystemExit('Use the pinned Godot editor: ' + pins['godot'])
def run(args, cwd=root):
    result = subprocess.run(args, cwd=cwd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=900)
    print(result.stdout)
    if result.returncode or 'SCRIPT ERROR:' in result.stdout:
        raise SystemExit('Check failed: ' + ' '.join(args))
run(['python3', '-m', 'unittest', 'discover', '-s', 'tests', '-p', 'test_*.py'])
run([engine, '--headless', '--editor', '--path', str(root), '--import'])
run([engine, '--headless', '--path', str(root), '--script', 'tests/godot/client-test.gd'])
if (root / 'examples/sdk-lab/addons/nuxie/native-pins.json').is_file():
    run([engine, '--headless', '--editor', '--path', str(root / 'examples/sdk-lab'), '--import'])
run(['./gradlew', ':android-plugin:testDebugUnitTest', ':android-plugin:lint', ':android-plugin:assembleDebug', ':android-plugin:assembleRelease'])
run(['python3', 'scripts/check-ios.py'])
