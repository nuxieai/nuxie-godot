"""Exercise the real build script against supported Xcode archive layouts."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

FAKE_TOOL = r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
import shutil
name = Path(sys.argv[0]).name
args = sys.argv[1:]
def value(flag): return args[args.index(flag) + 1]
if name == 'scons':
    pass
elif name == 'ditto':
    shutil.copytree(args[0], args[1], dirs_exist_ok=True)
elif name == 'xcrun':
    if '--show-sdk-path' in args:
        print(os.environ['FAKE_SDK'])
    elif '-verify_arch' in args:
        actual = json.loads(Path(args[1]).read_text())
        assert set(args[args.index('-verify_arch') + 1:]) <= set(actual), actual
    else:
        output = value('-o' if '-o' in args else '-output')
        if 'clang++' in args:
            architectures = [value('-arch')]
        else:
            architectures = sorted({arch for arg in args if arg.endswith(('.o', '.a')) and arg != output
                                    for arch in json.loads(Path(arg).read_text())})
        Path(output).write_text(json.dumps(architectures))
elif args[0] == 'archive':
    archive = Path(value('-archivePath'))
    simulator = archive.name.endswith('-simulator.xcarchive')
    layout = os.environ['SIMULATOR_LAYOUT' if simulator else 'DEVICE_LAYOUT']
    framework = archive / 'Products' / layout / 'NuxieGodotBridge.framework'
    framework.mkdir(parents=True)
    architectures = next(arg.removeprefix('ARCHS=') for arg in args if arg.startswith('ARCHS=')).split()
    (framework / 'NuxieGodotBridge').write_text(json.dumps(architectures))
    sdk = 'iphonesimulator' if simulator else 'iphoneos'
    bundle = Path(value('-derivedDataPath')) / 'Build/Intermediates.noindex/ArchiveIntermediates/NuxieGodotBridge/IntermediateBuildFilesPath/UninstalledProducts' / sdk / 'Nuxie_Nuxie.bundle'
    bundle.mkdir(parents=True, exist_ok=True)
    (bundle / 'fixture.txt').write_text('resources')
else:
    assert args[0] == '-create-xcframework'
    for i, arg in enumerate(args):
        if arg == '-framework':
            framework = Path(args[i + 1])
            assert framework.is_dir(), framework
            assert (framework / 'Nuxie_Nuxie.bundle/fixture.txt').read_text() == 'resources'
            expected = {'arm64', 'x86_64'} if '-simulator' in str(framework) else {'arm64'}
            assert set(json.loads((framework / 'NuxieGodotBridge').read_text())) == expected
        elif arg == '-library':
            library = Path(args[i + 1])
            expected = {'arm64', 'x86_64'} if '-simulator' in str(library) else {'arm64'}
            assert set(json.loads(library.read_text())) == expected
    Path(value('-output')).mkdir()
'''


class XCFrameworkBuildTests(unittest.TestCase):
    def test_archive_layouts_preserve_resources_and_required_architectures(self):
        for device, simulator in [
            ('usr/local/lib', 'Library/Frameworks'),
            ('Library/Frameworks', 'usr/local/lib'),
        ]:
            with self.subTest(device=device, simulator=simulator), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                scripts = root / 'ios-plugin/scripts'
                scripts.mkdir(parents=True)
                shutil.copy2(ROOT / 'ios-plugin/scripts/build_xcframework.sh', scripts)
                pin = json.loads((ROOT / 'NATIVE-PINS.json').read_text())['godot']
                (root / 'NATIVE-PINS.json').write_text(json.dumps({'godot': pin}))
                engine = root / 'engine'
                engine.mkdir()
                (engine / 'version.py').write_text('\n'.join(
                    f'{name} = {value}' for name, value in zip(('major', 'minor', 'patch'), pin.split('.'))
                ))
                binaries = root / 'bin'
                binaries.mkdir()
                for name in ('scons', 'xcodebuild', 'xcrun', 'ditto'):
                    tool = binaries / name
                    tool.write_text(FAKE_TOOL)
                    tool.chmod(0o755)
                result = subprocess.run(
                    ['bash', str(scripts / 'build_xcframework.sh')],
                    env={**os.environ, 'PATH': str(binaries) + os.pathsep + os.environ['PATH'],
                         'GODOT_SOURCE_DIR': str(engine), 'SCONS_BIN': str(binaries / 'scons'),
                         'FAKE_SDK': str(root), 'DEVICE_LAYOUT': device, 'SIMULATOR_LAYOUT': simulator},
                    capture_output=True, text=True,
                )
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                for variant in ('debug', 'release'):
                    for artifact in ('NuxieGodotBridge', 'nuxie_godot_plugin'):
                        self.assertTrue((root / 'ios-plugin/.build/xcframework' / f'{artifact}.{variant}.xcframework').is_dir())


if __name__ == '__main__':
    unittest.main()
