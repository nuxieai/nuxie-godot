#!/usr/bin/env python3
"""Prepare pinned native Bazel products inside the downstream checkout."""
import fcntl
import json
import os
import platform
from pathlib import Path
import subprocess
import sys


def checkout(root, sdk, pin):
    source = root / '.native' / sdk
    source.parent.mkdir(exist_ok=True)
    existed = source.exists()
    if not existed:
        subprocess.run(['git', 'clone', '--no-checkout', pin['repository'], str(source)], check=True)
    if existed and subprocess.check_output(['git', 'status', '--porcelain'], cwd=source, text=True).strip():
        raise ValueError('Preserving modified native checkout: ' + str(source))
    subprocess.run(['git', 'fetch', 'origin', pin['revision']], cwd=source, check=True)
    subprocess.run(['git', 'checkout', '--detach', pin['revision']], cwd=source, check=True)
    actual = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=source, text=True).strip()
    if actual != pin['revision']:
        raise ValueError('Native pin mismatch for ' + sdk)
    producer = source / 'scripts/bazel/sdk.py'
    if not producer.is_file():
        raise ValueError('The ' + sdk + ' pin needs its landed Bazel build migration')
    return source, producer


def supplied_artifacts(sdk, pin):
    value = os.environ.get('NUXIE_' + sdk.upper() + '_ARTIFACTS')
    if not value:
        return None
    selected = Path(value).expanduser()
    if not selected.is_absolute():
        raise ValueError('Native artifact overrides must use absolute paths')
    manifest = selected / 'sdk-artifacts.json' if selected.is_dir() else selected
    from native_artifacts import inventory
    inventory(manifest, sdk, pin['revision'])
    return manifest.resolve()


def prepare(root, sdks, configuration='Debug', android_output=None, ios_platforms=None, ios_architectures=None, ios_output=None):
    root = Path(root).resolve()
    pins = json.loads((root / 'NATIVE-PINS.json').read_text())
    native = root / '.native'
    native.mkdir(exist_ok=True)
    products = {}
    with (native / '.prepare.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        for sdk in sdks:
            supplied = supplied_artifacts(sdk, pins[sdk])
            if supplied:
                products[sdk] = supplied
                continue
            source, producer = checkout(root, sdk, pins[sdk])
            if sdk == 'ios':
                if sys.platform != 'darwin':
                    raise ValueError('iOS native preparation requires macOS')
                architecture = platform.machine()
                if architecture not in ('arm64', 'x86_64'):
                    raise ValueError('Unsupported simulator host architecture: ' + architecture)
                output = ios_output or native / 'artifacts/ios'
                command = [sys.executable, str(producer), 'prepare', '--output', str(output), '--configuration', configuration]
                for selected in ios_platforms or ['ios-simulator']:
                    command += ['--platform', selected]
                for selected in ([architecture] if ios_platforms is None and ios_architectures is None else ios_architectures or []):
                    command += ['--architecture', selected]
            else:
                output = android_output or native / 'artifacts/android'
                command = [sys.executable, str(producer), 'prepare', '--output', str(output),
                           '--maven-version', '0.2.0-' + pins[sdk]['revision']]
            subprocess.run(command, cwd=source, check=True)
            products[sdk] = Path(output) / 'sdk-artifacts.json'
    return products
