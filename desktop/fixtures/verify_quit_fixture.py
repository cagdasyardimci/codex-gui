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
from verify_history_fixture import seed_search_paths


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
        seed_search_paths(checkout)
        other_checkout = root / "Other checkout"
        other_checkout.mkdir()
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
        quit_environment = {
            **environment,
            "CODEX_GUI_QA_SCENARIO": "desktop-quit",
            "CODEX_GUI_QA_SECONDARY_QUIT_CHECKOUT": str(other_checkout),
            "CODEX_GUI_QA_TRACE": str(trace),
        }
        quit_environment.pop("CODEX_GUI_QA_STATE", None)
        errors = invoke_app(
            [executable, "--verify-quit", str(data), str(checkout), str(other_checkout)], quit_environment,
            "Verified desktop quit drained drafts and retained unresolved execution evidence",
        )
        assert "fixture draft write rejected" in errors
        records = sorted(
            (json.loads(line) for part in root.glob(f"{trace.name}.*")
             for line in part.read_text(encoding="utf-8").splitlines()),
            key=lambda event: event["time"],
        )
        starts = [item["params"] for item in records
                  if item["direction"] == "request" and item["method"] == "turn/start"]
        assert [start["threadId"] for start in starts] == [
            "history-second", "other-history-second", "history-second", "other-history-second",
        ], starts
        interrupts = [item["params"] for item in records
                      if item["direction"] == "request" and item["method"] == "turn/interrupt"]
        assert len(interrupts) == 3, interrupts
        assert {row["threadId"] for row in interrupts[:2]} == {"history-second", "other-history-second"}
        assert interrupts[-1]["threadId"] == "history-second"
        for event in records:
            if event["direction"] == "request" and event["method"] in ("turn/start", "turn/interrupt"):
                expected_checkout = other_checkout if event["threadId"].startswith("other-") else checkout
                assert os.path.samefile(event["resolvedCwd"], expected_checkout), event
        assert any(item.get("method") == "turn/completed" and item.get("status") == "completed"
                   and item.get("threadId") == "other-history-second" for item in records)
        assert sum(item.get("method") == "item/completed" and item.get("threadId") == "other-history-second"
                   and (item.get("item") or {}).get("id") == "fixture-pending-command" for item in records) == 2
        with closing(sqlite3.connect(database_path)) as database:
            drafts = dict(database.execute(
                "SELECT thread_id, text FROM thread_drafts JOIN drafts ON draft_id = id"
            ))
            assert drafts["history-first"] == "Recovered text before quit"
            assert drafts["history-second"] == "Accepted draft retained while quitting 日本語"
            unresolved = database.execute(
                "SELECT thread_id, turn_id, item_id FROM exit_recovery"
            ).fetchall()
            assert set(unresolved) == {
                ("history-second", interrupt["turnId"], "fixture-pending-command")
                for interrupt in interrupts if interrupt["threadId"] == "history-second"
            }, unresolved
        assert not list(codex_home.iterdir())
        print("Verified Stop All and Quit across both checkouts, including completion during confirmation and late command evidence")


if __name__ == "__main__":
    main()
