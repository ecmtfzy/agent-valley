#!/usr/bin/env python3
"""Check hook discovery without running hooks, starting a turn, or using auth.

Usage: python3 testing/check-codex-hooks.py /absolute/path/to/hooks.json

The app-server gets a disposable CODEX_HOME and empty working directory. On
macOS, sandbox-exec denies all network access. Only initialize and hooks/list
are sent. No trust records or user configuration are changed.
"""

import argparse
from collections import Counter
import json
import os
from pathlib import Path
import selectors
import shutil
import signal
import subprocess
import sys
import tempfile
import time


class ProbeError(Exception):
    pass


def probe(config_path, codex, timeout):
    config = json.loads(config_path.read_text(encoding="utf-8"))
    groups = config.get("hooks", {})
    expected = Counter()
    for event, matchers in groups.items():
        if not isinstance(matchers, list):
            raise ProbeError("Each configured hook event must contain a list.")
        expected[event[:1].lower() + event[1:]] = sum(
            len(group.get("hooks", [])) for group in matchers
        )
    if not expected or not sum(expected.values()):
        raise ProbeError("The supplied file contains no hook handlers.")

    sandbox = Path("/usr/bin/sandbox-exec")
    if sys.platform != "darwin" or not sandbox.is_file():
        raise ProbeError("This network-isolated probe requires macOS sandbox-exec.")

    with tempfile.TemporaryDirectory(prefix="agentvalley-hooks-check-") as temporary:
        root = Path(temporary)
        isolated_home = root / "codex-home"
        isolated_cwd = root / "empty-workspace"
        isolated_home.mkdir()
        isolated_cwd.mkdir()
        copied_hooks = isolated_home / "hooks.json"
        shutil.copyfile(config_path, copied_hooks)
        (isolated_home / "config.toml").write_text(
            'cli_auth_credentials_store = "file"\n'
            'check_for_update_on_startup = false\n'
            '[analytics]\nenabled = false\n'
            '[feedback]\nenabled = false\n'
            '[features]\nhooks = true\napps = false\nplugins = false\n',
            encoding="utf-8",
        )
        # Keep runtime essentials only; do not inherit API keys or auth tokens.
        environment = {
            key: os.environ[key]
            for key in ("PATH", "TMPDIR", "LANG", "LC_ALL", "SystemRoot")
            if key in os.environ
        }
        environment["CODEX_HOME"] = str(isolated_home)
        command = [
            str(sandbox), "-p", "(version 1)(allow default)(deny network*)",
            codex, "app-server", "--listen", "stdio://",
        ]
        with (root / "server-stderr.log").open("wb") as stderr:
            process = subprocess.Popen(
                command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                stderr=stderr, cwd=isolated_cwd, env=environment,
                start_new_session=True,
            )
            deadline = time.monotonic() + timeout
            pending = bytearray()
            selector = selectors.DefaultSelector()
            selector.register(process.stdout, selectors.EVENT_READ)

            def send(message):
                try:
                    process.stdin.write((json.dumps(message) + "\n").encode())
                    process.stdin.flush()
                except BrokenPipeError as error:
                    raise ProbeError("The isolated app-server exited before responding.") from error

            def response(request_id):
                while True:
                    while b"\n" in pending:
                        line, _, remainder = pending.partition(b"\n")
                        pending[:] = remainder
                        try:
                            message = json.loads(line)
                        except (ValueError, UnicodeDecodeError) as error:
                            raise ProbeError("The app-server returned invalid JSON.") from error
                        if message.get("id") != request_id:
                            continue
                        if "error" in message:
                            code = message["error"].get("code", "unknown")
                            raise ProbeError(f"App-server request {request_id} failed (code {code}).")
                        return message.get("result", {})
                    remaining = deadline - time.monotonic()
                    if remaining <= 0 or not selector.select(remaining):
                        raise ProbeError("Timed out waiting for the isolated app-server.")
                    chunk = os.read(process.stdout.fileno(), 65536)
                    if not chunk:
                        raise ProbeError("The isolated app-server exited before responding.")
                    pending.extend(chunk)
                    if len(pending) > 8 * 1024 * 1024:
                        raise ProbeError("App-server response exceeded the probe size limit.")

            try:
                send({
                    "id": 1, "method": "initialize",
                    "params": {"clientInfo": {
                        "name": "agentvalley_hook_discovery_check", "version": "0.1.0"
                    }},
                })
                response(1)
                send({"method": "initialized", "params": {}})
                send({
                    "id": 2, "method": "hooks/list",
                    "params": {"cwds": [str(isolated_cwd)]},
                })
                result = response(2)
            finally:
                selector.close()
                # Kill the process group too: app-server may launch helper children.
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=3)
                process.stdin.close()
                process.stdout.close()

        entries = result.get("data", [])
        hooks = [hook for entry in entries for hook in entry.get("hooks", [])
                 if Path(hook.get("sourcePath", "")).resolve() == copied_hooks.resolve()]
        observed = Counter(hook.get("eventName", "unknown") for hook in hooks)
        errors = [error for entry in entries for error in entry.get("errors", [])]
        warnings = [warning for entry in entries for warning in entry.get("warnings", [])]
        trust = Counter(hook.get("trustStatus", "unknown") for hook in hooks)
        ok = observed == expected and not errors and trust == {"untrusted": len(hooks)}
        return {
            "status": "ok" if ok else "failed",
            "expected_handler_count": sum(expected.values()),
            "discovered_handler_count": len(hooks),
            "event_counts": dict(sorted(observed.items())),
            "enabled_count": sum(bool(hook.get("enabled")) for hook in hooks),
            "trust_counts": dict(trust),
            "error_count": len(errors),
            "warning_count": len(warnings),
            "network": "denied",
            "hooks_executed": False,
        }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("hooks_json", type=Path)
    parser.add_argument("--codex", default=shutil.which("codex"))
    parser.add_argument("--timeout", type=float, default=30)
    args = parser.parse_args()
    try:
        if not args.hooks_json.is_absolute() or not args.hooks_json.is_file():
            raise ProbeError("Supply an absolute path to an existing hooks.json file.")
        if not args.codex:
            raise ProbeError("The Codex executable was not found on PATH.")
        if args.timeout <= 0:
            raise ProbeError("The timeout must be greater than zero.")
        summary = probe(args.hooks_json, args.codex, args.timeout)
    except (ProbeError, OSError, ValueError, TypeError, AttributeError) as error:
        summary = {"status": "failed", "errors": [str(error)], "hooks_executed": False}
    print(json.dumps(summary, indent=2, sort_keys=True))
    return 0 if summary["status"] == "ok" else 1


if __name__ == "__main__":
    raise SystemExit(main())
