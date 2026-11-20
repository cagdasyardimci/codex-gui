"""Verify per-chat file tools and settle hidden buffers through installed Close and Quit."""

import argparse
from base64 import b64decode
import json
import os
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory
from urllib.parse import quote

from verify_coding_probe import fixture_executable

PIXEL = b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGMQSTnxHwAEEAJAKtk0QwAAAABJRU5ErkJggg==")
GUIDE = "Guide café #.md"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    args = parser.parse_args()
    with TemporaryDirectory(prefix="codex-gui-file-tools-") as scratch:
        root = Path(scratch).resolve()
        checkout = root / "Files checkout"
        profile = root / "codex home"
        data = root / "desktop"
        (checkout / "folder").mkdir(parents=True)
        profile.mkdir()
        for name, contents in {
            "folder/alpha.txt": b"Alpha\n",
            "beta.txt": b"Original beta\r\n",
            "adopt.txt": b"Original adoption\n",
            "conflict.txt": b"Original conflict\n",
            "search.txt": ("Heading\r\n" + "".join(f"Café marker {line:02d}\r\n" for line in range(1, 30))).encode("utf-8"),
            "filtered.log": "Café marker from an excluded log\n".encode("utf-8"),
            "replace.txt": b"Unique replacement target\n",
            GUIDE: b"# Local guide\r\n\r\nAlpha first.\r\nALPHA second.\r\n",
            "pixel.png": PIXEL,
            "pixel2.png": PIXEL,
        }.items():
            (checkout / name).write_bytes(contents)
        git = ["git", "-C", str(checkout), "-c", "user.name=File Fixture", "-c", "user.email=fixtures@example.invalid",
               "-c", "core.autocrlf=false", "-c", "commit.gpgsign=false"]
        subprocess.run([*git, "init", "-q"], check=True, capture_output=True)
        subprocess.run([*git, "add", "--", GUIDE], check=True, capture_output=True)
        subprocess.run([*git, "commit", "-qm", "Recorded guide"], check=True, capture_output=True)
        subprocess.run([*git, "remote", "add", "origin", "git@github.com:example/files.git"], check=True, capture_output=True)
        head = subprocess.check_output([*git, "rev-parse", "HEAD"], text=True).strip()
        trace = root / "trace.jsonl"
        result = subprocess.run(
            [args.app.resolve(strict=True), "--verify-file-tools", data, checkout],
            env={**os.environ, "CODEX_HOME": str(profile), "CODEX_EXECUTABLE": str(fixture_executable(root)),
                 "CODEX_GUI_QA_SCENARIO": "desktop-attachments", "CODEX_GUI_QA_TRACE": str(trace),
                 "CODEX_GUI_QA_STATE": str(root / "state.json"), "PYTHONIOENCODING": "utf-8"},
            capture_output=True, encoding="utf-8", errors="replace", timeout=85,
        )
        print(result.stdout, end="")
        if result.returncode or "Verified installed file tools and hidden-tab quit settlement" not in result.stdout:
            raise SystemExit(result.stderr or "The installed file tools fixture did not complete")
        assert (checkout / "beta.txt").read_bytes() == b"The first chat owns this file.\r\n"
        assert (checkout / "adopt.txt").read_bytes() == b"Keep the new chat file.\n"
        assert (checkout / "conflict.txt").read_bytes() == b"An external change\n"
        assert (checkout / "folder" / "alpha.txt").read_bytes() == b"Alpha\n"
        assert (checkout / "replace.txt").read_bytes() == (checkout / "retired-search.txt").read_bytes() == b"Unique replacement target\n"
        saved_guide = "# Saved guide\r\n\r\nPreserve café from the first chat.\r\n".encode("utf-8")
        assert (checkout / GUIDE).read_bytes() == (data / "copied-file").read_bytes() == (data / "exported-file").read_bytes() == saved_guide
        actions = [json.loads(line) for line in (data / "file-actions.jsonl").read_text(encoding="utf-8").splitlines()]
        assert [action["action"] for action in actions] == ["reveal", "default", "editor", "github"], actions
        assert all(Path(action["target"]).samefile(checkout / GUIDE) for action in actions[:3]), actions
        assert actions[2]["editor"] == "vscode", actions
        assert actions[3]["target"] == f"https://github.com/example/files/blob/{head}/{quote(GUIDE)}", actions
        assert not list(profile.iterdir())
        records = [json.loads(line) for line in trace.read_text(encoding="utf-8").splitlines()]
        requests = [entry for entry in records if entry["direction"] == "request"]
        starts = [entry for entry in requests if entry["method"] == "turn/start"]
        assert len(starts) == 1 and starts[0]["input"] == [
            {"type": "text", "text": "Start a chat with its existing file tab."},
        ], starts
        assert Path(starts[0]["resolvedCwd"]).samefile(checkout)
        print("Verified exact save, copy and export bytes, captured destinations, and file settlement after close and quit")


if __name__ == "__main__":
    main()
