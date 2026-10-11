"""Publication stays isolated and refuses unsafe compiler product archives."""
from pathlib import Path
import tempfile
import subprocess
import sys
import os
import json
from unittest.mock import patch
import sdk
import unittest
import zipfile
from sdk import extract_archive, publish_tree, publish_file, verify_binary_platform, verify_binary_architectures

class SDKPublicationTests(unittest.TestCase):
    def test_readonly_compiler_files_can_be_published_repeatedly_without_cache_mutation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            debug, release = root / 'debug.txt', root / 'release.txt'
            debug.write_text('Debug license bytes')
            release.write_text('Release license bytes')
            modes = {debug: 0o444, release: 0o555}
            for source, mode in modes.items():
                source.chmod(mode)
            output = root / 'checkout/licenses/Godot.txt'
            publish_file(debug, output)
            self.assertEqual(output.read_text(), 'Debug license bytes')
            output.chmod(0o444)
            publish_file(release, output)
            self.assertEqual(output.read_text(), 'Release license bytes')
            self.assertEqual(output.stat().st_mode & 0o777, 0o644)
            for source, expected in ((debug, 'Debug license bytes'), (release, 'Release license bytes')):
                self.assertEqual(source.read_text(), expected)
                self.assertEqual(source.stat().st_mode & 0o777, modes[source])
            alias = root / 'checkout/licenses/alias.txt'
            alias.symlink_to(debug)
            with self.assertRaisesRegex(ValueError, 'Preserving publication symlink'):
                publish_file(release, alias)
            self.assertTrue(alias.is_symlink())
            self.assertEqual(debug.read_text(), 'Debug license bytes')

    def test_publication_copies_products_without_changing_compiler_cache(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            compiler, checkout = root / 'compiler-cache', root / 'checkout/artifacts'
            compiler.mkdir()
            source = compiler / 'product'
            source.write_text('compiled bytes')
            source.chmod(0o444)
            publish_tree(compiler, checkout)
            self.assertEqual(source.stat().st_mode & 0o777, 0o444)
            self.assertEqual((checkout / 'product').stat().st_mode & 0o777, 0o644)
            self.assertEqual((checkout / 'product').read_text(), 'compiled bytes')
            other = root / 'other-checkout/artifacts'
            other.parent.mkdir()
            other.symlink_to(checkout, target_is_directory=True)
            with self.assertRaisesRegex(ValueError, 'Preserving publication symlink'):
                publish_tree(compiler, other)
            self.assertEqual((checkout / 'product').read_text(), 'compiled bytes')

    def test_traversal_and_symlink_archive_members_fail_before_extraction(self):
        for name, mode, content in [('..\\outside', 0, b'file'), ('../outside', 0, b'file'), ('/outside', 0, b'file'), ('framework/link', 0o120777, b'../../outside')]:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                archive = root / 'compiled.zip'
                with zipfile.ZipFile(archive, 'w') as compressed:
                    entry = zipfile.ZipInfo(name)
                    entry.external_attr = mode << 16
                    compressed.writestr(entry, content)
                with self.assertRaises(ValueError):
                    extract_archive(archive, root / 'staged')
                self.assertFalse((root / 'staged').exists())

@unittest.skipUnless(sys.platform == 'darwin', 'Apple Mach-O oracle requires Xcode')
class MachOPlatformTests(unittest.TestCase):
    def test_actual_universal_binary_must_match_the_declared_architectures(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'fixture.c'
            source.write_text('int architecture_fixture(void) { return 42; }\n')
            objects = []
            for architecture in ('arm64', 'x86_64'):
                binary = root / (architecture + '.o')
                subprocess.run(['xcrun', 'clang', '-target', architecture + '-apple-ios15.0-simulator',
                                '-c', str(source), '-o', str(binary)], check=True, capture_output=True)
                objects.append(binary)
            universal = root / 'universal.o'
            subprocess.run(['xcrun', 'lipo', '-create', *map(str, objects), '-output', str(universal)],
                           check=True, capture_output=True)
            verify_binary_architectures(universal, ['arm64', 'x86_64'])
            verify_binary_architectures(objects[0], ['arm64'])
            with self.assertRaisesRegex(ValueError, 'has architectures'):
                verify_binary_architectures(universal, ['arm64'])
            with self.assertRaisesRegex(ValueError, 'has architectures'):
                verify_binary_architectures(objects[0], ['arm64', 'x86_64'])

    def test_device_simulator_and_host_objects_and_archives_have_distinct_platforms(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'fixture.c'
            source.write_text('int platform_fixture(void) { return 42; }\n')
            for sdk_platform, target in (('ios-device', 'arm64-apple-ios15.0'),
                                         ('ios-simulator', 'arm64-apple-ios15.0-simulator'),
                                         ('macos', 'arm64-apple-macosx12.0')):
                with self.subTest(platform=sdk_platform):
                    binary = root / (sdk_platform + '.o')
                    subprocess.run(['xcrun', 'clang', '-target', target, '-c', str(source), '-o', str(binary)], check=True, capture_output=True)
                    archive = root / (sdk_platform + '.a')
                    subprocess.run(['xcrun', 'libtool', '-static', '-o', str(archive), str(binary)], check=True, capture_output=True)
                    for product in (binary, archive):
                        verify_binary_platform(product, sdk_platform, 'arm64')
                        other = 'ios-simulator' if sdk_platform == 'ios-device' else 'ios-device'
                        with self.assertRaisesRegex(ValueError, 'Mach-O platforms'):
                            verify_binary_platform(product, other, 'arm64')


class SimulatorRunnerTests(unittest.TestCase):
    def test_exact_caller_lease_is_used_instead_of_its_custom_name(self):
        devices = {'devices': {'com.apple.CoreSimulator.SimRuntime.iOS-27-0': [
            {'udid': 'caller-owned-id', 'name': 'An arbitrary worktree lease name'}]}}
        with patch.dict(os.environ, {'NUXIE_IOS_SIMULATOR_ID': 'caller-owned-id'}), \
             patch.object(sdk.subprocess, 'check_output', return_value=json.dumps(devices)):
            self.assertEqual(sdk.simulator_flags(), ['--test_arg=--destination=platform=ios_simulator,id=caller-owned-id'])

    def test_other_platform_or_unsupported_ios_runtime_is_rejected(self):
        for runtime in ('com.apple.CoreSimulator.SimRuntime.tvOS-27-0', 'com.apple.CoreSimulator.SimRuntime.iOS-14-0'):
            with self.subTest(runtime=runtime), patch.dict(os.environ, {'NUXIE_IOS_SIMULATOR_ID': 'selected'}), \
                 patch.object(sdk.subprocess, 'check_output', return_value=json.dumps({'devices': {runtime: [{'udid': 'selected', 'name': 'test'}]}})), \
                 self.assertRaisesRegex(ValueError, 'must run iOS'):
                sdk.simulator_flags()


if __name__ == '__main__':
    unittest.main()
