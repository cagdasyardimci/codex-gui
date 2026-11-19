"""Launch the shared app-server fixture from an isolated working directory."""

import os
from pathlib import Path
import subprocess
import sys


ENTRY_POINT = (
    Path(__file__).resolve().parents[2] / "Tests" / "E2E" / "MockBackend" / "qa-backend"
)


def launch_mock_backend(checkout: Path, state_directory: Path, scenario: str):
    """Return the fixture process with piped stdio. The caller owns its lifetime."""
    checkout = checkout.resolve(strict=True)
    state_directory = state_directory.resolve()
    codex_home = state_directory / "codex-home"
    codex_home.mkdir(parents=True, exist_ok=True)

    environment = {
        **os.environ,
        "CODEX_HOME": str(codex_home),
        "CODEX_GUI_QA_STATE": str(state_directory / "state.json"),
        "CODEX_GUI_QA_TRACE": str(state_directory / "trace.jsonl"),
        "PYTHONIOENCODING": "utf-8",
    }
    return subprocess.Popen(
        [sys.executable, str(ENTRY_POINT), "app-server", "--stdio", "--scenario", scenario],
        cwd=checkout,
        env=environment,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
