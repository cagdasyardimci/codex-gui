"""Verify native close and Quit against durable workspace state."""

import argparse
from contextlib import closing
import json
import os
from pathlib import Path
import sqlite3
import subprocess
from tempfile import TemporaryDirectory

from verify_coding_probe import fixture_executable


def invoke_app(command: list[str], environment: dict[str, str], confirmation: str) -> str:
    result = subprocess.run(command, env=environment, timeout=60,
                            capture_output=True, encoding="utf-8", errors="replace")
    print(result.stdout, end="")
    if result.returncode or confirmation not in result.stdout:
        raise SystemExit(result.stderr or "The installed app did not confirm quit verification")
    return result.stderr


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    executable = str(parser.parse_args().app.resolve(strict=True))
    with TemporaryDirectory(prefix="codex-gui-quit-") as scratch:
        root = Path(scratch).resolve()
        data = root / "beta data"
        checkout = root / "Checkout café"
        checkout.mkdir()
        codex_home = root / "codex home"
        codex_home.mkdir()
        environment = {
            **os.environ,
            "CODEX_EXECUTABLE": str(fixture_executable(root)),
            "CODEX_HOME": str(codex_home),
            "CODEX_GUI_QA_SCENARIO": "desktop-history",
            "CODEX_GUI_QA_STATE": str(root / "history-state.json"),
            "PYTHONIOENCODING": "utf-8",
        }
        invoke_app([executable, "--verify-history", str(data), str(checkout)], environment,
                   "Verified installed project history")
        database_path = data / "workspace.sqlite3"
        with closing(sqlite3.connect(database_path)) as database:
            database.execute("""
                CREATE TRIGGER reject_fixture_edit BEFORE UPDATE OF text ON drafts
                WHEN NEW.text = 'Rejected fixture draft write'
                BEGIN SELECT RAISE(ABORT, 'fixture draft write rejected'); END
            """)
            database.commit()
        trace = root / "trace.jsonl"
        errors = invoke_app([executable, "--verify-quit", str(data), str(checkout)], {
            **environment,
            "CODEX_GUI_QA_SCENARIO": "desktop-quit",
            "CODEX_GUI_QA_STATE": str(root / "quit-state.json"),
            "CODEX_GUI_QA_TRACE": str(trace),
        }, "Verified desktop quit drained drafts and retained unresolved execution evidence")
        assert "fixture draft write rejected" in errors
        records = [json.loads(line) for line in trace.read_text().splitlines()]
        starts = [item["params"] for item in records
                  if item["direction"] == "request" and item["method"] == "turn/start"]
        [start] = starts
        assert start["threadId"] == "history-second"
        interrupts = [item["params"] for item in records
                      if item["direction"] == "request" and item["method"] == "turn/interrupt"]
        [interrupt] = interrupts
        assert interrupt["threadId"] == "history-second"
        assert any(item.get("method") == "turn/completed" and item.get("status") == "interrupted"
                   and item.get("turnId") == interrupt["turnId"] for item in records)
        with closing(sqlite3.connect(database_path)) as database:
            drafts = dict(database.execute(
                "SELECT thread_id, text FROM thread_drafts JOIN drafts ON draft_id = id"
            ))
            assert drafts["history-first"] == "Recovered text before quit"
            assert drafts["history-second"] == "Accepted draft retained while quitting 日本語"
            unresolved = database.execute(
                "SELECT thread_id, turn_id, item_id FROM exit_recovery"
            ).fetchall()
            assert unresolved == [("history-second", interrupt["turnId"], "fixture-pending-command")], unresolved
        assert not list(codex_home.iterdir())
        print("Verified cancel and write failure retained the app, and confirmed Quit kept the unresolved command")


if __name__ == "__main__":
    main()
