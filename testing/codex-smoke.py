#!/usr/bin/env python3
"""Replay synthetic hooks through the real bridge and compiled read-only diagnostic."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess
import sys
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    binary = args.binary.resolve()
    bridge = root / "integrations/codex/bridge.py"
    with tempfile.TemporaryDirectory(prefix="agentvalley-codex-smoke-") as folder:
        journal = Path(folder) / "events.jsonl"
        snapshots = []

        def emit(name, **fields):
            payload = dict(hook_event_name=name, session_id="synthetic-session", cwd=str(root),
                           model="synthetic-model", turn_id="turn-1", **fields)
            result = subprocess.run([sys.executable, str(bridge), "emit", "--events", str(journal)],
                                    input=json.dumps(payload), text=True, capture_output=True, timeout=3, check=True)
            assert result.stdout == "{}\n" and not result.stderr, result

        def check(label, main, child=None, closed=False):
            result = subprocess.run([str(binary), "codex-status", str(journal)], text=True,
                                    capture_output=True, timeout=10, check=True)
            cards = json.loads(result.stdout)
            assert len(cards) == 1, cards
            card = cards[0]
            assert card["id"] == "codex-synthetic-session", card
            assert card["closed"] == closed, card
            assert card["rows"][0]["status"] == main, card
            if child:
                assert len(card["rows"]) == 2 and card["rows"][1]["status"] == child, card
                assert card["rows"][1]["model"] == "", card
            snapshots.append({"phase": label, "main": main, "child": child, "closed": closed})

        def internal(name, **fields):
            # Internal bridge outcomes are synthetic fixtures, never approvals sent to Codex.
            event = dict(version=1, event=name, session_id="synthetic-session", cwd=str(root),
                         turn_id="turn-1", timestamp=datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z"),
                         **fields)
            with journal.open("a") as stream:
                stream.write(json.dumps(event) + "\n")

        emit("SessionStart")
        check("session start", "quiet")
        emit("UserPromptSubmit")
        emit("PreToolUse", tool_name="Bash", tool_use_id="tool-1", tool_input={"command": "PRIVATE INPUT"})
        check("tool running", "working")
        # PermissionRequest's documented schema has no tool_use_id.
        emit("PermissionRequest", tool_name="Bash")
        check("approval requested", "needsYou")
        emit("PostToolUse", tool_name="Bash", tool_use_id="tool-1", tool_response="PRIVATE OUTPUT")
        check("tool complete", "working")
        emit("SubagentStart", agent_id="child-1", agent_type="explore")
        check("child started", "working", "working")
        emit("Stop")
        check("parent complete", "done", "working")
        emit("SubagentStop", agent_id="child-1", agent_type="explore")
        check("child complete", "done", "done")
        emit("UserPromptSubmit")
        check("same-turn continuation", "working", "done")
        emit("SessionEnd")
        check("session closed", "done", "done", closed=True)
        assert "PRIVATE" not in journal.read_text(), "Raw tool data was persisted"
        emit("UserPromptSubmit")
        emit("PreToolUse", tool_name="Bash", tool_use_id="parallel-a")
        internal("PermissionRequest", tool_name="Bash", request_id="00000000-0000-4000-8000-000000000001")
        emit("PreToolUse", tool_name="Edit", tool_use_id="parallel-b")
        internal("PermissionRequest", tool_name="Edit", request_id="00000000-0000-4000-8000-000000000002")
        check("two explicit approvals pending", "needsYou", "done")
        internal("PermissionResolved", request_id="00000000-0000-4000-8000-000000000099", decision="allow")
        check("unknown approval cannot clear pending requests", "needsYou", "done")
        internal("PermissionResolved", request_id="00000000-0000-4000-8000-000000000001", decision="allow")
        check("approval A leaves B pending", "needsYou", "done")
        internal("PermissionResolved", request_id="00000000-0000-4000-8000-000000000001", decision="deny")
        check("duplicate resolution cannot clear B", "needsYou", "done")
        internal("PermissionResolved", request_id="00000000-0000-4000-8000-000000000002", decision="allow")
        check("both approvals answered before either tool result", "working", "done")
        emit("PostToolUse", tool_name="Bash", tool_use_id="parallel-a")
        emit("PostToolUse", tool_name="Edit", tool_use_id="parallel-b")
        emit("SessionEnd")
        check("approval replay session closed", "done", "done", closed=True)
    print(json.dumps({"status": "ok", "synthetic": True, "phases": snapshots}, indent=2))


if __name__ == "__main__":
    main()
