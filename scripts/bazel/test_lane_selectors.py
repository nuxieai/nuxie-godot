"""Execute canonical platform selectors with independent subprocess recorders."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class SelectorTests(unittest.TestCase):
    def fixture(self, root):
        (root / 'scripts/bazel').mkdir(parents=True)
        for name in ('check.py', 'prepare-native.py', 'pool.py'):
            shutil.copy2(ROOT / 'scripts' / name, root / 'scripts' / name)
        (root / 'NATIVE-PINS.json').write_text(json.dumps({'godot': '4.7.2'}))
        log = root / 'calls.jsonl'
        tools = root / 'tools'
        tools.mkdir()
        (tools / 'godot').write_text('fixture engine')
        (root / 'gradlew').write_text('fixture lint')
        (root / 'scripts/subprocess.py').write_text("""import json,os
from pathlib import Path
from types import SimpleNamespace
PIPE=-1
STDOUT=-2
def record(args):
 with Path(os.environ['CALLS']).open('a') as out: out.write(json.dumps(args)+'\\n')
def check_output(args,**kwargs):
 record(args);return '4.7.2.stable.fixture'
def run(args,**kwargs):
 record(args);return SimpleNamespace(returncode=0,stdout='recorded')
""")
        (root / 'scripts/bazel/sdk.py').write_text('''import json,os
from pathlib import Path
root=Path(__file__).resolve().parents[2]
def record(platform,configuration):
 with Path(os.environ['CALLS']).open('a') as out: out.write(json.dumps([platform,configuration])+'\\n')
def android_build(configuration):
 record('android',configuration)
 artifact=root/('bridge-'+configuration+'.aar');artifact.write_bytes(configuration.encode())
 return artifact,root/'sdk-artifacts.json'
def copy_maven(manifest,destination): pass
def ios_xcframework(configuration): record('ios',configuration)
''')
        return log, dict(os.environ, PATH=str(tools) + os.pathsep + os.environ['PATH'], _NUXIE_POOL_NESTED='1', CALLS=str(log), GODOT_BIN=str(tools / 'godot'))

    def calls(self, path):
        return [json.loads(line) if line.startswith("[") else line.rstrip("\t").split("\t") for line in path.read_text().splitlines()]

    def test_prepare_selectors_execute_only_selected_platform_and_full_default_keeps_both(self):
        for selected, expected in [(None, [('android', 'Debug'), ('ios', 'Debug'), ('android', 'Release'), ('ios', 'Release')]),
                                   ('android', [('android', 'Debug'), ('android', 'Release')]),
                                   ('ios', [('ios', 'Debug'), ('ios', 'Release')])]:
            with self.subTest(platform=selected), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                log, env = self.fixture(root)
                result = subprocess.run([sys.executable, 'scripts/prepare-native.py', *([] if selected is None else ['--platform', selected])], cwd=root, env=env, capture_output=True, text=True, timeout=15)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.calls(log), [list(call) for call in expected])

    def test_readiness_selectors_record_no_opposite_platform_preparation_or_tools(self):
        for selected in ('android', 'ios', 'all'):
            with self.subTest(platform=selected), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                log, env = self.fixture(root)
                if selected == 'ios':
                    # An Apple-only check must succeed without any Godot/Android executable.
                    (root / 'tools/godot').unlink()
                    (root / 'gradlew').unlink()
                result = subprocess.run([sys.executable, 'scripts/check.py', '--platform', selected], cwd=root, env=env, capture_output=True, text=True, timeout=15)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                calls = self.calls(log)
                prepare = [call[1:] for call in calls if 'scripts/prepare-native.py' in call]
                self.assertEqual(prepare, [['scripts/prepare-native.py', '--platform', selected]])
                android = any('test-android' in call for call in calls)
                ios = any('scripts/check-ios.py' in call for call in calls)
                lint = any(':android-plugin:lint' in call for call in calls)
                self.assertEqual((android, ios, lint), (selected != 'ios', selected != 'android', selected != 'ios'))

    def test_actual_ci_apple_path_sets_up_pinned_godot_and_joins_before_packing(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            (root / 'scripts/bazel').mkdir(parents=True)
            shutil.copy2(ROOT / 'scripts/ci.sh', root / 'scripts/ci.sh')
            (root / 'scripts/bazel/ci-cache.sh').write_text('# fixture installation boundary\n')
            log = root / 'shell-calls.txt'
            engine = root / '.native/tools/Godot.app/Contents/MacOS/Godot'
            engine.parent.mkdir(parents=True)
            engine.write_text('fixture executable')
            engine.chmod(0o755)
            hook = root / 'fixture-shell.sh'
            hook.write_text('python3() { if [[ "$1" == -c ]]; then echo 4.7.2; else printf "%s\\t" "$@" >> "$CALLS"; printf "\\n" >> "$CALLS"; fi; }\n'
                            + 'function ' + str(engine) + '() { printf "4.7.2.stable.fixture\\n"; }\n')
            result = subprocess.run(['/bin/bash', 'scripts/ci.sh', '--platform', 'ios'], cwd=root,
                                    env=dict(os.environ, BASH_ENV=str(hook), CALLS=str(log)),
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            calls = [line.rstrip('\t').split('\t') for line in log.read_text().splitlines()]
            self.assertEqual(calls, [
                ['scripts/bazel/lane_artifacts.py', 'verify', '--input', 'output/pipeline/android-products'],
                ['scripts/bazel/ios_simulator.py', '--', 'python3', 'scripts/check.py', '--platform', 'ios'],
                ['scripts/pack.py', '--require-android-handoff'],
                ['scripts/check.py', '--platform', 'portable'],
            ])

    def test_invalid_selector_fails_before_invoking_any_tool(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            log, env = self.fixture(root)
            result = subprocess.run([sys.executable, 'scripts/prepare-native.py', '--platform', 'wrong'], cwd=root, env=env, capture_output=True, timeout=15)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(log.exists())


if __name__ == '__main__':
    unittest.main()
