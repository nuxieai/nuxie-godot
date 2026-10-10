"""Observe simulator ownership and child status with a fake simctl executable."""

import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest

from ios_simulator import selection


HELPER = Path(__file__).with_name('ios_simulator.py')
OWNED = '00000000-0000-4000-8000-000000000001'
EXTERNAL = '00000000-0000-4000-8000-000000000002'
RUNTIMES = {'runtimes': [
    {'identifier': 'runtime.iOS-26-5', 'version': '26.5', 'isAvailable': True,
     'supportedDeviceTypes': [{'identifier': 'iPhone17', 'name': 'iPhone 17', 'productFamily': 'iPhone'}]},
    {'identifier': 'runtime.iOS-27-0', 'version': '27.0', 'isAvailable': True,
     'supportedDeviceTypes': [{'identifier': 'iPhone18', 'name': 'iPhone 18', 'productFamily': 'iPhone'},
                              {'identifier': 'iPhone18Pro', 'name': 'iPhone 18 Pro', 'productFamily': 'iPhone'}]},
    {'identifier': 'runtime.iOS-28-0', 'version': '28.0', 'isAvailable': False,
     'supportedDeviceTypes': [{'identifier': 'iPhone19', 'name': 'iPhone 19', 'productFamily': 'iPhone'}]},
]}


class SimulatorLeaseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        tool = self.root / 'xcrun'
        tool.write_text('#!' + sys.executable + '\n' + '''import json, os, sys
from pathlib import Path
root = Path(os.environ['LEASE_TEST_ROOT'])
args = sys.argv[1:]
with (root/'calls.jsonl').open('a') as stream: stream.write(json.dumps(args)+'\\n')
if args[1] == 'list': print((root/'runtimes.json').read_text())
elif args[1] == 'create': print(os.environ['LEASE_OWNED'])
elif args[1] == 'bootstatus' and os.environ.get('LEASE_BOOT_FAIL'): sys.exit(9)
''')
        tool.chmod(0o755)
        (self.root / 'runtimes.json').write_text(json.dumps(RUNTIMES))
        self.environment = dict(os.environ, PATH=str(self.root) + os.pathsep + os.environ['PATH'],
                                LEASE_TEST_ROOT=str(self.root), LEASE_OWNED=OWNED, NUXIE_IOS_SIMULATOR_ID='')

    def calls(self):
        path = self.root / 'calls.jsonl'
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def command(self, exit_code=0):
        return [sys.executable, str(HELPER), '--', sys.executable, '-c',
                'import os, pathlib, sys; pathlib.Path(os.environ["LEASE_TEST_ROOT"],"child-id").write_text(os.environ["NUXIE_IOS_SIMULATOR_ID"]); sys.exit(' + str(exit_code) + ')']

    def test_selects_latest_available_compatible_runtime_and_phone(self):
        self.assertEqual(selection(RUNTIMES, '17.0'), ('runtime.iOS-27-0', 'iPhone18Pro'))
        with self.assertRaisesRegex(ValueError, 'available iOS'):
            selection(RUNTIMES, '28.0')

    def test_private_lease_is_deleted_after_success_and_child_failure(self):
        for exit_code in (0, 7):
            with self.subTest(exit_code=exit_code):
                result = subprocess.run(self.command(exit_code), env=self.environment, capture_output=True, text=True)
                self.assertEqual(result.returncode, exit_code, result.stderr)
                self.assertEqual((self.root / 'child-id').read_text(), OWNED)
                self.assertEqual(self.calls()[-2:], [['simctl', 'shutdown', OWNED], ['simctl', 'delete', OWNED]])
                self.assertIn(['simctl', 'bootstatus', OWNED, '-b'], self.calls())

    def test_caller_lease_is_preserved(self):
        result = subprocess.run(self.command(0), env=dict(self.environment, NUXIE_IOS_SIMULATOR_ID=EXTERNAL), capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / 'child-id').read_text(), EXTERNAL)
        self.assertEqual(self.calls(), [])

    def test_boot_failure_deletes_only_created_device(self):
        result = subprocess.run(self.command(), env=dict(self.environment, LEASE_BOOT_FAIL='1'), capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertFalse((self.root / 'child-id').exists())
        self.assertEqual(self.calls()[-1], ['simctl', 'delete', OWNED])

    def test_termination_cleans_lease_and_owned_child(self):
        command = [sys.executable, str(HELPER), '--', sys.executable, '-c',
                   'import os,pathlib,time; pathlib.Path(os.environ["LEASE_TEST_ROOT"],"child-pid").write_text(str(os.getpid())); time.sleep(60)']
        process = subprocess.Popen(command, env=self.environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            deadline = time.monotonic() + 5
            while not (self.root / 'child-pid').exists() and process.poll() is None and time.monotonic() < deadline:
                time.sleep(0.02)
            self.assertTrue((self.root / 'child-pid').is_file())
            process.send_signal(signal.SIGTERM)
            _stdout, stderr = process.communicate(timeout=5)
            self.assertEqual(process.returncode, 143, stderr)
            self.assertEqual(self.calls()[-1], ['simctl', 'delete', OWNED])
            with self.assertRaises(ProcessLookupError):
                os.kill(int((self.root / 'child-pid').read_text()), 0)
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate()


if __name__ == '__main__':
    unittest.main()
