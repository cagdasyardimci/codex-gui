"""Verify the installed workspace UI and restart against isolated Codex history."""

import argparse
from base64 import b64decode
from contextlib import closing
import json
import os
from pathlib import Path
import sqlite3
import subprocess
from tempfile import TemporaryDirectory

from verify_coding_probe import fixture_executable


def seed_history_files(project: Path) -> None:
    for folder in ("notes", "node_modules", ".hidden"):
        (project / folder).mkdir()
        (project / folder / "Café.md").write_text("File search fixture\n", encoding="utf-8")
    (project / "notes" / "panel.png").write_bytes(b64decode(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/WZkAAAAASUVORK5CYII="
    ))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    args = parser.parse_args()
    with TemporaryDirectory(prefix="codex-gui-history-") as scratch:
        root = Path(scratch).resolve()
        data = root / "beta data"
        project = root / "Checkout café"
        project.mkdir()
        seed_history_files(project)
        codex_home = root / "codex home"
        codex_home.mkdir()
        trace = root / "trace.jsonl"
        environment = {
            **os.environ,
            "CODEX_EXECUTABLE": str(fixture_executable(root)),
            "CODEX_HOME": str(codex_home),
            "CODEX_GUI_QA_SCENARIO": "desktop-history",
            "CODEX_GUI_QA_STATE": str(root / "state.json"),
            "CODEX_GUI_QA_TRACE": str(trace),
            "PYTHONIOENCODING": "utf-8",
        }
        executable = str(args.app.resolve(strict=True))
        database_path = data / "workspace.sqlite3"
        state_path = Path(environment["CODEX_GUI_QA_STATE"])
        restart_offset = 0
        for index, command in enumerate([
            [executable, "--verify-history", str(data), str(project)],
            [executable, "--verify-history-restore", str(data)],
        ]):
            if index == 1:
                restart_offset = len(trace.read_text(encoding="utf-8").splitlines())
                seed_hidden_execution(database_path, state_path)
            result = subprocess.run(command, env=environment, timeout=60,
                                    capture_output=True, encoding="utf-8", errors="replace")
            print(result.stdout, end="")
            if result.returncode or "Verified installed project history" not in result.stdout:
                raise SystemExit(result.stderr or "The installed workspace did not confirm the fixture")
        events = [json.loads(line) for line in trace.read_text().splitlines()]
        methods = [event["method"] for event in events if event["direction"] == "request"]
        assert methods.count("initialize") == 4, methods
        assert methods.count("thread/list") >= 4, methods
        assert not {"thread/start", "turn/start"} & set(methods), methods
        hidden_requests = [
            event["method"] for event in events[restart_offset:]
            if event["direction"] == "request" and event.get("threadId") == "history-second"
        ]
        assert hidden_requests == ["thread/read", "thread/turns/list"], hidden_requests
        assert any(event.get("error", {}).get("message") == "Thread already has an active writer"
                   for event in events)
        assert sum(event.get("direction") == "event" and event.get("method") == "turn/completed"
                   for event in events) == 1
        with closing(sqlite3.connect(database_path)) as database:
            assert database.execute("SELECT project_path, thread_id FROM desktop_selection").fetchone() == (None, None)
            drafts = {row[0] for row in database.execute("SELECT text FROM drafts")}
            assert {"Composed café 日本語", "Unsent checkout draft"} <= drafts
            assert database.execute("SELECT COUNT(*) FROM exit_recovery").fetchone() == (0,)
        assert not list(codex_home.iterdir())
        print("Verified selected draft and checkout retention without any thread or turn start requests")
        print("Verified an unselected chat's execution and command evidence reconciled after relaunch")


def seed_hidden_execution(database_path: Path, state_path: Path) -> None:
    state = json.loads(state_path.read_text(encoding="utf-8"))
    thread = next(thread for thread in state["threads"] if thread["id"] == "history-second")
    turn = thread["turns"][0]
    command_id = "unselected-command"
    turn["items"].append({
        "id": command_id, "type": "commandExecution", "status": "completed",
    })
    state_path.write_text(json.dumps(state, ensure_ascii=True), encoding="utf-8")
    with closing(sqlite3.connect(database_path)) as database, database:
        checkout_key, checkout_path = database.execute(
            "SELECT project_key, project_path FROM desktop_selection"
        ).fetchone()
        database.execute("INSERT INTO exit_checkout_paths VALUES (?, ?)", (checkout_key, checkout_path))
        database.executemany(
            "INSERT INTO exit_recovery VALUES (?, ?, ?, ?)",
            [(checkout_key, thread["id"], turn["id"], item_id) for item_id in ("", command_id)],
        )


if __name__ == "__main__":
    main()
