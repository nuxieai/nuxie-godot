#!/usr/bin/env python3
"""Readiness; default runs portable behavior and both native platform oracles."""
import argparse
from pathlib import Path
import os
import subprocess
import json
import shutil

ROOT = Path(__file__).resolve().parent.parent


def run(args, cwd=ROOT):
    result = subprocess.run(args, cwd=cwd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=86400 if os.environ.get('_NUXIE_SDK_SNAPSHOT') == '1' else 900)
    print(result.stdout)
    if result.returncode or 'SCRIPT ERROR:' in result.stdout:
        raise SystemExit('Check failed: ' + ' '.join(args))


def portable():
    engine = os.environ.get('GODOT_BIN') or str(ROOT / '.native/tools/Godot.app/Contents/MacOS/Godot')
    if not Path(engine).is_file():
        engine = shutil.which('godot') or ''
    if not engine:
        raise SystemExit('Install the pinned Godot editor or set GODOT_BIN')
    pins = json.loads((ROOT / 'NATIVE-PINS.json').read_text())
    version = subprocess.check_output([engine, '--version'], text=True).strip()
    if not version.startswith(pins['godot'] + '.stable.'):
        raise SystemExit('Use the pinned Godot editor: ' + pins['godot'])
    run(['python3', '-m', 'unittest', 'discover', '-s', 'tests', '-p', 'test_*.py'])
    run([engine, '--headless', '--editor', '--path', str(ROOT), '--import'])
    run([engine, '--headless', '--path', str(ROOT), '--script', 'tests/godot/client-test.gd'])
    if (ROOT / 'examples/sdk-lab/addons/nuxie/native-pins.json').is_file():
        run([engine, '--headless', '--editor', '--path', str(ROOT / 'examples/sdk-lab'), '--import'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--platform', choices=('all', 'portable', 'android', 'ios'), default='all')
    selected = parser.parse_args().platform
    from pool import dispatch
    status = dispatch('check', ['--platform', selected])
    if status is not None: raise SystemExit(status)
    if selected in ('all', 'portable', 'android'):
        portable()
    if selected in ('all', 'android'):
        run(['python3', 'scripts/bazel/sdk.py', 'test-android'])
    if selected != 'portable':
        run(['python3', 'scripts/prepare-native.py', '--platform', selected])
    if selected in ('all', 'android'):
        # Gradle lint remains an independent upstream analysis oracle.
        run(['./gradlew', ':android-plugin:lint'])
    if selected in ('all', 'ios'):
        run(['python3', 'scripts/check-ios.py'])


if __name__ == '__main__':
    main()
