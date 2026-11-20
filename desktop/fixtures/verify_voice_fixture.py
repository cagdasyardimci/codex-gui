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
    app = parser.parse_args().app.resolve(strict=True)
    with TemporaryDirectory(prefix="codex-gui-voice-") as scratch:
        root = Path(scratch).resolve()
        data, profile, checkout = (root / name for name in ("desktop", "isolated Codex profile", "Voice fixture"))
        for directory in (data, profile, checkout):
            directory.mkdir()
        subprocess.run(["git", "init", "--quiet", checkout], check=True)
        (checkout / "notes.txt").write_text("A fixture attachment\n", encoding="utf-8")
        skill = checkout / "skill"
        skill.mkdir()
        (skill / "SKILL.md").write_text("# Review fixture\n", encoding="utf-8")
        state = root / "mock.json"
        state.write_text(json.dumps({"config": {
            "model_provider": "openai", "model": "fixture-default",
            "model_providers": {"openai": {"experimental_bearer_token": "fixture-only"}},
        }}), encoding="utf-8")
        voice_settings = root / "voice-settings.json"
        voice_settings.write_text('{"voice":"marin","version":1}', encoding="utf-8")
        trace = root / "trace.jsonl"
        exchange = data / "voice-exchange.json"
        result = subprocess.run(
            [app, "--verify-voice", data, checkout],
            env={**os.environ, "CODEX_HOME": str(profile), "CODEX_EXECUTABLE": str(fixture_executable(root)),
                 "CODEX_GUI_QA_SCENARIO": "desktop-voice", "CODEX_GUI_QA_STATE": str(state),
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
        owner = summary["owner"]["chatId"]
        assert summary["owner"]["media"] == ("native" if os.name == "posix" and os.uname().sysname == "Linux" else "webview")
        assert summary["duplex"] == {"receiving": True, "sending": True, "microphoneMuted": False, "speakerMuted": False}
        trace_lines = [json.loads(line) for line in trace.read_text(encoding="utf-8").splitlines()]
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


if __name__ == "__main__":
    main()
