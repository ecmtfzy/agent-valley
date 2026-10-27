#!/usr/bin/env python3
"""Ask the installed Claude CLI for account usage, letting it renew its own login.

Only initialize and get_usage(skip_behaviors=True) control requests are sent.
There is no user/model message, conversation resume, tool call or token handling.
The experimental control API is bounded and fails closed on incompatible CLIs.
"""
import argparse
import datetime
import json
import math
import os
from pathlib import Path
import selectors
import signal
import subprocess
import sys
import tempfile
import time


class ProbeError(Exception):
    def __init__(self, category):
        self.category = category
        super().__init__(category)


def clean_usage(value):
    """Project only the two existing UI windows; never emit account/session data."""
    if not isinstance(value, dict) or not isinstance(value.get('rate_limits'), dict):
        raise ProbeError('unreadable')
    raw = value['rate_limits']

    def number(value):
        if type(value) not in (int, float) or not 0 <= value <= 100000 or not math.isfinite(value):
            return None
        return value

    def reset(value):
        if not isinstance(value, str) or len(value) > 40:
            return None
        try:
            parsed = datetime.datetime.fromisoformat(value.replace('Z', '+00:00'))
        except ValueError:
            return None
        return value if parsed.tzinfo is not None else None

    windows = {}
    if isinstance(raw.get('limits'), list):
        for entry in raw['limits'][:128]:
            if not isinstance(entry, dict):
                continue
            kind, percent = entry.get('kind'), number(entry.get('percent'))
            if kind in ('session', 'weekly_all') and percent is not None and kind not in windows:
                windows[kind] = {'kind': kind, 'percent': percent, 'resets_at': reset(entry.get('resets_at'))}
    for key, kind in [('five_hour', 'session'), ('seven_day', 'weekly_all')]:
        entry = raw.get(key)
        if kind in windows or not isinstance(entry, dict):
            continue
        percent = number(entry.get('utilization'))
        if percent is not None:
            windows[kind] = {'kind': kind, 'percent': percent, 'resets_at': reset(entry.get('resets_at'))}
    if not windows:
        raise ProbeError('unreadable')
    return {'limits': list(windows.values())}


def controlled_environment(environment):
    # Do not inherit API keys, injected startup modules, endpoint overrides,
    # external credential helpers or proxy configuration from the host process.
    result = {key: environment[key] for key in ('HOME', 'USER', 'LOGNAME', 'TMPDIR') if key in environment}
    result.update({'PATH': '/usr/bin:/bin:/usr/sbin:/sbin', 'LANG': 'en_US.UTF-8',
                   'DISABLE_AUTOUPDATER': '1', 'DISABLE_TELEMETRY': '1'})
    # CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC also blocks /api/oauth/usage
    # before its official refresh step; disable telemetry alone instead.
    return result


def command(claude):
    return [claude, '--print', '--input-format', 'stream-json', '--output-format', 'stream-json',
            '--verbose', '--safe-mode', '--no-session-persistence', '--tools', '',
            '--strict-mcp-config', '--mcp-config', '{"mcpServers":{}}',
            '--setting-sources', '', '--settings', '{"disableAllHooks":true}']


class UsageProbe:
    MAX_LINE = 1024 * 1024
    MAX_TOTAL = 4 * 1024 * 1024

    def __init__(self, claude, timeout, environment=None):
        self.directory = tempfile.TemporaryDirectory(prefix='agentvalley-claude-usage-')
        self.selector = selectors.DefaultSelector()
        self.process = None
        self.buffer = bytearray()
        self.read_bytes = 0
        self.deadline = time.monotonic() + timeout
        try:
            self.process = subprocess.Popen(command(claude), stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                            stderr=subprocess.DEVNULL, cwd=self.directory.name,
                                            env=controlled_environment(os.environ if environment is None else environment))
            self.selector.register(self.process.stdout, selectors.EVENT_READ)
        except BaseException:
            self.close()
            raise

    def close(self):
        # TERM from the app must not strand the CLI owned by this helper.
        previous = {sig: signal.signal(sig, signal.SIG_IGN) for sig in (signal.SIGINT, signal.SIGTERM)}
        try:
            self.selector.close()
            if self.process is not None:
                try:
                    self.process.stdin.close()
                except OSError:
                    pass
                if self.process.poll() is None:
                    # EOF normally lets the control-only process leave cleanly.
                    # Its official shutdown hook waits up to two seconds for an
                    # OAuth refresh lock to release; do not cut that save short.
                    try:
                        self.process.wait(timeout=1)
                    except subprocess.TimeoutExpired:
                        self.process.terminate()
                        try:
                            self.process.wait(timeout=2.5)
                        except subprocess.TimeoutExpired:
                            self.process.kill()
                            try:
                                self.process.wait(timeout=0.15)
                            except subprocess.TimeoutExpired:
                                pass
                for pipe in (self.process.stdin, self.process.stdout):
                    try:
                        pipe.close()
                    except OSError:
                        pass
            self.directory.cleanup()
        finally:
            for sig, handler in previous.items():
                signal.signal(sig, handler)

    def read_message(self):
        while True:
            newline = self.buffer.find(b'\n')
            if newline >= 0:
                if newline > self.MAX_LINE:
                    raise ProbeError('unreadable')
                line = bytes(self.buffer[:newline])
                del self.buffer[:newline + 1]
                try:
                    value = json.loads(line)
                except (ValueError, UnicodeDecodeError):
                    raise ProbeError('unreadable')
                if not isinstance(value, dict):
                    raise ProbeError('unreadable')
                return value
            if len(self.buffer) > self.MAX_LINE:
                raise ProbeError('unreadable')
            remaining = self.deadline - time.monotonic()
            if remaining <= 0 or not self.selector.select(remaining):
                raise ProbeError('noAnswer')
            data = os.read(self.process.stdout.fileno(), 65536)
            if not data:
                raise ProbeError('offline')
            self.read_bytes += len(data)
            if self.read_bytes > self.MAX_TOTAL:
                raise ProbeError('unreadable')
            self.buffer.extend(data)

    def request(self, identity, request):
        message = {'type': 'control_request', 'request_id': identity, 'request': request}
        try:
            self.process.stdin.write((json.dumps(message, separators=(',', ':')) + '\n').encode('utf-8'))
            self.process.stdin.flush()
        except OSError:
            raise ProbeError('offline')
        while True:
            value = self.read_message()
            if value.get('type') == 'control_request':
                # No permission, hook or user dialog is ever answered by this transport.
                raise ProbeError('refused')
            if value.get('type') != 'control_response':
                continue
            response = value.get('response')
            if not isinstance(response, dict) or response.get('request_id') != identity:
                continue
            if response.get('subtype') != 'success':
                code = response.get('error_code')
                if code in ('authentication_error', 'unauthorized', 'oauth_token_expired'):
                    raise ProbeError('loginExpired')
                if code in ('permission_denied', 'forbidden'):
                    raise ProbeError('refused')
                raise ProbeError('offline')
            return response.get('response')

    def usage(self):
        self.request('agentvalley-initialize', {'subtype': 'initialize'})
        return clean_usage(self.request('agentvalley-usage', {'subtype': 'get_usage', 'skip_behaviors': True}))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--claude', required=True, help='Absolute path to the installed Claude CLI')
    parser.add_argument('--timeout', type=float, default=45)
    args = parser.parse_args(argv)
    if not Path(args.claude).is_absolute() or not math.isfinite(args.timeout) or not 0 < args.timeout <= 60:
        parser.error('Expected an absolute CLI path and timeout within (0, 60]')
    probe = None
    signal.signal(signal.SIGTERM, lambda *_: (_ for _ in ()).throw(ProbeError('offline')))
    signal.signal(signal.SIGINT, lambda *_: (_ for _ in ()).throw(ProbeError('offline')))
    try:
        probe = UsageProbe(args.claude, args.timeout)
        print(json.dumps(probe.usage(), separators=(',', ':'), allow_nan=False))
        return 0
    except ProbeError as error:
        print(json.dumps({'error': error.category}, separators=(',', ':')))
        return 1
    except (OSError, ValueError):
        print('{"error":"offline"}')
        return 1
    finally:
        if probe is not None:
            probe.close()


if __name__ == '__main__':
    sys.exit(main())
