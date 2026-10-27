import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest

SPEC = importlib.util.spec_from_file_location('usage_probe', Path(__file__).with_name('usage_probe.py'))
probe = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(probe)


class UsageProbeTests(unittest.TestCase):
    def test_only_existing_windows_leave_projection(self):
        value = {'session': {'cost': 9}, 'account': 'secret', 'rate_limits': {
            'five_hour': {'utilization': 25.5, 'resets_at': '2026-10-28T01:02:03Z', 'secret': 'token'},
            'seven_day': {'utilization': 51, 'resets_at': '2026-11-01T00:00:00+00:00'},
            'extra_usage': {'balance': 100}, 'model_scoped': [{'name': 'model'}]}, 'behaviors': 'private'}
        self.assertEqual(probe.clean_usage(value), {'limits': [
            {'kind': 'session', 'percent': 25.5, 'resets_at': '2026-10-28T01:02:03Z'},
            {'kind': 'weekly_all', 'percent': 51, 'resets_at': '2026-11-01T00:00:00+00:00'}]})

    def test_new_format_precedes_legacy_and_ignores_unknown_windows(self):
        value = {'rate_limits': {'limits': [{'kind': 'session', 'percent': 4}, {'kind': 'model', 'percent': 99}],
                                 'five_hour': {'utilization': 80}, 'seven_day': {'utilization': 7}}}
        self.assertEqual(probe.clean_usage(value), {'limits': [
            {'kind': 'session', 'percent': 4, 'resets_at': None},
            {'kind': 'weekly_all', 'percent': 7, 'resets_at': None}]})

    def test_invalid_numbers_never_become_zero_or_leak_raw_data(self):
        for number in [True, False, '12', None, -1, 100001, 10**1000, float('nan'), float('inf')]:
            with self.subTest(number=number), self.assertRaises(probe.ProbeError):
                probe.clean_usage({'rate_limits': {'five_hour': {'utilization': number}}})
        for value in [None, [], {}, {'rate_limits': None}, {'rate_limits': {'unknown': 'secret'}}]:
            with self.subTest(value=value), self.assertRaises(probe.ProbeError):
                probe.clean_usage(value)

    def test_invalid_reset_does_not_remove_valid_percentage(self):
        for reset in ['secret', '', 12, None, '2026-10-28T00:00:00', 'x' * 10000]:
            result = probe.clean_usage({'rate_limits': {'five_hour': {'utilization': 0, 'resets_at': reset}}})
            self.assertEqual(result, {'limits': [{'kind': 'session', 'percent': 0, 'resets_at': None}]})

    def test_environment_and_flags_cannot_inherit_injections_or_credentials(self):
        supplied = {key: 'secret' for key in ['ANTHROPIC_API_KEY', 'ANTHROPIC_BASE_URL', 'HTTP_PROXY',
                    'HTTPS_PROXY', 'ALL_PROXY', 'CLAUDE_CONFIG_DIR', 'CLAUDE_CODE_OAUTH_TOKEN',
                    'NODE_OPTIONS', 'BUN_OPTIONS', 'DYLD_INSERT_LIBRARIES', 'PATH', 'HOME',
                    'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC']}
        environment = probe.controlled_environment(supplied)
        self.assertEqual(environment['HOME'], 'secret')
        self.assertEqual(environment['PATH'], '/usr/bin:/bin:/usr/sbin:/sbin')
        self.assertEqual(environment['DISABLE_TELEMETRY'], '1')
        self.assertNotIn('CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC', environment)
        self.assertFalse(set(supplied).difference(['PATH', 'HOME']).intersection(environment))
        argv = probe.command('/trusted/claude')
        self.assertIn('--safe-mode', argv)
        self.assertIn('--no-session-persistence', argv)
        self.assertEqual(argv[argv.index('--settings') + 1], '{"disableAllHooks":true}')
        self.assertEqual(argv[argv.index('--mcp-config') + 1], '{"mcpServers":{}}')
        self.assertEqual(argv[argv.index('--tools') + 1], '')

    def run_fixture(self, body, timeout=2):
        directory = tempfile.TemporaryDirectory(prefix='agentvalley-usage-test-')
        self.addCleanup(directory.cleanup)
        path = Path(directory.name) / 'fake-claude'
        # An actual child process exercises framing, deadlines and termination;
        # it has no access path to real login, transcript or model APIs.
        path.write_text('#!' + sys.executable + '\nimport json, os, sys, time, signal\n' + body)
        path.chmod(0o700)
        client = probe.UsageProbe(str(path), timeout)
        self.addCleanup(client.close)
        return client

    def test_control_frames_only_and_wrong_identity_ignored(self):
        client = self.run_fixture('''
for count in range(2):
    m = json.loads(sys.stdin.readline())
    assert m['type'] == 'control_request'
    expected = {'subtype': 'initialize'} if count == 0 else {'subtype': 'get_usage', 'skip_behaviors': True}
    assert m['request'] == expected
    value = {} if count == 0 else {'rate_limits': {'five_hour': {'utilization': 9}}, 'email': 'must-not-escape'}
    print(json.dumps({'type': 'control_response', 'response': {'request_id': 'wrong', 'subtype': 'success', 'response': {'private': 1}}}), flush=True)
    print(json.dumps({'type': 'control_response', 'response': {'request_id': m['request_id'], 'subtype': 'success', 'response': value}}), flush=True)
sys.stdin.read()
''')
        self.assertEqual(client.usage(), {'limits': [{'kind': 'session', 'percent': 9, 'resets_at': None}]})
        pid = client.process.pid
        client.close()
        self.assertIsNotNone(client.process.poll())
        with self.assertRaises(ProcessLookupError):
            os.kill(pid, 0)

    def test_normal_eof_allows_cli_shutdown_without_term(self):
        client = self.run_fixture('''
signal.signal(signal.SIGTERM, lambda *_: sys.exit(9))
for count in range(2):
    m = json.loads(sys.stdin.readline())
    value = {} if count == 0 else {'rate_limits': {'five_hour': {'utilization': 8}}}
    print(json.dumps({'type': 'control_response', 'response': {'request_id': m['request_id'], 'subtype': 'success', 'response': value}}), flush=True)
sys.stdin.read()
time.sleep(0.25)
''')
        client.usage()
        client.close()
        self.assertEqual(client.process.returncode, 0)

    def test_term_grace_allows_official_style_credential_cleanup(self):
        client = self.run_fixture('''
def finish(*_):
    time.sleep(0.3)
    sys.exit(0)
signal.signal(signal.SIGTERM, finish)
sys.stdin.readline()
time.sleep(60)
''', timeout=0.15)
        with self.assertRaises(probe.ProbeError):
            client.usage()
        started = time.monotonic()
        client.close()
        self.assertEqual(client.process.returncode, 0)
        self.assertLess(time.monotonic() - started, 4)

    def test_unsolicited_permission_request_is_never_answered(self):
        client = self.run_fixture('''
sys.stdin.readline()
print(json.dumps({'type':'control_request','request_id':'approve','request':{'subtype':'can_use_tool'}}), flush=True)
assert sys.stdin.readline() == ''
''')
        with self.assertRaises(probe.ProbeError) as error:
            client.usage()
        self.assertEqual(error.exception.category, 'refused')
        client.close()

    def test_authentication_error_is_categorical_not_raw(self):
        client = self.run_fixture('''
m = json.loads(sys.stdin.readline())
print(json.dumps({'type':'control_response','response':{'request_id':m['request_id'],'subtype':'error','error_code':'authentication_error','error':'SECRET'}}), flush=True)
sys.stdin.read()
''')
        with self.assertRaises(probe.ProbeError) as error:
            client.usage()
        self.assertEqual(str(error.exception), 'loginExpired')

    def test_timeout_kills_term_ignoring_owned_child(self):
        client = self.run_fixture('''
signal.signal(signal.SIGTERM, signal.SIG_IGN)
sys.stdin.readline()
time.sleep(60)
''', timeout=0.15)
        started = time.monotonic()
        with self.assertRaises(probe.ProbeError) as error:
            client.usage()
        self.assertEqual(error.exception.category, 'noAnswer')
        client.close()
        self.assertIsNotNone(client.process.poll())
        self.assertLess(time.monotonic() - started, 5)

    def test_oversized_and_malformed_output_fail_closed(self):
        for body in ["sys.stdout.write('x' * (1024*1024+1)); sys.stdout.flush(); time.sleep(60)",
                     "print('not json', flush=True); time.sleep(60)",
                     "print('[]', flush=True); time.sleep(60)"]:
            client = self.run_fixture(body)
            with self.assertRaises(probe.ProbeError) as error:
                client.usage()
            self.assertEqual(error.exception.category, 'unreadable')
            client.close()

    def test_total_notification_stream_is_bounded(self):
        client = self.run_fixture('''
line = json.dumps({'type':'system','text':'x'*60000}) + '\\n'
for i in range(100):
    sys.stdout.write(line)
    sys.stdout.flush()
time.sleep(60)
''')
        with self.assertRaises(probe.ProbeError) as error:
            client.usage()
        self.assertEqual(error.exception.category, 'unreadable')

    def test_helper_sigterm_reaps_its_owned_cli(self):
        with tempfile.TemporaryDirectory(prefix='agentvalley-usage-cleanup-') as directory:
            executable = Path(directory) / 'fake-claude'
            pid_path = Path(directory) / 'pid'
            executable.write_text('#!' + sys.executable + '\nimport os, signal, time\n'
                                  'signal.signal(signal.SIGTERM, signal.SIG_IGN)\n'
                                  'open(' + repr(str(pid_path)) + ', "w").write(str(os.getpid()))\n'
                                  'time.sleep(60)\n')
            executable.chmod(0o700)
            child = subprocess.Popen([sys.executable, str(Path(probe.__file__)), '--claude', str(executable)],
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            try:
                deadline = time.monotonic() + 4
                while not pid_path.exists() and time.monotonic() < deadline:
                    time.sleep(0.01)
                self.assertTrue(pid_path.exists())
                pid = int(pid_path.read_text())
                child.terminate()
                stdout, stderr = child.communicate(timeout=5)
                self.assertEqual(json.loads(stdout), {'error': 'offline'})
                self.assertEqual(stderr, b'')
                with self.assertRaises(ProcessLookupError):
                    os.kill(pid, 0)
            finally:
                if child.poll() is None:
                    child.kill()
                    child.wait()


if __name__ == '__main__':
    unittest.main()
