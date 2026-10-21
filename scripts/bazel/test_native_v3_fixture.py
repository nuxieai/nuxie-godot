import copy
from datetime import datetime, timezone
import gzip
import hashlib
import json
from pathlib import Path
import tempfile
import threading
import time
import unittest
from unittest import mock
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from native_v3_fixture import NativeV3Fixture, native_v3_fixture, terminal_authentication_failure

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / 'ios-plugin/Tests/NuxieGodotBridgeTests/native-v3'
GOLDEN = Path(__file__).resolve().parent / 'fixtures/native-batch-item-encoding.json'


class FixtureTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.output = Path(self.temporary.name)
        self.log = self.output / 'native-log.ndjson'
        self.log.write_text('')
        self.fixture = NativeV3Fixture(ROOT, FIXTURES, self.output, self.log)
        self.server = self.fixture.server()
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.addCleanup(self.close_server)
        self.endpoint = 'http://127.0.0.1:' + str(self.server.server_port)
        self.key = 'pk_test_wrapper_regression'
        self.post('/v3/register', {'vector': 'accepted', 'apiKey': self.key,
                                  'customerId': 'wrapper-v3-regression', 'processId': 4288})

    def close_server(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=5)

    def post(self, path, body, compressed=False):
        raw = json.dumps(body).encode()
        headers = {'Content-Type': 'application/json'}
        if compressed:
            raw = gzip.compress(raw)
            headers['Content-Encoding'] = 'gzip'
        return urlopen(Request(self.endpoint + path, raw, headers), timeout=3)

    def rejects(self, action):
        with self.assertRaises(HTTPError) as failure:
            action()
        failure.exception.close()

    def test_real_http_native_golden_batch_accepts_gzip_and_snake_case_wire(self):
        # Owning native encoder fixture, rather than an invented server payload.
        provenance = json.loads(GOLDEN.with_name('native-batch-item-provenance.json').read_text())
        self.assertEqual(hashlib.sha256(GOLDEN.read_bytes()).hexdigest(), provenance['sha256'])
        self.assertEqual(provenance['revision'], self.fixture.ledger['nativePins']['ios']['revision'])
        events = [row['expect'] for row in json.loads(GOLDEN.read_text())['vectors']]
        for event in events:
            event.setdefault('properties', {})
        with self.post('/batch', {'apiKey': self.key, 'batch': events}, compressed=True) as response:
            self.assertEqual(json.load(response)['processed'], len(events))
        self.assertEqual(self.fixture.active['events'], events)
        self.assertEqual(self.fixture.ledger['requests'][-1]['contentEncoding'], 'gzip')
        self.assertNotEqual(self.fixture.ledger['requests'][-1]['wireSha256'],
                            self.fixture.ledger['requests'][-1]['decodedSha256'])

    def test_profile_delivers_exact_signed_bytes_authority_and_quoted_validator(self):
        with self.post('/profile', {'apiKey': self.key, 'distinct_id': 'wrapper-v3-regression'}) as response:
            self.assertEqual(response.read(), (FIXTURES / 'accepted.json').read_bytes())
            self.assertEqual(response.headers['Nuxie-App-Id'], 'app_wrapper_v3')
            self.assertEqual(response.headers['Nuxie-App-Environment'], 'test')
            expected_hash = next(case['sha256'] for case in self.fixture.manifest['cases'] if case['name'] == 'accepted')
            self.assertEqual(response.headers['ETag'], '"' + expected_hash + '"')

    def test_wrong_native_wire_and_malformed_gzip_cannot_be_observed_as_delivery(self):
        self.rejects(lambda: self.post('/profile', {'apiKey': self.key, 'distinctId': 'wrapper-v3-regression'}))
        self.rejects(lambda: self.post('/batch', {'apiKey': self.key, 'batch': [{'event': 'probe', 'distinctId': 'x', 'idempotencyKey': 'x'}]}))
        self.rejects(lambda: urlopen(Request(self.endpoint + '/batch', b'broken gzip', {'Content-Encoding': 'gzip'}), timeout=3))
        self.rejects(lambda: urlopen(Request(self.endpoint + '/batch', b'\x1f\x8b', {'Content-Encoding': 'gzip'}), timeout=3))
        self.assertFalse(self.fixture.active['profiles'])
        self.assertFalse(self.fixture.active['events'])
        self.assertEqual(len(self.fixture.ledger['violations']), 4)

    def test_other_api_key_and_overlapping_vector_are_rejected(self):
        self.rejects(lambda: self.post('/profile', {'apiKey': 'pk_test_wrong_case', 'distinct_id': 'x'}))
        self.rejects(lambda: self.post('/v3/register', {'vector': 'retired-v1', 'apiKey': 'pk_test_wrapper_second',
                                                       'customerId': 'wrapper-v3-second', 'processId': 4288}))
        self.assertEqual(len(self.fixture.ledger['cases']), 1)
        self.assertFalse(self.fixture.active['profiles'])

    def test_authentication_oracle_rejects_wrong_pid_prior_event_time_and_generic_network_error(self):
        now = time.time()
        row = {'timestamp': datetime.fromtimestamp(now, timezone.utc).isoformat(), 'processID': 4288,
               'subsystem': 'io.nuxie.sdk', 'category': 'NuxieSDK',
               'eventMessage': '[Nuxie] [DEBUG] [UserTransitionCoordinator.swift:127] Identity profile refresh failed: '
                               '<redacted:error=JourneyReleaseAuthenticationError hmac-sha256:0123456789abcdef>'}
        self.assertTrue(terminal_authentication_failure(row, 4288, now - 1))
        for mutation in [dict(row, processID=4289), dict(row, timestamp=datetime.fromtimestamp(now - 10, timezone.utc).isoformat()),
                         dict(row, category='NativeV3Tests'), dict(row, subsystem='io.nuxie.wrapper.v3-tests'),
                         dict(row, eventMessage=row['eventMessage'].replace('JourneyReleaseAuthenticationError', 'URLError')),
                         dict(row, eventMessage=row['eventMessage'].replace('UserTransitionCoordinator.swift', 'NuxieSDK.swift'))]:
            with self.subTest(row=mutation):
                self.assertFalse(terminal_authentication_failure(mutation, 4288, now - 1))

    def test_settled_profile_service_authentication_error_is_observed(self):
        now = time.time()
        row = {'timestamp': datetime.fromtimestamp(now, timezone.utc).isoformat(), 'processID': 4288,
               'subsystem': 'io.nuxie.sdk', 'category': 'NuxieSDK',
               'eventMessage': '[Nuxie] [DEBUG] [ProfileService.swift:48] Profile refresh failed: '
                               '<redacted:error=JourneyReleaseAuthenticationError hmac-sha256:0123456789abcdef>'}
        self.assertTrue(terminal_authentication_failure(row, 4288, now - 1))
        for mutation in [dict(row, processID=4289), dict(row, timestamp=datetime.fromtimestamp(now - 10, timezone.utc).isoformat()),
                         dict(row, category='NativeV3Tests'), dict(row, subsystem='io.nuxie.wrapper.v3-tests'),
                         dict(row, eventMessage=row['eventMessage'].replace('JourneyReleaseAuthenticationError', 'URLError')),
                         dict(row, eventMessage=row['eventMessage'].replace('ProfileService.swift', 'NuxieSDK.swift'))]:
            with self.subTest(row=mutation):
                self.assertFalse(terminal_authentication_failure(mutation, 4288, now - 1))

    def test_authentication_snapshot_requires_identified_delivery_and_event_time_not_stream_arrival(self):
        now = time.time()
        row = {'timestamp': datetime.fromtimestamp(now - 10, timezone.utc).isoformat(), 'processID': 4288,
               'subsystem': 'io.nuxie.sdk', 'category': 'NuxieSDK',
               'eventMessage': '[Nuxie] [WARNING] [NuxieSDK.swift:342] Profile fetch failed: '
                               '<redacted:error=JourneyReleaseAuthenticationError hmac-sha256:0123456789abcdef>'}
        self.log.write_text(json.dumps(row) + '\n')
        self.assertFalse(self.fixture.snapshot(self.key)['authenticationFailures'])
        with self.post('/profile', {'apiKey': self.key, 'distinct_id': 'anonymous'}) as response:
            response.read()
        row['timestamp'] = datetime.fromtimestamp(time.time() + 0.1, timezone.utc).isoformat()
        self.log.write_text(json.dumps(row) + '\n')
        self.assertFalse(self.fixture.snapshot(self.key)['authenticationFailures'])
        with self.post('/profile', {'apiKey': self.key, 'distinct_id': 'wrapper-v3-regression'}) as response:
            response.read()
        self.assertEqual(self.fixture.snapshot(self.key)['authenticationFailures'], [row])

    def test_cached_or_empty_test_results_and_failed_teardown_do_not_qualify(self):
        self.fixture.active = None
        with self.assertRaisesRegex(ValueError, 'Every signed vector'):
            self.fixture.verify()
        cases = []
        for vector in ('accepted', 'retired-v1', 'retired-v2', 'wrong-domain'):
            case = copy.deepcopy(self.fixture.ledger['cases'][0])
            case.update(vector=vector, teardownCompleted=False, failure=None)
            cases.append(case)
        self.fixture.ledger['cases'] = cases
        with self.assertRaisesRegex(ValueError, 'shutdown failed'):
            self.fixture.verify()

    def reference_ledger(self):
        """Independent signed manifest plus authored observations for verifier mutations."""
        now = time.time()
        cases, logs = [], []
        expected = self.fixture.manifest['expectedProperties']
        journey_id = '00000000-0000-4000-8000-000000004288'
        for vector in self.fixture.manifest['cases']:
            case = {'vector': vector['name'], 'apiKey': 'pk_test_wrapper_' + vector['name'],
                    'processId': 4288, 'customerId': 'wrapper-v3-' + vector['name'],
                    'registeredAt': now - 1, 'finishedAt': now + 1, 'teardownCompleted': True,
                    'failure': None, 'profileSha256': vector['sha256']}
            case['profiles'] = [{'body': {'distinct_id': identity}, 'responseSha256': vector['sha256'],
                                 'responseCompletedAt': now - 0.5}
                                for identity in ('anonymous', case['customerId'])]
            case['events'] = [{'distinct_id': case['customerId'], 'event': 'wrapper_v3_flush_probe',
                               'properties': {'index': index}, 'idempotency_key': str(index)} for index in range(45)]
            case['events'].append({'distinct_id': case['customerId'], 'event': 'wrapper_v3_probe',
                                   'properties': copy.deepcopy(self.fixture.manifest['triggerProperties']),
                                   'idempotency_key': 'trigger'})
            accepted = vector['verdict'] == 'accepted'
            activities = []
            if accepted:
                for activity in ('journey_started', 'journey_completed'):
                    properties = dict(expected, journey_id=journey_id)
                    activities.append({'name': activity, 'properties': properties})
                    native_properties = dict(properties)
                    native_properties['experience_version_id'] = native_properties.pop('experience_version')
                    if activity == 'journey_completed':
                        native_properties['outputs'] = copy.deepcopy(self.fixture.manifest['expectedOutputs'])
                    case['events'].append({'event': '$journey_leg_' + activity.removeprefix('journey_'),
                                           'distinct_id': case['customerId'], 'properties': native_properties,
                                           'idempotency_key': activity})
            case['observation'] = {'nativeVersion': 'source-fixture-version', 'activities': activities,
                                   'finalFeatureState': 'ready' if accepted else 'unknown'}
            stamp = datetime.fromtimestamp(now, timezone.utc).isoformat()
            logs.append({'timestamp': stamp, 'processID': 4288, 'subsystem': 'io.nuxie.wrapper.v3-tests',
                         'category': 'NativeV3Tests', 'eventMessage': 'NATIVE_V3_LOG_READY ' + case['apiKey']})
            if not accepted:
                logs.append({'timestamp': stamp, 'processID': 4288, 'subsystem': 'io.nuxie.sdk',
                             'category': 'NuxieSDK', 'eventMessage': '[Nuxie] [DEBUG] [UserTransitionCoordinator.swift:127] '
                             'Identity profile refresh failed: <redacted:error=JourneyReleaseAuthenticationError hmac-sha256:0123456789abcdef>'})
            cases.append(case)
        self.fixture.ledger['cases'] = cases
        self.fixture.active = None
        self.log.write_text(''.join(json.dumps(row) + '\n' for row in logs))
        return cases

    def test_verifier_rejects_boolean_control_missing_index_reordered_journey_and_typed_output_mutations(self):
        cases = self.reference_ledger()
        self.assertEqual(len(self.fixture.verify()), 4)
        cases[0]['events'][42]['properties']['index'] = 42.0
        self.assertEqual(len(self.fixture.verify()), 4)
        accepted = copy.deepcopy(cases[0])
        mutations = []
        boolean_index = copy.deepcopy(accepted)
        boolean_index['events'][1]['properties']['index'] = True
        mutations.append(boolean_index)
        fractional_index = copy.deepcopy(accepted)
        fractional_index['events'][42]['properties']['index'] = 42.5
        mutations.append(fractional_index)
        missing_index = copy.deepcopy(accepted)
        missing_index['events'].pop(1)
        mutations.append(missing_index)
        wrong_order = copy.deepcopy(accepted)
        wrong_order['events'][-2:] = reversed(wrong_order['events'][-2:])
        mutations.append(wrong_order)
        wrong_output = copy.deepcopy(accepted)
        wrong_output['events'][-1]['properties']['outputs']['event']['probeBoolean'] = 1
        mutations.append(wrong_output)
        wrong_identity = copy.deepcopy(accepted)
        wrong_identity['events'][-1]['properties']['journey_id'] = 'different'
        mutations.append(wrong_identity)
        for case in mutations:
            with self.subTest(case=case):
                self.fixture.ledger['cases'][0] = case
                with self.assertRaises(ValueError):
                    self.fixture.verify()

    def test_startup_failure_terminates_owned_log_client(self):
        process = mock.Mock()
        process.returncode = -15
        with tempfile.TemporaryDirectory() as directory, \
             mock.patch('native_v3_fixture.subprocess.Popen', return_value=process), \
             mock.patch.object(NativeV3Fixture, 'server', side_effect=RuntimeError('startup failed')):
            root = Path(directory)
            (root / 'NATIVE-PINS.json').write_bytes((ROOT / 'NATIVE-PINS.json').read_bytes())
            with self.assertRaisesRegex(RuntimeError, 'startup failed'):
                with native_v3_fixture(root, 'unity', FIXTURES, 'owned-simulator'):
                    self.fail('A failed startup must not yield')
        process.terminate.assert_called_once()
        process.wait.assert_called_once_with(timeout=5)

    def test_thread_start_failure_closes_server_without_waiting_for_a_nonexistent_serving_thread(self):
        process, server, thread = mock.Mock(), mock.Mock(), mock.Mock()
        process.returncode = -15
        thread.start.side_effect = RuntimeError('thread startup failed')
        thread.is_alive.return_value = False
        with tempfile.TemporaryDirectory() as directory, \
             mock.patch('native_v3_fixture.subprocess.Popen', return_value=process), \
             mock.patch('native_v3_fixture.threading.Thread', return_value=thread), \
             mock.patch.object(NativeV3Fixture, 'server', return_value=server):
            root = Path(directory)
            (root / 'NATIVE-PINS.json').write_bytes((ROOT / 'NATIVE-PINS.json').read_bytes())
            with self.assertRaisesRegex(RuntimeError, 'thread startup failed'):
                with native_v3_fixture(root, 'unity', FIXTURES, 'owned-simulator'):
                    self.fail('Failed thread startup must not yield')
        server.shutdown.assert_not_called()
        server.server_close.assert_called_once()
        process.terminate.assert_called_once()

    def test_authentication_requires_completed_profile_response_not_request_or_prepared_body(self):
        # Model an independently observed error between request receipt and the
        # final response write; merely preparing correct bytes cannot admit it.
        now = time.time()
        row = {'timestamp': datetime.fromtimestamp(now, timezone.utc).isoformat(), 'processID': 4288,
               'subsystem': 'io.nuxie.sdk', 'category': 'NuxieSDK',
               'eventMessage': '[Nuxie] [DEBUG] [UserTransitionCoordinator.swift:127] Identity profile refresh failed: '
                               '<redacted:error=JourneyReleaseAuthenticationError hmac-sha256:0123456789abcdef>'}
        self.log.write_text(json.dumps(row) + '\n')
        self.fixture.active['profiles'].append({'body': {'distinct_id': 'wrapper-v3-regression'},
                                               'receivedAt': now - 1, 'responsePreparedAt': now - 0.5})
        self.assertFalse(self.fixture.snapshot(self.key)['authenticationFailures'])
        self.fixture.active['profiles'][-1]['responseCompletedAt'] = now + 0.1
        self.assertFalse(self.fixture.snapshot(self.key)['authenticationFailures'])
        row['timestamp'] = datetime.fromtimestamp(now + 0.2, timezone.utc).isoformat()
        self.log.write_text(json.dumps(row) + '\n')
        self.assertEqual(self.fixture.snapshot(self.key)['authenticationFailures'], [row])


if __name__ == '__main__':
    unittest.main()
