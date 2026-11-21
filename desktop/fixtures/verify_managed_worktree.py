"""Exercise creation and binding of a managed checkout through the installed app."""

import argparse
from contextlib import closing
import json
import os
import shutil
from pathlib import Path
import sqlite3
import subprocess
from tempfile import TemporaryDirectory

from verify_coding_probe import fixture_executable
from verify_diff_fixture import git


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    app = parser.parse_args().app.resolve(strict=True)
    with TemporaryDirectory(prefix="codex-gui-managed-worktree-") as temporary:
        root = Path(temporary).resolve()
        source, profile, home = (root / name for name in ("Source project", "Desktop", "Codex home"))
        for folder in (source, profile, home):
            folder.mkdir()
        intermediate = root / "Path spelling"
        intermediate.mkdir()
        profile_argument = intermediate / ".." / profile.name
        git(source, "init", "--quiet", "--template=")
        git(source, "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
            "-c", "commit.gpgSign=false", "commit", "--allow-empty", "--quiet", "-m", "Establish source HEAD")
        (source / "dirty.txt").write_bytes(b"Keep this file in the source checkout\n")
        trace = root / "trace.jsonl"
        state = root / "state.json"
        environment = {
            **os.environ, "CODEX_EXECUTABLE": str(fixture_executable(root)),
            "CODEX_HOME": str(home), "CODEX_GUI_QA_SCENARIO": "desktop-history",
            "CODEX_GUI_QA_STATE": str(state), "PYTHONIOENCODING": "utf-8",
        }
        requests = run(app, profile_argument, source, trace, environment)
        (record,) = (profile / "worktrees").glob("*.json")
        workspace = json.loads(record.read_bytes())["workspace"]
        checkout = Path(workspace["checkoutPath"])
        assert checkout.parent.samefile(root / "Desktop-checkouts") and workspace["sourceWasDirty"]
        assert not (checkout / "dirty.txt").exists() and (source / "dirty.txt").is_file()
        (thread,) = [row for row in requests if row["method"] == "thread/start"]
        (turn,) = [row for row in requests if row["method"] == "turn/start"]
        assert Path(thread["params"]["cwd"]).samefile(checkout) and Path(turn["resolvedCwd"]).samefile(checkout)
        bound_thread = workspace.get("threadID")
        assert bound_thread == turn["params"]["threadId"], "The managed checkout lost its thread binding"
        assert not list(home.iterdir())
        with closing(sqlite3.connect(profile / "workspace.sqlite3")) as database:
            assert database.execute(
                "SELECT text FROM drafts WHERE text = 'Keep the original draft in the source checkout.'"
            ).fetchall() == [("Keep the original draft in the source checkout.",)]
        print("Verified native managed checkout creation, durable binding, and source draft isolation")

        # Recreate the boundary after the worktree record committed and before the draft was promoted.
        bound = record.read_bytes()
        original_profile = root / "Original desktop"
        profile.rename(original_profile)
        profile.mkdir()
        shutil.copytree(original_profile / "worktrees", profile / "worktrees")
        backend = json.loads(state.read_bytes())
        (pending,) = [row for row in backend["threads"] if row["id"] == bound_thread]
        pending["turns"] = []
        state.write_text(json.dumps(backend), encoding="utf-8")
        recovered = run(app, profile_argument, checkout, root / "recovery.jsonl", environment)
        assert not any(row["method"] == "thread/start" for row in recovered), recovered
        (resume,) = [row["params"] for row in recovered if row["method"] == "thread/resume"]
        (retry,) = [row["params"] for row in recovered if row["method"] == "turn/start"]
        assert resume["threadId"] == retry["threadId"] == bound_thread
        assert Path(resume["cwd"]).samefile(checkout) and record.read_bytes() == bound
        print("Verified recovery of a managed thread after binding and before draft promotion")


def run(app, profile, checkout, trace, environment):
    process = subprocess.run([app, "--verify-managed-worktree", profile, checkout], env={
        **environment, "CODEX_GUI_QA_TRACE": str(trace),
    }, capture_output=True, encoding="utf-8", errors="replace", timeout=60)
    if process.returncode or "Verified installed managed worktree" not in process.stdout:
        raise AssertionError(process.stderr or process.stdout)
    return [row for row in map(json.loads, trace.read_text(encoding="utf-8").splitlines())
            if row["direction"] == "request"]


if __name__ == "__main__":
    main()
