"""The preparation boundary preserves source edits and source-addressed products."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from native_prepare import checkout, prepare


class NativePreparationTests(unittest.TestCase):
    def setUp(self):
        environment = patch.dict(os.environ, {'NUXIE_IOS_ARTIFACTS': '', 'NUXIE_IOS_DEBUG_ARTIFACTS': '',
                                              'NUXIE_IOS_RELEASE_ARTIFACTS': '', 'NUXIE_ANDROID_ARTIFACTS': ''})
        environment.start()
        self.addCleanup(environment.stop)
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve() / 'downstream'
        self.root.mkdir()
        self.upstream = Path(self.temporary.name) / 'upstream'
        self.upstream.mkdir()
        self.git('init', '-q', cwd=self.upstream)
        producer = self.upstream / 'scripts/bazel/sdk.py'
        producer.parent.mkdir(parents=True)
        producer.write_text('''import json
from pathlib import Path
import sys
args = sys.argv[1:]
out = Path(args[args.index('--output') + 1])
out.mkdir(parents=True, exist_ok=True)
(out / 'invocation.json').write_text(json.dumps(args))
''')
        (self.upstream / 'SDK.txt').write_text('original SDK source\n')
        self.git('add', '.', cwd=self.upstream)
        self.git('-c', 'user.name=Native test', '-c', 'user.email=test@nuxie.test', 'commit', '-qm', 'fixture', cwd=self.upstream)
        self.revision = self.git('rev-parse', 'HEAD', cwd=self.upstream).strip()
        self.pin = {'repository': str(self.upstream), 'revision': self.revision}
        (self.root / 'NATIVE-PINS.json').write_text(json.dumps({'android': self.pin}))

    def git(self, *arguments, cwd):
        return subprocess.check_output(['git', *arguments], cwd=cwd, text=True, stderr=subprocess.DEVNULL)

    def test_clean_source_and_maven_products_belong_to_downstream(self):
        prepare(self.root, ['android'])
        source = self.root / '.native/android'
        self.assertEqual(self.git('rev-parse', 'HEAD', cwd=source).strip(), self.revision)
        output = self.root / '.native/artifacts/android'
        args = json.loads((output / 'invocation.json').read_text())
        self.assertIn('0.2.0-' + self.revision, args)
        self.assertIn(str(output), args)
        self.assertFalse((self.upstream / '.native').exists())

    def test_modified_native_source_is_preserved(self):
        (self.root / '.native').mkdir()
        source, _ = checkout(self.root, 'android', self.pin)
        owned = source / 'SDK.txt'
        owned.write_text('user edit\n')
        with self.assertRaisesRegex(ValueError, 'Preserving modified'):
            checkout(self.root, 'android', self.pin)
        self.assertEqual(owned.read_text(), 'user edit\n')
        self.assertEqual(self.git('rev-parse', 'HEAD', cwd=source).strip(), self.revision)

    def test_maven_publication_override_is_checkout_specific(self):
        output = self.root / 'android/maven'
        prepare(self.root, ['android'], android_output=output)
        self.assertTrue((output / 'invocation.json').is_file())
        self.assertFalse((self.root / '.native/artifacts/android').exists())

    def test_supplied_products_skip_native_checkout_and_preparation(self):
        products = self.root / 'parent-artifacts'
        products.mkdir()
        manifest = products / 'sdk-artifacts.json'
        (products / 'product.aar').write_bytes(b'prepared artifact')
        manifest.write_text(json.dumps({'schemaVersion': 1, 'sdk': 'android', 'sourceRevision': self.revision, 'sourceDirty': False,
                                       'artifacts': [{'path': 'product.aar', 'size': 17, 'sha256': hashlib.sha256(b'prepared artifact').hexdigest()}]}))
        with patch.dict(os.environ, {'NUXIE_ANDROID_ARTIFACTS': str(products)}):
            selected = prepare(self.root, ['android'])
        self.assertEqual(selected, {'android': manifest})
        self.assertFalse((self.root / '.native/android').exists())

    def ios_fixture(self, name, configuration, revision=None):
        products = self.root / name
        products.mkdir()
        manifest = products / 'sdk-artifacts.json'
        artifact = b'independent native fixture'
        (products / 'product.a').write_bytes(artifact)
        manifest.write_text(json.dumps({
            'schemaVersion': 1, 'sdk': 'ios', 'sourceRevision': revision or self.revision, 'sourceDirty': False,
            'products': [{'platform': 'ios-simulator', 'configuration': configuration}],
            'artifacts': [{'path': 'product.a', 'size': len(artifact), 'sha256': hashlib.sha256(artifact).hexdigest()}],
        }))
        (self.root / 'NATIVE-PINS.json').write_text(json.dumps({'ios': self.pin}))
        return manifest

    def test_each_ios_configuration_selects_its_original_producer_receipt(self):
        debug = self.ios_fixture('debug', 'Debug')
        release = self.ios_fixture('release', 'Release')
        with patch.dict(os.environ, {'NUXIE_IOS_DEBUG_ARTIFACTS': str(debug.parent),
                                    'NUXIE_IOS_RELEASE_ARTIFACTS': str(release),
                                    'NUXIE_IOS_ARTIFACTS': str(self.root / 'unused-legacy-manifest')}):
            self.assertEqual(prepare(self.root, ['ios'], configuration='Debug'), {'ios': debug})
            self.assertEqual(prepare(self.root, ['ios'], configuration='Release'), {'ios': release})
        self.assertFalse((self.root / '.native/ios').exists())
        self.assertEqual(json.loads(debug.read_text())['products'][0]['configuration'], 'Debug')
        self.assertEqual(json.loads(release.read_text())['products'][0]['configuration'], 'Release')

    def test_legacy_ios_override_remains_the_fallback(self):
        for configuration in ('Debug', 'Release'):
            with self.subTest(configuration=configuration):
                manifest = self.ios_fixture('legacy-' + configuration, configuration)
                with patch.dict(os.environ, {'NUXIE_IOS_ARTIFACTS': str(manifest)}):
                    self.assertEqual(prepare(self.root, ['ios'], configuration=configuration), {'ios': manifest})
        self.assertFalse((self.root / '.native/ios').exists())

    def test_wrong_ios_configuration_does_not_fall_back(self):
        wrong = self.ios_fixture('wrong-configuration', 'Release')
        fallback = self.ios_fixture('fallback', 'Debug')
        with patch.dict(os.environ, {'NUXIE_IOS_DEBUG_ARTIFACTS': str(wrong), 'NUXIE_IOS_ARTIFACTS': str(fallback)}):
            with self.assertRaisesRegex(ValueError, 'requested Debug configuration'):
                prepare(self.root, ['ios'], configuration='Debug')
        self.assertFalse((self.root / '.native/ios').exists())

    def test_wrong_ios_revision_does_not_fall_back(self):
        wrong = self.ios_fixture('wrong-revision', 'Debug', '0' * 40)
        fallback = self.ios_fixture('fallback', 'Debug')
        with patch.dict(os.environ, {'NUXIE_IOS_DEBUG_ARTIFACTS': str(wrong), 'NUXIE_IOS_ARTIFACTS': str(fallback)}):
            with self.assertRaisesRegex(ValueError, 'NATIVE-PINS'):
                prepare(self.root, ['ios'], configuration='Debug')
        self.assertFalse((self.root / '.native/ios').exists())

    def test_wrong_supplied_revision_cannot_fall_back_to_rebuilding(self):
        manifest = self.root / 'sdk-artifacts.json'
        manifest.write_text(json.dumps({'schemaVersion': 1, 'sdk': 'android', 'sourceRevision': '0' * 40, 'sourceDirty': False}))
        with patch.dict(os.environ, {'NUXIE_ANDROID_ARTIFACTS': str(manifest)}):
            with self.assertRaisesRegex(ValueError, 'NATIVE-PINS'):
                prepare(self.root, ['android'])
        self.assertFalse((self.root / '.native/android').exists())


if __name__ == '__main__':
    unittest.main()
