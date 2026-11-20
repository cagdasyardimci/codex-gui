"""Verify the installed archive workflows against local metadata and isolated drafts."""

import argparse
from contextlib import closing
import json
import os
from pathlib import Path
import sqlite3
import subprocess
from tempfile import TemporaryDirectory

from verify_coding_probe import fixture_executable


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    args = parser.parse_args()
    with TemporaryDirectory(prefix="codex-gui-archive-") as scratch:
        root = Path(scratch).resolve()
        project = root / "Archive primary"
        other = root / "Archive external"
        profile = root / "codex home"
        for directory in (project, other, profile):
            directory.mkdir()
        data = root / "desktop"
        trace = root / "trace.jsonl"
        state = root / "backend.json"
        threads = [
            {"id": "history-first", "name": "First fixture chat", "preview": "First project conversation"},
            {"id": "history-second", "name": "Second fixture chat", "preview": "Second project conversation"},
            {"id": "older-primary", "name": "Older local conversation", "preview": "", "archived": True},
        ]
        threads += [
            {"id": f"archive-row-{index:02}", "name": f"Saved discussion {index}", "preview": "",
             "archived": True, "cwd": str(other)}
            for index in range(42)
        ]
        threads.append({
            "id": "zz-archive-deep", "name": "Rare topic", "preview": "Paperclip semaphore",
            "archived": True, "cwd": str(other),
        })
        state.write_text(json.dumps({"threads": threads}), encoding="utf-8")
        environment = {
            **os.environ,
            "CODEX_HOME": str(profile),
            "CODEX_EXECUTABLE": str(fixture_executable(root)),
            "CODEX_GUI_QA_SCENARIO": "desktop-archive",
            "CODEX_GUI_QA_TRACE": str(trace),
            "CODEX_GUI_QA_STATE": str(state),
            "PYTHONIOENCODING": "utf-8",
        }
        result = subprocess.run(
            [args.app.resolve(strict=True), "--verify-archive", data, project], env=environment,
            capture_output=True, encoding="utf-8", errors="replace", timeout=80,
        )
        print(result.stdout, end="")
        if result.returncode or "Verified installed project and chat archive" not in result.stdout:
            raise SystemExit(result.stderr or "The installed archive fixture did not complete")

        requests = [entry for line in trace.read_text(encoding="utf-8").splitlines()
                    if (entry := json.loads(line))["direction"] == "request"]
        mutations = [(request["method"], request["params"]) for request in requests
                     if request["method"] in ("thread/archive", "thread/unarchive")]
        assert mutations == [
            ("thread/archive", {"threadId": "history-first"}),
            ("thread/archive", {"threadId": "history-second"}),
            ("thread/unarchive", {"threadId": "history-first"}),
            ("thread/archive", {"threadId": "history-first"}),
            ("thread/unarchive", {"threadId": "history-first"}),
            ("thread/unarchive", {"threadId": "older-primary"}),
        ], mutations
        first_archive = next(index for index, request in enumerate(requests)
                             if request["method"] == "thread/archive")
        preflight, summary, turns = requests[first_archive - 3:first_archive]
        assert preflight["method"] == "thread/list" and preflight["params"]["archived"] is False
        assert Path(preflight["params"]["cwd"]).samefile(project)
        assert summary["method"] == "thread/read" and summary["params"] == {
            "threadId": "history-first", "includeTurns": False,
        }
        assert turns["method"] == "thread/turns/list" and turns["params"]["itemsView"] == "notLoaded"
        assert requests[first_archive + 1]["method"] == "thread/read"
        assert requests[first_archive + 1]["params"]["threadId"] == "history-second"
        assert any(request.get("cursor") == "archive-after-replay" for request in requests)
        assert not any(request["method"] in ("thread/start", "turn/start", "thread/delete") for request in requests)
        saved = json.loads(state.read_text(encoding="utf-8"))
        assert saved["becameActiveDuringArchive"] and saved["archiveRejected"] and saved["returnedObsoleteArchive"]
        archived = {thread["id"] for thread in saved["threads"] if thread["archived"]}
        assert len(archived) == 43 and "zz-archive-deep" in archived, archived
        with closing(sqlite3.connect(data / "workspace.sqlite3")) as database:
            assert database.execute(
                "SELECT thread_id, text FROM thread_drafts JOIN drafts ON draft_id = id ORDER BY thread_id"
            ).fetchall() == [("history-first", ""), ("history-second", "Keep the rejected archive draft.")]
            assert database.execute(
                "SELECT thread_id, archived FROM desktop_sidebar_chats ORDER BY thread_id"
            ).fetchall() == [("history-first", 0), ("history-second", 0), ("older-primary", 0)]
        assert not list(profile.iterdir())
        print("Verified partial archive, exact mutations, stale-result rejection, draft retention, and independent archive paging")


if __name__ == "__main__":
    main()
