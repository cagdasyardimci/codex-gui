"""Exercise lazy patches in the installed app against an isolated Git checkout."""

import argparse
from base64 import b64decode
from contextlib import closing
import json
import os
from pathlib import Path
import subprocess
import sqlite3
from tempfile import TemporaryDirectory

from verify_coding_probe import fixture_executable


def git(checkout: Path, *args: str) -> None:
    subprocess.run(["git", "--literal-pathspecs", "-C", str(checkout), *args], check=True,
                   stdout=subprocess.DEVNULL, timeout=15)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    app = parser.parse_args().app.resolve(strict=True)
    with TemporaryDirectory(prefix="codex-gui-diff-") as scratch:
        root = Path(scratch).resolve()
        checkout = root / "Checkout café"
        checkout.mkdir()
        codex_home = root / "codex home"
        codex_home.mkdir()
        tracked = checkout / "notes café [draft].txt"
        untracked = checkout / "untracked café.txt"
        prefix = "".join(f"Context {index:02d}\n" for index in range(1, 16))
        suffix = "".join(f"Following {index:02d}\n" for index in range(1, 16))

        def content(line):
            return f"{prefix}{line}\n{suffix}".encode("utf-8")

        git(checkout, "init", "--quiet", "--template=")
        git(checkout, "config", "--local", "core.autocrlf", "false")
        tracked.write_bytes(content("Before café"))
        git(checkout, "add", "--", tracked.name)
        git(checkout, "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
            "-c", "commit.gpgSign=false", "commit", "--quiet", "-m", "Create fixture")
        git(checkout, "branch", "comparison-base")
        tracked.write_bytes(content("Staged café"))
        git(checkout, "add", "--", tracked.name)
        tracked.write_bytes(content("After 日本語"))
        untracked.write_bytes("Untracked café\n".encode())
        (checkout / "compared.md").write_bytes(b"# Compared Markdown\n\n**Captured content**\n")
        (checkout / "pixel.png").write_bytes(b64decode(
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGMQSTnxHwAEEAJAKtk0QwAAAABJRU5ErkJggg=="))
        index = checkout / ".git" / "index"
        before = index.read_bytes()
        git_trace = root / "git.jsonl"
        data = root / "beta data"
        result = subprocess.run(
            [str(app), "--verify-diff", str(data), str(checkout)],
            env={
                **os.environ,
                "CODEX_EXECUTABLE": str(fixture_executable(root)),
                "CODEX_HOME": str(codex_home),
                "CODEX_GUI_QA_SCENARIO": "desktop-history",
                "CODEX_GUI_QA_STATE": str(root / "state.json"),
                "GIT_TRACE2_EVENT": str(git_trace),
                "PYTHONIOENCODING": "utf-8",
            },
            timeout=60, capture_output=True, encoding="utf-8", errors="replace",
        )
        print(result.stdout, end="")
        if result.returncode or "Verified installed checkout changes" not in result.stdout:
            raise SystemExit(result.stderr or "The installed workspace did not confirm the diff fixture")
        entries = [json.loads(line) for line in git_trace.read_text(encoding="utf-8").splitlines()]
        diffs = [entry["argv"] for entry in entries if entry.get("event") == "start" and "diff" in entry["argv"]]
        detail_queries = [arguments for arguments in diffs if "--patch" in arguments or "--no-index" in arguments]
        assert detail_queries and all("--literal-pathspecs" in arguments for arguments in detail_queries), detail_queries
        assert detail_queries[0][-1] == tracked.name and "--raw" in detail_queries[0], detail_queries
        assert any(arguments[-1] == untracked.name and "--no-index" in arguments for arguments in detail_queries)
        assert (data / "diff-exported-file").read_bytes() == (data / "diff-editor-file").read_bytes() == content("After 日本語")
        captured_patch = (data / "diff-exported-patch").read_bytes()
        assert captured_patch == (data / "diff-copied").read_bytes()
        assert b"-Before caf\xc3\xa9" in captured_patch and "+After 日本語".encode("utf-8") in captured_patch
        assert b"External revision" not in captured_patch
        with closing(sqlite3.connect(data / "workspace.sqlite3")) as database:
            assert database.execute("SELECT hunk FROM desktop_review_markers ORDER BY hunk").fetchall() == [(-1,), (0,)]
        assert index.read_bytes() == before
        assert tracked.read_bytes() == content("External revision")
        assert untracked.read_bytes() == "Untracked café\n".encode()
        assert not list(codex_home.iterdir())
        print("Verified lazy comparison details, review fingerprints, exact captured exports, and an untouched Git index")


if __name__ == "__main__":
    main()
