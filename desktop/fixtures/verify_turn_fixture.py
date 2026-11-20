"""Exercise the installed composer, approval, questions, and Stop against a local backend."""

import argparse
from contextlib import closing
import json
import os
from pathlib import Path
import sqlite3
import subprocess
from tempfile import TemporaryDirectory
from uuid import UUID

from verify_coding_probe import fixture_executable


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    executable = parser.parse_args().app.resolve(strict=True)
    with TemporaryDirectory(prefix="codex-gui-turn-") as scratch:
        root = Path(scratch).resolve()
        data = root / "beta data"
        checkout = root / "Checkout café"
        checkout.mkdir()
        codex_home = root / "codex home"
        codex_home.mkdir()
        trace = root / "trace.jsonl"
        result = subprocess.run(
            [str(executable), "--verify-turn", str(data), str(checkout)],
            env={
                **os.environ,
                "CODEX_EXECUTABLE": str(fixture_executable(root)),
                "CODEX_HOME": str(codex_home),
                "CODEX_GUI_QA_SCENARIO": "desktop-turn",
                "CODEX_GUI_QA_STATE": str(root / "state.json"),
                "CODEX_GUI_QA_TRACE": str(trace),
                "PYTHONIOENCODING": "utf-8",
            },
            timeout=60, capture_output=True, encoding="utf-8", errors="replace",
        )
        print(result.stdout, end="")
        if result.returncode or "Verified installed Send" not in result.stdout:
            raise SystemExit(result.stderr or "The installed workspace did not confirm the turn fixture")
        entries = [json.loads(line) for line in trace.read_text().splitlines()]
        requests = [item for item in entries if item["direction"] == "request"]
        starts = [item["params"] for item in requests if item["method"] == "turn/start"]
        prompts = ["Recover this fixture receipt", "Fixture mixed questions", "Hold this fixture turn"]
        assert [item["input"] for item in starts] == [
            [{"type": "text", "text": prompt}] for prompt in prompts
        ], starts
        assert len({UUID(item["clientUserMessageId"]) for item in starts}) == 3
        assert sum(item["method"] == "thread/start" for item in requests) == 1
        owner = starts[0]["threadId"]
        assert all(item["threadId"] == owner and Path(item["cwd"]).samefile(checkout) for item in starts)
        [stop] = [item["params"] for item in requests if item["method"] == "turn/interrupt"]
        assert stop["threadId"] == owner
        assert any(item.get("direction") == "event" and item.get("method") == "turn/completed" and
                   item.get("status") == "interrupted" and item.get("turnId") == stop["turnId"]
                   for item in entries)
        assert [item["result"] for item in entries if item["direction"] == "command-approval-response"] == [
            {"decision": "accept"},
        ]
        assert [item["result"] for item in entries if item["direction"] == "question-response"] == [
            {"answers": {"details": {"answers": ["Faster typing 日本語"]},
                         "area": {"answers": ["Composer", "Settings"]}}},
        ]
        with closing(sqlite3.connect(data / "workspace.sqlite3")) as database:
            assert database.execute("SELECT thread_id FROM desktop_selection").fetchone() == ("history-second",)
            assert database.execute("SELECT COUNT(*) FROM submission_outcomes").fetchone() == (3,)
            assert database.execute(
                "SELECT drafts.text FROM thread_drafts JOIN drafts ON drafts.id = thread_drafts.draft_id "
                "WHERE thread_id = ?", [owner]
            ).fetchone() == ("",)
        assert not list(codex_home.iterdir())
        print("Verified three exact sends without replay and one interrupt for the original chat")


if __name__ == "__main__":
    main()
