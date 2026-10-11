#!/usr/bin/env python3
"""An owned loopback fixture and native simulator log capture for adapter tests."""

from contextlib import contextmanager
from datetime import datetime
import gzip
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import math
from pathlib import Path
import re
import subprocess
import threading
import time
from urllib.parse import parse_qs, urlsplit
import uuid


AUTHENTICATION_FAILURE = re.compile(
    r'\[Nuxie\] (?:\[WARNING\] \[NuxieSDK\.swift:\d+\] Profile fetch failed|'
    r'\[DEBUG\] \[UserTransitionCoordinator\.swift:\d+\] Identity profile refresh failed): '
    r'<redacted:error=JourneyReleaseAuthenticationError hmac-sha256:[0-9a-f]{16}>')
LOG_SUBSYSTEM = 'io.nuxie.wrapper.v3-tests'


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def log_timestamp(row):
    try:
        return datetime.fromisoformat(row['timestamp'].replace('Z', '+00:00')).timestamp()
    except (ValueError, KeyError, TypeError):
        return None


def scoped_log(row, process_id, since):
    timestamp = log_timestamp(row)
    return (row.get('processID') == process_id and timestamp is not None
            and timestamp >= since)


def terminal_authentication_failure(row, process_id, delivered_at):
    return (scoped_log(row, process_id, delivered_at)
            and row.get('subsystem') == 'io.nuxie.sdk'
            and row.get('category') == 'NuxieSDK'
            and AUTHENTICATION_FAILURE.search(row.get('eventMessage', '')) is not None)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def typed_equal(actual, expected):
    if type(expected) in (int, float):
        return type(actual) in (int, float) and actual == expected
    if isinstance(expected, dict):
        return (isinstance(actual, dict) and actual.keys() == expected.keys()
                and all(typed_equal(actual[key], value) for key, value in expected.items()))
    if isinstance(expected, list):
        return (isinstance(actual, list) and len(actual) == len(expected)
                and all(typed_equal(left, right) for left, right in zip(actual, expected)))
    return type(actual) is type(expected) and actual == expected


def json_integer(value):
    return type(value) is int or (type(value) is float and math.isfinite(value) and value == int(value))


class NativeV3Fixture:
    """Serve original signed bytes; observations never replace native behavior."""

    def __init__(self, root, fixture_directory, output, native_log):
        self.root = Path(root)
        self.output = Path(output)
        self.native_log = Path(native_log)
        directory = Path(fixture_directory)
        manifest_bytes = (directory / 'manifest.json').read_bytes()
        self.manifest = json.loads(manifest_bytes)
        pins = json.loads((self.root / 'NATIVE-PINS.json').read_bytes())
        for platform, key in [('ios', 'nativeIOSRevision'), ('android', 'nativeAndroidRevision')]:
            if self.manifest[key] != pins[platform]['revision']:
                raise ValueError('Fixture native source differs from NATIVE-PINS.json')
        self.profiles = {}
        for row in self.manifest['cases']:
            body = (directory / row['file']).read_bytes()
            if sha256(body) != row['sha256']:
                raise ValueError('Signed fixture bytes differ from the manifest')
            self.profiles[row['name']] = body
        self.lock = threading.RLock()
        self.ledger = {'nativePins': pins, 'manifestSha256': sha256(manifest_bytes),
                       'cases': [], 'requests': [], 'violations': []}
        self.active = None
        self.log_process = None

    def save(self):
        temporary = self.output / 'ledger.tmp'
        temporary.write_text(json.dumps(self.ledger, indent=2) + '\n')
        temporary.replace(self.output / 'ledger.json')

    def logs(self):
        rows = []
        for line in self.native_log.read_text(errors='replace').splitlines():
            try:
                row = json.loads(line)
            except ValueError:
                continue
            if isinstance(row, dict):
                rows.append(row)
        return rows

    def register(self, body):
        if self.active is not None:
            raise ValueError('Finish native shutdown before registering another vector')
        vector, api_key, process_id = body['vector'], body['apiKey'], body['processId']
        customer = body['customerId']
        if vector not in self.profiles or not isinstance(api_key, str) or not api_key.startswith('pk_test_wrapper_'):
            raise ValueError('Unknown signed vector or case API key')
        if type(process_id) is not int or process_id <= 0:
            raise ValueError('The native XCTest PID is required')
        if not isinstance(customer, str) or not customer.startswith('wrapper-v3-'):
            raise ValueError('The fresh identified native customer is required')
        if any(case['apiKey'] == api_key for case in self.ledger['cases']):
            raise ValueError('Every vector must use a fresh API key')
        case = {'vector': vector, 'apiKey': api_key, 'processId': process_id, 'customerId': customer,
                'registeredAt': time.time(), 'profileSha256': sha256(self.profiles[vector]),
                'profiles': [], 'events': [], 'finishedAt': None, 'teardownCompleted': False}
        self.ledger['cases'].append(case)
        self.active = case
        self.save()
        return {'profileSha256': case['profileSha256']}

    def snapshot(self, api_key):
        case = next(case for case in self.ledger['cases'] if case['apiKey'] == api_key)
        rows = self.logs()
        ready = [row for row in rows if scoped_log(row, case['processId'], case['registeredAt'])
                 and row.get('subsystem') == LOG_SUBSYSTEM
                 and row.get('category') == 'NativeV3Tests'
                 and row.get('eventMessage') == 'NATIVE_V3_LOG_READY ' + api_key]
        delivered_at = min((row['responseCompletedAt'] for row in case['profiles']
                            if row['body']['distinct_id'] == case['customerId']
                            and 'responseCompletedAt' in row), default=None)
        failures = [row for row in rows if delivered_at is not None
                    and terminal_authentication_failure(row, case['processId'], delivered_at)
                    and (case['finishedAt'] is None or log_timestamp(row) <= case['finishedAt'])]
        if self.log_process is not None and self.log_process.poll() is not None:
            raise ValueError('Native simulator log stream exited before the test completed')
        return {'profiles': case['profiles'], 'events': case['events'],
                'violations': self.ledger['violations'], 'logReady': bool(ready),
                'authenticationFailures': failures}

    def verify(self):
        """Check native delivery and public adapter observations after teardown."""
        require(not self.ledger['violations'], 'Fixture transport violations were recorded')
        require(self.active is None, 'An adapter session did not finish')
        cases = self.ledger['cases']
        require(len(cases) == 4 and {case['vector'] for case in cases} == set(self.profiles),
                'Every signed vector must execute exactly once; cached tests do not qualify')
        verdicts = []
        for case in cases:
            vector = next(row for row in self.manifest['cases'] if row['name'] == case['vector'])
            require(case['teardownCompleted'] is True and case['failure'] is None,
                    'Native adapter test or shutdown failed: ' + str(case.get('failure')))
            snapshot = self.snapshot(case['apiKey'])
            require(snapshot['logReady'], 'External stream never observed this native test process')
            profiles = case['profiles']
            require(len(profiles) >= 2 and any(row['body']['distinct_id'] == case['customerId'] for row in profiles),
                    'Native startup and identified profile delivery must both complete')
            require(all(row['responseSha256'] == vector['sha256'] for row in profiles),
                    'Native profile bytes differ from the independent signed vector')
            events = [row for row in case['events'] if row['distinct_id'] == case['customerId']]
            controls = [row for row in events if row['event'] == 'wrapper_v3_flush_probe']
            indexes = [row.get('properties', {}).get('index') for row in controls]
            require(len(indexes) == 45 and all(json_integer(index) for index in indexes)
                    and set(indexes) == set(range(45)), 'All 45 distinct native transport controls are required')
            require(any(row['event'] == self.manifest['trigger']
                        and all(typed_equal(row.get('properties', {}).get(key), value)
                                for key, value in self.manifest['triggerProperties'].items()) for row in events),
                    'Native trigger typed values differ from the independent fixture')
            observation = case['observation']
            require(isinstance(observation.get('nativeVersion'), str) and observation['nativeVersion'],
                    'Native version must be returned by the actual adapter')
            activities = observation['activities']
            journeys = [row for row in events if row['event'].startswith('$journey_leg_')]
            if vector['verdict'] == 'accepted':
                require(observation['finalFeatureState'] == 'ready', 'Accepted profile is not ready')
                require([row['name'] for row in activities] == self.manifest['expectedActivities'],
                        'Actual adapter Journey activity order/count differs')
                require([row['event'] for row in journeys] == ['$journey_leg_started', '$journey_leg_completed'],
                        'Actual native Journey event order/count differs')
                journey_id = activities[0]['properties']['journey_id']
                uuid.UUID(journey_id)
                expected = self.manifest['expectedProperties']
                for row in activities:
                    require(row['properties']['journey_id'] == journey_id, 'Adapter Journey identity changed')
                    for field in ('experience_id', 'experience_version', 'leg_id', 'leg_generation'):
                        require(typed_equal(row['properties'].get(field), expected[field]),
                                'Actual adapter Journey context differs: ' + field)
                for row in journeys:
                    require(row['properties']['journey_id'] == journey_id, 'Native and adapter Journey identity differs')
                    for field in ('experience_id', 'experience_version', 'leg_id', 'leg_generation'):
                        wire_field = 'experience_version_id' if field == 'experience_version' else field
                        require(typed_equal(row['properties'].get(wire_field), expected[field]),
                                'Actual native Journey context differs: ' + wire_field)
                require(len({row['idempotency_key'] for row in journeys}) == 2, 'Native Journey idempotency keys differ')
                require(activities[-1]['properties'].get('outcome') == expected['outcome']
                        and journeys[-1]['properties'].get('outcome') == expected['outcome'],
                        'Actual native and adapter completion outcomes differ')
                require(typed_equal(journeys[-1]['properties'].get('outputs'), self.manifest['expectedOutputs']),
                        'Actual native typed run outputs differ from the independent projection')
            else:
                require(snapshot['authenticationFailures'], 'Missing actual terminal native authentication error')
                require(observation['finalFeatureState'] == 'unknown', 'Rejected profile published authority')
                require(not activities and not journeys, 'Rejected signed profile admitted a Journey')
            verdicts.append({'vector': case['vector'], 'status': 'PASS', 'profileSha256': vector['sha256'],
                             'nativeControlEvents': len(controls), 'adapterActivities': len(activities),
                             'nativeJourneyEvents': len(journeys), 'teardownCompleted': True,
                             'nativeAuthenticationFailures': snapshot['authenticationFailures'],
                             'authenticationScope': 'terminal-error-category-only',
                             'renderedFormOrLicensedEnginePlayerQualified': False})
        return verdicts

    def handle(self, path, raw, encoding):
        if encoding not in (None, 'gzip'):
            raise ValueError('Unsupported native content encoding')
        decoded = gzip.decompress(raw) if encoding == 'gzip' else raw
        body = json.loads(decoded)
        if not isinstance(body, dict):
            raise ValueError('Expected native JSON object')
        if path == '/v3/register':
            return 200, self.register(body), {}
        api_key = body.get('apiKey')
        case = self.active
        if case is None or api_key != case['apiKey']:
            raise ValueError('Native request must carry the active fresh case API key')
        request = {'path': path, 'apiKey': api_key, 'receivedAt': time.time(),
                   'wireSha256': sha256(raw), 'decodedSha256': sha256(decoded),
                   'contentEncoding': encoding, 'body': body}
        if path == '/profile':
            if not isinstance(body.get('distinct_id'), str) or not body['distinct_id']:
                raise ValueError('Native profile must encode distinct_id')
            response = self.profiles[case['vector']]
            headers = dict(self.manifest['authorityHeaders'], ETag='"' + sha256(response) + '"')
            delivered = dict(request, responsePreparedAt=time.time(), responseSha256=sha256(response),
                             responseHeaders=headers)
            case['profiles'].append(delivered)
            request.update(responseSha256=sha256(response), responseHeaders=headers)
        elif path in ('/batch', '/event'):
            events = body.get('batch') if path == '/batch' else [body]
            if not isinstance(events, list) or not events or not all(
                    isinstance(event, dict) and all(isinstance(event.get(key), str) and event[key]
                    for key in ('event', 'distinct_id', 'idempotency_key')) for event in events):
                raise ValueError('Native event transport must carry event, distinct_id and idempotency_key')
            case['events'].extend(events)
            response = {'status': 'ok', 'processed': len(events), 'failed': 0, 'total': len(events)}
            headers = {}
        elif path == '/v3/finish':
            if type(body['teardownCompleted']) is not bool:
                raise ValueError('Report an explicit Boolean native teardown result')
            case.update(finishedAt=time.time(), teardownCompleted=body['teardownCompleted'],
                        observation=body.get('observation'), failure=body.get('failure'))
            self.active = None
            response, headers = {'status': 'retained'}, {}
        else:
            raise ValueError('Unexpected native API route: ' + path)
        self.ledger['requests'].append(request)
        self.save()
        return 200, response, headers

    def server(self):
        fixture = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *unused):
                pass

            def answer(self, status, body, headers=None):
                data = body if isinstance(body, bytes) else json.dumps(body).encode()
                self.send_response(status)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Content-Length', str(len(data)))
                for key, value in (headers or {}).items():
                    self.send_header(key, value)
                self.end_headers()
                self.wfile.write(data)
                self.wfile.flush()

            def do_GET(self):
                with fixture.lock:
                    try:
                        url = urlsplit(self.path)
                        if url.path != '/v3/status':
                            raise ValueError('Unknown fixture observation route')
                        self.answer(200, fixture.snapshot(parse_qs(url.query)['apiKey'][0]))
                    except (ValueError, KeyError, StopIteration) as error:
                        self.answer(400, {'error': str(error)})

            def do_POST(self):
                with fixture.lock:
                    try:
                        raw = self.rfile.read(int(self.headers.get('Content-Length', '0')))
                        status, body, headers = fixture.handle(urlsplit(self.path).path, raw,
                                                              self.headers.get('Content-Encoding'))
                        self.answer(status, body, headers)
                        if urlsplit(self.path).path == '/profile' and status == 200:
                            # Request receipt/preparation cannot fence authentication:
                            # bind native event time to the complete200 response write.
                            completed = time.time()
                            fixture.active['profiles'][-1]['responseCompletedAt'] = completed
                            fixture.ledger['requests'][-1]['responseCompletedAt'] = completed
                            fixture.save()
                    except (ValueError, KeyError, OSError, EOFError) as error:
                        fixture.ledger['violations'].append(str(error))
                        fixture.save()
                        self.answer(400, {'error': str(error)})

        return ThreadingHTTPServer(('127.0.0.1', 0), Handler)


@contextmanager
def native_v3_fixture(root, sdk, fixture_directory, simulator_id, artifact_manifest=None):
    """Keep private evidence after failure; terminate only this fixture's log client."""
    root = Path(root)
    output = root / '.native/test-evidence/ios-v3' / uuid.uuid4().hex
    output.mkdir(parents=True, exist_ok=False)
    native_log = output / 'native-log.ndjson'
    stderr = output / 'native-log.stderr'
    with native_log.open('w') as log_output, stderr.open('w') as log_error:
        fixture = NativeV3Fixture(root, fixture_directory, output, native_log)
        retained = output / 'fixtures'
        retained.mkdir()
        for name in ['manifest.json', *(row['file'] for row in fixture.manifest['cases'])]:
            (retained / name).write_bytes((Path(fixture_directory) / name).read_bytes())
        if artifact_manifest is not None:
            receipt = Path(artifact_manifest).read_bytes()
            (output / 'native-ios-sdk-artifacts.json').write_bytes(receipt)
            fixture.ledger.update(nativeArtifactManifest=str(artifact_manifest), nativeArtifactReceiptSha256=sha256(receipt))
        if (root / '.git').exists():
            fixture.ledger['consumerSourceRevision'] = subprocess.check_output(
                ['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
            fixture.ledger['consumerSourceStatus'] = subprocess.check_output(
                ['git', 'status', '--porcelain'], cwd=root, text=True)
        command = ['xcrun', 'simctl', 'spawn', simulator_id, 'log', 'stream', '--style', 'ndjson',
                   '--level', 'debug', '--predicate',
                   'subsystem == "io.nuxie.sdk" OR subsystem == "' + LOG_SUBSYSTEM + '"']
        log_process = server = thread = None
        try:
            log_process = subprocess.Popen(command, stdout=log_output, stderr=log_error)
            fixture.log_process = log_process
            server = fixture.server()
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            endpoint = 'http://127.0.0.1:' + str(server.server_port)
            fixture.ledger.update(endpoint=endpoint, simulatorId=simulator_id, nativeLogCommand=command)
            fixture.save()
            print('Native v3 loopback fixture evidence: ' + str(output), flush=True)
            yield ['--test_env=NUXIE_' + sdk.upper() + '_API_ENDPOINT=' + endpoint,
                   '--test_env=NUXIE_NATIVE_V3_FIXTURE_ENDPOINT=' + endpoint]
            (output / 'verdict.json').write_text(json.dumps(fixture.verify(), indent=2) + '\n')
        finally:
            if server is not None:
                if thread is not None and thread.is_alive():
                    server.shutdown()
                    thread.join(timeout=5)
                server.server_close()
            if log_process is not None:
                log_process.terminate()
                try:
                    log_process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    log_process.kill()
                    log_process.wait(timeout=5)
            fixture.ledger.update(closedAt=time.time(), nativeLogExit=log_process.returncode if log_process else None)
            fixture.save()
