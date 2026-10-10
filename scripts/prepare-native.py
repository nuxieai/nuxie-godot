#!/usr/bin/env python3
"""Stage directly compiled native bridge products for the Godot addon."""
from pathlib import Path
import shutil
import sys
root = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(root / 'scripts/bazel'))
from sdk import android_build, copy_maven, ios_xcframework

(root / '.native').mkdir(exist_ok=True)
(root / '.native/.gdignore').touch()
for configuration in ('Debug', 'Release'):
    artifact, manifest = android_build(configuration)
    copy_maven(manifest, root / '.native/maven')
    destination = root / ('addons/nuxie/android/bin/' + configuration.lower())
    destination.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(artifact, destination / ('NuxieGodot-' + configuration.lower() + '.aar'))
    ios_xcframework(configuration)
