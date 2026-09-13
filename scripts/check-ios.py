#!/usr/bin/env python3
from pathlib import Path
import json
import subprocess

root = Path(__file__).resolve().parent.parent
project = root / '.native/ios-tests'
project.mkdir(parents=True, exist_ok=True)
pin = json.loads((root / 'NATIVE-PINS.json').read_text())['ios']
config = {'name': 'GodotBridgeTests', 'options': {'deploymentTarget': {'iOS': '15.0'}},
 'packages': {'Nuxie': {'url': pin['repository'], 'revision': pin['revision']}},
 'targets': {
  'NuxieGodotBridge': {'type': 'framework', 'platform': 'iOS', 'sources': [str(root / 'ios-plugin/Sources/NuxieGodotBridge')], 'dependencies': [{'package': 'Nuxie'}], 'settings': {'base': {'PRODUCT_BUNDLE_IDENTIFIER': 'ai.nuxie.godot.bridge', 'GENERATE_INFOPLIST_FILE': 'YES', 'SWIFT_VERSION': '5.0'}}},
  'BridgeTests': {'type': 'bundle.unit-test', 'platform': 'iOS', 'sources': [str(root / 'ios-plugin/Tests/NuxieGodotBridgeTests')], 'dependencies': [{'target': 'NuxieGodotBridge'}, {'package': 'Nuxie'}], 'settings': {'base': {'PRODUCT_BUNDLE_IDENTIFIER': 'ai.nuxie.godot.tests', 'GENERATE_INFOPLIST_FILE': 'YES', 'SWIFT_VERSION': '5.0'}}}},
 'schemes': {'BridgeTests': {'build': {'targets': {'NuxieGodotBridge': 'all', 'BridgeTests': ['test']}}, 'test': {'targets': ['BridgeTests']}}}}
(project / 'project.json').write_text(json.dumps(config, indent=2))
subprocess.run(['xcodegen', 'generate', '--spec', 'project.json'], cwd=project, check=True)
devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '--json'], text=True))['devices']
phone = next(device for group in devices.values() for device in group if 'iPhone' in device['name'])
subprocess.run(['xcodebuild', '-project', 'GodotBridgeTests.xcodeproj', '-scheme', 'BridgeTests', '-destination', 'platform=iOS Simulator,id=' + phone['udid'], '-derivedDataPath', 'build', 'test'], cwd=project, check=True)
