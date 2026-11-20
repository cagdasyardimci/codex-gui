"""Exercise the AppKit worktree handoff and interruption boundary on installed Mac packages."""

import argparse
from contextlib import closing
import json
import os
from pathlib import Path
import plistlib
import sqlite3
import subprocess
from tempfile import TemporaryDirectory
from uuid import UUID

from verify_appkit_retirement import native_probe
from verify_diff_fixture import git


def attempt(arguments, expected, success=True, extra_environment=None):
    outcome = subprocess.run(arguments, env={**os.environ, **(extra_environment or {})},
                             encoding="utf-8", capture_output=True, timeout=30)
    assert (outcome.returncode == 0) == success, outcome.stdout + outcome.stderr
    assert expected in (outcome.stdout if success else outcome.stderr), outcome.stdout + outcome.stderr
    return outcome


def setup(root):
    original, checkouts, records, profile, staged, bundle = (
        root / "Project", root / "AppKit/checkouts", root / "AppKit/records",
        root / "Tauri", root / "Copied preferences", root / "Codex GUI.app",
    )
    for directory in (original, checkouts, records, profile, staged, bundle):
        directory.mkdir(parents=True)
    (profile / ".appkit-cutover-fixture").write_text("isolated cutover\n", encoding="utf-8")
    git(original, "init", "--quiet", "--template=")
    (original / "file.txt").write_text("Recorded version\n", encoding="utf-8")
    git(original, "add", "file.txt")
    git(original, "-c", "commit.gpgSign=false", "-c", "user.name=Fixture",
        "-c", "user.email=fixture@example.invalid", "commit", "--quiet", "-m", "Create source")
    base = subprocess.check_output(["git", "-C", original, "rev-parse", "HEAD"], encoding="utf-8").strip()
    identity = UUID(int=3)
    name = f"migrated-{identity}"
    checkout = checkouts / name
    branch = f"codex/task/{name}"
    git(original, "worktree", "add", "--quiet", "-b", branch, str(checkout))
    (checkout / "file.txt").write_text("Uncommitted migrated work\n", encoding="utf-8")
    (checkout / "new.txt").write_bytes(b"Untracked data\n")
    (original / "source.txt").write_bytes(b"Separate source draft\n")
    record = records / f"{identity}.json"
    payload = {"id": str(identity).upper(), "taskID": "imported-task", "threadID": "imported-thread",
               "sourceProjectPath": str(original), "repositoryGitDirectory": str(original / ".git"),
               "checkoutPath": str(checkout), "branch": branch, "baseCommit": base, "sourceWasDirty": True,
               "createdAt": 234, "phase": "active"}
    record.write_text(json.dumps({"version": 1, "workspace": payload}), encoding="utf-8")
    (staged / "preferences.plist").write_bytes(plistlib.dumps({
        "CodexGUI.pendingCommands": {str(checkout): json.dumps([
            {"threadID": "imported-thread", "turnID": "unfinished-turn", "itemID": "existing-command"},
        ]).encode("utf-8")},
        "CodexGUI.activeExecutionThreads": {str(checkout): ["imported-thread"]},
    }))
    return original, checkout, records, record, profile, staged, bundle


def registrations(original):
    return subprocess.check_output(["git", "-C", original, "worktree", "list", "--porcelain", "-z"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--appkit-repository", type=Path, required=True)
    args = parser.parse_args()
    app = args.app.resolve(strict=True)
    with TemporaryDirectory(prefix="codex-gui-appkit-transfer-") as temporary:
        root = Path(temporary).resolve()
        swift = native_probe(args.appkit_repository.resolve(strict=True), root)
        original, checkout, records, record, profile, staged, bundle = setup(root)
        attempt([app, "--import-appkit", staged, root / "original images", profile], '"unresolvedCommands":1')
        transfer = [app, "--transfer-appkit-worktrees"]
        prepare = [*transfer, "prepare", profile, records, bundle]
        commit = [*transfer, "commit", profile]
        abandon = [*transfer, "abandon", profile]
        legacy = [swift, records, "write"]
        journal = profile / "appkit-worktree-transfer.json"
        destination = profile / "worktrees" / record.name
        before = registrations(original)
        checkout_bytes = {name: (checkout / name).read_bytes() for name in ("file.txt", "new.txt", ".git")}
        assert subprocess.run(legacy, check=False, timeout=10).returncode == 0
        attempt(prepare, "Prepared the AppKit worktree handoff")
        attempt(commit, "retire the AppKit bundle", success=False)
        assert not destination.exists() and (records / ".lock").is_file()
        attempt(abandon, "Abandoned the prepared handoff")
        assert not journal.exists()
        assert subprocess.run(legacy, check=False, timeout=10).returncode == 0

        attempt(prepare, "Prepared the AppKit worktree handoff")
        snapshot = record.read_bytes()
        bundle.rename(root / "Retired fixture.app")
        changed = json.loads(snapshot)
        changed["workspace"]["sourceWasDirty"] = False
        record.write_text(json.dumps(changed), encoding="utf-8")
        attempt(commit, "changed after preparation", success=False)
        assert (records / ".lock").is_file() and not destination.exists()
        record.write_bytes(snapshot)

        attempt(commit, "fixture interrupted after AppKit retirement", success=False,
                extra_environment={"CODEX_GUI_QA_STOP_AFTER_APPKIT_SEAL": "1"})
        evidence = json.loads(journal.read_bytes())
        assert not evidence["completed"] and not destination.exists()
        assert (records / ".lock").readlink() == Path(".retired-by-tauri") / evidence["id"]
        assert subprocess.run(legacy, check=False, capture_output=True, timeout=10).returncode == 23
        attempt(abandon, "the AppKit handoff is already committed", success=False)
        attempt([*transfer, "resume", profile], "Reopened the AppKit worktree handoff")
        attempt(commit, "Committed the one-way AppKit worktree handoff")
        assert json.loads(journal.read_bytes())["completed"]
        migrated = json.loads(destination.read_bytes())["workspace"]
        assert migrated["checkoutPath"] == str(checkout) and migrated["threadID"] == "imported-thread"
        assert migrated["repositoryIdentity"].startswith("macos:") and migrated["checkoutIdentity"].startswith("macos:")
        assert registrations(original) == before and record.read_bytes() == snapshot
        assert {name: (checkout / name).read_bytes() for name in checkout_bytes} == checkout_bytes
        assert (original / "source.txt").read_bytes() == b"Separate source draft\n"
        with closing(sqlite3.connect(profile / "workspace.sqlite3")) as database:
            assert database.execute("SELECT thread_id, turn_id, item_id FROM exit_recovery").fetchall() == [
                ("imported-thread", "unfinished-turn", "existing-command")]
            assert database.execute("SELECT count(*) FROM appkit_unresolved_commands").fetchone() == (0,)
            assert database.execute("SELECT count(*) FROM desktop_appkit_execution_admission").fetchone() == (1,)
            assert database.execute("SELECT thread_id FROM appkit_active_threads").fetchall() == [("imported-thread",)]
        print("Verified abandonment before retirement, resumable one-way transfer, and unchanged dirty Git worktrees")


if __name__ == "__main__":
    main()
