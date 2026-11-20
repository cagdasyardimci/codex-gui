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
    parser.add_argument("--devices", action="store_true")
    args = parser.parse_args()
    app = args.app.resolve(strict=True)
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
        if not args.devices:
            conflict.touch()
        scenario = "desktop-relay-devices" if args.devices else "desktop-relay-host"
        mode = "--verify-relay-devices" if args.devices else "--verify-relay-host"
        initial, secondary = (source, managed) if args.devices else (managed, source)
        peer = root / "paired-devices.json"
        state = root / "backend.json"
        state.write_text('{"config": {}}', encoding="utf-8")
        result = subprocess.run([app, mode, data, initial, secondary], env={
            **os.environ, "CODEX_HOME": str(profile), "CODEX_EXECUTABLE": str(fixture_executable(root)),
            "CODEX_GUI_QA_RELAY_CONFLICT": str(conflict), "CODEX_GUI_QA_RELAY_AWAKE": str(awake),
            "CODEX_GUI_QA_SCENARIO": scenario, "CODEX_GUI_QA_STATE": str(state),
            "CODEX_GUI_QA_RELAY_DEVICES": str(peer), "CODEX_GUI_QA_RELAY_SOURCE": str(source),
            "CODEX_GUI_QA_TRACE": str(trace), "PYTHONIOENCODING": "utf-8",
        }, capture_output=True, encoding="utf-8", errors="replace", timeout=100)
        print(result.stdout, end="")
        prefix = "Verified installed desktop voice: "
        summary = [json.loads(line.removeprefix(prefix)) for line in result.stdout.splitlines() if line.startswith(prefix)]
        events = sorted(
            (json.loads(line) for part in root.glob(f"{trace.name}.*")
             for line in part.read_text(encoding="utf-8").splitlines()),
            key=lambda event: event["time"],
        )
        if result.returncode or len(summary) != 1:
            print("Fixture requests:", [row["method"] for row in events if row["direction"] == "request"][-24:])
            print("Relay fixture trace:", [row for row in events if row["direction"] == "relay-host"][-20:])
            raise SystemExit(result.stderr or "The installed relay host fixture did not finish")
        (result,) = summary
        relay = [row for row in events if row["direction"] == "relay-host"]
        assert relay and all(Path(event["cwd"]).samefile(source) for event in relay)
        if args.devices:
            verify_devices(result, events, relay, peer, data, profile, source)
            return
        assert result["first"]["phase"] == result["hidden"]["phase"] == "connected" and not result["disabled"]["enabled"]
        enabled = [row["process"] for row in relay if row["method"] == "remoteControl/enable"]
        disabled = [row["process"] for row in relay if row["method"] == "remoteControl/disable"]
        assert len(enabled) == 3 and enabled[0] == enabled[1] and enabled[1] != enabled[2], enabled
        assert disabled == [enabled[0], enabled[2]]
        mutations = {"remoteControl/enable", "remoteControl/disable"}
        reads = {"remoteControl/status/read", "remoteControl/client/list"}
        assert {row["method"] for row in relay} <= mutations | reads, relay
        assert all(row["params"] == {"ephemeral": True} for row in relay if row["method"] in mutations), relay
        assert awake.read_text(encoding="utf-8").splitlines() == ["hold", "release", "hold", "release"]
        preferences = json.loads((data / "remote-host-v1.json").read_text(encoding="utf-8"))
        assert preferences["enabled"] is False and preferences["keepAwake"] is True
        assert Path(preferences["source"]["path"]).samefile(source) and not list(profile.iterdir())
        print("Verified source-only hosting, duplicate outcome, reconnect, and awake lease release")


def verify_devices(result, events, relay, peer, data, profile, source):
    enabled = [row["process"] for row in relay if row["method"] == "remoteControl/enable"]
    assert len(enabled) == 3 and len(set(enabled)) == 3, enabled
    pairings = [row["params"] for row in relay if row["method"] == "remoteControl/pairing/start"]
    assert pairings == [{"manualCode": True}] * 5
    (revoke,) = [row["params"] for row in relay if row["method"] == "remoteControl/client/revoke"]
    assert revoke == {"environmentId": f"fixture-environment-{enabled[0]}", "clientId": "fixture-device-3"}
    assert any(row["params"].get("cursor") == "fixture-next-devices" for row in relay)
    assert any(row.get("error", {}).get("message") == "Fixture stale device list read" for row in events)
    assert not any(row.get("method") == "turn/start" for row in events)
    (project,) = [row for row in events if row["direction"] == "relay-peer-project"]
    assert Path(project["projectPath"]).samefile(source)
    approvals = [row for row in events if row["direction"] == "relay-approval"]
    assert [row["process"] for row in approvals] == enabled[1:]
    assert {row["params"]["threadId"] for row in approvals} == {result["chat"]}
    assert {row["params"]["turnId"] for row in approvals} == {"relay-mobile-turn"}
    (ack,) = [row["result"] for row in events if row["direction"] == "command-approval-response"]
    assert ack == {"decision": "accept"}
    persisted = json.loads(peer.read_text(encoding="utf-8"))
    assert persisted["peerTurn"] == "completed" and persisted["devices"] == [
        {"clientId": "fixture-device-4", "displayName": "Fixture Computer"},
    ]
    assert "FIXTURE-" not in (data / "remote-host-v1.json").read_text(encoding="utf-8")
    assert not list(profile.iterdir())
    print("Verified phone and computer enrollment, credential retirement, exact revocation, peer discovery, and approval recovery")


if __name__ == "__main__":
    main()
