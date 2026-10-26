#!/usr/bin/env python3
"""Test read-only quota filtering, CLI routing, and owned-proxy cleanup."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch


PROBE = Path(__file__).with_name('probe-codex-runtime.py')
SPEC = importlib.util.spec_from_file_location('runtime_probe', PROBE)
probe = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(probe)


class RateLimitTests(unittest.TestCase):
    def test_weekly_primary_and_absent_secondary_keep_server_semantics(self):
        raw = {'rateLimits': {'limitId': 'codex', 'planType': 'pro',
                             'primary': {'usedPercent': 3, 'windowDurationMins': 10080,
                                         'resetsAt': 1793000000}, 'secondary': None},
               'ordinaryUsageAllowed': True}
        clean = probe.clean_rate_limits(raw)
        self.assertEqual(clean['rateLimits']['primary'], raw['rateLimits']['primary'])
        self.assertEqual(clean['rateLimits']['planType'], 'pro')
        self.assertIsNone(clean['rateLimits']['secondary'])
        self.assertIsNone(clean['rateLimitsByLimitId'])
        self.assertIs(clean['ordinaryUsageAllowed'], True)

    def test_only_codex_bucket_and_needed_fields_cross_the_output_boundary(self):
        snapshot = {'limitId': 'codex', 'planType': 'pro',
                    'primary': {'usedPercent': 100, 'windowDurationMins': 300,
                                'resetsAt': 1793000000, 'email': 'SECRET'},
                    'secondary': {'usedPercent': 19, 'windowDurationMins': 10080},
                    'rateLimitReachedType': 'workspace_member_usage_limit_reached',
                    'spendControlReached': True,
                    'credits': {'balance': 'SECRET'}, 'accountId': 'SECRET',
                    'limitName': 'SECRET', 'token': 'SECRET'}
        raw = {'rateLimits': snapshot,
               'rateLimitsByLimitId': {'codex': snapshot, 'codex_other': {'secret': 'SECRET'}},
               'ordinaryUsageAllowed': False, 'accountId': 'SECRET', 'email': 'SECRET',
               'rateLimitResetCredits': {'availableCount': 2, 'credits': [{'id': 'SECRET'}]}}
        clean = probe.clean_rate_limits(raw)
        self.assertEqual(set(clean), {'rateLimits', 'rateLimitsByLimitId', 'ordinaryUsageAllowed'})
        self.assertEqual(set(clean['rateLimitsByLimitId']), {'codex'})
        self.assertEqual(set(clean['rateLimits']), {'limitId', 'planType', 'primary', 'secondary',
                                                  'rateLimitReachedType', 'spendControlReached'})
        self.assertEqual(clean['rateLimits']['rateLimitReachedType'], snapshot['rateLimitReachedType'])
        self.assertIs(clean['rateLimits']['spendControlReached'], True)
        self.assertIs(clean['ordinaryUsageAllowed'], False)
        self.assertNotIn('SECRET', json.dumps(clean))

    def test_present_map_without_codex_never_becomes_legacy_fallback(self):
        for buckets in ({}, {'other': {}}, [], 'invalid'):
            with self.subTest(buckets=buckets):
                clean = probe.clean_rate_limits({'rateLimits': {'limitId': 'codex'},
                                                 'rateLimitsByLimitId': buckets})
                self.assertEqual(clean['rateLimitsByLimitId'], {})

    def test_unrelated_or_mismatched_snapshot_is_unavailable(self):
        clean = probe.clean_rate_limits({'rateLimits': {'limitId': 'other'},
                                         'rateLimitsByLimitId': {'codex': {'limitId': 'other'}}})
        self.assertIsNone(clean['rateLimits'])
        self.assertEqual(clean['rateLimitsByLimitId'], {'codex': None})
        for missing_id in ({}, {'limitId': None}):
            self.assertIsNotNone(probe.clean_rate_limits({'rateLimits': missing_id})['rateLimits'])

    def test_missing_and_malformed_fields_stay_unknown_not_zero(self):
        clean = probe.clean_rate_limits({'rateLimits': {
            'planType': 'SECRET@example.com', 'primary': {
                'usedPercent': True, 'windowDurationMins': -1, 'resetsAt': '1793000000'},
            'secondary': [], 'rateLimitReachedType': 'x' * 65, 'spendControlReached': 0},
            'ordinaryUsageAllowed': 1})
        self.assertEqual(clean['rateLimits']['primary'], {
            'usedPercent': None, 'windowDurationMins': None, 'resetsAt': None})
        for key in ('planType', 'secondary', 'rateLimitReachedType', 'spendControlReached'):
            self.assertIsNone(clean['rateLimits'][key])
        self.assertIsNone(clean['ordinaryUsageAllowed'])
        self.assertEqual(probe.clean_rate_limits({}), {
            'rateLimits': None, 'rateLimitsByLimitId': None, 'ordinaryUsageAllowed': None})

    def test_numeric_bounds_and_unknown_strings_cannot_expand_output(self):
        for number in (-1, 2**64, 1.5, float('nan'), float('inf')):
            clean = probe.clean_rate_limits({'rateLimits': {
                'primary': {'usedPercent': number, 'windowDurationMins': number, 'resetsAt': number},
                'planType': 'a' * 100000, 'rateLimitReachedType': 'b' * 100000}})
            self.assertTrue(all(v is None for v in clean['rateLimits']['primary'].values()))
            self.assertLess(len(json.dumps(clean)), 400)
        # Usage may exceed quota; do not reinterpret it as zero or unavailable.
        clean = probe.clean_rate_limits({'rateLimits': {'primary': {'usedPercent': 101}}})
        self.assertEqual(clean['rateLimits']['primary']['usedPercent'], 101)

    def test_malformed_response_is_a_bounded_error(self):
        for value in (None, [], 'SECRET'):
            with self.assertRaisesRegex(probe.ProbeError, '^The daemon returned malformed account limits$'):
                probe.clean_rate_limits(value)

    def test_read_limits_calls_only_the_read_endpoint(self):
        runtime = object.__new__(probe.RuntimeProbe)
        with patch.object(runtime, 'request', return_value={}) as request:
            self.assertEqual(runtime.read_limits(), probe.clean_rate_limits({}))
            request.assert_called_once_with('account/rateLimits/read', {})

    def test_unrelated_notifications_and_approvals_are_never_answered(self):
        runtime = object.__new__(probe.RuntimeProbe)
        runtime.request_id = 0
        runtime.timeout = 1
        messages = [
            {'method': 'account/rateLimits/updated', 'params': {'accountId': 'SECRET'}},
            {'id': 999, 'method': 'item/commandExecution/requestApproval', 'params': {}},
            {'id': 1, 'result': {'rateLimits': {'primary': {'usedPercent': 12}}}},
        ]
        with patch.object(runtime, 'send') as send, patch.object(runtime, 'receive', side_effect=messages):
            self.assertEqual(runtime.read_limits()['rateLimits']['primary']['usedPercent'], 12)
            send.assert_called_once_with({'id': 1, 'method': 'account/rateLimits/read', 'params': {}})

    def test_existing_thread_status_and_bounded_metadata_are_preserved(self):
        runtime = object.__new__(probe.RuntimeProbe)
        thread = {'id': 'test-thread', 'status': {'type': 'active', 'activeFlags': ['waitingOnApproval']},
                  'name': 'a' * 600, 'model': 'gpt-test', 'modelProvider': 'openai',
                  'cwd': '/example/project', 'source': 'cli', 'gitInfo': {'branch': 'main'},
                  'path': '/example/rollout.jsonl', 'preview': 'b' * 600}
        with patch.object(runtime, 'request', return_value={'thread': thread}) as request:
            self.assertEqual(runtime.read('test-thread'), {
                'thread_id': 'test-thread', 'status': 'active', 'active_flags': ['waitingOnApproval']})
            detail = runtime.read('test-thread', details=True)
            self.assertEqual(detail['name'], 'a' * 512)
            self.assertEqual(detail['task_preview'], 'b' * 500)
            self.assertEqual(detail['model'], 'gpt-test')
            self.assertEqual(detail['git_branch'], 'main')
            self.assertEqual(detail['rollout_path'], '/example/rollout.jsonl')
            self.assertEqual(request.call_count, 2)
            request.assert_called_with('thread/read', {'threadId': 'test-thread', 'includeTurns': False})


class ProbeRoutingTests(unittest.TestCase):
    def run_main(self, arguments, runtime_class):
        output = io.StringIO()
        with patch.object(probe.sys, 'argv', [str(PROBE)] + arguments), \
                patch.object(probe, 'RuntimeProbe', runtime_class), contextlib.redirect_stdout(output):
            result = probe.main()
        return result, output.getvalue()

    def test_limits_reads_once_without_a_thread_and_always_closes(self):
        with patch.object(probe, 'RuntimeProbe') as runtime_class:
            runtime = runtime_class.return_value
            runtime.read_limits.return_value = probe.clean_rate_limits({})
            result, output = self.run_main(['--limits', '--codex', '/fake/codex'], runtime_class)
            self.assertEqual(result, 0)
            self.assertEqual(json.loads(output), runtime.read_limits.return_value)
            runtime.connect.assert_called_once_with()
            runtime.read_limits.assert_called_once_with()
            runtime.read.assert_not_called()
            runtime.close.assert_called_once_with()

    def test_limits_error_is_bounded_and_still_closes(self):
        with patch.object(probe, 'RuntimeProbe') as runtime_class, \
                patch.object(probe, 'StdioLimitsProbe') as fallback:
            runtime = runtime_class.return_value
            runtime.read_limits.side_effect = probe.ProbeError('Read-only RPC failed with code -32601')
            result, output = self.run_main(['--limits', '--codex', '/fake/codex'], runtime_class)
            self.assertEqual(result, 1)
            self.assertEqual(json.loads(output), {'error': 'Read-only RPC failed with code -32601'})
            runtime.close.assert_called_once_with()
            fallback.assert_not_called()

    def test_missing_proxy_uses_only_remaining_quota_budget(self):
        clock = [10.0]
        with patch.object(probe, 'RuntimeProbe') as runtime_class, \
                patch.object(probe, 'StdioLimitsProbe') as fallback, \
                patch.object(probe.time, 'monotonic', side_effect=lambda: clock[0]):
            runtime = runtime_class.return_value
            def unavailable():
                clock[0] += 2
                raise probe.ProbeError('Proxy unavailable')
            def close():
                clock[0] += 0.25
            runtime.connect.side_effect = unavailable
            runtime.close.side_effect = close
            fallback.return_value.read_limits.return_value = probe.clean_rate_limits({})
            result, _ = self.run_main(['--limits', '--codex', '/fake/codex', '--timeout', '8'], runtime_class)
            self.assertEqual(result, 0)
            runtime.close.assert_called_once_with()
            fallback.assert_called_once_with('/fake/codex', 5.75)
            self.assertEqual(fallback.return_value.deadline, 18)
            fallback.return_value.read_limits.assert_called_once_with()
            fallback.return_value.read.assert_not_called()
            fallback.return_value.close.assert_called_once_with()

    def test_thread_connection_failure_never_starts_a_server(self):
        with patch.object(probe, 'RuntimeProbe') as runtime_class, \
                patch.object(probe, 'StdioLimitsProbe') as fallback:
            runtime_class.return_value.connect.side_effect = probe.ProbeError('Proxy unavailable')
            result, _ = self.run_main(['test-thread', '--codex', '/fake/codex'], runtime_class)
            self.assertEqual(result, 1)
            fallback.assert_not_called()

    def test_temporary_reader_rejects_thread_and_auth_operations(self):
        runtime = object.__new__(probe.StdioLimitsProbe)
        with patch.object(runtime, 'write') as write:
            for method in ('thread/read', 'thread/start', 'thread/resume', 'account/login/start', 'account/logout'):
                with self.subTest(method=method), self.assertRaises(probe.ProbeError):
                    runtime.send({'id': 1, 'method': method, 'params': {}})
            write.assert_not_called()

    def test_status_and_details_routing_are_unchanged(self):
        for details in (False, True):
            with self.subTest(details=details), patch.object(probe, 'RuntimeProbe') as runtime_class:
                runtime = runtime_class.return_value
                runtime.read.return_value = {'thread_id': 'test-thread', 'status': 'active',
                                             'active_flags': ['waitingOnApproval']}
                args = ['test-thread', '--codex', '/fake/codex'] + (['--details'] if details else [])
                result, output = self.run_main(args, runtime_class)
                self.assertEqual(result, 0)
                self.assertEqual(json.loads(output), runtime.read.return_value)
                runtime.read.assert_called_once_with('test-thread', details=details)
                runtime.read_limits.assert_not_called()
                runtime.close.assert_called_once_with()

    def test_invalid_mode_combinations_do_not_start_a_proxy(self):
        for args in ([], ['--limits', 'test-thread'], ['--limits', '--details'],
                     ['--limits', '--watch-seconds', '0'], ['--limits', '--interval', '1']):
            with self.subTest(args=args), patch.object(probe, 'RuntimeProbe') as runtime_class, \
                    contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as error:
                self.run_main(args + ['--codex', '/fake/codex'], runtime_class)
            self.assertEqual(error.exception.code, 2)
            runtime_class.assert_not_called()

    def test_rpc_errors_never_echo_account_data(self):
        runtime = object.__new__(probe.RuntimeProbe)
        runtime.request_id = 0
        runtime.timeout = 1
        with patch.object(runtime, 'send') as send, patch.object(runtime, 'receive', return_value={
                'id': 1, 'error': {'code': {'email': 'SECRET'}, 'message': 'SECRET'}}):
            with self.assertRaisesRegex(probe.ProbeError, '^Read-only RPC failed with code unknown$'):
                runtime.read_limits()
            send.assert_called_once_with({'id': 1, 'method': 'account/rateLimits/read', 'params': {}})


class ProbeCleanupTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='agentvalley-probe-test-')
        self.root = Path(self.directory.name)
        self.pid_file = self.root / 'owned-proxy.pid'
        self.fake = self.root / 'fake-codex'
        self.fake.write_text('''#!/usr/bin/python3
import os, signal, time
signal.signal(signal.SIGTERM, signal.SIG_IGN)
with open(os.environ['AGENTVALLEY_PROBE_TEST_PID_FILE'], 'w') as output:
    output.write(str(os.getpid()))
while True:
    time.sleep(60)
''')
        self.fake.chmod(0o700)
        self.process = None
        self.proxy_pid = None

    def tearDown(self):
        if self.process is not None and self.process.poll() is None:
            self.process.kill()
            self.process.wait(timeout=1)
        if self.proxy_pid is not None:
            try:
                os.kill(self.proxy_pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        self.directory.cleanup()

    def start(self, timeout, limits=False):
        environment = dict(os.environ, AGENTVALLEY_PROBE_TEST_PID_FILE=str(self.pid_file))
        self.process = subprocess.Popen(
            ['/usr/bin/python3', str(PROBE), '--limits' if limits else 'test-owned-thread', '--codex',
             str(self.fake), '--timeout', str(timeout)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=environment)
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            if self.pid_file.exists() and self.pid_file.read_text():
                self.proxy_pid = int(self.pid_file.read_text())
                return
            time.sleep(0.01)
        self.fail('Owned fake proxy did not start')

    def assert_proxy_reaped(self):
        with self.assertRaises(ProcessLookupError):
            os.kill(self.proxy_pid, 0)
        self.proxy_pid = None

    def test_timeout_kills_and_reaps_a_proxy_that_ignores_term(self):
        self.start(0.1)
        output, _ = self.process.communicate(timeout=2)
        self.assertEqual(self.process.returncode, 1)
        self.assertIn(b'Timed out reading', output)
        self.assert_proxy_reaped()

    def test_sigterm_unwinds_and_reaps_proxy_within_outer_cleanup_window(self):
        self.start(30)
        began = time.monotonic()
        self.process.terminate()
        output, _ = self.process.communicate(timeout=1)
        self.assertEqual(self.process.returncode, 128 + signal.SIGTERM)
        self.assertLess(time.monotonic() - began, 0.5)
        self.assertEqual(output, b'')
        self.assert_proxy_reaped()

    def test_limits_timeout_reaps_owned_proxy(self):
        self.start(0.1, limits=True)
        output, _ = self.process.communicate(timeout=2)
        self.assertEqual(self.process.returncode, 1)
        self.assertIn(b'Timed out reading', output)
        self.assertNotIn(b'thread_id', output)
        self.assert_proxy_reaped()

    def test_limits_sigterm_reaps_owned_proxy(self):
        self.start(30, limits=True)
        began = time.monotonic()
        self.process.terminate()
        output, _ = self.process.communicate(timeout=1)
        self.assertEqual(self.process.returncode, 128 + signal.SIGTERM)
        self.assertLess(time.monotonic() - began, 0.5)
        self.assertEqual(output, b'')
        self.assert_proxy_reaped()


class StdioFallbackTests(ProbeCleanupTests):
    # Reuse owned-process cleanup helpers, without running the proxy-only cases.
    test_timeout_kills_and_reaps_a_proxy_that_ignores_term = None
    test_sigterm_unwinds_and_reaps_proxy_within_outer_cleanup_window = None
    test_limits_timeout_reaps_owned_proxy = None
    test_limits_sigterm_reaps_owned_proxy = None

    def setUp(self):
        super().setUp()
        self.requests = Path(str(self.pid_file) + '.requests')
        self.fake.write_text('''#!/usr/bin/python3
import json, os, signal, sys, time
if sys.argv[1:] == ['app-server', 'proxy']:
    sys.exit(1)
if sys.argv[1:] != ['app-server', '--listen', 'stdio://']:
    sys.exit(2)
signal.signal(signal.SIGTERM, signal.SIG_IGN)
path = os.environ['AGENTVALLEY_PROBE_TEST_PID_FILE']
with open(path, 'w') as output:
    output.write(str(os.getpid()))
for line in sys.stdin:
    request = json.loads(line)
    method = request['method']
    with open(path + '.requests', 'a') as output:
        output.write(method + '\\n')
    if method == 'initialized':
        continue
    if method == 'initialize':
        result = {'userAgent': 'fixture'}
    elif method == 'account/rateLimits/read':
        if os.environ.get('AGENTVALLEY_PROBE_TEST_HANG'):
            while True:
                time.sleep(60)
        result = {'accountId': 'PRIVATE_ACCOUNT', 'ordinaryUsageAllowed': True,
                  'rateLimits': {'limitId': 'codex', 'credits': {'balance': 'PRIVATE_CREDITS'},
                                 'primary': {'usedPercent': 17, 'windowDurationMins': 10080, 'resetsAt': 1900000000}}}
    else:
        sys.exit(3)
    print(json.dumps({'id': request['id'], 'result': result}), flush=True)
''')

    def test_fallback_reads_only_account_limits_and_reaps_process(self):
        self.start(2, limits=True)
        output, _ = self.process.communicate(timeout=3)
        self.assertEqual(self.process.returncode, 0)
        result = json.loads(output)
        self.assertEqual(result['rateLimits']['primary']['usedPercent'], 17)
        self.assertTrue(result['ordinaryUsageAllowed'])
        self.assertNotIn(b'PRIVATE_', output)
        self.assertEqual(self.requests.read_text().splitlines(),
                         ['initialize', 'initialized', 'account/rateLimits/read'])
        self.assert_proxy_reaped()

    def test_fallback_timeout_reaps_process_within_shared_budget(self):
        began = time.monotonic()
        with patch.dict(os.environ, {'AGENTVALLEY_PROBE_TEST_HANG': '1'}):
            self.start(0.3, limits=True)
        output, _ = self.process.communicate(timeout=2)
        self.assertEqual(self.process.returncode, 1)
        self.assertIn(b'Timed out reading', output)
        self.assertLess(time.monotonic() - began, 1.2)
        self.assert_proxy_reaped()

    def test_fallback_sigterm_reaps_owned_process(self):
        with patch.dict(os.environ, {'AGENTVALLEY_PROBE_TEST_HANG': '1'}):
            self.start(30, limits=True)
        began = time.monotonic()
        self.process.terminate()
        output, _ = self.process.communicate(timeout=1)
        self.assertEqual(self.process.returncode, 128 + signal.SIGTERM)
        self.assertLess(time.monotonic() - began, 0.5)
        self.assertEqual(output, b'')
        self.assert_proxy_reaped()


if __name__ == '__main__':
    unittest.main()
