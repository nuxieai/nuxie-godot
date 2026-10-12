"""Independent receipt and byte oracles for one-candidate Android transfer."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import lane_artifacts as lane

PIN = 'a' * 40


class TransferTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / 'godot'
        self.root.mkdir()
        self.root_patch = patch.object(lane, 'ROOT', self.root)
        self.root_patch.start()
        self.addCleanup(self.root_patch.stop)
        self.env_patch = patch.dict(os.environ, {}, clear=True)
        self.env_patch.start()
        self.addCleanup(self.env_patch.stop)
        self.bundle = self.root / 'output/pipeline/android-products'
        self.write('NATIVE-PINS.json', json.dumps({'version': '0.4.0', 'android': {'revision': PIN}, 'ios': {'revision': 'b' * 40}, 'godot': '4.7.2'}).encode())
        subprocess.run(['git', 'init', '-q'], cwd=self.root, check=True)
        subprocess.run(['git', 'add', 'NATIVE-PINS.json'], cwd=self.root, check=True)
        subprocess.run(['git', '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'Fixture source'], cwd=self.root, check=True)
        version = '0.2.0-' + PIN
        coordinate = 'ai/nuxie/nuxie-android/' + version + '/nuxie-android-' + version
        native = self.root / '.native/artifacts/android'
        for extension in ('aar', 'pom', 'module'):
            data = ('published-' + extension).encode()
            self.write('.native/artifacts/android/' + coordinate + '.' + extension, data)
            self.write('.native/maven/' + coordinate + '.' + extension, data)
        self.write('.native/artifacts/android/licenses/LICENSE', b'original native license')
        self.write(lane.LICENSE, b'original native license')
        for name in lane.BRIDGES:
            self.write(name, name.encode())
        receipt = {'schemaVersion': 1, 'sdk': 'android', 'sourceRevision': PIN, 'sourceDirty': False,
                   'runtime': {'mode': 'published', 'checksum': 'c' * 64, 'release': 'pinned-runtime'},
                   'maven': {'groupId': 'ai.nuxie', 'artifactId': 'nuxie-android', 'version': version},
                   'artifacts': [{'path': p.relative_to(native).as_posix(), 'size': p.stat().st_size,
                                  'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}
                                 for p in sorted(native.rglob('*')) if p.is_file()]}
        self.write(lane.PRODUCER, json.dumps(receipt).encode())
        self.original = (self.root / lane.PRODUCER).read_bytes()

    def write(self, name, data):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)

    def test_roundtrip_preserves_original_receipt_pins_licenses_and_both_bridge_variants(self):
        document = lane.export(self.bundle)
        expected = {item['path']: (self.root / item['path']).read_bytes() for item in document['artifacts']}
        shutil.rmtree(self.root / '.native')
        shutil.rmtree(self.root / 'addons')
        lane.restore(self.bundle)
        self.assertEqual((self.root / lane.PRODUCER).read_bytes(), self.original)
        self.assertTrue(lane.BRIDGES <= expected.keys())
        for name, data in expected.items():
            self.assertEqual((self.root / name).read_bytes(), data)
        lane.verify_restored(self.bundle)
        self.assertFalse((self.root / '.native/android').exists())

    def test_corrupt_missing_and_unlisted_artifacts_fail_before_any_restoration(self):
        for mutation in ('corrupt', 'missing', 'unlisted'):
            with self.subTest(mutation=mutation):
                lane.export(self.bundle)
                bridge = self.bundle / 'payload' / sorted(lane.BRIDGES)[0]
                if mutation == 'corrupt': bridge.write_bytes(b'corrupt')
                elif mutation == 'missing': bridge.unlink()
                else: (bridge.parent / 'unlisted.aar').write_bytes(b'unlisted')
                before = (self.root / sorted(lane.BRIDGES)[0]).read_bytes()
                with self.assertRaises(ValueError): lane.restore(self.bundle)
                self.assertEqual((self.root / sorted(lane.BRIDGES)[0]).read_bytes(), before)
                shutil.rmtree(self.bundle)

    def test_wrong_native_pins_or_candidate_commit_fail_before_consumption(self):
        lane.export(self.bundle)
        pins = self.root / 'NATIVE-PINS.json'
        original = pins.read_bytes()
        pins.write_bytes(original + b'\n')
        with self.assertRaises(ValueError): lane.verify(self.bundle)
        pins.write_bytes(original)
        with patch.dict(os.environ, {'BUILDKITE_COMMIT': '0' * 40}):
            with self.assertRaisesRegex(ValueError, 'candidate build'): lane.verify(self.bundle)

    def test_changed_restored_bytes_and_external_symlinks_fail(self):
        lane.export(self.bundle)
        bridge = self.root / sorted(lane.BRIDGES)[0]
        bridge.write_bytes(b'changed after restore')
        with self.assertRaisesRegex(ValueError, 'differs from its prerequisite'): lane.verify_restored(self.bundle)
        bridge.unlink()
        bridge.symlink_to(self.root / 'NATIVE-PINS.json')
        with self.assertRaises(ValueError): lane.restore(self.bundle)

    def test_original_native_receipt_pin_and_runtime_remain_authority(self):
        receipt = self.root / lane.PRODUCER
        for field, value in [('sourceRevision', '0' * 40), ('runtime', {'mode': 'local'})]:
            receipt.write_bytes(self.original)
            changed = json.loads(receipt.read_text()); changed[field] = value
            receipt.write_text(json.dumps(changed))
            with self.assertRaises(ValueError): lane.export(self.bundle)
            self.assertFalse(self.bundle.exists())

    def copy_pack_cli(self):
        script = self.root / 'scripts/pack.py'
        script.parent.mkdir(exist_ok=True)
        shutil.copy2(Path(__file__).resolve().parents[1] / 'pack.py', script)
        (self.root / 'scripts/bazel').mkdir(exist_ok=True)
        for name in ('lane_artifacts.py', 'native_artifacts.py'):
            shutil.copy2(Path(__file__).with_name(name), self.root / 'scripts/bazel' / name)
        return script

    def test_actual_pack_joins_both_platforms_and_preserves_original_licenses_and_bytes(self):
        import zipfile
        lane.export(self.bundle)
        for configuration in ('Debug', 'Release'):
            native = self.root / '.native/artifacts/ios' / configuration
            native.mkdir(parents=True)
            (native / 'LICENSE').write_bytes(b'original iOS license')
            receipt = {'schemaVersion': 1, 'sdk': 'ios', 'sourceRevision': 'b' * 40, 'sourceDirty': False,
                       'runtime': {'checksum': 'd' * 64, 'sourceCommit': 'e' * 40},
                       'products': [{'platform': selected, 'configuration': configuration} for selected in ('ios-device', 'ios-simulator')],
                       'artifacts': [{'path': 'licenses/LICENSE', 'size': 20, 'sha256': hashlib.sha256(b'original iOS license').hexdigest()}]}
            (native / 'licenses').mkdir()
            (native / 'LICENSE').rename(native / 'licenses/LICENSE')
            (native / 'sdk-artifacts.json').write_text(json.dumps(receipt))
            for bridge in ('NuxieGodotBridge', 'nuxie_godot_plugin'):
                self.write('ios-plugin/.build/xcframework/' + bridge + '.' + configuration.lower() + '.xcframework/product',
                           (bridge + configuration).encode())
        for name, data in [('Nuxie-iOS.txt', b'original iOS license'), ('Godot.txt', b'Godot license'), ('Godot-COPYRIGHT.txt', b'Godot copyright')]:
            self.write('.native/licenses/' + name, data)
        script = self.copy_pack_cli()
        result = subprocess.run(['python3', str(script), '--require-android-handoff'], cwd=self.root, capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        with zipfile.ZipFile(self.root / 'dist/nuxie-godot-0.4.0.zip') as archive:
            checksums = json.loads(archive.read('addons/nuxie/artifact-checksums.json'))
            for name, expected in checksums.items():
                data = archive.read('addons/nuxie/' + name)
                self.assertEqual(hashlib.sha256(data).hexdigest(), expected)
                self.assertEqual((self.root / 'examples/sdk-lab/addons/nuxie' / name).read_bytes(), data)
            self.assertTrue(all(name.removeprefix('addons/nuxie/') in checksums for name in lane.BRIDGES))
            self.assertEqual(len([name for name in checksums if '.xcframework/product' in name]), 4)
            self.assertEqual(archive.read('addons/nuxie/licenses/Nuxie-Android.txt'), b'original native license')
            self.assertEqual(archive.read('addons/nuxie/licenses/Nuxie-iOS.txt'), b'original iOS license')

    def test_another_builds_source_identical_prerequisite_is_rejected(self):
        producer = {'BUILDKITE_BUILD_ID': 'a' * 8 + '-' + 'a' * 4 + '-' + 'a' * 4 + '-' + 'a' * 4 + '-' + 'a' * 12,
                    'BUILDKITE_JOB_ID': 'b' * 8 + '-' + 'b' * 4 + '-' + 'b' * 4 + '-' + 'b' * 4 + '-' + 'b' * 12}
        with patch.dict(os.environ, producer):
            lane.export(self.bundle)
            lane.verify(self.bundle)
        with patch.dict(os.environ, {'BUILDKITE_BUILD_ID': 'c' * 8 + '-' + 'c' * 4 + '-' + 'c' * 4 + '-' + 'c' * 4 + '-' + 'c' * 12}):
            with self.assertRaisesRegex(ValueError, 'different build'): lane.restore(self.bundle)

    def test_actual_pack_cli_refuses_missing_handoff_before_staging_products(self):
        script = self.root / 'scripts/pack.py'
        script.parent.mkdir()
        shutil.copy2(Path(__file__).resolve().parents[1] / 'pack.py', script)
        (self.root / 'scripts/bazel').mkdir()
        for name in ('lane_artifacts.py', 'native_artifacts.py'):
            shutil.copy2(Path(__file__).with_name(name), self.root / 'scripts/bazel' / name)
        result = subprocess.run(['python3', str(script), '--require-android-handoff'], cwd=self.root, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / '.native/package').exists())
        self.assertFalse((self.root / 'dist').exists())


if __name__ == '__main__':
    unittest.main()
