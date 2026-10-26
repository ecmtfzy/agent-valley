#!/usr/bin/env python3
"""Read thread status or account limits from the existing Codex daemon.

The installed `codex app-server proxy` is a raw tunnel to the Unix socket, so
this client performs WebSocket Upgrade and framing before sending JSON-RPC.
Only initialize, initialized and thread/read or account/rateLimits/read are sent.
No thread is resumed, approval answered, credit consumed, or limit reset.
"""
import argparse
import base64
import hashlib
import json
import os
import re
import selectors
import shutil
import signal
import struct
import subprocess
import sys
import time


class ProbeError(Exception):
    pass


def clean_rate_limits(result):
    """Return only the Codex quota fields used by the shared usage interface.

    Missing or invalid data stays unavailable. In particular, an existing
    multi-bucket map without Codex must remain {}, so consumers do not fall
    back to a legacy snapshot for some other product.
    """
    if not isinstance(result, dict):
        raise ProbeError('The daemon returned malformed account limits')

    def integer(value, minimum, maximum):
        return value if type(value) is int and minimum <= value <= maximum else None

    def boolean(value):
        return value if type(value) is bool else None

    def token(value):
        return value if isinstance(value, str) and re.fullmatch(r'[a-z][a-z0-9_]{0,63}', value) else None

    def window(value):
        if not isinstance(value, dict):
            return None
        return {
            'usedPercent': integer(value.get('usedPercent'), 0, 2**31 - 1),
            'windowDurationMins': integer(value.get('windowDurationMins'), 1, 2**63 - 1),
            'resetsAt': integer(value.get('resetsAt'), 0, 2**63 - 1),
        }

    def snapshot(value):
        if not isinstance(value, dict) or value.get('limitId') not in (None, 'codex'):
            return None
        return {
            'limitId': value.get('limitId'),
            'planType': token(value.get('planType')),
            'primary': window(value.get('primary')),
            'secondary': window(value.get('secondary')),
            'rateLimitReachedType': token(value.get('rateLimitReachedType')),
            'spendControlReached': boolean(value.get('spendControlReached')),
        }

    # A malformed non-null map also suppresses legacy fallback. Never turn a
    # present but unusable multi-bucket response into an apparently older API.
    buckets = result.get('rateLimitsByLimitId')
    by_limit = None
    if buckets is not None:
        by_limit = {}
        if isinstance(buckets, dict) and 'codex' in buckets:
            by_limit['codex'] = snapshot(buckets['codex'])
    return {
        'rateLimits': snapshot(result.get('rateLimits')),
        'rateLimitsByLimitId': by_limit,
        'ordinaryUsageAllowed': boolean(result.get('ordinaryUsageAllowed')),
    }


class RuntimeProbe:
    MAX_MESSAGE = 16 * 1024 * 1024

    def __init__(self, codex, timeout):
        self.timeout = timeout
        self.process = subprocess.Popen(
            [codex, 'app-server', 'proxy'], stdin=subprocess.PIPE,
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        )
        self.selector = selectors.DefaultSelector()
        self.selector.register(self.process.stdout, selectors.EVENT_READ)
        self.buffer = bytearray()
        self.request_id = 0

    def close(self):
        # A second termination signal must not interrupt cleanup before the proxy
        # is reaped. This helper owns only this proxy, never the shared daemon.
        handlers = {sig: signal.signal(sig, signal.SIG_IGN)
                    for sig in (signal.SIGINT, signal.SIGTERM)}
        try:
            self.selector.close()
            if self.process.poll() is None:
                self.process.terminate()
                try:
                    self.process.wait(timeout=0.1)
                except subprocess.TimeoutExpired:
                    self.process.kill()
                    try:
                        self.process.wait(timeout=0.1)
                    except subprocess.TimeoutExpired:
                        pass  # Already killed; do not block the app's polling queue.
        finally:
            for pipe in (self.process.stdin, self.process.stdout):
                try:
                    pipe.close()
                except OSError:
                    pass
            for sig, handler in handlers.items():
                signal.signal(sig, handler)

    def write(self, data):
        try:
            self.process.stdin.write(data)
            self.process.stdin.flush()
        except (BrokenPipeError, OSError) as error:
            raise ProbeError('The existing-daemon proxy connection closed') from error

    def fill(self, count, deadline):
        while len(self.buffer) < count:
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not self.selector.select(remaining):
                raise ProbeError('Timed out reading the existing-daemon proxy')
            data = os.read(self.process.stdout.fileno(), 65536)
            if not data:
                raise ProbeError('The existing-daemon proxy connection closed')
            self.buffer.extend(data)
            if len(self.buffer) > self.MAX_MESSAGE + 65536:
                raise ProbeError('Response exceeded the probe size limit')

    def take(self, count, deadline):
        self.fill(count, deadline)
        data = bytes(self.buffer[:count])
        del self.buffer[:count]
        return data

    def connect(self):
        key = base64.b64encode(os.urandom(16)).decode('ascii')
        self.write((
            'GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\n'
            'Connection: Upgrade\r\nSec-WebSocket-Key: ' + key + '\r\n'
            'Sec-WebSocket-Version: 13\r\n\r\n'
        ).encode('ascii'))
        deadline = time.monotonic() + self.timeout
        while b'\r\n\r\n' not in self.buffer:
            self.fill(len(self.buffer) + 1, deadline)
            if len(self.buffer) > 65536:
                raise ProbeError('WebSocket response headers exceeded the size limit')
        header, _, rest = self.buffer.partition(b'\r\n\r\n')
        self.buffer = bytearray(rest)
        lines = header.decode('ascii').split('\r\n')
        if not lines[0].startswith('HTTP/1.1 101 '):
            raise ProbeError('The daemon did not accept WebSocket Upgrade')
        headers = dict(line.split(':', 1) for line in lines[1:] if ':' in line)
        headers = {name.lower(): value.strip() for name, value in headers.items()}
        expected = base64.b64encode(hashlib.sha1(
            (key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').encode('ascii')
        ).digest()).decode('ascii')
        if headers.get('sec-websocket-accept') != expected:
            raise ProbeError('Invalid WebSocket Upgrade response')
        self.request('initialize', {'clientInfo': {
            'name': 'agentvalley_readonly_runtime_probe', 'version': '0.1.0'
        }})
        self.send({'method': 'initialized', 'params': {}})

    def frame(self, opcode, data):
        mask = os.urandom(4)
        length = len(data)
        if length < 126:
            header = bytes([0x80 | opcode, 0x80 | length])
        elif length < 65536:
            header = bytes([0x80 | opcode, 0x80 | 126]) + struct.pack('!H', length)
        else:
            header = bytes([0x80 | opcode, 0x80 | 127]) + struct.pack('!Q', length)
        masked = bytes(byte ^ mask[index % 4] for index, byte in enumerate(data))
        self.write(header + mask + masked)

    def send(self, message):
        self.frame(1, json.dumps(message, separators=(',', ':')).encode('utf-8'))

    def receive(self, deadline):
        message = bytearray()
        started = False
        while True:
            first, second = self.take(2, deadline)
            opcode, final = first & 15, bool(first & 128)
            if first & 112 or second & 128:
                raise ProbeError('Unsupported server WebSocket framing')
            length = second & 127
            if length == 126:
                length = struct.unpack('!H', self.take(2, deadline))[0]
            elif length == 127:
                length = struct.unpack('!Q', self.take(8, deadline))[0]
            if length > self.MAX_MESSAGE:
                raise ProbeError('WebSocket frame exceeded the size limit')
            payload = self.take(length, deadline)
            if opcode == 8:
                raise ProbeError('The daemon closed the read-only connection')
            if opcode == 9:
                self.frame(10, payload)
                continue
            if opcode == 10:
                continue
            if opcode == 1 and not started:
                started = True
            elif opcode != 0 or not started:
                raise ProbeError('Unsupported server WebSocket message')
            message.extend(payload)
            if len(message) > self.MAX_MESSAGE:
                raise ProbeError('WebSocket message exceeded the size limit')
            if final:
                try:
                    return json.loads(message)
                except (ValueError, UnicodeDecodeError) as error:
                    raise ProbeError('The daemon returned malformed JSON') from error

    def request(self, method, params):
        self.request_id += 1
        request_id = self.request_id
        self.send({'id': request_id, 'method': method, 'params': params})
        deadline = time.monotonic() + self.timeout
        while True:
            message = self.receive(deadline)
            # Ignore notifications and server requests; never answer an approval.
            if not isinstance(message, dict) or 'method' in message or message.get('id') != request_id:
                continue
            if 'error' in message:
                error = message['error']
                code = error.get('code') if isinstance(error, dict) else None
                if type(code) is not int or not -(2**31) <= code < 2**31:
                    code = 'unknown'
                raise ProbeError('Read-only RPC failed with code ' + str(code))
            return message.get('result', {})

    def read(self, thread_id, details=False):
        result = self.request('thread/read', {'threadId': thread_id, 'includeTurns': False})
        thread = result.get('thread', {})
        if thread.get('id') != thread_id:
            raise ProbeError('The daemon returned a different thread')
        status = thread.get('status', {})
        result = {'thread_id': thread_id, 'status': status.get('type', 'unknown'),
                  'active_flags': status.get('activeFlags', [])}
        if details:
            def text(key, limit=512):
                value = thread.get(key)
                return value[:limit] if isinstance(value, str) else None
            git = thread.get('gitInfo') or {}
            result.update({
                'name': text('name'), 'cwd': text('cwd', 4096),
                'model': text('model', 160), 'model_provider': text('modelProvider', 160),
                'source': thread.get('source'), 'git_branch': git.get('branch'),
                'parent_thread_id': text('parentThreadId', 160),
                'agent_role': text('agentRole', 160), 'agent_nickname': text('agentNickname', 160),
                'task_preview': text('preview', 500), 'rollout_path': text('path', 4096),
            })
        return result

    def read_limits(self):
        return clean_rate_limits(self.request('account/rateLimits/read', {}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('thread_id', nargs='?')
    parser.add_argument('--codex', default=shutil.which('codex'))
    parser.add_argument('--timeout', type=float, default=10)
    parser.add_argument('--watch-seconds', type=float)
    parser.add_argument('--interval', type=float)
    parser.add_argument('--details', action='store_true', help='Include bounded session metadata for the shared card UI')
    parser.add_argument('--limits', action='store_true', help='Read bounded Codex quota fields once; accepts no thread or watch options')
    args = parser.parse_args()
    if args.limits:
        if args.thread_id is not None or args.details or args.watch_seconds is not None or args.interval is not None:
            parser.error('--limits cannot be combined with a thread ID, --details, --watch-seconds, or --interval')
    elif args.thread_id is None:
        parser.error('thread_id is required unless --limits is selected')
    args.watch_seconds = 0 if args.watch_seconds is None else args.watch_seconds
    args.interval = 1 if args.interval is None else args.interval
    def interrupted(signum, _frame):
        raise SystemExit(128 + signum)
    previous_termination = signal.signal(signal.SIGTERM, interrupted)
    probe = None
    try:
        if not args.limits and not re.fullmatch(r'[A-Za-z0-9_.:-]{1,160}', args.thread_id):
            raise ProbeError('Invalid thread ID')
        if not args.codex:
            raise ProbeError('Codex is not on PATH')
        if not 0 < args.timeout <= 60 or not 0 <= args.watch_seconds <= 300 or not 0.2 <= args.interval <= 10:
            raise ProbeError('Probe duration or interval is outside the supported bounds')
        probe = RuntimeProbe(args.codex, args.timeout)
        probe.connect()
        if args.limits:
            print(json.dumps(probe.read_limits(), sort_keys=True), flush=True)
            return 0
        finish = time.monotonic() + args.watch_seconds
        while True:
            print(json.dumps(probe.read(args.thread_id, details=args.details), sort_keys=True), flush=True)
            if time.monotonic() >= finish:
                break
            time.sleep(min(args.interval, max(0, finish - time.monotonic())))
        return 0
    except (ProbeError, OSError, UnicodeError, ValueError, TypeError, AttributeError) as error:
        result = {'error': str(error)}
        if not args.limits:
            result['thread_id'] = args.thread_id
        print(json.dumps(result), flush=True)
        return 1
    finally:
        try:
            if probe is not None:
                probe.close()
        finally:
            signal.signal(signal.SIGTERM, previous_termination)


if __name__ == '__main__':
    sys.exit(main())
