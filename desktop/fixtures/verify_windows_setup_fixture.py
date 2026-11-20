"""Exercise installed setup and update actions with isolated Windows sandbox fixtures."""

import argparse
from contextlib import closing
import json
import os
from pathlib import Path
import sqlite3
import subprocess
from tempfile import TemporaryDirectory

from verify_coding_probe import fixture_executable


def verify(app: Path, readiness: str, mode: str) -> None:
    with TemporaryDirectory(prefix="codex-gui-sandbox-ui-") as scratch:
        root = Path(scratch).resolve()
        data = root / "beta data"
        project = root / "Checkout café"
        project.mkdir()
        codex_home = root / "codex home"
        codex_home.mkdir()
        trace = root / "trace.jsonl"
        state = root / "state.json"
        state.write_text(json.dumps({"windowsSandboxReadiness": readiness}))
        result = subprocess.run(
            [str(app), "--verify-windows-setup", str(data), str(project)],
            env={
                **os.environ,
                "CODEX_EXECUTABLE": str(fixture_executable(root)),
                "CODEX_HOME": str(codex_home),
                "CODEX_GUI_QA_SCENARIO": "desktop-windows-sandbox",
                "CODEX_GUI_QA_STATE": str(state),
                "CODEX_GUI_QA_TRACE": str(trace),
                "PYTHONIOENCODING": "utf-8",
            },
            timeout=60, capture_output=True, encoding="utf-8", errors="replace",
        )
        print(result.stdout, end="")
        if result.returncode or "Verified installed Windows sandbox setup" not in result.stdout:
            raise SystemExit(result.stderr or "The installed workspace did not confirm sandbox setup")
        entries = [json.loads(line) for line in trace.read_text().splitlines()]
        requests = [(index, item) for index, item in enumerate(entries)
                    if item["direction"] == "request"]
        methods = [item["method"] for _, item in requests]
        assert methods.count("initialize") == 2, methods
        assert methods.count("windowsSandbox/readiness") == 2, methods
        assert methods.count("windowsSandbox/setupStart") == 1, methods
        assert methods.count("thread/resume") == 1, methods
        assert not {"thread/start", "turn/start"} & set(methods)
        setup_index, setup = next((i, e) for i, e in requests if e["method"] == "windowsSandbox/setupStart")
        assert setup["params"]["mode"] == mode and Path(setup["params"]["cwd"]).resolve() == project
        completion_index = next(i for i, e in enumerate(entries)
                                if e["direction"] == "event" and e["method"] == "windowsSandbox/setupCompleted"
                                and e["mode"] == mode)
        recheck_index = max(i for i, e in requests if e["method"] == "windowsSandbox/readiness")
        resume_index = next(i for i, e in requests if e["method"] == "thread/resume")
        assert setup_index < completion_index < recheck_index < resume_index
        with closing(sqlite3.connect(data / "workspace.sqlite3")) as database:
            assert database.execute("SELECT thread_id FROM desktop_selection").fetchone() == ("history-first",)
            assert ("Draft retained during Windows sandbox setup 日本語",) in database.execute("SELECT text FROM drafts").fetchall()
        assert not list(codex_home.iterdir())
        print(f"Verified {mode} mode and writer admission after matching completion and readiness")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    app = parser.parse_args().app.resolve(strict=True)
    verify(app, "notConfigured", "unelevated")
    verify(app, "updateRequired", "elevated")


if __name__ == "__main__":
    main()
