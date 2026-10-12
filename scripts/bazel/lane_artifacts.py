#!/usr/bin/env python3
"""Carry exact Android producer receipts and Godot products between one build's jobs.

The native sdk-artifacts.json remains the producer authority. This transport
inventory binds its bytes and the downstream bridge files to this Godot commit
and exact NATIVE-PINS.json; it grants neither runtime eligibility nor new pins.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

from native_artifacts import inventory, relative, sha256

ROOT = Path(__file__).resolve().parents[2]
LIMIT = 4 * 1024**3
MANIFEST = 'lane-artifacts.json'
PRODUCER = '.native/artifacts/android/sdk-artifacts.json'
BRIDGES = {'addons/nuxie/android/bin/' + variant + '/NuxieGodot-' + variant + '.aar'
           for variant in ('debug', 'release')}
LICENSE = '.native/licenses/Nuxie-Android.txt'


def identity():
    revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True, timeout=10).strip()
    if not re.fullmatch('[0-9a-f]{40}', revision):
        raise ValueError('Expected the exact committed Godot source')
    if os.environ.get('BUILDKITE_COMMIT', revision) != revision:
        raise ValueError('The Godot checkout differs from this candidate build')
    status = subprocess.check_output(['git', 'status', '--porcelain', '--untracked-files=no'], cwd=ROOT, text=True, timeout=10).strip()
    if status:
        raise ValueError('Android handoff requires unchanged committed Godot source')
    return revision, sha256(ROOT / 'NATIVE-PINS.json'), json.loads((ROOT / 'NATIVE-PINS.json').read_text())


def build_identity(producer=False):
    build = os.environ.get('BUILDKITE_BUILD_ID')
    if not build:
        if os.environ.get('BUILDKITE'):
            raise ValueError('Require the exact Buildkite build identity')
        return None
    if not re.fullmatch('[0-9a-f-]{36}', build):
        raise ValueError('Invalid Buildkite build identity')
    job = os.environ.get('BUILDKITE_JOB_ID') if producer else None
    if producer and (not job or not re.fullmatch('[0-9a-f-]{36}', job)):
        raise ValueError('Require the exact Android producer job identity')
    return {'buildId': build, 'producerJobId': job, 'producerStep': 'godot-android'}


def safe_file(root, name):
    path = root / relative(name)
    for part in [path, *path.parents]:
        if not part.is_relative_to(root):
            break
        if part.is_symlink():
            raise ValueError('Transport paths must not contain symlinks: ' + name)
    if not path.is_file():
        raise ValueError('Missing transport artifact: ' + name)
    return path


def producer_files(root, pins):
    receipt, native, files, links = inventory(safe_file(root, PRODUCER), 'android', pins['android']['revision'])
    if links:
        raise ValueError('Android lane products must not contain symlinks')
    if receipt.get('runtime', {}).get('mode') != 'published' or not re.fullmatch('[0-9a-f]{64}', receipt['runtime'].get('checksum', '')):
        raise ValueError('Require the checksum-pinned published Android runtime')
    maven = receipt.get('maven', {})
    version = '0.2.0-' + pins['android']['revision']
    if (maven.get('groupId'), maven.get('artifactId'), maven.get('version')) != ('ai.nuxie', 'nuxie-android', version):
        raise ValueError('Require the source-addressed Android Maven coordinate')
    coordinate = 'ai/nuxie/nuxie-android/' + version + '/'
    selected = {name for name in files if name.startswith(coordinate)}
    for extension in ('aar', 'pom', 'module'):
        if coordinate + 'nuxie-android-' + version + '.' + extension not in selected:
            raise ValueError('Missing native Maven product: ' + extension)
    if 'licenses/LICENSE' not in files:
        raise ValueError('Missing inventoried Android dependency license')
    names = {PRODUCER, LICENSE, *BRIDGES}
    names.update('.native/artifacts/android/' + name for name in files)
    names.update('.native/maven/' + name for name in selected)
    return names, coordinate, receipt, files


def verify_products(root, pins):
    names, coordinate, receipt, producer = producer_files(root, pins)
    for name in producer:
        if name.startswith(coordinate) and sha256(safe_file(root, '.native/maven/' + name)) != producer[name]['sha256']:
            raise ValueError('Maven publication differs from its producer receipt')
    if sha256(safe_file(root, LICENSE)) != producer['licenses/LICENSE']['sha256']:
        raise ValueError('Android license differs from its producer receipt')
    actual = {path.relative_to(root).as_posix() for path in (root / '.native/maven' / coordinate).rglob('*')
              if path.is_file() or path.is_symlink()}
    expected = {name for name in names if name.startswith('.native/maven/')}
    if actual != expected:
        raise ValueError('Maven inventory contains missing or unlisted products')
    for name in names:
        safe_file(root, name)
    return names


def bundle_path(value):
    path = Path(value).absolute()
    if not path.is_relative_to(ROOT) or path == ROOT:
        raise ValueError('Transport must remain inside this owning checkout')
    for part in [path, *path.parents]:
        if not part.is_relative_to(ROOT):
            break
        if part.is_symlink():
            raise ValueError('Transport paths must not contain symlinks')
    if '..' in path.parts:
        raise ValueError('Transport path must be canonical')
    return path


def export(output):
    revision, pin_hash, pins = identity()
    names = verify_products(ROOT, pins)
    items = [{'path': name, 'size': safe_file(ROOT, name).stat().st_size,
              'sha256': sha256(safe_file(ROOT, name))} for name in sorted(names)]
    if len(items) > 10000 or sum(item['size'] for item in items) > LIMIT:
        raise ValueError('Android transport inventory exceeds its budget')
    document = {'schemaVersion': 1, 'sdk': 'godot', 'platform': 'android',
                'sourceRevision': revision, 'pinsSha256': pin_hash,
                'configurations': ['Debug', 'Release'], 'build': build_identity(producer=True), 'artifacts': items}
    output = bundle_path(output)
    if output.exists() or output.is_symlink():
        raise ValueError('Preserving existing transport output')
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.android-export-', dir=output.parent) as temporary:
        stage = Path(temporary) / 'products'
        for item in items:
            target = stage / 'payload' / item['path']
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(safe_file(ROOT, item['path']), target)
            if target.stat().st_size != item['size'] or sha256(target) != item['sha256']:
                raise ValueError('Artifact changed during transport publication')
        (stage / MANIFEST).write_text(json.dumps(document, indent=2) + '\n')
        stage.rename(output)
    return document


def verify(bundle):
    bundle = bundle_path(bundle)
    manifest = safe_file(bundle, MANIFEST)
    if manifest.stat().st_size > 1024**2:
        raise ValueError('Transport manifest exceeds its budget')
    document = json.loads(manifest.read_text())
    revision, pin_hash, pins = identity()
    if (document.get('schemaVersion'), document.get('sdk'), document.get('platform'),
        document.get('sourceRevision'), document.get('pinsSha256'), document.get('configurations')) != \
            (1, 'godot', 'android', revision, pin_hash, ['Debug', 'Release']):
        raise ValueError('Android prerequisite identity or native pins differ')
    expected_build = build_identity()
    observed_build = document.get('build')
    if expected_build is not None:
        if not isinstance(observed_build, dict) or observed_build.get('buildId') != expected_build['buildId'] or observed_build.get('producerStep') != 'godot-android' or not re.fullmatch('[0-9a-f-]{36}', observed_build.get('producerJobId', '')):
            raise ValueError('Android prerequisite belongs to a different build or producer')
    elif observed_build is not None:
        raise ValueError('A Buildkite prerequisite requires its original build context')
    items = document.get('artifacts')
    if not isinstance(items, list) or not items or len(items) > 10000:
        raise ValueError('Invalid Android transport inventory')
    names, total = set(), 0
    payload = bundle / 'payload'
    for item in items:
        name = relative(item['path'])
        if name in names or type(item.get('size')) is not int or item['size'] < 0:
            raise ValueError('Duplicate or invalid transport artifact')
        names.add(name)
        total += item['size']
        if total > LIMIT or not re.fullmatch('[0-9a-f]{64}', item.get('sha256', '')):
            raise ValueError('Transport inventory exceeds its budget or has an invalid digest')
        path = safe_file(payload, name)
        if path.stat().st_size != item['size'] or sha256(path) != item['sha256']:
            raise ValueError('Transport artifact integrity failure: ' + name)
    actual = {p.relative_to(payload).as_posix() for p in payload.rglob('*') if p.is_file() or p.is_symlink()}
    if actual != names or verify_products(payload, pins) != names:
        raise ValueError('Transport inventory has missing or unlisted products')
    return document, payload


def restore(bundle):
    document, payload = verify(bundle)
    # Verify all destinations before publishing any bytes. Original native
    # receipts are copied unchanged; no fallback checkout/build occurs here.
    for item in document['artifacts']:
        target = ROOT / item['path']
        for part in [target, *target.parents]:
            if not part.is_relative_to(ROOT):
                break
            if part.is_symlink():
                raise ValueError('Preserving unsafe restoration destination')
        if target.exists() and not target.is_file():
            raise ValueError('Preserving non-file restoration destination')
    for item in document['artifacts']:
        target = ROOT / item['path']
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(safe_file(payload, item['path']), target)
        if target.stat().st_size != item['size'] or sha256(target) != item['sha256']:
            raise ValueError('Artifact changed during restoration')
    verify_restored(bundle)


def verify_restored(bundle):
    document, _ = verify(bundle)
    for item in document['artifacts']:
        path = safe_file(ROOT, item['path'])
        if path.stat().st_size != item['size'] or sha256(path) != item['sha256']:
            raise ValueError('Restored Android product differs from its prerequisite')
    if verify_products(ROOT, identity()[2]) != {item['path'] for item in document['artifacts']}:
        raise ValueError('Restored Android inventory differs')
    return document


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('export', 'restore', 'verify'))
    parser.add_argument('--input', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    if args.command == 'export':
        if not args.output:
            parser.error('export requires --output')
        export(args.output)
    elif args.input:
        restore(args.input) if args.command == 'restore' else verify_restored(args.input)
    else:
        parser.error('restore/verify requires --input')


if __name__ == '__main__':
    main()
