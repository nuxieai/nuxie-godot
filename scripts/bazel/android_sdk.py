"""Expose the installed SDK through an isolated view with integer API aliases."""
import os
from pathlib import Path
import re


def sdk_view(root, sdk=None, api=37):
    selected = sdk or os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT')
    if not selected:
        raise ValueError('Set ANDROID_HOME to the installed Android SDK')
    source = Path(selected).resolve()
    platform = source / 'platforms' / ('android-' + str(api))
    if not platform.is_dir():
        platform = source / 'platforms' / ('android-' + str(api) + '.0')
    if not (platform / 'android.jar').is_file():
        raise ValueError('The installed Android SDK needs platform API' + str(api))
    properties = (platform / 'source.properties').read_text()
    match = re.search(r'^AndroidVersion.ApiLevel=(.+)$', properties, re.M)
    if not match or match.group(1).strip() not in (str(api), str(api) + '.0'):
        raise ValueError('Installed Android platform identity differs from API' + str(api))
    view = Path(root).resolve() / '.build/android-sdk'
    if view.is_symlink():
        raise ValueError('Preserving modified SDK view: ' + str(view))
    view.mkdir(parents=True, exist_ok=True)
    def link(path, target):
        if path.is_symlink():
            if path.resolve() == target.resolve():
                return
            path.unlink()
        elif path.exists():
            raise ValueError('Preserving modified SDK view: ' + str(path))
        path.symlink_to(target, target_is_directory=target.is_dir())
    for entry in source.iterdir():
        if entry.name != 'platforms':
            link(view / entry.name, entry)
    platforms = view / 'platforms'
    if platforms.is_symlink():
        raise ValueError('Preserving modified SDK view: ' + str(platforms))
    platforms.mkdir(exist_ok=True)
    for entry in (source / 'platforms').iterdir():
        link(platforms / entry.name, entry)
    link(platforms / ('android-' + str(api)), platform)
    return view
