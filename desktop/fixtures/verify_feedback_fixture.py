"""Verify installed feedback scope, request privacy, and recovery without replay."""

import argparse
from contextlib import closing
import json
import os
from pathlib import Path
import sqlite3
import subprocess
from tempfile import TemporaryDirectory

from verify_coding_probe import fixture_executable


def thread(name):
    return {
        "id": f"history-{name}", "name": f"{name.title()} fixture chat", "preview": "",
        "turns": [{"id": f"{name}-feedback-turn", "status": "completed", "items": [
            {"id": f"{name}-response", "type": "agentMessage", "text": f"The {name} fixture response."},
        ]}],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    args = parser.parse_args()
    with TemporaryDirectory(prefix="codex-gui-feedback-") as scratch:
        root = Path(scratch).resolve()
        project = root / "Feedback checkout"
        profile = root / "codex home"
        project.mkdir()
        profile.mkdir()
        trace = root / "trace.jsonl"
        state = root / "backend.json"
        data = root / "desktop"
        threads = [thread(name) for name in ("first", "second", "third")]
        threads[0]["turns"].append({"id": "user-only-turn", "status": "completed", "items": [
            {"id": "user-only-prompt", "type": "userMessage", "content": [
                {"type": "text", "text": "No assistant response in this turn."},
            ]},
        ]})
        state.write_text(json.dumps({"threads": threads, "config": {"feedback": {"enabled": True}}}), encoding="utf-8")
        result = subprocess.run(
            [args.app.resolve(strict=True), "--verify-feedback", data, project],
            env={**os.environ, "CODEX_HOME": str(profile), "CODEX_EXECUTABLE": str(fixture_executable(root)),
                 "CODEX_GUI_QA_SCENARIO": "desktop-feedback", "CODEX_GUI_QA_TRACE": str(trace),
                 "CODEX_GUI_QA_STATE": str(state), "PYTHONIOENCODING": "utf-8"},
            capture_output=True, encoding="utf-8", errors="replace", timeout=75,
        )
        print(result.stdout, end="")
        if result.returncode or "Verified installed scoped turn feedback" not in result.stdout:
            raise SystemExit(result.stderr or "The installed feedback fixture did not complete")
        records = [json.loads(line) for line in trace.read_text(encoding="utf-8").splitlines()]
        requests = [entry for entry in records if entry["direction"] == "request"]
        uploads = [entry["params"] for entry in requests if entry["method"] == "feedback/upload"]
        assert uploads == [
            {"classification": "good_result", "threadId": "history-first", "includeLogs": False,
             "tags": {"turn_id": "first-feedback-turn"}},
            {"classification": "bad_result", "threadId": "history-second", "includeLogs": False,
             "tags": {"turn_id": "second-feedback-turn"}},
        ], uploads
        assert not any(entry["method"] in ("thread/start", "turn/start") for entry in requests)
        with closing(sqlite3.connect(data / "workspace.sqlite3")) as database:
            saved = database.execute(
                "SELECT thread_id, turn_id, confirmed FROM desktop_turn_feedback ORDER BY thread_id"
            ).fetchall()
            assert saved == [("history-first", "first-feedback-turn", 1), ("history-second", "second-feedback-turn", 0)], saved
        assert not list(profile.iterdir())
        print("Verified exact log-free payloads, one confirmed receipt, and durable suppression of an uncertain report")


if __name__ == "__main__":
    main()
