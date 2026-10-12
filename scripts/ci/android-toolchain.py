#!/usr/bin/env python3
"""Validate the provisioned Linux Java/Android toolchain without changing it."""
import os
from pathlib import Path
import re
import subprocess


def validate(environment=None):
    environment = os.environ if environment is None else environment
    java = Path(environment.get('JAVA_HOME', ''))
    sdk = Path(environment.get('ANDROID_HOME') or environment.get('ANDROID_SDK_ROOT', ''))
    if not java.is_absolute() or not (java / 'bin/java').is_file():
        raise ValueError('Set JAVA_HOME to provisioned Java 21')
    version = subprocess.check_output([java / 'bin/java', '-version'], stderr=subprocess.STDOUT, text=True)
    if not re.search(r'version "21(?:\.|\")', version):
        raise ValueError('The SDK Android bridge requires Java 21')
    if not sdk.is_absolute():
        raise ValueError('Set ANDROID_HOME to the provisioned Android SDK')
    for relative in ('platforms/android-36/android.jar', 'build-tools/36.0.0/aapt2',
                     'ndk/29.0.14206865/source.properties', 'cmake/3.22.1/bin/cmake'):
        if not (sdk / relative).is_file():
            raise ValueError('Missing provisioned Android toolchain input: ' + relative)
    ndk = (sdk / 'ndk/29.0.14206865/source.properties').read_text()
    if not re.search(r'^Pkg.Revision\s*=\s*29\.0\.14206865\s*$', ndk, re.MULTILINE):
        raise ValueError('The provisioned Android NDK identity differs')


if __name__ == '__main__':
    validate()
