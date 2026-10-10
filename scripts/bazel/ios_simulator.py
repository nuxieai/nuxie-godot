#!/usr/bin/env python3
"""Run a command with a caller's simulator or a private, temporary iOS lease."""

import argparse
import json
import os
import re
import signal
import subprocess
import sys
import time
import uuid


def version(value):
    return tuple(int(part) for part in value.split('.')) + (0,) * (3 - len(value.split('.')))


def selection(devices, minimum_os):
    candidates = []
    for runtime in devices.get('runtimes', []):
        if not runtime.get('isAvailable') or '.iOS-' not in runtime['identifier']:
            continue
        if version(runtime['version']) < version(minimum_os):
            continue
        for device in runtime.get('supportedDeviceTypes', []):
            if device.get('productFamily') == 'iPhone' and device['name'].startswith('iPhone '):
                natural_name = tuple((1, int(part)) if part.isdigit() else (0, part)
                                     for part in re.split(r'(\d+)', device['name']))
                candidates.append((version(runtime['version']), natural_name, runtime['identifier'], device['identifier']))
    if not candidates:
        raise ValueError('Install an available iOS ' + minimum_os + '+ simulator runtime with an iPhone device type')
    selected = max(candidates)
    return selected[2], selected[3]


def simctl(*arguments):
    return subprocess.check_output(['xcrun', 'simctl', *arguments], text=True, timeout=120).strip()


def run(command, minimum_os='15.0'):
    environment = dict(os.environ)
    owned = None
    child = None
    previous = {}
    terminated = None

    def terminate(signum, _frame):
        nonlocal terminated
        if child is None:
            raise SystemExit(128 + signum)
        terminated = (signum, time.monotonic())
        try:
            os.killpg(child.pid, signum)
        except ProcessLookupError:
            pass

    try:
        for signum in (signal.SIGTERM, signal.SIGINT):
            previous[signum] = signal.signal(signum, terminate)
        if not environment.get('NUXIE_IOS_SIMULATOR_ID'):
            runtime, device = selection(json.loads(simctl('list', '--json')), minimum_os)
            owned = simctl('create', 'Nuxie-Bazel-' + uuid.uuid4().hex, device, runtime)
            # simctl emits a UUID only after it successfully creates this device.
            uuid.UUID(owned)
            environment['NUXIE_IOS_SIMULATOR_ID'] = owned
            simctl('bootstatus', owned, '-b')
        child = subprocess.Popen(command, env=environment, start_new_session=True)
        while True:
            try:
                status = child.wait(timeout=0.25)
                return 128 + terminated[0] if terminated else status
            except subprocess.TimeoutExpired:
                if terminated and time.monotonic() - terminated[1] > 10:
                    os.killpg(child.pid, signal.SIGKILL)
    finally:
        for signum, handler in previous.items():
            signal.signal(signum, handler)
        if owned is not None:
            # Shutdown may report an already-stopped device. Deletion is still required.
            try:
                subprocess.run(['xcrun', 'simctl', 'shutdown', owned], check=False, timeout=30,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            finally:
                subprocess.run(['xcrun', 'simctl', 'delete', owned], check=True, timeout=30)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--minimum-os', default='15.0')
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not command:
        parser.error('Supply a command after --')
    return run(command, args.minimum_os)


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
