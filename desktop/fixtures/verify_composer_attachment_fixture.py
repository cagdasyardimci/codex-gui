"""Verify draft attachment ownership in the packaged desktop app."""

import argparse
from base64 import b64decode
from contextlib import closing
import json
import os
from pathlib import Path
import sqlite3
import subprocess
from tempfile import TemporaryDirectory

from mock_backend import ENTRY_POINT
from verify_coding_probe import fixture_executable

PIXEL = b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGMQSTnxHwAEEAJAKtk0QwAAAABJRU5ErkJggg==")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    args = parser.parse_args()
    executable = args.app.resolve(strict=True)
    with TemporaryDirectory(prefix="codex-gui-composer-attachments-") as directory:
        root = Path(directory).resolve()
        checkout = root / "Attachment checkout café"
        checkout.mkdir()
        (checkout / "picked.png").write_bytes(PIXEL)
        (checkout / "notes.txt").write_text("Fixture note\n", encoding="utf-8")
        profile = root / "codex-home"
        profile.mkdir()
        data = root / "desktop"
        state = root / "backend.json"
        trace = root / "trace.jsonl"
        scenario = ENTRY_POINT.parent / "mock_backend" / "scenarios" / "desktop-history.json"
        threads = json.loads(scenario.read_text(encoding="utf-8"))["threads"]
        first = next(thread for thread in threads if thread["id"] == "history-first")
        first["turns"][0]["items"].append({
            "id": "recorded-file", "type": "userMessage", "content": [
                {"type": "mention", "name": "notes.txt", "path": "notes.txt"},
            ],
        })
        state.write_text(json.dumps({"threads": threads}, ensure_ascii=True), encoding="utf-8")
        result = subprocess.run(
            [str(executable), "--verify-attachments", str(data), str(checkout)],
            env={**os.environ, "CODEX_HOME": str(profile), "CODEX_EXECUTABLE": str(fixture_executable(root)),
                 "CODEX_GUI_QA_SCENARIO": "desktop-attachments", "CODEX_GUI_QA_STATE": str(state),
                 "CODEX_GUI_QA_TRACE": str(trace), "PYTHONIOENCODING": "utf-8"},
            encoding="utf-8", capture_output=True, errors="replace", timeout=75,
        )
        print(result.stdout, end="")
        if result.returncode or "Verified installed draft attachment capture" not in result.stdout:
            raise SystemExit(result.stderr or "The desktop attachment fixture did not complete")
        starts = [event for line in trace.read_text(encoding="utf-8").splitlines()
                  if (event := json.loads(line))["direction"] == "request" and event["method"] == "turn/start"]
        assert len(starts) == 1 and starts[0]["threadId"] == "history-first", starts
        inputs = starts[0]["input"]
        assert len(inputs) == 1 and inputs[0]["type"] == "localImage", inputs
        sent_path = Path(inputs[0]["path"]).resolve(strict=True)
        assert sent_path.is_relative_to(data) and sent_path.read_bytes() == PIXEL
        with closing(sqlite3.connect(data / "workspace.sqlite3")) as database:
            draft = database.execute(
                "SELECT d.text, d.context FROM drafts AS d JOIN thread_drafts AS t ON t.draft_id = d.id "
                "WHERE t.thread_id = 'history-first'"
            ).fetchone()
            assert draft and draft[0] == "Keep this text when reusing attachments.", draft
            context = json.loads(draft[1])
            assert [item["kind"] for item in context] == ["image", "fileReference"], context
            assert Path(context[0]["path"]).resolve() == sent_path and context[1]["path"] == "notes.txt", context
        assert not list(profile.iterdir())
        print("Verified one image-only send with identical stored bytes and retained reused references")


if __name__ == "__main__":
    main()
