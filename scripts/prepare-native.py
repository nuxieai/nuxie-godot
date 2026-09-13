#!/usr/bin/env python3
"""Prepare native inputs from exact pins. Run on macOS with Android/Xcode tooling."""
from pathlib import Path
import json
import os
import subprocess

root = Path(__file__).resolve().parent.parent
pins = json.loads((root / 'NATIVE-PINS.json').read_text())
scratch = root / '.native'
scratch.mkdir(exist_ok=True)
(scratch / '.gdignore').touch()
def run(args, cwd=root, env=None):
    subprocess.run(args, cwd=cwd, env=env, check=True)
def checkout(name, url, revision):
    path = scratch / name
    fresh = not path.exists()
    if fresh:
        run(['git', 'clone', '--no-checkout', url, str(path)])
    if not fresh and subprocess.check_output(['git', 'status', '--porcelain'], cwd=path, text=True).strip():
        raise SystemExit('Preserving modified native input: ' + str(path))
    run(['git', 'fetch', '--depth', '1', 'origin', revision], path)
    run(['git', 'checkout', '--detach', revision], path)
    return path
android = checkout('android', pins['android']['repository'], pins['android']['revision'])
init = scratch / 'publish.gradle'
init.write_text('''allprojects { project ->
  if (project.name == 'nuxie-android') {
    project.pluginManager.withPlugin('com.android.library') {
      project.pluginManager.apply('maven-publish')
      project.android.publishing { singleVariant('release') }
      project.afterEvaluate {
        project.publishing {
          publications { nuxie(MavenPublication) {
            from project.components.release
            groupId = 'ai.nuxie'; artifactId = 'nuxie-android'
            version = '0.2.0-''' + pins['android']['revision'] + ''''
          } }
          repositories { maven { name = 'Package'; url = uri(System.getenv('NUXIE_GODOT_MAVEN')) } }
        }
      }
    }
  }
}
''')
run(['./gradlew', '-I', str(init), ':nuxie-android:publishNuxiePublicationToPackageRepository'], android,
    dict(os.environ, NUXIE_GODOT_MAVEN=str(scratch / 'maven')))
run(['./gradlew', ':android-plugin:assembleDebug', ':android-plugin:assembleRelease'])
godot = checkout('godot', 'https://github.com/godotengine/godot.git', pins['godot'] + '-stable')
run(['bash', 'ios-plugin/scripts/build_xcframework.sh'], env=dict(os.environ, GODOT_SOURCE_DIR=str(godot)))
