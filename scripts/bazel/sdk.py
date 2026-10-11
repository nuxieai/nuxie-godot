#!/usr/bin/env python3
"""Run direct compiler targets and stage products in this SDK checkout."""

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile

from android_sdk import sdk_view
from native_artifacts import copy_verified_file, copy_verified_tree, inventory
from native_prepare import prepare

ROOT = Path(__file__).resolve().parents[2]
LAUNCHER = ROOT / 'scripts/bazel/bazel.sh'
SDK = 'godot'
MODULE = {'unity': 'NuxieUnityBridge', 'godot': 'NuxieGodotBridge', 'ue': 'NuxieUnrealBridge'}[SDK]
MINIMUM_IOS = '17.0' if SDK == 'ue' else '15.0'


def non_android_environment():
    return dict(os.environ, ANDROID_HOME='', ANDROID_SDK_ROOT='')


def environment(android=False, products=None):
    selected = dict(os.environ)
    if android:
        view = sdk_view(ROOT, api=36)
        selected.update(ANDROID_HOME=str(view), ANDROID_SDK_ROOT=str(view))
    else:
        selected.update(ANDROID_HOME='', ANDROID_SDK_ROOT='')
    for sdk, manifest in (products or {}).items():
        selected['NUXIE_' + sdk.upper() + '_ARTIFACTS'] = str(manifest)
    return selected


def bazel(command, labels, flags=(), env=None, capture=False):
    result = subprocess.run([str(LAUNCHER), command, *labels, *flags], cwd=ROOT,
                            env=env or environment(), check=True, text=True,
                            stdout=subprocess.PIPE if capture else None)
    return result.stdout if capture else ''


def outputs(label, flags, env):
    files = bazel('cquery', [label], [*flags, '--output=files', '--noshow_progress'], env, True).splitlines()
    execution_root = Path(bazel('info', ['execution_root'], env=env, capture=True).strip())
    return [execution_root / line for line in files if line]


def artifact(label, flags, env, suffix):
    files = [path for path in outputs(label, flags, env) if path.name.endswith(suffix)]
    if len(files) != 1 or not files[0].is_file():
        raise ValueError('Expected one built ' + suffix + ' from ' + label)
    return files[0]


def publish_tree(source, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.is_symlink():
        raise ValueError('Preserving publication symlink: ' + str(destination))
    with tempfile.TemporaryDirectory(prefix='.bazel-publish-', dir=destination.parent) as temporary:
        stage = Path(temporary) / 'product'
        shutil.copytree(source, stage, symlinks=True)
        for path in [stage, *stage.rglob('*')]:
            if not path.is_symlink():
                path.chmod(0o755 if path.is_dir() else 0o644)
        backup = Path(temporary) / 'previous'
        if destination.exists():
            destination.rename(backup)
        try:
            stage.rename(destination)
        except BaseException:
            if backup.exists():
                backup.rename(destination)
            raise


def extract_archive(archive, stage):
    with zipfile.ZipFile(archive) as compressed:
        for item in compressed.infolist():
            relative = PurePosixPath(item.filename)
            if relative.is_absolute() or '..' in relative.parts or '\\' in item.filename:
                raise ValueError('Unsafe compiler archive path')
            if (item.external_attr >> 16) & 0o170000 == 0o120000:
                raise ValueError('iOS compiler archives must not contain symlinks')
        compressed.extractall(stage)


def copy_maven(manifest, destination):
    pins = json.loads((ROOT / 'NATIVE-PINS.json').read_text())
    receipt, source, files, _ = inventory(manifest, 'android', pins['android']['revision'])
    coordinate = Path('ai/nuxie/nuxie-android') / ('0.2.0-' + pins['android']['revision'])
    selected = [name for name in files if name.startswith(coordinate.as_posix() + '/')]
    if not selected:
        raise ValueError('No source-addressed native SDK Maven files')
    with tempfile.TemporaryDirectory(prefix='maven-', dir=ROOT / '.native') as temporary:
        stage = Path(temporary)
        for name in selected:
            target = stage / Path(name).relative_to(coordinate)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source / name, target)
        publish_tree(stage, destination / coordinate)
    licenses = ROOT / ".native/licenses"
    licenses.mkdir(exist_ok=True)
    if "licenses/LICENSE" in files:
        shutil.copy2(source / "licenses/LICENSE", licenses / "Nuxie-Android.txt")
    return receipt, source, files


def ios_flags(configuration, simulator=False):
    cpu = ('sim_arm64' if platform.machine() == 'arm64' else 'x86_64') if simulator else 'arm64'
    selected = '@apple_support//platforms:ios_' + cpu
    return ['--compilation_mode=' + ('opt' if configuration == 'Release' else 'dbg'),
            '--platforms=' + selected, '--apple_platforms=' + selected,
            '--ios_multi_cpus=' + cpu, '--ios_minimum_os=' + MINIMUM_IOS]


def simulator_flags():
    identifier = os.environ.get('NUXIE_IOS_SIMULATOR_ID')
    if not identifier:
        raise ValueError('Set NUXIE_IOS_SIMULATOR_ID to the simulator used for the bridge test')
    devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '-j'], text=True))['devices']
    matches = [(runtime, device) for runtime, group in devices.items() for device in group if device.get('udid') == identifier]
    if len(matches) != 1:
        raise ValueError('Selected simulator is unavailable')
    runtime, _device = matches[0]
    if '.iOS-' not in runtime:
        raise ValueError('Selected simulator must run iOS')
    actual_version = tuple(int(part) for part in runtime.split('.iOS-', 1)[1].split('-'))
    minimum_version = tuple(int(part) for part in MINIMUM_IOS.split('.'))
    if actual_version < minimum_version:
        raise ValueError('Selected simulator must run iOS ' + MINIMUM_IOS + '+')
    return ['--test_arg=--destination=platform=ios_simulator,id=' + identifier]


def ios_check(test=False):
    products = prepare(ROOT, ['ios'])
    flags = ios_flags('Debug', True)
    if test:
        flags += simulator_flags()
    bazel('test' if test else 'build', ['//:ios_bridge_test' if test else '//:ios_bridge'], flags, environment(products=products))


def verify_binary_architectures(binary, architectures):
    actual = set(subprocess.check_output(['xcrun', 'lipo', '-archs', str(binary)], text=True).split())
    expected = set(architectures)
    if actual != expected:
        raise ValueError(f'Prepared binary has architectures {sorted(actual)}; expected {sorted(expected)}')


def verify_binary_platform(binary, sdk_platform, architecture):
    """Inspect every Mach-O load command, including members of static archives."""
    expected = {'macos': 1, 'ios-device': 2, 'ios-simulator': 7}[sdk_platform]
    metadata = subprocess.check_output(['xcrun', 'otool', '-arch', architecture, '-l', str(binary)], text=True)
    actual = [int(value) for value in re.findall(r'^\s*platform\s+(\d+)\s*$', metadata, re.MULTILINE)]
    if not actual or any(value != expected for value in actual):
        raise ValueError(f'Prepared {sdk_platform}/{architecture} binary has Mach-O platforms {actual}; expected {expected}')


def ios_xcframework(configuration):
    products = prepare(ROOT, ['ios'], configuration=configuration, ios_platforms=['ios-device', 'ios-simulator'],
                       ios_output=ROOT / '.native/artifacts/ios' / configuration)
    env, flags = environment(products=products), ios_flags(configuration)
    labels = ['//:ios_bridge_xcframework'] + (['//:ios_plugin_xcframework'] if SDK == 'godot' else [])
    # The publication query uses the top-level header configuration, while the
    # plugin compiles its headers in each Apple split configuration.
    publication_inputs = ['//:godot_headers'] if SDK == 'godot' else []
    bazel('build', [*labels, *publication_inputs], flags, env)
    pin = json.loads((ROOT / 'NATIVE-PINS.json').read_text())['ios']['revision']
    receipt, native, files, links = inventory(products['ios'], 'ios', pin)
    destination = ROOT / ('ios-plugin/.build/xcframework' if SDK == 'godot' else '.native/xcframework')
    for label in labels:
        archive = artifact(label, flags, env, '.zip')
        with tempfile.TemporaryDirectory(prefix='xcframework-', dir=ROOT / '.native') as temporary:
            stage = Path(temporary)
            extract_archive(archive, stage)
            frameworks = list(stage.rglob('*.xcframework'))
            if len(frameworks) != 1:
                raise ValueError('Expected one compiled XCFramework')
            bundle = frameworks[0]
            info = plistlib.loads((bundle / 'Info.plist').read_bytes())
            actual = {(item['SupportedPlatform'], item.get('SupportedPlatformVariant', ''), tuple(sorted(item['SupportedArchitectures']))) for item in info['AvailableLibraries']}
            if actual != {('ios', '', ('arm64',)), ('ios', 'simulator', ('arm64', 'x86_64'))}:
                raise ValueError('XCFramework must contain the device and both simulator architectures')
            for item in info['AvailableLibraries']:
                library = bundle / item['LibraryIdentifier'] / item['LibraryPath']
                binary = library / library.stem if library.suffix == '.framework' else library
                verify_binary_architectures(binary, item['SupportedArchitectures'])
                native_platform = 'ios-simulator' if item.get('SupportedPlatformVariant') == 'simulator' else 'ios-device'
                for architecture in item['SupportedArchitectures']:
                    verify_binary_platform(binary, native_platform, architecture)
                if library.suffix == '.framework':
                    matches = [product for product in receipt['products'] if product['platform'] == native_platform and product['configuration'] == configuration]
                    if len(matches) != 1 or len(matches[0]['resourceBundles']) != 1:
                        raise ValueError('Prepared native products must carry one matching resource bundle')
                    resource = matches[0]['resourceBundles'][0]
                    copy_verified_tree(native, resource, library / Path(resource).name, files, links)
            name = 'nuxie_godot_plugin' if label == '//:ios_plugin_xcframework' else MODULE
            publish_tree(bundle, destination / (name + '.' + configuration.lower() + '.xcframework'))
    licenses = ROOT / '.native/licenses'
    licenses.mkdir(exist_ok=True)
    copy_verified_file(native, 'licenses/LICENSE', licenses / 'Nuxie-iOS.txt', files)
    if SDK == 'godot':
        headers = outputs('//:godot_headers', flags, env)
        if len(headers) != 1 or not headers[0].is_dir():
            raise ValueError('Expected the declared Godot header tree')
        for source, name in [('LICENSE.txt', 'Godot.txt'), ('COPYRIGHT.txt', 'Godot-COPYRIGHT.txt')]:
            shutil.copy2(headers[0] / source, licenses / name)
    return destination / (MODULE + '.' + configuration.lower() + '.xcframework')


def android_build(configuration='Release', test=False):
    products = prepare(ROOT, ['android'])
    flags = ['--platforms=//:android_arm64', '--extra_toolchains=@androidsdk//:sdk-toolchain',
             '--compilation_mode=' + ('opt' if configuration == 'Release' else 'dbg')]
    env = environment(True, products)
    bazel('test' if test else 'build', ['//:android_bridge_test' if test else '//:android_bridge_aar'], flags, env)
    if not test:
        return artifact('//:android_bridge_aar', flags, env, '.aar'), products['android']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = ['build', 'test', 'build-android', 'check-ios', 'prepare-ios']
    if SDK != 'unity':
        commands += ['test-android', 'test-ios']
    parser.add_argument('command', choices=commands)
    parser.add_argument('--configuration', choices=['Debug', 'Release'], default='Release')
    args = parser.parse_args()
    if args.command in ('build', 'test'):
        labels = ['//:managed_test'] if SDK == 'unity' else ['//:source_tests' if SDK == 'godot' else '//:portable_tests']
        if args.command == 'build' and SDK == 'unity':
            labels = ['//:managed']
        bazel(args.command, labels)
    elif args.command in ('check-ios', 'test-ios'):
        ios_check(args.command == 'test-ios')
    elif args.command == 'prepare-ios':
        ios_xcframework(args.configuration)
    elif args.command == 'test-android':
        android_build('Debug', True)
    else:
        print(android_build(args.configuration)[0])


if __name__ == '__main__':
    main()
