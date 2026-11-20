"""Verify confirmed chat deletion and retained managed-checkout data."""

import argparse
from contextlib import closing
import json
import os
from pathlib import Path
import sqlite3
import subprocess
from tempfile import TemporaryDirectory

from verify_coding_probe import fixture_executable


def git(path, *arguments):
    return subprocess.check_output(["git", "-C", path, *arguments], encoding="utf-8").strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    args = parser.parse_args()
    with TemporaryDirectory(prefix="codex-gui-chat-deletion-") as scratch:
        root = Path(scratch).resolve()
        project = root / "Deletion source"
        profile = root / "codex home"
        for directory in (project, profile):
            directory.mkdir()
        git(project, "init", "--quiet", "--initial-branch=main")
        (project / "tracked.txt").write_text("Preserve the source repository.", encoding="utf-8")
        git(project, "add", "tracked.txt")
        git(project, "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
            "commit", "--quiet", "--no-gpg-sign", "-m", "Fixture")

        data = root / "desktop"
        trace = root / "trace.jsonl"
        state = root / "backend.json"
        threads = [
            {"id": "history-first", "name": "First fixture chat", "preview": ""},
            {"id": "history-second", "name": "Second fixture chat", "preview": ""},
            {"id": "archived-chat", "name": "Archived example", "preview": "", "archived": True},
            {"id": "uncertain-delete", "name": "Uncertain fixture chat", "preview": ""},
            {"id": "managed-chat", "name": "Managed fixture chat", "preview": ""},
        ]
        state.write_text(json.dumps({"threads": threads}), encoding="utf-8")
        environment = {
            **os.environ,
            "CODEX_HOME": str(profile),
            "CODEX_EXECUTABLE": str(fixture_executable(root)),
            "CODEX_GUI_QA_SCENARIO": "desktop-chat-deletion",
            "CODEX_GUI_QA_TRACE": str(trace),
            "CODEX_GUI_QA_STATE": str(state),
            "PYTHONIOENCODING": "utf-8",
        }
        result = subprocess.run(
            [args.app.resolve(strict=True), "--verify-chat-deletion", data, project], env=environment,
            capture_output=True, encoding="utf-8", errors="replace", timeout=100,
        )
        print(result.stdout, end="")
        if result.returncode or "Verified installed scoped permanent chat deletion" not in result.stdout:
            raise SystemExit(result.stderr or "The installed deletion fixture did not complete")
        assert "the recorded checkout contains changes or ignored files" in result.stderr, result.stderr
        requests = [request for line in trace.read_text(encoding="utf-8").splitlines()
                    if (request := json.loads(line))["direction"] == "request"]
        expected = ["history-first", "archived-chat", "uncertain-delete", "managed-chat"]
        deletes = [request["params"] for request in requests if request["method"] == "thread/delete"]
        assert deletes == [{"threadId": thread} for thread in expected], deletes
        assert not any(request["method"] in ("thread/start", "turn/start") for request in requests)
        backend = json.loads(state.read_text(encoding="utf-8"))
        assert backend["retiredDuringDelete"]
        assert {thread["id"] for thread in backend["threads"]} == {"history-second", "uncertain-delete"}
        with closing(sqlite3.connect(data / "workspace.sqlite3")) as database:
            assert database.execute(
                "SELECT thread_id, confirmed FROM desktop_chat_deletions ORDER BY thread_id"
            ).fetchall() == [("archived-chat", 1), ("history-first", 1), ("managed-chat", 1), ("uncertain-delete", 0)]
            assert database.execute(
                "SELECT thread_id, text FROM thread_drafts JOIN drafts ON draft_id = id ORDER BY thread_id"
            ).fetchall() == [("uncertain-delete", "Keep the draft after a lost deletion reply.")]

        (record_file,) = (data / "worktrees").glob("*.json")
        record = json.loads(record_file.read_text(encoding="utf-8"))["workspace"]
        checkout = Path(record["checkoutPath"])
        assert record["phase"] == "active" and record["threadID"] == "managed-chat"
        assert (checkout / "keep-local.txt").read_bytes() == b"Local work must survive chat deletion."
        assert git(project, "rev-parse", f"refs/heads/{record['branch']}") == git(project, "rev-parse", "HEAD")
        assert git(project, "status", "--porcelain") == ""
        assert not list(profile.iterdir())
        print("Verified exact captured deletions, no uncertain replay, and preserved dirty worktree, branch, and draft")


if __name__ == "__main__":
    main()
