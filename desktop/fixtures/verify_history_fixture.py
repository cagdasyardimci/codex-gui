"""Verify the installed workspace UI and restart against isolated Codex history."""

import argparse
from contextlib import closing
import json
import os
from pathlib import Path
import sqlite3
import subprocess
from tempfile import TemporaryDirectory

from verify_coding_probe import fixture_executable


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    args = parser.parse_args()
    with TemporaryDirectory(prefix="codex-gui-history-") as scratch:
        root = Path(scratch).resolve()
        data = root / "beta data"
        project = root / "Checkout café"
        project.mkdir()
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
        for command in [
            [executable, "--verify-history", str(data), str(project)],
            [executable, "--verify-history-restore", str(data)],
        ]:
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
        assert any(event.get("error", {}).get("message") == "Thread already has an active writer"
                   for event in events)
        assert sum(event.get("direction") == "event" and event.get("method") == "turn/completed"
                   for event in events) == 1
        with closing(sqlite3.connect(data / "workspace.sqlite3")) as database:
            assert database.execute("SELECT project_path, thread_id FROM desktop_selection").fetchone() == (None, None)
            drafts = {row[0] for row in database.execute("SELECT text FROM drafts")}
            assert {"Composed café 日本語", "Unsent checkout draft"} <= drafts
        assert not list(codex_home.iterdir())
        print("Verified selected draft and checkout retention without any thread or turn start requests")


if __name__ == "__main__":
    main()
