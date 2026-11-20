"""Exercise lazy patches in the installed app against an isolated Git checkout."""

import argparse
import json
import os
from pathlib import Path
import subprocess
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
        git(checkout, "init", "--quiet", "--template=")
        git(checkout, "config", "--local", "core.autocrlf", "false")
        tracked.write_bytes("Before café\n".encode())
        git(checkout, "add", "--", tracked.name)
        git(checkout, "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
            "-c", "commit.gpgSign=false", "commit", "--quiet", "-m", "Create fixture")
        tracked.write_bytes("Staged café\n".encode())
        git(checkout, "add", "--", tracked.name)
        tracked.write_bytes("After 日本語\n".encode())
        untracked.write_bytes("Untracked café\n".encode())
        index = checkout / ".git" / "index"
        before = index.read_bytes()
        git_trace = root / "git.jsonl"
        result = subprocess.run(
            [str(app), "--verify-diff", str(root / "beta data"), str(checkout)],
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
        assert len(diffs) == 4, diffs
        summary, tracked_patch, untracked_patch, refresh = diffs
        assert "--name-status" in summary and "--name-status" in refresh
        assert tracked_patch[-1] == tracked.name and "--literal-pathspecs" in tracked_patch, tracked_patch
        assert untracked_patch[-1] == untracked.name and "--no-index" in untracked_patch, untracked_patch
        assert index.read_bytes() == before
        assert tracked.read_bytes() == "After 日本語\n".encode()
        assert untracked.read_bytes() == "Untracked café\n".encode()
        assert not list(codex_home.iterdir())
        print("Verified each patch ran only after selection and Git left the checkout unchanged")


if __name__ == "__main__":
    main()
