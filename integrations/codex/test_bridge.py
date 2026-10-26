import concurrent.futures
import importlib.util
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).with_name("bridge.py")
spec = importlib.util.spec_from_file_location("bridge", SCRIPT)
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


class BridgeTests(unittest.TestCase):
    def emit(self, path, payload):
        return subprocess.run([sys.executable, str(SCRIPT), "emit", "--events", str(path)],
                              input=payload, text=True, capture_output=True, timeout=3)

    def test_metadata_only_and_neutral_result(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "events.jsonl"
            result = self.emit(path, json.dumps({
                "hook_event_name": "PreToolUse", "session_id": "thread-1", "turn_id": "turn-1",
                "tool_name": "Bash", "cwd": "/tmp/demo", "model": "example-model",
                "prompt": "PRIVATE", "tool_input": {"command": "PRIVATE"}, "tool_response": "PRIVATE",
                "transcript_path": "/private/transcript",
            }))
            self.assertEqual((result.returncode, result.stdout), (0, "{}\n"))
            self.assertNotIn("PRIVATE", path.read_text())
            event = json.loads(path.read_text())
            self.assertEqual(event["event"], "PreToolUse")
            self.assertNotIn("transcript_path", event)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    def test_malformed_unknown_and_pathlike_ids_are_ignored(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "events.jsonl"
            for payload in ("broken", "[]", json.dumps({"hook_event_name": "Unknown", "session_id": "id"}),
                            json.dumps({"hook_event_name": "Stop", "session_id": "../escape"})):
                result = self.emit(path, payload)
                self.assertEqual((result.returncode, result.stdout), (0, "{}\n"))
            self.assertFalse(path.exists())

    def test_concurrent_append_keeps_whole_records(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "events.jsonl"
            def emit(index):
                return self.emit(path, json.dumps({"hook_event_name": "Stop", "session_id": f"thread-{index}"}))
            with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
                results = list(pool.map(emit, range(24)))
            failures = [{"session_id": f"thread-{index}", "returncode": result.returncode,
                         "stdout": result.stdout, "stderr": result.stderr}
                        for index, result in enumerate(results)
                        if result.returncode != 0 or result.stdout != "{}\n" or result.stderr]
            self.assertFalse(failures, "Concurrent emit failures:\n" + json.dumps(failures, indent=2))
            records = [json.loads(line) for line in path.read_text().splitlines()]
            self.assertEqual(len(records), 24, "Concurrent emit produced missing or extra records")
            self.assertEqual({r["session_id"] for r in records}, {f"thread-{index}" for index in range(24)})

    def test_symlink_and_shared_file_fail_open_without_writing(self):
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder) / "target"
            target.write_text("untouched")
            link = Path(folder) / "events.jsonl"
            link.symlink_to(target)
            payload = json.dumps({"hook_event_name": "PermissionRequest", "session_id": "thread-1"})
            for path in (link, target):
                result = self.emit(path, payload)
                self.assertEqual((result.returncode, result.stdout), (0, "{}\n"))
                self.assertTrue(result.stderr)
            self.assertEqual(target.read_text(), "untouched")

    def test_full_journal_fails_open(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "events.jsonl"
            path.touch(mode=0o600)
            os.truncate(path, bridge.MAX_JOURNAL)
            result = self.emit(path, json.dumps({"hook_event_name": "Stop", "session_id": "thread-1"}))
            self.assertEqual((result.returncode, result.stdout), (0, "{}\n"))
            self.assertTrue(result.stderr)
            self.assertEqual(path.stat().st_size, bridge.MAX_JOURNAL)

    def test_configuration_is_complete_and_bounded(self):
        config = bridge.configuration("/tmp/an event folder/events.jsonl")
        self.assertEqual(set(config["hooks"]), set(bridge.EVENTS))
        for groups in config["hooks"].values():
            handler = groups[0]["hooks"][0]
            self.assertEqual(handler["timeout"], 2)
            self.assertNotIn("async", handler)
            self.assertEqual(shlex.split(handler["command"])[-1], str(Path("/tmp/an event folder/events.jsonl").resolve()))


if __name__ == "__main__":
    unittest.main()
