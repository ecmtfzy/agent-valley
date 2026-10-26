#!/usr/bin/env python3
"""Observe Codex hooks; optionally relay explicit notch Allow/Deny clicks."""

import argparse
import ctypes
import datetime
import fcntl
import json
import os
from pathlib import Path
import re
import shlex
import socket
import stat
import struct
import sys
import time
import uuid

EVENTS = (
    "SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest",
    "PostToolUse", "SubagentStart", "SubagentStop", "Stop", "Interrupt",
    "SessionEnd", "PreCompact", "PostCompact",
)
MAX_INPUT = 1024 * 1024
MAX_JOURNAL = 16 * 1024 * 1024
MAX_REPLY = 8192
ANSWER_WAIT = 590
MESSAGE_WAIT = 86390
MAX_DISPLAY_INPUT = 8 * 1024
ID = re.compile(r"[A-Za-z0-9_.:-]{1,128}\Z")


def normalize(payload):
    if not isinstance(payload, dict):
        return None
    event = payload.get("hook_event_name")
    session = payload.get("session_id")
    if event not in EVENTS or not isinstance(session, str) or not ID.fullmatch(session):
        return None
    result = {"version": 1, "event": event, "session_id": session}
    for key in ("turn_id", "tool_use_id", "agent_id"):
        value = payload.get(key)
        if isinstance(value, str) and ID.fullmatch(value):
            result[key] = value
    for key, limit in (("cwd", 4096), ("model", 160), ("tool_name", 160), ("agent_type", 160)):
        value = payload.get(key)
        if isinstance(value, str):
            result[key] = "".join(c for c in value[:limit] if c.isprintable())
    # No prompts, transcript paths, tool arguments, outputs, or credentials leave stdin.
    return result


def display_input(payload):
    """A bounded step summary, never the full arguments used to approve a request."""
    values = payload.get("tool_input")
    if not isinstance(values, dict):
        return {}, False
    shown, shortened = {}, False
    for key in ("command", "description", "file_path", "path", "pattern", "query", "url", "name"):
        value = values.get(key)
        if not isinstance(value, str) or not value:
            continue
        original = value
        value = value.encode("utf-8")[:2048].decode("utf-8", errors="ignore")
        truncated = value != original
        def candidate(prefix):
            return dict(shown, **{key: prefix + ("…" if truncated or prefix != value else "")})
        def size(value):
            return len(json.dumps(value, ensure_ascii=True, separators=(",", ":")).encode())
        if size(candidate(value)) > MAX_DISPLAY_INPUT:
            low, high = 0, len(value)
            while low < high:
                middle = (low + high + 1) // 2
                if size(candidate(value[:middle])) <= MAX_DISPLAY_INPUT:
                    low = middle
                else:
                    high = middle - 1
            if low == 0:
                shortened = True
                continue
            shown = candidate(value[:low])
            shortened = True
        else:
            shown = candidate(value)
            shortened = shortened or truncated
    return shown, shortened


def append_event(path, event):
    path = Path(path)
    if not path.is_absolute():
        raise ValueError("The event journal path must be absolute")
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_CREAT | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
            raise ValueError("The event journal must be a private regular file owned by you")
        deadline = time.monotonic() + 0.25
        while True:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise TimeoutError("The event journal is busy")
                time.sleep(0.01)
        event = dict(event)
        event["timestamp"] = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")
        data = (json.dumps(event, ensure_ascii=True, separators=(",", ":")) + "\n").encode()
        if os.fstat(fd).st_size + len(data) > MAX_JOURNAL:
            raise ValueError("The prototype journal is full; stop the preview and remove its journal before restarting")
        written = os.write(fd, data)
        if written != len(data):
            raise OSError("Incomplete event journal write")
    finally:
        os.close(fd)


def default_answer_socket():
    return Path.home() / "Library/Application Support/AgentValley/answers.sock"


def private_socket(path):
    """The existing app creates a 0700 directory and 0600 socket owned by this uid."""
    path = Path(path)
    if not path.is_absolute():
        return False
    try:
        folder, endpoint = path.parent.lstat(), path.lstat()
    except OSError:
        return False
    return (stat.S_ISDIR(folder.st_mode) and folder.st_uid == os.getuid()
            and not folder.st_mode & 0o077 and stat.S_ISSOCK(endpoint.st_mode)
            and endpoint.st_uid == os.getuid() and not endpoint.st_mode & 0o077)


def own_peer(connection):
    """Check the connected peer too, rather than relying solely on its path."""
    if sys.platform == "darwin":
        uid, gid = ctypes.c_uint(), ctypes.c_uint()
        getpeereid = ctypes.CDLL(None, use_errno=True).getpeereid
        getpeereid.argtypes = [ctypes.c_int, ctypes.POINTER(ctypes.c_uint), ctypes.POINTER(ctypes.c_uint)]
        getpeereid.restype = ctypes.c_int
        return getpeereid(connection.fileno(), ctypes.byref(uid), ctypes.byref(gid)) == 0 and uid.value == os.getuid()
    if hasattr(socket, "SO_PEERCRED"):
        credentials = connection.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, struct.calcsize("3i"))
        return struct.unpack("3i", credentials)[1] == os.getuid()
    return False


def answer_request(payload):
    """Adapt only a permission request to the existing Claude-shaped local UI protocol.

    The transcript field is an identity token only: AnswerProtocol takes its basename
    and never opens it. No real transcript path or prompt is sent. Full tool input is
    kept in memory for the UI so the person's Allow button cannot hide an argument.
    """
    event = normalize(payload)
    if event is None or event["event"] != "PermissionRequest":
        return None
    tool, tool_input = payload.get("tool_name"), payload.get("tool_input")
    if not isinstance(tool, str) or not tool or not isinstance(tool_input, dict):
        return None
    # Codex PermissionRequest cannot accept Claude's updatedInput question answers.
    if tool in ("AskUserQuestion", "ExitPlanMode"):
        return None
    return {"hook_event_name": "PermissionRequest", "session_id": "codex-" + event["session_id"],
            "transcript_path": "codex-" + event["session_id"] + ".jsonl",
            "tool_name": tool, "tool_input": tool_input}


def clean_decision(body):
    """Accept only the existing UI's once-only Allow/Deny replies, never rewrites."""
    try:
        result = json.loads(body)
        output = result["hookSpecificOutput"]
        decision = output["decision"]
        if (set(result) != {"hookSpecificOutput"}
                or set(output) != {"hookEventName", "decision"}
                or output["hookEventName"] != "PermissionRequest"
                or not isinstance(decision, dict)
                or set(decision) - {"behavior", "message"}):
            return None
        behavior = decision.get("behavior")
        if behavior not in ("allow", "deny"):
            return None
        clean = {"behavior": behavior}
        if behavior == "deny" and "message" in decision:
            if not isinstance(decision["message"], str) or len(decision["message"]) > 4096:
                return None
            clean["message"] = decision["message"]
        return {"hookSpecificOutput": {"hookEventName": "PermissionRequest", "decision": clean}}
    except (ValueError, TypeError, KeyError, AttributeError):
        return None


def local_reply(request, path, endpoint, timeout, max_reply=MAX_REPLY):
    if not private_socket(path):
        return None
    body = json.dumps(request, ensure_ascii=True, separators=(",", ":")).encode()
    if len(body) > MAX_INPUT or not 0 < timeout <= MESSAGE_WAIT:
        return None
    header = ("POST " + endpoint + " HTTP/1.1\r\nHost: notch\r\n"
              "Content-Type: application/json\r\nContent-Length: " + str(len(body))
              + "\r\nConnection: close\r\n\r\n").encode("ascii")
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
            connection.settimeout(min(1, timeout))
            connection.connect(str(path))
            if not own_peer(connection):
                return None
            deadline = time.monotonic() + timeout
            connection.sendall(header + body)
            received = bytearray()
            while b"\r\n\r\n" not in received:
                connection.settimeout(max(0.001, deadline - time.monotonic()))
                chunk = connection.recv(4096)
                if not chunk or time.monotonic() >= deadline:
                    return None
                received.extend(chunk)
                if len(received) > 16 * 1024 + max_reply:
                    return None
            response_header, _, response_body = received.partition(b"\r\n\r\n")
            if len(response_header) > 16 * 1024:
                return None
            lines = response_header.decode("ascii").split("\r\n")
            if lines[0] not in ("HTTP/1.1 200 OK", "HTTP/1.0 200 OK"):
                return None
            headers = {}
            for line in lines[1:]:
                name, value = line.split(":", 1)
                name = name.lower()
                if name in headers:
                    return None
                headers[name] = value.strip()
            if "transfer-encoding" in headers:
                return None
            length = int(headers.get("content-length", "-1"))
            if not 0 < length <= max_reply or len(response_body) > length:
                return None
            while len(response_body) < length:
                connection.settimeout(max(0.001, deadline - time.monotonic()))
                chunk = connection.recv(length - len(response_body))
                if not chunk or time.monotonic() >= deadline:
                    return None
                response_body.extend(chunk)
            return response_body
    except (OSError, ValueError, TypeError, AttributeError):
        return None


def permission_reply(payload, socket_path=None, timeout=ANSWER_WAIT):
    request = answer_request(payload)
    path = Path(socket_path) if socket_path is not None else default_answer_socket()
    if request is None or not 0 < timeout <= ANSWER_WAIT:
        return None
    body = local_reply(request, path, "/permission-request", timeout)
    return clean_decision(body) if body is not None else None


def stop_reply(payload, socket_path=None, timeout=MESSAGE_WAIT):
    event = normalize(payload)
    path = Path(socket_path) if socket_path is not None else default_answer_socket()
    if event is None or event["event"] != "Stop" or not private_socket(path):
        return None
    try:
        flag = (path.parent / "away").lstat()
        if not stat.S_ISREG(flag.st_mode) or flag.st_uid != os.getuid() or flag.st_mode & 0o022:
            return None
    except OSError:
        return None
    request = {"hook_event_name": "Stop", "session_id": "codex-" + event["session_id"],
               "transcript_path": "codex-" + event["session_id"] + ".jsonl"}
    body = local_reply(request, path, "/stop-wait", timeout, max_reply=MAX_INPUT)
    if body is None:
        return None
    try:
        result = json.loads(body)
        if (not isinstance(result, dict) or set(result) != {"decision", "reason"}
                or result["decision"] != "block" or not isinstance(result["reason"], str)
                or not result["reason"].strip()):
            return None
        return {"decision": "block", "reason": result["reason"]}
    except (ValueError, TypeError):
        return None


def process_event(payload, events_path, answers=False, socket_path=None, timeout=ANSWER_WAIT,
                  messages=False, message_timeout=MESSAGE_WAIT, display_inputs=False):
    event = normalize(payload)
    if event is None:
        return {}
    interactive = answers and event["event"] == "PermissionRequest"
    if interactive:
        event["request_id"] = str(uuid.uuid4())
    if display_inputs and event["event"] == "PreToolUse":
        shown, shortened = display_input(payload)
        if shown:
            event["display_input"] = shown
            if shortened:
                event["display_truncated"] = True
    append_event(events_path, event)
    if messages and event["event"] == "Stop":
        return stop_reply(payload, socket_path=socket_path, timeout=message_timeout) or {}
    if not interactive:
        return {}
    reply = permission_reply(payload, socket_path=socket_path, timeout=timeout)
    if reply is None:
        return {}
    # Only a concrete valid UI decision resolves this precise wait. The marker is
    # metadata-only, including when the tool has no hook tool_use_id.
    resolved = dict(event, event="PermissionResolved",
                    decision=reply["hookSpecificOutput"]["decision"]["behavior"])
    try:
        append_event(events_path, resolved)
    except (OSError, ValueError):
        pass  # A diagnostic write cannot revoke the person's explicit decision.
    return reply


def configuration(events_path, answers=False, messages=False, display_inputs=False):
    command = shlex.join([sys.executable, str(Path(__file__).resolve()), "emit", "--events", str(Path(events_path).resolve())])
    def handler(event):
        if answers and event == "PermissionRequest":
            return {"type": "command", "command": command + " --answers", "timeout": 600}
        if messages and event == "Stop":
            return {"type": "command", "command": command + " --messages", "timeout": 86400}
        if display_inputs and event == "PreToolUse":
            return {"type": "command", "command": command + " --display-inputs", "timeout": 2}
        return {"type": "command", "command": command, "timeout": 2}
    return {
        "description": "AgentValley hooks; interactive replies only from explicit user actions." if answers or messages else "AgentValley status observation only.",
        "hooks": {event: [{"hooks": [handler(event)]}] for event in EVENTS},
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("emit", "config"))
    parser.add_argument("--events", required=True, help="Absolute path to the local event journal")
    parser.add_argument("--answers", action="store_true", help="Relay PermissionRequest to the existing notch Allow/Deny buttons")
    parser.add_argument("--messages", action="store_true", help="Relay Stop to the existing Away message queue when Away is on")
    parser.add_argument("--display-inputs", action="store_true", help="Keep bounded local tool step text for the shared card display")
    args = parser.parse_args()
    if args.action == "config":
        print(json.dumps(configuration(args.events, answers=args.answers, messages=args.messages,
                                       display_inputs=args.display_inputs), indent=2))
        return 0
    reply = {}
    try:
        raw = sys.stdin.buffer.read(MAX_INPUT + 1)
        if len(raw) <= MAX_INPUT:
            reply = process_event(json.loads(raw), args.events, answers=args.answers, messages=args.messages,
                                  display_inputs=args.display_inputs)
    except (OSError, ValueError, TypeError, RecursionError) as error:
        # Missing UI, delivery errors and every other hook leave Codex in control.
        print("AgentValley status event skipped: " + str(error), file=sys.stderr)
    print(json.dumps(reply, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
