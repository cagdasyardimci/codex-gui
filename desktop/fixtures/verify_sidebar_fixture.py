"""Verify project and chat organization across installed application launches."""

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
    executable = args.app.resolve(strict=True)
    with TemporaryDirectory(prefix="codex-gui-sidebar-") as scratch:
        root = Path(scratch).resolve()
        source = root / "Primary café"
        other = root / "Other checkout"
        profile = root / "codex home"
        source.mkdir()
        other.mkdir()
        profile.mkdir()
        data = root / "desktop"
        trace = root / "trace.jsonl"
        state = root / "backend.json"
        environment = {
            **os.environ,
            "CODEX_HOME": str(profile),
            "CODEX_EXECUTABLE": str(fixture_executable(root)),
            "CODEX_GUI_QA_SCENARIO": "desktop-sidebar",
            "CODEX_GUI_QA_SIDEBAR_CHECKOUT": str(other),
            "CODEX_GUI_QA_TRACE": str(trace),
            "CODEX_GUI_QA_STATE": str(state),
            "PYTHONIOENCODING": "utf-8",
        }
        for command in (
            [executable, "--verify-sidebar", data, source, other],
            [executable, "--verify-sidebar-restore", data],
        ):
            result = subprocess.run(command, env=environment, capture_output=True,
                                    encoding="utf-8", errors="replace", timeout=75)
            print(result.stdout, end="")
            if result.returncode or "Verified installed sidebar projects" not in result.stdout:
                raise SystemExit(result.stderr or "The installed sidebar fixture did not complete")

        requests = [record for line in trace.read_text(encoding="utf-8").splitlines()
                    if (record := json.loads(line))["direction"] == "request"]
        renames = [request for request in requests if request["method"] == "thread/name/set"]
        assert [(request["params"], Path(request["backendCheckout"]).samefile(source)) for request in renames] == [
            ({"threadId": "history-first", "name": "Renamed fixture chat"}, True),
            ({"threadId": "history-first", "name": "Final fixture chat"}, True),
        ], renames
        for request in requests:
            thread = request.get("threadId")
            if thread:
                expected = other if thread.startswith("other-") else source
                assert Path(request["backendCheckout"]).samefile(expected), request
        assert not any(request["method"] in ("thread/start", "turn/start") for request in requests)
        with closing(sqlite3.connect(data / "workspace.sqlite3")) as database:
            target, path, thread = database.execute(
                "SELECT project_key, project_path, thread_id FROM desktop_selection"
            ).fetchone()
            assert Path(path).samefile(source) and thread == "history-first"
            assert database.execute(
                "SELECT title, pinned FROM desktop_projects WHERE id = ?", (target,)
            ).fetchone() == ("Primary design", 1)
            assert database.execute(
                "SELECT pinned, unread FROM desktop_sidebar_chats WHERE project_id = ? ORDER BY thread_id", (target,)
            ).fetchall() == [(1, 0), (0, 1)]
            (preferences,) = database.execute("SELECT content FROM desktop_sidebar_preferences").fetchone()
            preferences = json.loads(preferences)
            assert preferences["group"] == "oneList" and preferences["sort"] == "manual", preferences
            assert [item["chatId"] for item in preferences["order"] if item["projectId"] == target] == [
                "history-first", "history-second",
            ], preferences
        assert not list(profile.iterdir())
        print("Verified two owned checkouts, exact rename requests, pinned navigation and durable manual order")


if __name__ == "__main__":
    main()
