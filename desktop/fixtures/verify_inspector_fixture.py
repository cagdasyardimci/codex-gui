"""Verify installed sources, commands, and scoped child conversation paging."""

import argparse
from base64 import b64decode
import json
import os
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory

from verify_coding_probe import fixture_executable


def turn(identity, items):
    return {"id": identity, "status": "completed", "items": items}


def threads():
    first = turn("first-inspector", [
        {"id": "prompt", "type": "userMessage", "content": [
            {"type": "text", "text": "Inspect the first source"},
            {"type": "localImage", "path": "inspector.png"},
        ]},
        {"id": "site", "type": "webSearch", "query": "Fixture documentation",
         "action": {"type": "openPage", "url": "https://example.invalid/guide"}},
        {"id": "lookup", "type": "mcpToolCall", "server": "fixture", "tool": "lookup", "status": "completed",
         "result": {"content": [{"type": "text", "text": "Lookup fixture result"}]}},
        {"id": "child-review", "type": "subAgentActivity", "kind": "started",
         "agentThreadId": "inspector-child-review", "agentPath": "parent/Review_notes"},
        {"id": "child-slow", "type": "subAgentActivity", "kind": "started",
         "agentThreadId": "inspector-child-slow", "agentPath": "parent/Slow_worker"},
    ])
    second = turn("second-inspector", [
        {"id": "second-command", "type": "commandExecution", "command": "second command",
         "aggregatedOutput": "second output", "status": "completed", "exitCode": 0},
    ])
    children = [turn(f"child-turn-{number:02d}", [
        {"id": "response", "type": "agentMessage", "text": f"Saved child result {number}"},
    ]) for number in range(1, 26)]
    return [
        {"id": "history-first", "name": "First fixture chat", "preview": "", "turns": [first]},
        {"id": "history-second", "name": "Second fixture chat", "preview": "", "turns": [second]},
        {"id": "inspector-child-review", "name": "Review notes", "preview": "", "turns": children},
        {"id": "inspector-child-slow", "name": "Slow worker", "preview": "", "turns": children[-1:]},
    ]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    args = parser.parse_args()
    with TemporaryDirectory(prefix="codex-gui-inspector-") as scratch:
        root = Path(scratch).resolve()
        project = root / "Inspector checkout"
        profile = root / "codex home"
        project.mkdir()
        profile.mkdir()
        (project / "inspector.png").write_bytes(b64decode(
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGMQSTnxHwAEEAJAKtk0QwAAAABJRU5ErkJggg=="
        ))
        trace = root / "trace.jsonl"
        state = root / "backend.json"
        state.write_text(json.dumps({"threads": threads()}), encoding="utf-8")
        result = subprocess.run(
            [args.app.resolve(strict=True), "--verify-inspector", root / "desktop", project],
            env={
                **os.environ,
                "CODEX_HOME": str(profile),
                "CODEX_EXECUTABLE": str(fixture_executable(root)),
                "CODEX_GUI_QA_SCENARIO": "desktop-inspector",
                "CODEX_GUI_QA_TRACE": str(trace),
                "CODEX_GUI_QA_STATE": str(state),
                "PYTHONIOENCODING": "utf-8",
            },
            capture_output=True, encoding="utf-8", errors="replace", timeout=85,
        )
        print(result.stdout, end="")
        if result.returncode or "Verified installed scoped conversation inspectors" not in result.stdout:
            raise SystemExit(result.stderr or "The installed inspector fixture did not complete")
        records = [json.loads(line) for line in trace.read_text(encoding="utf-8").splitlines()]
        requests = [entry for entry in records if entry["direction"] == "request"]
        child = [entry for entry in requests if entry.get("threadId") == "inspector-child-review"]
        assert [entry["method"] for entry in child] == [
            "thread/read", "thread/turns/list", "thread/turns/list", "thread/turns/list",
        ], child
        assert [entry.get("cursor") for entry in child[1:]] == [None, None, "child-turn-06"], child
        assert len([record for record in records if record["direction"] == "event"
                    and record.get("method") == "item/agentMessage/delta"
                    and record.get("threadId") == "inspector-child-review"]) == 4
        assert not any(entry.get("threadId") == "unrecorded-child" for entry in requests)
        assert not any(entry["method"] in ("thread/start", "turn/start") for entry in requests)
        assert not list(profile.iterdir())
        print("Verified source ownership, per-chat inspector selection, child paging, and one coalesced live refresh")


if __name__ == "__main__":
    main()
