"""Real public receipt, Git bytes and child-process oracles for producer admission."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import native_prepare
import native_producer_policy as policy


class NativeProducerPolicyTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name).resolve()
        self.trust = self.base / 'trust'
        self.policy = self.trust / 'etc/nuxie/qualifications.json'
        self.policy.parent.mkdir(parents=True)
        for path in (self.trust, self.trust / 'etc', self.policy.parent):
            path.chmod(0o700)
        self.source = self.base / 'producer'
        self.source.mkdir()
        self.git('init', '-q')
        self.producer = self.source / 'scripts/bazel/sdk.py'
        self.producer.parent.mkdir(parents=True)
        self.producer.write_text('''import hashlib, json, os, sys
from pathlib import Path
Path(os.environ['PRODUCER_MARKER']).write_text(json.dumps({'args': sys.argv[1:], 'isolated': sys.flags.isolated, 'bytecode': sys.dont_write_bytecode}))
out = Path(sys.argv[sys.argv.index('--output') + 1])
out.mkdir(parents=True, exist_ok=True)
data = b'independent native product'
(out / 'sdk.aar').write_bytes(data)
(out / 'sdk-artifacts.json').write_text(json.dumps({'schemaVersion': 1, 'sdk': 'android',
    'sourceRevision': os.environ['PRODUCER_REVISION'], 'sourceDirty': False,
    'artifacts': [{'path': 'sdk.aar', 'size': len(data), 'sha256': hashlib.sha256(data).hexdigest()}]}))
''')
        for name in ('MODULE.bazel', 'MODULE.bazel.lock', 'BUILD', '.bazelrc', '.bazelversion',
                     'Package.swift', 'Package.resolved', 'Runtime/artifact-set.json',
                     'scripts/bazel/frontend.data', 'bazel/tool.data', 'gradle/wrapper/gradle-wrapper.jar'):
            path = self.source / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('public fixture ' + name + '\n')
        (self.source / 'README.md').write_text('not an executing frontend\n')
        self.git('add', '.')
        self.git('-c', 'user.name=Producer test', '-c', 'user.email=test@nuxie.test', 'commit', '-qm', 'fixture')
        self.revision = self.git('rev-parse', 'HEAD').strip()
        self.pin = {'repository': policy.REPOSITORIES['android'], 'revision': self.revision}
        self.frontend = {name: hashlib.sha256((self.source / name).read_bytes()).hexdigest()
                         for name in self.git('ls-files').splitlines() if policy.control(name)}
        self.entry = dict(repository=self.pin['repository'], revision=self.revision, frontend=self.frontend,
                          platform='linux', profile='linux-native', capability='linux-14g-v2',
                          qualificationId='synthetic-independent-oracle', qualifiedAt='2026-01-01T00:00:00Z')
        self.write_receipt()
        for target, value in [('TRUST_OWNER', os.getuid()), ('TRUST_ROOT', self.trust),
                              ('POLICY_PATHS', {'linux': self.policy, 'darwin': self.policy})]:
            fixture = patch.object(policy, target, value)
            fixture.start()
            self.addCleanup(fixture.stop)
        # This is the filesystem trust boundary only; production has no override.
        host = patch.object(policy.sys, 'platform', 'linux')
        host.start()
        self.addCleanup(host.stop)
        self.marker = self.base / 'producer-invoked.json'
        environment = patch.dict(os.environ, {'NUXIE_CI_RUNNER_POLICY_VERSION': '2', 'NUXIE_CI_RUNNER_PROFILE': 'linux-native',
            'NUXIE_NATIVE_PREPARED_ONLY': '0', 'NUXIE_ANDROID_ARTIFACTS': '', 'NUXIE_IOS_ARTIFACTS': '',
            'NUXIE_IOS_DEBUG_ARTIFACTS': '', 'NUXIE_IOS_RELEASE_ARTIFACTS': '',
            'PRODUCER_MARKER': str(self.marker), 'PRODUCER_REVISION': self.revision})
        environment.start()
        self.addCleanup(environment.stop)
        self.consumer = self.base / 'consumer'
        self.consumer.mkdir()
        (self.consumer / 'NATIVE-PINS.json').write_text(json.dumps({'android': self.pin}))

    def git(self, *args):
        return subprocess.check_output(['git', *args], cwd=self.source, text=True, stderr=subprocess.DEVNULL)

    def write_receipt(self, entries=None, **changes):
        value = dict(schema='nuxie-native-producer-qualifications.v1', policyVersion=2,
                     qualifications=[self.entry] if entries is None else entries)
        value.update(changes)
        self.policy.write_text(json.dumps(value))
        self.policy.chmod(0o600)

    def prepare(self):
        with patch.object(native_prepare, 'checkout', return_value=(self.source, self.producer)):
            return native_prepare.prepare(self.consumer, ['android'])

    def test_valid_exact_inventory_reaches_isolated_child_and_verified_products(self):
        approval = policy.verify(self.source, 'android', self.pin)
        self.assertEqual(approval['qualificationId'], self.entry['qualificationId'])
        result = self.prepare()
        self.assertTrue(result['android'].is_file())
        observed = json.loads(self.marker.read_text())
        self.assertEqual(observed['isolated'], 1)
        self.assertTrue(observed['bytecode'])
        self.assertEqual(observed['args'][0], 'prepare')
        self.assertFalse((self.source / 'scripts/bazel/__pycache__').exists())

    def test_approved_child_cannot_return_a_corrupted_producer_receipt(self):
        # The exact approved child executes, then publishes a receipt whose
        # byte hash contradicts its actual product. Admission alone is not
        # artifact qualification.
        self.producer.write_text(self.producer.read_text() + "\n(out / 'sdk.aar').write_bytes(b'corrupted actual bytes')\n")
        self.git('add', 'scripts/bazel/sdk.py')
        self.git('-c', 'user.name=Producer test', '-c', 'user.email=test@nuxie.test', 'commit', '-qm', 'corrupt publication fixture')
        self.revision = self.git('rev-parse', 'HEAD').strip()
        self.pin['revision'] = self.revision
        self.frontend['scripts/bazel/sdk.py'] = hashlib.sha256(self.producer.read_bytes()).hexdigest()
        self.entry.update(revision=self.revision, frontend=self.frontend)
        self.write_receipt()
        (self.consumer / 'NATIVE-PINS.json').write_text(json.dumps({'android': self.pin}))
        with patch.dict(os.environ, {'PRODUCER_REVISION': self.revision}):
            with self.assertRaisesRegex(ValueError, 'Artifact (size|SHA-256) changed'):
                self.prepare()
        self.assertTrue(self.marker.is_file())

    def test_symlinked_native_parent_or_lock_has_no_external_write(self):
        outside = self.base / 'outside'
        outside.mkdir()
        native = self.consumer / '.native'
        native.symlink_to(outside, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'symlinked native'):
            self.prepare()
        self.assertEqual(list(outside.iterdir()), [])
        native.unlink()
        native.mkdir()
        (native / '.prepare.lock').symlink_to(outside / 'lock')
        with self.assertRaisesRegex(ValueError, 'symlinked native'):
            self.prepare()
        self.assertFalse((outside / 'lock').exists())
        self.assertFalse(self.marker.exists())

    def test_missing_and_wrong_revision_refuse_before_checkout_or_child(self):
        for missing in (True, False):
            with self.subTest(missing=missing):
                if missing:
                    self.policy.unlink()
                else:
                    self.write_receipt(entries=[dict(self.entry, revision='0' * 40)])
                with patch.object(native_prepare, 'checkout') as checkout:
                    with self.assertRaises(ValueError):
                        native_prepare.prepare(self.consumer, ['android'])
                    checkout.assert_not_called()
                self.assertFalse(self.marker.exists())

    def test_incomplete_frontend_refuses_child(self):
        self.write_receipt(entries=[dict(self.entry, frontend={name: digest for name, digest in self.frontend.items() if name != 'Runtime/artifact-set.json'})])
        with self.assertRaisesRegex(ValueError, 'complete concrete'):
            self.prepare()
        self.assertFalse(self.marker.exists())

    def test_wrong_profile_capability_or_repository_never_matches(self):
        for change in ({'profile': 'linux-portable'}, {'capability': 'linux-16g-v2'},
                       {'platform': 'macos', 'profile': 'macos-apple', 'capability': 'mac-64g-v2'},
                       {'repository': 'https://github.com/other/nuxie-android.git'}):
            with self.subTest(change=change):
                self.write_receipt(entries=[dict(self.entry, **change)])
                with self.assertRaises(ValueError):
                    self.prepare()
                self.assertFalse(self.marker.exists())
        self.write_receipt()
        with patch.dict(os.environ, {'NUXIE_CI_RUNNER_PROFILE': 'linux-portable'}):
            with self.assertRaisesRegex(ValueError, 'native builder'):
                self.prepare()

    def test_mutable_file_and_nested_ancestor_refuse_without_process(self):
        for path in (self.policy, self.trust / 'etc'):
            original = path.stat().st_mode & 0o777
            path.chmod(0o777)
            with self.subTest(path=path), self.assertRaisesRegex(ValueError, 'root-controlled'):
                self.prepare()
            path.chmod(original)
        self.assertFalse(self.marker.exists())

    def test_nested_ancestor_and_leaf_symlinks_refuse_without_process(self):
        original_parent = self.trust / 'etc'
        retained = self.trust / 'retained'
        original_parent.rename(retained)
        original_parent.symlink_to(retained, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'root-controlled'):
            self.prepare()
        original_parent.unlink()
        retained.rename(original_parent)
        original = self.policy.read_bytes()
        actual = self.policy.with_name('retained.json')
        actual.write_bytes(original)
        actual.chmod(0o600)
        self.policy.unlink()
        self.policy.symlink_to(actual)
        with self.assertRaisesRegex(ValueError, 'root-controlled'):
            self.prepare()
        self.assertFalse(self.marker.exists())

    def test_dirty_tracked_and_ignored_untracked_frontends_refuse(self):
        self.producer.write_text(self.producer.read_text() + '# unapproved frontend\n')
        with self.assertRaisesRegex(ValueError, 'clean qualified'):
            self.prepare()
        self.git('restore', 'scripts/bazel/sdk.py')
        ignored = self.source / 'scripts/bazel/__pycache__/shadow.pyc'
        ignored.parent.mkdir()
        ignored.write_bytes(b'unapproved ignored executable input')
        (self.source / '.git/info/exclude').write_text('__pycache__/\n')
        with self.assertRaisesRegex(ValueError, 'Untracked native'):
            self.prepare()
        self.assertFalse(self.marker.exists())

    def test_rebound_dirty_digest_cannot_replace_git_bytes(self):
        self.producer.write_text(self.producer.read_text() + '# different bytes\n')
        self.git('update-index', '--assume-unchanged', 'scripts/bazel/sdk.py')
        frontend = dict(self.frontend, **{'scripts/bazel/sdk.py': hashlib.sha256(self.producer.read_bytes()).hexdigest()})
        self.write_receipt(entries=[dict(self.entry, frontend=frontend)])
        with self.assertRaisesRegex(ValueError, 'Git blob'):
            self.prepare()
        self.assertFalse(self.marker.exists())

    def test_generated_native_products_do_not_change_frontend_inventory(self):
        product = self.source / 'Runtime/prepared/bin/native-product'
        product.parent.mkdir(parents=True)
        product.write_bytes(b'synthetic generated product')
        product.chmod(0o755)
        rc = self.source / '.bazel-cache.local.bazelrc'
        rc.write_text('build --disk_cache=/synthetic/cache\n')
        policy.verify(self.source, 'android', self.pin)
        rc.unlink()
        rc.symlink_to(product)
        with self.assertRaisesRegex(ValueError, 'bounded regular'):
            policy.verify(self.source, 'android', self.pin)

    def test_schema_duplicates_boolean_version_and_unsafe_paths_refuse(self):
        self.policy.write_text('{"schema":"nuxie-native-producer-qualifications.v1","policyVersion":2,"policyVersion":2,"qualifications":[]}')
        with self.assertRaisesRegex(ValueError, 'Duplicate'):
            self.prepare()
        self.write_receipt(policyVersion=True)
        with self.assertRaisesRegex(ValueError, 'schema'):
            self.prepare()
        for name in ('../escape.py', 'scripts//sdk.py', '/absolute.py', 'scripts/../sdk.py'):
            self.write_receipt(entries=[dict(self.entry, frontend={name: '0' * 64})])
            with self.subTest(name=name), self.assertRaises(ValueError):
                self.prepare()
        self.assertFalse(self.marker.exists())


if __name__ == '__main__':
    unittest.main()
