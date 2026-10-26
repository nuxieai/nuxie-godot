#!/usr/bin/env python3
"""Stage selected directly compiled native bridge products for the Godot addon."""
import argparse
from pathlib import Path
import shutil
import sys

from pool import dispatch
status = dispatch('prepare-native', sys.argv[1:])
if status is not None: raise SystemExit(status)

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'scripts/bazel'))
from sdk import android_build, copy_maven, ios_xcframework


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--platform', choices=('all', 'android', 'ios'), default='all')
    selected = parser.parse_args().platform
    (ROOT / '.native').mkdir(exist_ok=True)
    (ROOT / '.native/.gdignore').touch()
    for configuration in ('Debug', 'Release'):
        if selected in ('all', 'android'):
            artifact, manifest = android_build(configuration)
            copy_maven(manifest, ROOT / '.native/maven')
            destination = ROOT / ('addons/nuxie/android/bin/' + configuration.lower())
            destination.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(artifact, destination / ('NuxieGodot-' + configuration.lower() + '.aar'))
        if selected in ('all', 'ios'):
            ios_xcframework(configuration)


if __name__ == '__main__':
    main()
