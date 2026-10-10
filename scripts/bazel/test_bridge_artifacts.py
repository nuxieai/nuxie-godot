"""Compiler product packaging checked against archive and Gradle publication oracles."""
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zipfile
from bridge_artifacts import aar, manifest

class BridgeArtifactsTests(unittest.TestCase):
    def test_aar_preserves_compiled_entries_and_owning_consumer_rules(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, rules, output = root / 'compiled.aar', root / 'consumer.pro', root / 'bridge.aar'
            with zipfile.ZipFile(source, 'w') as archive:
                for name, content in {'classes.jar': b'compiled JVM bytecode', 'AndroidManifest.xml': b'compiled manifest', 'res/values/strings.xml': b'owned resources'}.items():
                    archive.writestr(name, content)
            rules.write_bytes(b'-keep class ai.nuxie.** { *; }')
            aar(source, output, rules)
            first = output.read_bytes()
            with zipfile.ZipFile(output) as archive:
                self.assertEqual(archive.read('classes.jar'), b'compiled JVM bytecode')
                self.assertEqual(archive.read('res/values/strings.xml'), b'owned resources')
                self.assertEqual(archive.read('proguard.txt'), rules.read_bytes())
                self.assertTrue(all(item.date_time == (1980, 1, 1, 0, 0, 0) for item in archive.infolist()))
            aar(source, output, rules)
            self.assertEqual(output.read_bytes(), first)

    def test_manifest_keeps_permissions_and_requires_resolved_engine_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, output = root / 'source.xml', root / 'manifest.xml'
            source.write_text('<manifest xmlns:android="http://schemas.android.com/apk/res/android"><uses-permission android:name="android.permission.INTERNET"/><application><meta-data android:name="plugin" android:value="${plugin}"/></application></manifest>')
            with self.assertRaisesRegex(ValueError, 'Unresolved'):
                manifest(source, output, 'ai.nuxie.bridge', [])
            manifest(source, output, 'ai.nuxie.bridge', ['plugin=engine'])
            contents = ET.parse(output).getroot()
            android = '{http://schemas.android.com/apk/res/android}'
            self.assertEqual(contents.find('uses-permission').get(android + 'name'), 'android.permission.INTERNET')
            self.assertEqual(contents.find('application/meta-data').get(android + 'value'), 'engine')
            self.assertEqual(contents.find('uses-sdk').get(android + 'minSdkVersion'), '23')

if __name__ == '__main__':
    unittest.main()
