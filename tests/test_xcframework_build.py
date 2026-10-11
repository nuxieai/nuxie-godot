"""Package real Bazel archive layouts while preserving native resources and slices."""
import hashlib
import json
from pathlib import Path
import plistlib
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

sys.path.insert(0, str(Path(__file__).absolute().parents[1] / 'scripts/bazel'))
import sdk

PIN = '1' * 40

class XCFrameworkBuildTests(unittest.TestCase):
    def fixtures(self, root, configuration, prefix='', missing_architecture=False, static_framework=True,
                 missing_binary_architecture=False):
        (root / '.native').mkdir()
        (root / 'NATIVE-PINS.json').write_text(json.dumps({'ios': {'revision': PIN}}))
        native = root / '.native/native-products'
        products = []
        for selected in ('ios-device', 'ios-simulator'):
            resource = selected + '/' + configuration + '/Nuxie_Nuxie.bundle'
            (native / resource).mkdir(parents=True)
            (native / resource / 'fixture.txt').write_text('owned SDK resources')
            products.append({'platform': selected, 'configuration': configuration, 'resourceBundles': [resource]})
        (native / 'licenses').mkdir()
        (native / 'licenses/LICENSE').write_text('native license')
        receipt = {'schemaVersion': 1, 'sdk': 'ios', 'sourceRevision': PIN, 'sourceDirty': False, 'products': products,
                   'artifacts': [{'path': path.relative_to(native).as_posix(), 'size': path.stat().st_size,
                                  'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
                                 for path in native.rglob('*') if path.is_file()]}
        manifest = native / 'sdk-artifacts.json'
        manifest.write_text(json.dumps(receipt))
        archives = {}
        for name in ('NuxieGodotBridge', 'nuxie_godot_plugin'):
            bundle = prefix + name + '.xcframework/'
            framework = name == 'NuxieGodotBridge' or static_framework
            slices = [dict(LibraryIdentifier='ios-arm64', LibraryPath=name + '.framework' if framework else 'lib' + name + '.a',
                           SupportedPlatform='ios', SupportedArchitectures=['arm64']),
                      dict(LibraryIdentifier='ios-arm64_x86_64-simulator', LibraryPath=name + '.framework' if framework else 'lib' + name + '.a',
                           SupportedPlatform='ios', SupportedPlatformVariant='simulator', SupportedArchitectures=['arm64'] if missing_architecture else ['arm64','x86_64'])]
            archive = root / (name + '.zip')
            with zipfile.ZipFile(archive, 'w') as compressed:
                compressed.writestr(bundle + 'Info.plist', plistlib.dumps({'AvailableLibraries': slices}))
                for item in slices:
                    binary = item['LibraryPath'] + ('/' + name if framework else '')
                    architectures = ['arm64'] if missing_binary_architecture else item['SupportedArchitectures']
                    compressed.writestr(bundle + item['LibraryIdentifier'] + '/' + binary, json.dumps(architectures))
            archives['//:ios_bridge_xcframework' if name == 'NuxieGodotBridge' else '//:ios_plugin_xcframework'] = archive
        headers = root / 'godot-headers'
        headers.mkdir()
        (headers / 'LICENSE.txt').write_text('Godot license')
        (headers / 'COPYRIGHT.txt').write_text('Godot copyright')
        return manifest, archives, headers

    def binary_architectures(self, command, **_kwargs):
        self.assertEqual(command[:3], ['xcrun', 'lipo', '-archs'])
        return ' '.join(json.loads(Path(command[3]).read_text()))


    def test_archive_layouts_keep_resources_and_all_device_simulator_architectures(self):
        for prefix in ('', 'products/'):
            for configuration in ('Debug', 'Release'):
                with self.subTest(prefix=prefix, configuration=configuration), tempfile.TemporaryDirectory() as directory:
                    root = Path(directory)
                    manifest, archives, headers = self.fixtures(root, configuration, prefix)
                    for native_platform in ('ios-device', 'ios-simulator'):
                        (manifest.parent / native_platform / configuration / 'Nuxie_Nuxie.bundle/unrecorded.png').write_bytes(b'not in receipt')
                    with patch.object(sdk, 'ROOT', root), patch.object(sdk, 'prepare', return_value={'ios': manifest}), \
                         patch.object(sdk, 'bazel'), patch.object(sdk, 'verify_binary_platform'), patch.object(sdk, 'artifact', side_effect=lambda label, *_args: archives[label]), \
                         patch.object(sdk, 'outputs', return_value=[headers]), patch.object(sdk.subprocess, 'check_output', side_effect=self.binary_architectures):
                        product = sdk.ios_xcframework(configuration)
                    info = plistlib.loads((product / 'Info.plist').read_bytes())
                    for item in info['AvailableLibraries']:
                        framework = product / item['LibraryIdentifier'] / item['LibraryPath']
                        self.assertEqual((framework / 'Nuxie_Nuxie.bundle/fixture.txt').read_text(), 'owned SDK resources')
                        self.assertFalse((framework / 'Nuxie_Nuxie.bundle/unrecorded.png').exists())
                    plugin = product.parent / ('nuxie_godot_plugin.' + configuration.lower() + '.xcframework')
                    self.assertTrue(plugin.is_dir())
                    plugin_info = plistlib.loads((plugin / 'Info.plist').read_bytes())
                    for item in plugin_info['AvailableLibraries']:
                        framework = plugin / item['LibraryIdentifier'] / item['LibraryPath']
                        self.assertEqual((framework / 'Nuxie_Nuxie.bundle/fixture.txt').read_text(), 'owned SDK resources')
                        self.assertFalse((framework / 'Nuxie_Nuxie.bundle/unrecorded.png').exists())
                    self.assertEqual((root / '.native/licenses/Godot.txt').read_text(), 'Godot license')

    def test_static_library_archive_layout_remains_supported(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest, archives, headers = self.fixtures(root, 'Release', static_framework=False)
            with patch.object(sdk, 'ROOT', root), patch.object(sdk, 'prepare', return_value={'ios': manifest}), \
                 patch.object(sdk, 'bazel'), patch.object(sdk, 'verify_binary_platform'), patch.object(sdk, 'artifact', side_effect=lambda label, *_args: archives[label]), \
                 patch.object(sdk, 'outputs', return_value=[headers]), patch.object(sdk.subprocess, 'check_output', side_effect=self.binary_architectures):
                sdk.ios_xcframework('Release')
            plugin = root / 'ios-plugin/.build/xcframework/nuxie_godot_plugin.release.xcframework'
            self.assertTrue((plugin / 'ios-arm64/libnuxie_godot_plugin.a').is_file())

    def test_binary_missing_a_declared_architecture_is_not_published(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest, archives, _headers = self.fixtures(root, 'Release', missing_binary_architecture=True)
            with patch.object(sdk, 'ROOT', root), patch.object(sdk, 'prepare', return_value={'ios': manifest}), \
                 patch.object(sdk, 'bazel'), patch.object(sdk, 'verify_binary_platform'), patch.object(sdk, 'artifact', side_effect=lambda label, *_args: archives[label]), \
                 patch.object(sdk.subprocess, 'check_output', side_effect=self.binary_architectures), \
                 self.assertRaisesRegex(ValueError, 'has architectures'):
                sdk.ios_xcframework('Release')
            self.assertFalse((root / 'ios-plugin/.build/xcframework').exists())

    def test_incomplete_simulator_slice_is_not_published(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest, archives, headers = self.fixtures(root, 'Release', missing_architecture=True)
            with patch.object(sdk, 'ROOT', root), patch.object(sdk, 'prepare', return_value={'ios': manifest}), \
                 patch.object(sdk, 'bazel'), patch.object(sdk, 'verify_binary_platform'), patch.object(sdk, 'artifact', side_effect=lambda label, *_args: archives[label]), \
                 self.assertRaisesRegex(ValueError, 'both simulator architectures'):
                sdk.ios_xcframework('Release')
            self.assertFalse((root / 'ios-plugin/.build/xcframework').exists())

if __name__ == '__main__':
    unittest.main()
