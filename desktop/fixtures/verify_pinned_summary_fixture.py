"""Verify the installed chat summary with scoped source previews and Git changes."""

import argparse
from base64 import b64decode
import json
import os
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory

from verify_coding_probe import fixture_executable

PNG = b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGMQSTnxHwAEEAJAKtk0QwAAAABJRU5ErkJggg=="
)


def thread(label, file_change):
    return {
        "id": f"history-{label.lower()}", "name": f"{label} fixture chat", "preview": "",
        "turns": [{
            "id": f"{label.lower()}-summary-turn", "status": "completed", "startedAt": 1,
            "items": [
                {"type": "userMessage", "id": "own-source", "content": [
                    {"type": "text", "text": f"{label} summary prompt"},
                    {"type": "localImage", "path": f"{label.lower()}-source.png"},
                ]},
                {"type": "fileChange", "id": "edits", "status": "completed", "changes": [file_change]},
            ],
        }],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    args = parser.parse_args()
    with TemporaryDirectory(prefix="codex-gui-pinned-summary-") as scratch:
        root = Path(scratch).resolve()
        project = root / "Summary checkout"
        profile = root / "codex home"
        project.mkdir()
        profile.mkdir()
        for name in ("first-source.png", "second-source.png"):
            (project / name).write_bytes(PNG)
        notes = project / "tracked.txt"
        notes.write_bytes(b"before\n")
        subprocess.run(["git", "init", "--quiet", project], check=True)
        subprocess.run(["git", "-C", project, "add", "."], check=True)
        subprocess.run(["git", "-C", project, "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                        "commit", "--quiet", "--no-gpg-sign", "-m", "Fixture"], check=True)
        notes.write_bytes(b"after\n")
        trace = root / "trace.jsonl"
        state = root / "backend.json"
        state.write_text(json.dumps({"threads": [
            thread("First", {"path": "tracked.txt", "kind": {"type": "update"}, "diff": "@@ -1 +1 @@\n-before\n+after"}),
            thread("Second", {"path": "new.txt", "kind": {"type": "add"}, "diff": "one\ntwo\n"}),
        ]}), encoding="utf-8")
        result = subprocess.run(
            [args.app.resolve(strict=True), "--verify-pinned-summary", root / "desktop", project],
            env={
                **os.environ,
                "CODEX_HOME": str(profile),
                "CODEX_EXECUTABLE": str(fixture_executable(root)),
                "CODEX_GUI_QA_SCENARIO": "desktop-attachments",
                "CODEX_GUI_QA_TRACE": str(trace),
                "CODEX_GUI_QA_STATE": str(state),
                "PYTHONIOENCODING": "utf-8",
            },
            capture_output=True, encoding="utf-8", errors="replace", timeout=75,
        )
        print(result.stdout, end="")
        if result.returncode or "Verified installed scoped pinned chat summaries" not in result.stdout:
            raise SystemExit(result.stderr or "The installed summary fixture did not complete")
        requests = [entry for line in trace.read_text(encoding="utf-8").splitlines()
                    if (entry := json.loads(line))["direction"] == "request"]
        assert not any(request["method"] in ("thread/start", "turn/start") for request in requests)
        assert notes.read_bytes() == b"after\n"
        assert not list(profile.iterdir())
        print("Verified per-chat summary visibility, distinct previews and totals, and preserved Changes handles")


if __name__ == "__main__":
    main()
