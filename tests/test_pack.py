"""Validate the customer ZIP using a cache containing multiple native revisions."""
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]


class PackageTests(unittest.TestCase):
    def make_checkout(self, root, include_selected=True):
        def write(name, data=b'fixture'):
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)

        write('scripts/pack.py', (ROOT / 'scripts/pack.py').read_bytes())
        write('NATIVE-PINS.json', json.dumps({'version': '0.4.0', 'android': {'revision': 'selected'}}).encode())
        for variant in ('debug', 'release'):
            write(f'addons/nuxie/android/bin/{variant}/NuxieGodot-{variant}.aar')
            for bridge in ('NuxieGodotBridge', 'nuxie_godot_plugin'):
                write(f'ios-plugin/.build/xcframework/{bridge}.{variant}.xcframework/fixture')
        for name in ('.native/godot/LICENSE.txt', '.native/godot/COPYRIGHT.txt', '.native/android/LICENSE',
                     'ios-plugin/.build/DerivedData/SourcePackages/checkouts/nuxie-ios/LICENSE'):
            write(name)
        base = 'ai/nuxie/nuxie-android'
        for revision in (['old', 'selected'] if include_selected else ['old']):
            for extension in ('aar', 'pom', 'module'):
                write(f'.native/maven/{base}/0.2.0-{revision}/nuxie-android-0.2.0-{revision}.{extension}', revision.encode())
        write(f'.native/maven/{base}/maven-metadata.xml', b'old and selected')
        # A previously staged repository must not leak through the source-addon copy either.
        write(f'addons/nuxie/android/maven/{base}/0.2.0-stale/nuxie-android-0.2.0-stale.aar')

    def test_only_selected_coordinate_is_packaged_and_checksummed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.make_checkout(root)
            result = subprocess.run(['python3', 'scripts/pack.py'], cwd=root, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            with zipfile.ZipFile(root / 'dist/nuxie-godot-0.4.0.zip') as archive:
                prefix = 'addons/nuxie/android/maven/'
                selected = {f'ai/nuxie/nuxie-android/0.2.0-selected/nuxie-android-0.2.0-selected.{ext}'
                            for ext in ('aar', 'pom', 'module')}
                self.assertEqual({name.removeprefix(prefix) for name in archive.namelist() if name.startswith(prefix)}, selected)
                checksums = json.loads(archive.read('addons/nuxie/artifact-checksums.json'))
                self.assertEqual({name.removeprefix('android/maven/') for name in checksums if name.startswith('android/maven/')}, selected)
                for name in selected:
                    content = archive.read(prefix + name)
                    self.assertEqual(checksums['android/maven/' + name], hashlib.sha256(content).hexdigest())
                    self.assertEqual((root / 'examples/sdk-lab' / (prefix + name)).read_bytes(), content)

    def test_missing_selected_revision_fails_even_when_old_versions_exist(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.make_checkout(root, include_selected=False)
            result = subprocess.run(['python3', 'scripts/pack.py'], cwd=root, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((root / 'dist/nuxie-godot-0.4.0.zip').exists())


if __name__ == '__main__':
    unittest.main()
