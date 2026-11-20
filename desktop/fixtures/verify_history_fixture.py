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
from mock_backend import ENTRY_POINT


def seed_history_files(project: Path) -> None:
    for folder in ("notes", "node_modules", ".hidden"):
        (project / folder).mkdir()
        (project / folder / "Café.md").write_text("File search fixture\n", encoding="utf-8")
    (project / "notes" / "panel.png").write_bytes(b64decode(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGMQSTnxHwAEEAJAKtk0QwAAAABJRU5ErkJggg=="
    ))


def seed_paginated_history(state_path: Path, count: int = 32) -> None:
    scenario = ENTRY_POINT.parent / "mock_backend" / "scenarios" / "desktop-history.json"
    threads = json.loads(scenario.read_text(encoding="utf-8"))["threads"]
    first = next(thread for thread in threads if thread["id"] == "history-first")
    if count > 32:
        first["preview"] = "Large transcript fixture"
    else:
        first["turns"][0]["items"].extend([
            {"id": "first-attached", "type": "userMessage", "content": [
                {"type": "localImage", "path": "notes/panel.png"},
                {"type": "localImage", "path": "../panel.png"},
                {"type": "localImage", "path": "notes/panel.png"},
            ]},
            {"id": "first-markdown", "type": "agentMessage", "text": (
                "## Markdown fixture\n\n"
                "```rust\nlet label = \"café 日本語\";\n```\n\n"
                "[External guide](https://example.invalid/path) | [Heading](#markdown-fixture) | "
                "[Blocked destination](javascript:discard)\n\n"
                "![Contained panel](notes/panel.png) ![Offline remote](https://example.invalid/panel.png) "
                "![Escaping path](../panel.png)\n\n"
                "<figure data-fixture-raw>Literal HTML reference</figure>\n\n"
                "| Name | Value |\n| --- | --- |\n| Label | **café** |\n\n"
                + "Further context for the heading link.\n\n" * 18
            )},
            {"id": "first-markdown-depth", "type": "agentMessage",
             "text": "> " * 40 + "Readable source past the nesting limit"},
        ])
    earlier = []
    for number in range(1, count + 1):
        turn_id = f"older-fixture-{number:02}"
        items = [{
            "id": "response", "type": "agentMessage",
            "text": f"Saved history page fixture {number:02}\n" + "First line\nSecond line\nThird line",
        }]
        if count == 32 and number in {3, 5}:
            items = [{"type": "reasoning", "id": f"step-{step}", "content": [], "summary": []}
                     for step in range(104)] + items
        if count == 32 and number == 3:
            items.insert(0, {"id": "prompt", "type": "userMessage", "content": [
                {"type": "text", "text": "A saved long turn"},
            ]})
        if count > 32:
            items[0]["text"] += "\nVariable-height fixture content" * (number % 7)
            if 64 <= number <= count - 19:
                items[0]["text"] += "\nA tall landing for the reading anchor" * 45
        earlier.append({"id": turn_id, "status": "completed", "items": items})
    first["turns"] = earlier + first["turns"]
    state_path.write_text(json.dumps({"threads": threads}, ensure_ascii=True), encoding="utf-8")


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
            "CODEX_GUI_QA_SCENARIO": "desktop-rich-history",
            "CODEX_GUI_QA_STATE": str(root / "state.json"),
            "CODEX_GUI_QA_TRACE": str(trace),
            "PYTHONIOENCODING": "utf-8",
        }
        executable = str(args.app.resolve(strict=True))
        database_path = data / "workspace.sqlite3"
        state_path = Path(environment["CODEX_GUI_QA_STATE"])
        seed_paginated_history(state_path)
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
        assert (data / "preview-Image.png").read_bytes() == (project / "notes" / "panel.png").read_bytes()
        methods = [event["method"] for event in events if event["direction"] == "request"]
        assert methods.count("initialize") == 4, methods
        assert methods.count("thread/list") >= 4, methods
        assert not {"thread/start", "turn/start"} & set(methods), methods
        paged = [event for event in events if event["direction"] == "request"
                 and event["method"] == "thread/turns/list" and event.get("cursor")]
        assert [(entry.get("threadId"), entry["cursor"], entry.get("itemsView")) for entry in paged] == [
            ("history-first", "older-fixture-14", "full"),
        ], paged
        turn_reads = [event for event in events if event["direction"] == "request"
                      and event["method"] == "thread/items/list"
                      and event.get("turnId") in {"older-fixture-03", "older-fixture-04", "older-fixture-05"}]
        assert [(entry["turnId"], entry["sortDirection"], entry.get("cursor")) for entry in turn_reads] == [
            ("older-fixture-03", "asc", None), ("older-fixture-03", "desc", None),
            ("older-fixture-05", "asc", None), ("older-fixture-05", "asc", "step-99"),
        ], turn_reads
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
        print("Verified the saved attachment downloaded its original bytes")
        print("Verified an unselected chat's execution and command evidence reconciled after relaunch")
        print("Verified one cursor-scoped older history request from the deliberate scroll")
        print("Verified bounded turn preview reads and a complete read for the committed jump")
    verify_residency(executable)


def verify_residency(executable: str) -> None:
    with TemporaryDirectory(prefix="codex-gui-residency-") as scratch:
        root = Path(scratch).resolve()
        project = root / "Checkout café"
        project.mkdir()
        data = root / "beta data"
        state = root / "state.json"
        trace = root / "trace.jsonl"
        codex_home = root / "codex home"
        codex_home.mkdir()
        seed_paginated_history(state, count=95)
        result = subprocess.run([executable, "--verify-history", str(data), str(project)],
            env={**os.environ, "CODEX_EXECUTABLE": str(fixture_executable(root)),
                 "CODEX_HOME": str(codex_home), "CODEX_GUI_QA_SCENARIO": "desktop-history",
                 "CODEX_GUI_QA_STATE": str(state), "CODEX_GUI_QA_TRACE": str(trace), "PYTHONIOENCODING": "utf-8"},
            timeout=60, capture_output=True, encoding="utf-8", errors="replace")
        print(result.stdout, end="")
        if result.returncode or "Verified installed project history" not in result.stdout:
            raise SystemExit(result.stderr or "The installed app did not complete transcript residency verification")
        requests = [entry for entry in map(json.loads, trace.read_text(encoding="utf-8").splitlines())
                    if entry["direction"] == "request"]
        targeted = [entry for entry in requests if entry["method"] == "thread/items/list"]
        assert len(targeted) == 2 and targeted[0]["turnId"] == targeted[1]["turnId"], targeted
        assert all(entry["threadId"] == "history-first" and not entry.get("cursor") for entry in targeted)
        assert len([entry for entry in requests if entry["method"] == "thread/turns/list"
                    and entry.get("cursor") and entry.get("itemsView") == "full"]) == 4
        assert not list(codex_home.iterdir())
        print("Verified bounded transcript residency, mounted selection, and targeted anchor restoration")


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
