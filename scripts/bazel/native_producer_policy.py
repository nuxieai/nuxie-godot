"""Consume fixed root-issued native frontend qualifications; never issue one."""
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess
import sys

TRUST_OWNER = 0
TRUST_ROOT = Path('/')
POLICY_PATHS = {
    'linux': Path('/etc/nuxie/buildkite-native-producer-qualifications.json'),
    'darwin': Path('/Library/NuxieBuildkite/native-producer-qualifications.json'),
}
MAX_RECEIPT_BYTES = 512 * 1024
MAX_SOURCE_BYTES = 128 * 1024 * 1024
MAX_FRONTEND_FILES = 1024
REPOSITORIES = {'ios': 'https://github.com/nuxieai/nuxie-ios.git', 'android': 'https://github.com/nuxieai/nuxie-android.git'}
CONTEXTS = {'linux': ('linux', 'linux-native', 'linux-14g-v2'), 'darwin': ('macos', 'macos-apple', 'mac-64g-v2')}
CONTROL_NAMES = {'BUILD', 'MODULE', 'WORKSPACE', 'WORKSPACE.bazel', 'MODULE.bazel.lock', '.bazelrc', '.bazelversion', '.bazel-cache.bazelrc', '.bazel-cache.local.bazelrc',
                 'Cargo.toml', 'Cargo.lock', 'Makefile', 'Package.swift', 'Package.resolved', 'project.yml', 'project.yaml',
                 'CMakeLists.txt', 'gradlew', 'gradlew.bat', 'gradle.properties', 'gradle-wrapper.properties',
                 'gradle-wrapper.jar', 'libs.versions.toml', 'build.gradle', 'build.gradle.kts', 'settings.gradle',
                 'settings.gradle.kts', 'project.pbxproj', 'contents.xcworkspacedata', 'NATIVE-PINS.json',
                 'artifact.json', 'artifact-set.json', 'android-toolchain.properties', 'Gemfile', 'Gemfile.lock', 'Podfile', 'Podfile.lock'}


def unique_object(pairs):
    value = {}
    for key, item in pairs:
        if key in value:
            raise ValueError('Duplicate native qualification JSON field')
        value[key] = item
    return value


def identity(metadata):
    return metadata.st_dev, metadata.st_ino, metadata.st_mode, metadata.st_uid, metadata.st_size, metadata.st_mtime_ns, metadata.st_ctime_ns


def protected_chain(path):
    if not path.is_absolute() or not path.is_relative_to(TRUST_ROOT):
        raise ValueError('Native qualification must use its fixed protected host path')
    records = []
    current = path
    while True:
        metadata = current.lstat()
        if metadata.st_uid != TRUST_OWNER or metadata.st_mode & 0o022 or stat.S_ISLNK(metadata.st_mode):
            raise ValueError('Native qualification path must be root-controlled without symlinks')
        if current == path:
            if not stat.S_ISREG(metadata.st_mode) or metadata.st_size > MAX_RECEIPT_BYTES:
                raise ValueError('Native qualification must be bounded regular JSON')
        elif not stat.S_ISDIR(metadata.st_mode):
            raise ValueError('Native qualification ancestry must contain only directories')
        records.append((current, identity(metadata)))
        if current == TRUST_ROOT:
            return records
        current = current.parent


def qualification(sdk, pin):
    if sys.platform not in CONTEXTS or pin.get('repository') != REPOSITORIES.get(sdk) or not re.fullmatch(r'[0-9a-f]{40}', pin.get('revision', '')):
        raise ValueError('Unsupported native producer repository, revision or host')
    context = CONTEXTS[sys.platform]
    if os.environ.get('NUXIE_CI_RUNNER_PROFILE') != context[1]:
        raise ValueError('Native producer requires the admitted native builder profile')
    path = POLICY_PATHS[sys.platform]
    try:
        before = protected_chain(path)
        descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
        with os.fdopen(descriptor, 'rb') as source:
            if identity(os.fstat(source.fileno())) != before[0][1]:
                raise ValueError('Native qualification changed before reading')
            encoded = source.read(MAX_RECEIPT_BYTES + 1)
            if len(encoded) > MAX_RECEIPT_BYTES or identity(os.fstat(source.fileno())) != before[0][1]:
                raise ValueError('Native qualification changed or exceeds its bound')
        if protected_chain(path) != before:
            raise ValueError('Native qualification path changed during reading')
    except OSError as error:
        raise ValueError('Missing or unsafe root-issued native producer qualification') from error
    value = json.loads(encoded, object_pairs_hook=unique_object)
    if not isinstance(value, dict) or set(value) != {'schema', 'policyVersion', 'qualifications'} or value['schema'] != 'nuxie-native-producer-qualifications.v1' or type(value['policyVersion']) is not int or value['policyVersion'] != 2:
        raise ValueError('Unsupported native producer qualification schema')
    entries = value['qualifications']
    if not isinstance(entries, list) or len(entries) > 64:
        raise ValueError('Native qualifications must be a bounded list')
    matches = []
    keys = {'repository', 'revision', 'frontend', 'platform', 'profile', 'capability', 'qualificationId', 'qualifiedAt'}
    for entry in entries:
        if not isinstance(entry, dict) or set(entry) != keys:
            raise ValueError('Invalid native producer qualification fields')
        if entry['repository'] not in REPOSITORIES.values() or not isinstance(entry['revision'], str) or not re.fullmatch(r'[0-9a-f]{40}', entry['revision']):
            raise ValueError('Invalid native producer identity')
        if (entry['platform'], entry['profile'], entry['capability']) not in CONTEXTS.values():
            raise ValueError('Invalid native producer runner qualification')
        if not isinstance(entry['qualificationId'], str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{0,127}', entry['qualificationId']):
            raise ValueError('Invalid native qualification identity')
        if not isinstance(entry['qualifiedAt'], str) or not re.fullmatch(r'\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ', entry['qualifiedAt']):
            raise ValueError('Invalid native qualification time')
        qualified_at = datetime.fromisoformat(entry['qualifiedAt'].replace('Z', '+00:00'))
        if qualified_at > datetime.now(timezone.utc):
            raise ValueError('Native qualification time is in the future')
        frontend = entry['frontend']
        if not isinstance(frontend, dict) or not frontend or len(frontend) > MAX_FRONTEND_FILES:
            raise ValueError('Native frontend inventory must be bounded and nonempty')
        for name, digest in frontend.items():
            relative(name)
            if not isinstance(digest, str) or not re.fullmatch(r'[0-9a-f]{64}', digest):
                raise ValueError('Invalid native frontend digest')
        if entry['repository'] == pin['repository'] and entry['revision'] == pin['revision'] and (entry['platform'], entry['profile'], entry['capability']) == context:
            matches.append(entry)
    if len(matches) != 1:
        raise ValueError('No unique root-issued qualification matches this exact native producer and runner')
    return dict(matches[0], receiptSha256=hashlib.sha256(encoded).hexdigest())


def relative(value):
    if not isinstance(value, str) or any(character in value for character in '\0\r\n\\'):
        raise ValueError('Invalid native frontend path')
    path = PurePosixPath(value)
    if path.is_absolute() or '..' in path.parts or path.as_posix() != value or value in ('', '.') or len(value) > 4096:
        raise ValueError('Native frontend paths must be canonical relative paths')
    return value


def control(path, mode='100644'):
    value = PurePosixPath(path)
    return value.parts[0] in ('scripts', 'bazel', 'tools', 'gradle') or value.suffix in ('.py', '.sh', '.bzl', '.bazel', '.cmake') or value.name in CONTROL_NAMES or mode == '100755'


def git(source, *arguments):
    result = subprocess.run(['git', '--no-replace-objects', *arguments], cwd=source, check=True, capture_output=True, timeout=30)
    if len(result.stdout) > MAX_SOURCE_BYTES:
        raise ValueError('Native frontend Git inventory exceeds its bound')
    return result.stdout


def verify(source, sdk, pin, approval=None):
    approval = qualification(sdk, pin) if approval is None else approval
    source = Path(source)
    if source.is_symlink() or not source.is_dir():
        raise ValueError('Native producer source must be its own directory')
    if git(source, 'rev-parse', 'HEAD').decode().strip() != pin['revision'] or git(source, 'status', '--porcelain', '--untracked-files=no').strip():
        raise ValueError('Native producer source differs from its clean qualified Git revision')
    tracked = {}
    for record in git(source, 'ls-files', '--stage', '-z').decode().split('\0'):
        if not record:
            continue
        metadata, name = record.split('\t', 1)
        mode, blob, stage = metadata.split(' ')
        relative(name)
        if stage != '0' or name in tracked:
            raise ValueError('Native producer index must contain unique unconflicted paths')
        tracked[name] = (mode, blob)
    required = {name for name, (mode, _) in tracked.items() if control(name, mode)}
    frontend = approval['frontend']
    if not required.issubset(frontend) or not set(frontend).issubset(tracked) or 'scripts/bazel/sdk.py' not in frontend:
        raise ValueError('Native qualification must cover the complete concrete frontend/control inventory')
    for name in git(source, 'ls-files', '--others', '-z').decode().split('\0'):
        # The approved cache.py regenerates this exact dynamic rc before Bazel.
        # Every other untracked control, including ignored Python bytecode, fails.
        if not name:
            continue
        relative(name)
        parts = PurePosixPath(name).parts
        if name == '.bazel-cache.local.bazelrc':
            metadata = (source / name).lstat()
            if not stat.S_ISREG(metadata.st_mode) or metadata.st_size > 65536:
                raise ValueError('Generated native cache rc must be bounded regular data')
            continue
        if parts[0] in ('scripts', 'bazel', 'tools', 'gradle') or len(parts) == 1 and control(name) or parts[0] == 'runtime' and control(name):
            raise ValueError('Untracked native executing frontend/control input')
    total = 0
    for name, approved_digest in frontend.items():
        if tracked[name][0] not in ('100644', '100755'):
            raise ValueError('Native frontend inventory may contain only regular tracked files')
        path = source / name
        for component in [path, *path.parents]:
            if component == source:
                break
            if component.is_symlink():
                raise ValueError('Native frontend may not traverse symlinks')
        before = path.lstat()
        if not stat.S_ISREG(before.st_mode):
            raise ValueError('Native frontend must be a regular file')
        total += before.st_size
        if total > MAX_SOURCE_BYTES:
            raise ValueError('Native frontend exceeds its source size budget')
        digest = hashlib.sha256()
        with path.open('rb') as content:
            for block in iter(lambda: content.read(1024 * 1024), b''):
                digest.update(block)
        if identity(path.lstat()) != identity(before) or digest.hexdigest() != approved_digest:
            raise ValueError('Native frontend bytes differ from their qualified digest')
        if int(git(source, 'cat-file', '-s', tracked[name][1])) != before.st_size:
            raise ValueError('Native frontend differs from its Git blob size')
        if hashlib.sha256(git(source, 'cat-file', 'blob', tracked[name][1])).hexdigest() != approved_digest:
            raise ValueError('Native frontend qualification must match exact Git bytes')
    return approval
