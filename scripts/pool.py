#!/usr/bin/env python3
"""Submit this SDK's existing frontend to the shared, capability-selected pool."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
SDK = 'godot'
OUTPUTS = ['android-plugin/build/outputs', 'android-plugin/build/reports', 'android-plugin/build/test-results', '.native/artifacts', '.native/test-evidence', '.native/build', 'dist', '.native/maven', '.native/licenses', 'ios-plugin/.build/xcframework', 'addons/nuxie/android/bin', 'addons/nuxie/android/maven', 'addons/nuxie/ios', 'addons/nuxie/artifact-checksums.json']


def selection(mode, arguments, command=None, selected_platform=None):
    selected = 'android' if mode == 'prepare-native' and SDK in ('react-native', 'unity') else 'all'
    for i, arg in enumerate(arguments):
        if arg == '--platform' and i + 1 < len(arguments): selected = arguments[i + 1]
        elif arg.startswith('--platform='): selected = arg.split('=', 1)[1]
    if selected_platform is not None: selected = selected_platform
    command = command or (arguments[0] if arguments else '')
    requirements = set()
    apple = False
    if SDK == 'android':
        requirements.add('android')
    elif mode == 'sdk':
        if command == 'build-native':
            apple = selected in ('ios', 'all')
            if selected in ('android', 'all'): requirements.add('android')
        elif command.endswith('-ios'):
            apple = True
        elif command.endswith('-android'):
            requirements.add('android')
    elif mode == 'check-ios':
        apple = True
    else:
        apple = selected in ('ios', 'all')
        if mode in ('prepare-native', 'prepare-android') and SDK == 'unity': apple = False
        if mode == 'prepare-android': apple = False
        if selected in ('android', 'all'): requirements.add('android')
        if mode == 'check':
            requirements.update({'react-native': ['node'], 'flutter': [],
                'godot': [] if selected == 'ios' else ['godot'], 'unity': ['unity@6000.6.7f1'], 'ue': ['unreal@5.8']}.get(SDK, []))
    if 'godot' in requirements:
        version = json.loads((ROOT / 'NATIVE-PINS.json').read_text())['godot']
        requirements.remove('godot'); requirements.add('godot@' + version)
    if (mode == 'gradle' or (mode == 'check' and 'android' in requirements)
            or (SDK == 'android' and mode == 'sdk' and command in ('check', 'lint', 'api-check', 'providers'))):
        requirements.add('java17')
    if mode == 'gradle':
        apple = False; requirements = {'android', 'java17'}
    if apple: requirements.add('xcode')
    return ('macos' if apple else 'portable'), sorted(requirements)


def gradle_tasks(arguments):
    values = iter(arguments)
    tasks = []
    takes_value = {'-P', '--project-prop', '-D', '--system-prop', '-p', '--project-dir', '-g', '--gradle-user-home', '-I', '--init-script',
                   '-c', '--settings-file', '-b', '--build-file', '-x', '--exclude-task',
                   '--include-build', '--project-cache-dir', '--console', '--warning-mode',
                   '--max-workers', '--priority', '--configuration-cache-problems'}
    for value in values:
        if value in takes_value: next(values, None)
        elif not value.startswith('-'): tasks.append(value.rsplit(':', 1)[-1])
    return tasks


def dispatch(mode, arguments, *, output=None, command=None, input_files=None, environment=None, selected_platform=None):
    if (os.environ.get('_NUXIE_POOL_NESTED') == '1' or os.environ.get('NUXIE_HOMELAB') == '0'
            or os.environ.get('NUXIE_EXECUTION') == 'local' or os.environ.get('NUXIE_CI_RUNNER_POLICY_VERSION') == '2' or '--help' in arguments or '-h' in arguments): return None
    if mode == 'gradle':
        tasks = gradle_tasks(arguments)
        if (tasks and all(value == 'clean' for value in tasks)) or '--stop' in arguments: return None
    helper = Path.home() / '.local/share/nuxie-homelab/sdk-task.py'
    configured = (Path.home() / '.config/nuxie/homelab-cluster.json').is_file()
    if not helper.is_file():
        if configured and os.environ.get('NUXIE_HOMELAB') != '0' and os.environ.get('NUXIE_EXECUTION') != 'local':
            raise RuntimeError('Configured pool needs its SDK task client installed')
        return None
    spec = importlib.util.spec_from_file_location('pool_sdk_task', helper)
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    platform, requirements = selection(mode, arguments, command, selected_platform)
    names = {name: ROOT / name for name in OUTPUTS}
    if output is not None:
        names['build/pool-prepared'] = Path(output).resolve()
        names.pop('build/bazel-sdk', None)
    frontend = 'scripts/bazel/sdk.py' if mode == 'sdk' else 'scripts/pool.py'
    args = list(arguments) if mode == 'sdk' else [mode, *arguments]
    if output is not None:
        for index, argument in enumerate(args):
            if argument == '--output' and index + 1 < len(args): args[index + 1] = str(Path(output).resolve())
            elif argument.startswith('--output='): args[index] = '--output=' + str(Path(output).resolve())
    if output is not None and not any(a == '--output' or a.startswith('--output=') for a in args):
        args += ['--output', str(output)]
    addon = ROOT / 'examples/sdk-lab/addons'
    if mode == 'check' and addon.is_dir():
        input_files = {'examples/sdk-lab/addons': addon, **(input_files or {})}
    if mode == 'gradle':
        input_files = dict(input_files or {})
        for name in ('.native/maven', 'addons/nuxie/android/bin'):
            if (ROOT / name).is_dir(): input_files[name] = ROOT / name
        if not any(value in ('-p', '--project-dir') or value.startswith('--project-dir=') for value in args):
            args += ['--project-dir', str(Path.cwd().resolve())]
        for index, value in enumerate(args):
            if value in ('-p', '--project-dir') and index + 1 < len(args): args[index + 1] = str(Path(args[index + 1]).resolve())
            elif value.startswith('--project-dir='): args[index] = '--project-dir=' + str(Path(value.split('=',1)[1]).resolve())
    if mode == 'gradle':
        from urllib.parse import urlsplit, unquote
        value = os.environ.get('NUXIE_ANDROID_MAVEN_REPO')
        if value:
            uri = urlsplit(value)
            if uri.scheme in ('https', 'http'):
                args.append('--nuxie-pool-maven-repository=' + value)
            else:
                selected = Path(unquote(uri.path) if uri.scheme == 'file' else value).expanduser().resolve(strict=True)
                input_files = {**(input_files or {}), '.nuxie/sdk-inputs/maven-repository': selected}
                args.append('--nuxie-pool-maven-repository=' + str(selected))
    return module.route(ROOT, args, frontend=frontend, platform=platform,
                        requirements=requirements, outputs=names, input_files=input_files, environment=environment,
                        merge_outputs=[name for name in names if not (SDK == 'react-native' and name == 'dist')])


def main():
    mode, *arguments = sys.argv[1:]
    for value in arguments:
        if value.startswith('--nuxie-pool-maven-repository='):
            os.environ['NUXIE_ANDROID_MAVEN_REPO'] = value.split('=', 1)[1]
    arguments = [value for value in arguments if not value.startswith('--nuxie-pool-maven-repository=')]
    status = dispatch(mode, arguments)
    if status is not None: return status
    if mode == 'gradle':
        command = [str(ROOT / 'gradlew'), *arguments]
        if os.environ.get('_NUXIE_POOL_NESTED') == '1':
            command += ['--no-daemon', '--max-workers=' + os.environ.get('NUXIE_BAZEL_CPU', '2')]
    elif SDK == 'react-native' and mode == 'check':
        # Dependencies belong to the selected host's disposable snapshot.
        subprocess.run(['pnpm', '--ignore-workspace', 'install', '--frozen-lockfile'], cwd=ROOT, check=True)
        command = ['node', 'scripts/check.mjs', *arguments]
    else:
        command = [sys.executable, 'scripts/' + mode + '.py', *arguments]
    return subprocess.run(command, cwd=Path.cwd() if mode == 'gradle' else ROOT, env=dict(os.environ, _NUXIE_POOL_NESTED='1')).returncode


if __name__ == '__main__':
    raise SystemExit(main())
