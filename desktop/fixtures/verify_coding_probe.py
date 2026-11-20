"""Exercise an installed coding probe using the isolated protocol fixture."""

import argparse
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
from tempfile import TemporaryDirectory

from mock_backend import ENTRY_POINT


def fixture_executable(directory: Path) -> Path:
    if os.name == "nt":
        executable = directory / "codex.cmd"
        executable.write_text(f'@"{sys.executable}" "{ENTRY_POINT}" %*\r\n', encoding="utf-8")
    else:
        executable = directory / "codex"
        command = shlex.join([sys.executable, str(ENTRY_POINT)])
        executable.write_text(f'#!/bin/sh\nexec {command} "$@"\n', encoding="utf-8")
        executable.chmod(0o755)
    return executable


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    args = parser.parse_args()

    with TemporaryDirectory(prefix="codex-gui-coding-fixture-") as scratch:
        directory = Path(scratch).resolve()
        home = directory / "isolated home"
        home.mkdir()
        trace = directory / "trace.jsonl"
        report = directory / "report.txt"
        executable = fixture_executable(directory)
        subprocess.run(
            [str(args.app.resolve(strict=True)), "--verify-coding-turn", str(report)],
            check=True,
            timeout=60,
            env={
                **os.environ,
                "CODEX_EXECUTABLE": str(executable),
                "CODEX_HOME": str(home),
                "CODEX_GUI_QA_SCENARIO": "coding-probe",
                "CODEX_GUI_QA_STATE": str(directory / "state.json"),
                "CODEX_GUI_QA_TRACE": str(trace),
                "PYTHONIOENCODING": "utf-8",
            },
        )
        expected = [
            "Default-policy coding probe completed",
            f"Codex executable: {executable}",
            "Codex CLI version: 0.153.2",
        ]
        if report.read_text(encoding="utf-8").splitlines() != expected:
            raise SystemExit("Missing evidence for the selected Codex executable and completed turn")
        entries = [json.loads(line) for line in trace.read_text(encoding="utf-8").splitlines()]
        requests = [entry for entry in entries if entry["direction"] == "request"]
        assert any(entry["direction"] == "fixture" and not entry["modelCalls"] for entry in entries)
        assert [request["method"] for request in requests] == [
            "initialize", "initialized", "account/read", "thread/start", "turn/start",
        ]
        thread, turn = requests[-2:]
        assert set(thread["params"]) == {"cwd"}
        assert set(turn["params"]) == {"threadId", "cwd", "clientUserMessageId", "input"}
        assert thread["cwd"] == turn["resolvedCwd"] == turn["cwd"]
        print("Verified the installed coding probe with the protocol fixture")


if __name__ == "__main__":
    main()
