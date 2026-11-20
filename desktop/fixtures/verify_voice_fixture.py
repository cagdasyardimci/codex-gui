"""Verify installed chat-bound WebRTC with an isolated synthetic media pair."""

import argparse
import json
import os
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory

from verify_coding_probe import fixture_executable


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    variants = parser.add_mutually_exclusive_group()
    variants.add_argument("--reconnect", action="store_true")
    variants.add_argument("--no-fallback", action="store_true")
    variants.add_argument("--handoff", action="store_true")
    arguments = parser.parse_args()
    app = arguments.app.resolve(strict=True)
    with TemporaryDirectory(prefix="codex-gui-voice-") as scratch:
        root = Path(scratch).resolve()
        data, profile, checkout = (root / name for name in ("desktop", "isolated Codex profile", "Voice fixture"))
        for directory in (data, profile, checkout):
            directory.mkdir()
        subprocess.run(["git", "init", "--quiet", checkout], check=True)
        secondary = root / "Other voice checkout"
        if arguments.handoff:
            secondary.mkdir()
            subprocess.run(["git", "init", "--quiet", secondary], check=True)
        (checkout / "notes.txt").write_text("A fixture attachment\n", encoding="utf-8")
        skill = checkout / "skill"
        skill.mkdir()
        (skill / "SKILL.md").write_text("# Review fixture\n", encoding="utf-8")
        state = root / "mock.json"
        provider = {"experimental_bearer_token": "fixture-only"}
        if arguments.no_fallback:
            provider["env_key"] = "CODEX_GUI_FIXTURE_REQUIRED_VOICE_KEY"
        configuration = {"model_provider": "openai", "model": "fixture-default",
                         "model_providers": {"openai": provider}}
        if arguments.handoff:
            configuration.update({"model_reasoning_effort": "high", "approval_policy": "untrusted",
                                  "sandbox_mode": "workspace-write", "approvals_reviewer": "user",
                                  "sandbox_workspace_write": {"network_access": False}, "service_tier": "flex"})
        state_seed = json.dumps({"config": configuration})
        state.write_text(state_seed, encoding="utf-8")
        if arguments.handoff:
            Path(str(state) + ".other").write_text(state_seed, encoding="utf-8")
        voice_settings = root / "voice-settings.json"
        voice_settings.write_text(json.dumps({"voice": "cedar" if arguments.reconnect else "marin", "version": 1}),
                                  encoding="utf-8")
        trace = root / "trace.jsonl"
        exchange = data / "voice-exchange.json"
        if arguments.reconnect:
            fixture = "--verify-voice-reconnect"
        elif arguments.no_fallback:
            fixture = "--verify-voice-no-fallback"
        elif arguments.handoff:
            fixture = "--verify-voice-handoff"
        else:
            fixture = "--verify-voice"
        scenario = "desktop-voice" if fixture == "--verify-voice" else "desktop-voice-reconnect"
        if arguments.handoff:
            scenario = "desktop-voice-handoff"
        environment = os.environ.copy()
        environment.pop("OPENAI_API_KEY", None)
        environment.pop("CODEX_GUI_FIXTURE_REQUIRED_VOICE_KEY", None)
        command = [app, fixture, data, checkout]
        if arguments.handoff:
            command.append(secondary)
            environment["CODEX_GUI_QA_VOICE_SECONDARY"] = str(secondary)
            environment["CODEX_GUI_QA_HANDOFF_TRIGGER"] = str(data / "voice-handoff-trigger")
        result = subprocess.run(
            command,
            env={**environment, "CODEX_HOME": str(profile), "CODEX_EXECUTABLE": str(fixture_executable(root)),
                 "CODEX_GUI_QA_SCENARIO": scenario, "CODEX_GUI_QA_STATE": str(state),
                 "CODEX_GUI_QA_TRACE": str(trace), "CODEX_GUI_QA_VOICE_EXCHANGE": str(exchange),
                 "CODEX_GUI_QA_VOICE_SETTINGS": str(voice_settings),
                 "PYTHONIOENCODING": "utf-8"},
            capture_output=True, encoding="utf-8", errors="replace", timeout=105,
        )
        print(result.stdout, end="")
        prefix = "Verified installed desktop voice: "
        summaries = [line.removeprefix(prefix) for line in result.stdout.splitlines() if line.startswith(prefix)]
        if result.returncode or len(summaries) != 1:
            raise SystemExit(result.stderr or "The installed voice fixture did not finish")
        summary = json.loads(summaries[0])
        trace_lines = [json.loads(line) for line in trace.read_text(encoding="utf-8").splitlines()]
        if arguments.no_fallback:
            starts = [row["params"] for row in trace_lines
                      if row["direction"] == "request" and row["method"] == "thread/realtime/start"]
            (attempted,) = starts
            assert attempted["transport"]["type"] == "webrtc" and attempted["threadId"] == summary["closedChat"]
            assert any(row["direction"] == "event" and row.get("reason") == "fixture-startup-closed"
                       for row in trace_lines)
            print("Verified WebRTC-only admission when the effective provider key is missing")
            return
        if arguments.handoff:
            verify_handoff(summary, trace_lines, checkout)
            return
        if arguments.reconnect:
            verify_reconnect(summary, trace_lines, voice_settings)
            return
        owner = summary["owner"]["chatId"]
        assert summary["owner"]["media"] == ("native" if os.name == "posix" and os.uname().sysname == "Linux" else "webview")
        assert summary["duplex"] == {"receiving": True, "sending": True, "microphoneMuted": False, "speakerMuted": False}
        requests = [record for record in trace_lines if record.get("direction") == "request"]
        groups = {method: [record["params"] for record in requests if record["method"] == method] for method in
                  ("thread/start", "thread/realtime/start", "thread/realtime/appendText", "thread/realtime/stop", "turn/start",
                   "thread/queue/add", "thread/queue/update", "config/value/write", "thread/realtime/appendSpeech")}
        (created,) = [request for request in groups["thread/start"] if not request.get("ephemeral")]
        assert created["historyMode"] == "paginated"
        assert len([request for request in groups["thread/start"] if request.get("ephemeral")]) == 2
        (started,) = [request for request in groups["thread/realtime/start"] if request["transport"]["type"] == "webrtc"]
        samples = [request for request in groups["thread/realtime/start"] if request["transport"]["type"] == "websocket"]
        assert [sample["voice"] for sample in samples] == ["rindo", "cedar"]
        sampled_threads = {sample["threadId"] for sample in samples}
        speech = groups["thread/realtime/appendSpeech"]
        assert {sample["threadId"] for sample in speech} == sampled_threads
        assert speech[0]["text"].startswith("こんにちは") and speech[1]["text"].startswith("Hello")
        assert sampled_threads.issubset({request["threadId"] for request in groups["thread/realtime/stop"]})
        (saved,) = groups["config/value/write"]
        assert saved["keyPath"] == "realtime.voice" and saved["expectedVersion"] == "1" and saved["value"] == "cedar"
        assert json.loads(voice_settings.read_text(encoding="utf-8")) == {"voice": "cedar", "version": 2}
        assert started["voice"] == "cedar"
        (append,) = groups["thread/realtime/appendText"]
        (stopped,) = [request for request in groups["thread/realtime/stop"] if request["threadId"] == owner]
        assert started["threadId"] == append["threadId"] == stopped["threadId"] == owner
        assert started["realtimeSessionId"] == summary["owner"]["id"]
        assert append["text"] == "Text to the captured voice call"
        other, attached, structured, held = groups["turn/start"]
        assert other["threadId"] == "history-second"
        assert attached["threadId"] == structured["threadId"] == held["threadId"] == owner
        assert any(item.get("type") == "mention" and item.get("name") == "notes.txt" for item in attached["input"])
        assert any(item.get("type") == "skill" and item.get("name") == "Review fixture" for item in structured["input"])
        assert any("Preserve the captured project context." in item.get("text", "") for item in structured["input"])
        (queued,) = groups["thread/queue/add"]
        (edited,) = groups["thread/queue/update"]
        assert queued["threadId"] == edited["threadId"] == owner
        assert [item["text"] for item in queued["input"]] == ["Original queued input"]
        assert [item["text"] for item in edited["input"]] == ["Revised queued input"]
        assert any(line["direction"] == "event" and line["method"] == "thread/realtime/closed"
                   and line["threadId"] == owner for line in trace_lines)
        print("Verified V3 voice selection, scoped speech preview retirement, and the saved voice on the next call")
        print("Verified duplex media, independent mute, captured text, structured coding, queue edits, and exact session closure")


def verify_reconnect(summary, trace, voice_settings):
    dropped, fallback, restored = (summary[key] for key in ("dropped", "fallback", "restored"))
    owner = dropped["chatId"]
    assert fallback["chatId"] == restored["chatId"] == owner
    assert summary["duplex"] == {"receiving": True, "sending": True, "microphoneMuted": False, "speakerMuted": False}
    assert restored["speakerMuted"] is True
    requests = [(index, event) for index, event in enumerate(trace) if event["direction"] == "request"]
    starts = [(index, row["params"]) for index, row in requests if row["method"] == "thread/realtime/start"]
    assert [params["transport"]["type"] for _, params in starts] == ["webrtc", "websocket", "webrtc"]
    assert all(params["voice"] == "cedar" and params["threadId"] == owner for _, params in starts)
    assert [params["realtimeSessionId"] for _, params in starts] == [dropped["id"], fallback["id"], restored["id"]]
    stop_requests = [(index, row["params"]) for index, row in requests if row["method"] == "thread/realtime/stop"]
    assert [row["threadId"] for _, row in stop_requests] == [owner, owner]
    (closure,) = [index for index, event in enumerate(trace)
                  if event["direction"] == "event" and event.get("reason") == "fixture-startup-closed"]
    assert starts[0][0] < stop_requests[0][0] < closure < starts[1][0]
    pcm = [row["params"] for _, row in requests if row["method"] == "thread/realtime/appendAudio"]
    assert pcm and all(row["threadId"] == owner and row["audio"]["samplesPerChannel"] == 2400 for row in pcm)
    (text,) = [row["params"] for _, row in requests if row["method"] == "thread/realtime/appendText"]
    assert text["text"] == "Drop this call" and text["threadId"] == owner
    assert json.loads(voice_settings.read_text(encoding="utf-8")) == {"voice": "marin", "version": 2}
    print("Verified authoritative startup closure, duplex WebSocket fallback, and reconnect with the captured voice and mute")


def verify_handoff(summary, trace, checkout):
    call = summary["call"]
    owner = call["chatId"]
    assert call["projectId"] != summary["otherProject"]
    requests = [row for row in trace if row["direction"] == "request"]
    (created,) = [row["params"] for row in requests if row["method"] == "thread/start"]
    assert Path(created["cwd"]).samefile(checkout) and created["historyMode"] == "paginated"
    assert created["model"] == "fixture-default" and created["serviceTier"] == "flex"
    assert created["approvalPolicy"] == "untrusted" and created["approvalsReviewer"] == "user"
    assert created["sandbox"] == "workspace-write" and created["config"] == {
        "realtime.type": "conversational",
        "model_reasoning_effort": "high",
        "sandbox_workspace_write.network_access": False,
    }
    (started,) = [row["params"] for row in requests if row["method"] == "thread/realtime/start"]
    assert started["threadId"] == owner and started["clientManagedHandoffs"] is False
    assert not any(row["method"] in ("turn/start", "turn/steer") for row in requests)
    (handoff,) = [row for row in trace if row["direction"] == "voice-handoff"]
    (approval,) = [row for row in trace if row["direction"] == "server-request" and
                   row["method"] == "item/commandExecution/requestApproval"]
    (accepted,) = [row for row in trace if row["direction"] == "command-approval-response"]
    assert Path(handoff["cwd"]).samefile(checkout) and Path(approval["params"]["cwd"]).samefile(checkout)
    assert handoff["threadId"] == approval["params"]["threadId"] == owner
    assert approval["id"] == accepted["id"] and accepted["result"]["decision"] == "accept"
    (completed,) = [row for row in trace if row["direction"] == "event" and
                    row["method"] == "turn/completed" and row["threadId"] == owner]
    assert completed["status"] == "completed" and completed["turnId"] == approval["params"]["turnId"]
    print("Verified backend-owned voice handoff, captured coding policy, and approval on the parked checkout")


if __name__ == "__main__":
    main()
