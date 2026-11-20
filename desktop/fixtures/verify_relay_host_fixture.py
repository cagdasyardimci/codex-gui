"""Verify the installed relay owner and the awake lease with an isolated backend."""

import argparse
import json
import os
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory
from uuid import uuid4

from verify_coding_probe import fixture_executable
from verify_diff_fixture import git


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    app = parser.parse_args().app.resolve(strict=True)
    with TemporaryDirectory(prefix="codex-gui-relay-host-") as scratch:
        root = Path(scratch).resolve()
        data, profile, source, managed = (root / name for name in (
            "desktop", "isolated Codex profile", "Source relay checkout", "Managed relay checkout",
        ))
        for folder in (data, profile, source):
            folder.mkdir()
        git(source, "init", "--quiet", "--template=")
        git(source, "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
            "-c", "commit.gpgSign=false", "commit", "--allow-empty", "--quiet", "-m", "Relay source")
        git(source, "worktree", "add", "--quiet", "-b", "fixture-remote-task", str(managed))
        commit = subprocess.check_output(["git", "-C", source, "rev-parse", "HEAD"], encoding="utf-8").strip()
        records = data / "worktrees"
        records.mkdir()
        (records / ".authority").write_text('{"version":1,"edition":"tauri"}', encoding="utf-8")
        record = str(uuid4())
        workspace = {"id": record, "taskID": "fixture-remote-task", "sourceProjectPath": str(source),
                     "repositoryGitDirectory": str(source / ".git"), "checkoutPath": str(managed),
                     "branch": "fixture-remote-task", "baseCommit": commit, "sourceWasDirty": False,
                     "createdAt": 1, "phase": "active"}
        (records / f"{record}.json").write_text(json.dumps({"version": 1, "workspace": workspace}), encoding="utf-8")
        trace, conflict, awake = (root / name for name in ("trace.jsonl", "duplicate-host", "awake.log"))
        conflict.touch()
        result = subprocess.run([app, "--verify-relay-host", data, managed, source], env={
            **os.environ, "CODEX_HOME": str(profile), "CODEX_EXECUTABLE": str(fixture_executable(root)),
            "CODEX_GUI_QA_RELAY_CONFLICT": str(conflict), "CODEX_GUI_QA_RELAY_AWAKE": str(awake),
            "CODEX_GUI_QA_SCENARIO": "desktop-relay-host", "CODEX_GUI_QA_STATE": str(root / "backend.json"),
            "CODEX_GUI_QA_TRACE": str(trace), "PYTHONIOENCODING": "utf-8",
        }, capture_output=True, encoding="utf-8", errors="replace", timeout=100)
        print(result.stdout, end="")
        prefix = "Verified installed desktop voice: "
        summary = [json.loads(line.removeprefix(prefix)) for line in result.stdout.splitlines() if line.startswith(prefix)]
        if result.returncode or len(summary) != 1:
            if trace.exists():
                print("Relay fixture trace:", [json.loads(line) for line in trace.read_text(encoding="utf-8").splitlines()
                                               if '"direction": "relay-host"' in line])
            raise SystemExit(result.stderr or "The installed relay host fixture did not finish")
        (result,) = summary
        assert result["first"]["phase"] == result["hidden"]["phase"] == "connected" and not result["disabled"]["enabled"]
        events = [json.loads(line) for line in trace.read_text(encoding="utf-8").splitlines()]
        relay = [row for row in events if row["direction"] == "relay-host"]
        assert relay and all(Path(event["cwd"]).samefile(source) for event in relay)
        enabled = [row["process"] for row in relay if row["method"] == "remoteControl/enable"]
        disabled = [row["process"] for row in relay if row["method"] == "remoteControl/disable"]
        assert len(enabled) == 3 and enabled[0] == enabled[1] and enabled[1] != enabled[2], enabled
        assert disabled == [enabled[0], enabled[2]]
        assert all(row["params"] == {"ephemeral": True} for row in relay if not row["method"].endswith("/read"))
        assert awake.read_text(encoding="utf-8").splitlines() == ["hold", "release", "hold", "release"]
        preferences = json.loads((data / "remote-host-v1.json").read_text(encoding="utf-8"))
        assert preferences["enabled"] is False and preferences["keepAwake"] is True
        assert Path(preferences["source"]["path"]).samefile(source) and not list(profile.iterdir())
        print("Verified source-only hosting, duplicate outcome, reconnect, and awake lease release")


if __name__ == "__main__":
    main()
