"""Private fake-socket tests; no real agent is contacted or command executed."""
import concurrent.futures
import importlib.util
import json
import os
from pathlib import Path
import socket
import tempfile
import threading
import unittest

SCRIPT = Path(__file__).with_name("bridge.py")
spec = importlib.util.spec_from_file_location("answer_bridge", SCRIPT)
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


def decision(behavior, **extra):
    return {"hookSpecificOutput": {"hookEventName": "PermissionRequest",
                                    "decision": dict(behavior=behavior, **extra)}}


class FakeNotch:
    def __init__(self, path, reply, *, wait=False, status="200 OK"):
        self.path = path
        self.reply = json.dumps(reply).encode() if reply is not None else b""
        self.status = status
        self.received = threading.Event()
        self.release = threading.Event()
        if not wait:
            self.release.set()
        self.input = None
        self.error = None
        self.listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.listener.bind(str(path))
        os.chmod(path, 0o600)
        self.listener.listen(1)
        self.listener.settimeout(3)
        self.thread = threading.Thread(target=self.serve, daemon=True)

    def __enter__(self):
        self.thread.start()
        return self

    def serve(self):
        try:
            with self.listener.accept()[0] as connection:
                connection.settimeout(3)
                data = bytearray()
                while b"\r\n\r\n" not in data:
                    chunk = connection.recv(4096)
                    if not chunk:
                        return
                    data.extend(chunk)
                header, _, body = data.partition(b"\r\n\r\n")
                self.endpoint = header.split(b"\r\n", 1)[0].decode("ascii")
                length = int(next(line.split(b":", 1)[1] for line in header.split(b"\r\n")
                                  if line.lower().startswith(b"content-length:")))
                while len(body) < length:
                    body.extend(connection.recv(length - len(body)))
                self.input = json.loads(body)
                self.received.set()
                self.release.wait(3)
                response = ("HTTP/1.1 " + self.status + "\r\nContent-Length: "
                            + str(len(self.reply)) + "\r\nConnection: close\r\n\r\n").encode()
                try:
                    connection.sendall(response + self.reply)
                except (BrokenPipeError, ConnectionResetError):
                    pass  # Expected when the bridge times out and declines to decide.
        except Exception as error:
            self.error = error

    def __exit__(self, *_):
        self.release.set()
        self.thread.join(3)
        self.listener.close()
        if self.path.exists():
            self.path.unlink()
        if self.error:
            raise self.error


class AnswerBridgeTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory(prefix="av-answers-", dir="/tmp")
        self.path = Path(self.folder.name)
        self.journal = self.path / "events.jsonl"
        self.socket = self.path / "answers.sock"
        self.payload = {
            "hook_event_name": "PermissionRequest", "session_id": "thread-1", "turn_id": "turn-1",
            "model": "test-model", "tool_name": "Bash", "cwd": "/tmp/project",
            "tool_input": {"command": "echo PRIVATE_TEST_MARKER", "description": "Only prints a marker"},
            "transcript_path": "/private/real-transcript.jsonl", "prompt": "PRIVATE_PROMPT",
        }

    def tearDown(self):
        self.folder.cleanup()

    def events(self):
        return [json.loads(line) for line in self.journal.read_text().splitlines()]

    def test_allow_waits_for_explicit_reply_and_resolves_only_its_request(self):
        with FakeNotch(self.socket, decision("allow"), wait=True) as notch:
            with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
                result = pool.submit(bridge.process_event, self.payload, self.journal, True, self.socket, 2)
                self.assertTrue(notch.received.wait(1))
                self.assertFalse(result.done())
                self.assertEqual([row["event"] for row in self.events()], ["PermissionRequest"])
                self.assertEqual(notch.input["transcript_path"], "codex-thread-1.jsonl")
                self.assertEqual(notch.input["session_id"], "codex-thread-1")
                self.assertEqual(notch.input["tool_input"], self.payload["tool_input"])
                self.assertNotIn("prompt", notch.input)
                notch.release.set()
                self.assertEqual(result.result(timeout=2), decision("allow"))
        rows = self.events()
        self.assertEqual([row["event"] for row in rows], ["PermissionRequest", "PermissionResolved"])
        self.assertEqual(rows[0]["request_id"], rows[1]["request_id"])
        self.assertEqual(rows[0]["session_id"], rows[1]["session_id"])
        self.assertEqual(rows[0]["turn_id"], rows[1]["turn_id"])
        self.assertEqual(rows[1]["decision"], "allow")
        self.assertNotIn("PRIVATE", self.journal.read_text())
        self.assertEqual(self.journal.stat().st_mode & 0o777, 0o600)

    def test_deny_is_once_only_and_carries_the_existing_ui_reason(self):
        answer = decision("deny", message="Denied from the notch.")
        with FakeNotch(self.socket, answer):
            self.assertEqual(bridge.process_event(self.payload, self.journal, True, self.socket, 1), answer)
        self.assertEqual(self.events()[-1]["decision"], "deny")

    def test_missing_socket_and_timeout_decline_without_resolving(self):
        self.assertEqual(bridge.process_event(self.payload, self.journal, True, self.socket, 0.1), {})
        with FakeNotch(self.socket, decision("allow"), wait=True):
            self.assertEqual(bridge.process_event(self.payload, self.journal, True, self.socket, 0.1), {})
        self.assertEqual([row["event"] for row in self.events()], ["PermissionRequest", "PermissionRequest"])
        self.assertNotEqual(self.events()[0]["request_id"], self.events()[1]["request_id"])

    def test_empty_or_rewrite_reply_is_never_treated_as_permission(self):
        for response in ({}, decision("allow", updatedInput={"command": "different"}),
                         decision("allow", updatedPermissions=[]), decision("acceptForSession")):
            with FakeNotch(self.socket, response):
                self.assertEqual(bridge.process_event(self.payload, self.journal, True, self.socket, 1), {})
        self.assertTrue(all(row["event"] == "PermissionRequest" for row in self.events()))

    def test_shared_or_symlinked_socket_is_rejected(self):
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as listener:
            listener.bind(str(self.socket))
            os.chmod(self.socket, 0o666)
            self.assertFalse(bridge.private_socket(self.socket))
            os.chmod(self.socket, 0o600)
            link = self.path / "link.sock"
            link.symlink_to(self.socket)
            self.assertFalse(bridge.private_socket(link))
            os.chmod(self.path, 0o755)
            self.assertFalse(bridge.private_socket(self.socket))
            os.chmod(self.path, 0o700)
            self.assertTrue(bridge.private_socket(self.socket))

    def test_disabled_observer_and_other_events_never_open_the_answer_socket(self):
        # A listening endpoint without an accept thread proves these paths do not wait.
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as listener:
            listener.bind(str(self.socket))
            os.chmod(self.socket, 0o600)
            listener.listen(1)
            self.assertEqual(bridge.process_event(self.payload, self.journal, False, self.socket, 1), {})
            for event in ("Stop", "PreToolUse", "PostToolUse"):
                payload = dict(self.payload, hook_event_name=event)
                self.assertEqual(bridge.process_event(payload, self.journal, True, self.socket, 1), {})
            listener.settimeout(0.05)
            with self.assertRaises(socket.timeout):
                listener.accept()
        self.assertTrue(all("request_id" not in row for row in self.events()))

    def test_question_rewrite_contracts_are_not_offered_as_permission_buttons(self):
        self.assertIsNone(bridge.answer_request(dict(self.payload, tool_name="AskUserQuestion")))
        self.assertIsNone(bridge.answer_request(dict(self.payload, tool_name="ExitPlanMode")))
        self.assertIsNone(bridge.answer_request(dict(self.payload, tool_input=["unsupported"])))

    def test_only_permission_hook_gets_interactive_configuration(self):
        config = bridge.configuration("/tmp/events.jsonl", answers=True)
        for event, entries in config["hooks"].items():
            handler = entries[0]["hooks"][0]
            self.assertEqual(handler["timeout"], 600 if event == "PermissionRequest" else 2)
            self.assertEqual(" --answers" in handler["command"], event == "PermissionRequest")

    def test_stop_only_relays_queued_user_words_while_away(self):
        payload = dict(self.payload, hook_event_name="Stop")
        reply = {"decision": "block", "reason": "The user's queued follow-up"}
        with FakeNotch(self.socket, reply) as notch:
            (self.path / "away").touch(mode=0o600)
            result = bridge.process_event(payload, self.journal, socket_path=self.socket,
                                          messages=True, message_timeout=1)
            self.assertEqual(result, reply)
            self.assertEqual(notch.endpoint, "POST /stop-wait HTTP/1.1")
            self.assertEqual(notch.input["transcript_path"], "codex-thread-1.jsonl")
            self.assertNotIn("tool_input", notch.input)
            self.assertNotIn("prompt", notch.input)
        self.assertEqual([event["event"] for event in self.events()], ["Stop"])
        self.assertNotIn(reply["reason"], self.journal.read_text())

    def test_stop_without_away_never_connects_or_blocks_turn_completion(self):
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as listener:
            listener.bind(str(self.socket))
            os.chmod(self.socket, 0o600)
            listener.listen(1)
            self.assertEqual(bridge.process_event(dict(self.payload, hook_event_name="Stop"),
                             self.journal, socket_path=self.socket, messages=True, message_timeout=1), {})
            listener.settimeout(0.05)
            with self.assertRaises(socket.timeout):
                listener.accept()

    def test_stop_rejects_empty_reasons_and_wrong_output_contracts(self):
        (self.path / "away").touch(mode=0o600)
        for reply in ({}, decision("allow"), {"decision": "block", "reason": ""},
                      {"decision": "block", "reason": "message", "continue": True}):
            with FakeNotch(self.socket, reply):
                self.assertEqual(bridge.process_event(dict(self.payload, hook_event_name="Stop"),
                                 self.journal, socket_path=self.socket, messages=True, message_timeout=1), {})

    def test_interactive_handlers_are_scoped_and_bounded(self):
        config = bridge.configuration("/tmp/events.jsonl", answers=True, messages=True, display_inputs=True)
        for event, entries in config["hooks"].items():
            handler = entries[0]["hooks"][0]
            self.assertEqual(" --answers" in handler["command"], event == "PermissionRequest")
            self.assertEqual(" --messages" in handler["command"], event == "Stop")
            self.assertEqual(" --display-inputs" in handler["command"], event == "PreToolUse")
            self.assertEqual(handler["timeout"], {"PermissionRequest": 600, "Stop": 86400}.get(event, 2))

    def test_display_inputs_are_opt_in_selected_and_bounded(self):
        payload = dict(self.payload, hook_event_name="PreToolUse", tool_input={
            "command": "print marker", "description": "Display description", "api_key": "PRIVATE_KEY",
            "file_path": "/tmp/file", "prompt": "PRIVATE_PROMPT", "nested": {"secret": "PRIVATE_NESTED"},
            "query": "字" * 5000, "pattern": "x" * 5000, "url": "u" * 5000,
        })
        self.assertEqual(bridge.process_event(payload, self.journal, display_inputs=True), {})
        row = self.events()[0]
        self.assertEqual(row["display_input"]["command"], "print marker")
        self.assertEqual(row["display_input"]["description"], "Display description")
        self.assertLessEqual(len(json.dumps(row["display_input"], ensure_ascii=True,
                                           separators=(",", ":")).encode()), bridge.MAX_DISPLAY_INPUT)
        self.assertTrue(row["display_truncated"])
        self.assertNotIn("PRIVATE", self.journal.read_text())
        bridge.process_event(dict(payload, hook_event_name="PostToolUse"), self.journal, display_inputs=True)
        self.assertNotIn("display_input", self.events()[-1])


if __name__ == "__main__":
    unittest.main()
