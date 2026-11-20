"""Exercise installed sign-in actions with a disposable local account fixture."""

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
    with TemporaryDirectory(prefix="codex-gui-account-") as scratch:
        root = Path(scratch).resolve()
        data = root / "beta data"
        codex_home = root / "codex home"
        codex_home.mkdir()
        trace = root / "trace.jsonl"
        result = subprocess.run(
            [str(args.app.resolve(strict=True)), "--verify-account", str(data)],
            env={
                **os.environ,
                "CODEX_EXECUTABLE": str(fixture_executable(root)),
                "CODEX_HOME": str(codex_home),
                "CODEX_GUI_QA_SCENARIO": "desktop-account",
                "CODEX_GUI_QA_STATE": str(root / "state.json"),
                "CODEX_GUI_QA_TRACE": str(trace),
                "PYTHONIOENCODING": "utf-8",
            },
            timeout=60, capture_output=True, encoding="utf-8", errors="replace",
        )
        print(result.stdout, end="")
        if result.returncode or "Verified installed ChatGPT sign-in" not in result.stdout:
            raise SystemExit(result.stderr or "The installed workspace did not confirm the account fixture")
        records = [json.loads(line) for line in trace.read_text().splitlines()]
        requests = [item for item in records if item["direction"] == "request"]
        assert [item["method"] for item in requests] == [
            "initialize", "initialized", "account/read", "config/read", "account/login/start",
            "account/login/cancel", "account/login/start", "account/read", "config/read",
            "model/list", "model/list",
        ], requests
        assert requests[5]["params"] == {"loginId": "browser-login-1"}, requests[5]
        assert requests[3]["params"] == requests[8]["params"] == {"includeLayers": False, "cwd": None}
        completions = [item["loginId"] for item in records
                       if item.get("direction") == "event" and item.get("method") == "account/login/completed"]
        assert completions == ["browser-login-1", "browser-login-2"], completions
        with closing(sqlite3.connect(data / "workspace.sqlite3")) as database:
            assert database.execute("SELECT text FROM drafts").fetchone() == (
                "Draft retained through ChatGPT sign-in 日本語",
            )
        assert not list(codex_home.iterdir())
        print("Verified the obsolete completion was ignored and the original draft was retained")


if __name__ == "__main__":
    main()
