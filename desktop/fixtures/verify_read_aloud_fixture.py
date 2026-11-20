"""Verify installed Read Aloud against an isolated speech provider."""

import argparse
import json
import os
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory

from verify_coding_probe import fixture_executable
from verify_voice_history_fixture import message, turn

BODY = "Speech with café and 日本語. " * 18
RETRY = "Retry this reply after the provider disconnects."


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    app = parser.parse_args().app.resolve(strict=True)
    with TemporaryDirectory(prefix="codex-gui-read-aloud-") as scratch:
        root = Path(scratch).resolve()
        data, profile, checkout = (root / name for name in ("desktop", "isolated Codex profile", "Read Aloud checkout"))
        for folder in (data, profile, checkout):
            folder.mkdir()
        subprocess.run(["git", "init", "--quiet", checkout], check=True)
        threads = [
            {"id": "history-first", "name": "Read Aloud first", "preview": "", "turns": [
                turn("read-first", [message("say-first", "agentMessage", f"## Fixture heading\n\n**{BODY.strip()}**")]),
            ]},
            {"id": "history-second", "name": "Read Aloud second", "preview": "", "turns": [
                turn("read-second", [message("say-second", "agentMessage", RETRY)]),
            ]},
        ]
        state = root / "backend.json"
        state.write_text(json.dumps({"threads": threads, "config": {
            "model_provider": "openai", "model": "fixture-default",
            "model_providers": {"openai": {"experimental_bearer_token": "fixture-only"}},
        }}), encoding="utf-8")
        settings, fault, trace = (root / name for name in ("voice-settings.json", "fail-once", "trace.jsonl"))
        settings.write_text('{"voice":"cedar","version":1}', encoding="utf-8")
        fault.touch()
        result = subprocess.run([app, "--verify-read-aloud", data, checkout], env={
            **os.environ, "CODEX_HOME": str(profile), "CODEX_EXECUTABLE": str(fixture_executable(root)),
            "CODEX_GUI_QA_SCENARIO": "desktop-read-aloud", "CODEX_GUI_QA_STATE": str(state),
            "CODEX_GUI_QA_VOICE_SETTINGS": str(settings), "CODEX_GUI_QA_TRACE": str(trace),
            "CODEX_GUI_QA_READ_ALOUD_FAILURE": str(fault), "PYTHONIOENCODING": "utf-8",
        }, capture_output=True, encoding="utf-8", errors="replace", timeout=90)
        print(result.stdout, end="")
        prefix = "Verified installed desktop voice: "
        summaries = [json.loads(line.removeprefix(prefix)) for line in result.stdout.splitlines() if line.startswith(prefix)]
        if result.returncode or len(summaries) != 1:
            if trace.exists():
                requests = [json.loads(line) for line in trace.read_text(encoding="utf-8").splitlines()]
                print("Last fixture requests:", [(row.get("method"), row.get("params"))
                                                for row in requests if row["direction"] == "request"][-20:])
            raise SystemExit(result.stderr or "The installed Read Aloud fixture did not finish")
        (summary,) = summaries
        assert summary["failed"]["frames"] == 0
        groups = {}
        for line in trace.read_text(encoding="utf-8").splitlines():
            row = json.loads(line)
            if row["direction"] == "request":
                groups.setdefault(row["method"], []).append(row["params"])
        private = {entry["realtimeSessionId"]: entry for entry in groups["thread/realtime/start"]}
        assert set(private) == {entry["id"] for entry in summary.values()}
        threads_started = {entry["threadId"] for entry in private.values()}
        assert len(threads_started) == 5 and all("voice" not in entry for entry in private.values())
        starts = groups["thread/start"]
        assert len(starts) == 5 and all(start["ephemeral"] and start["sandbox"] == "read-only" for start in starts)
        assert threads_started == {entry["threadId"] for entry in groups["thread/realtime/stop"]}
        texts = {thread: [entry["text"] for entry in groups["thread/realtime/appendSpeech"] if entry["threadId"] == thread]
                 for thread in threads_started}
        assert len(texts[private[summary["first"]["id"]]["threadId"]]) == 2
        assert "".join(texts[private[summary["first"]["id"]]["threadId"]]) == f"Fixture heading\n{BODY.strip()}"
        for scenario, expected in (("repeated", "Fixture heading"), ("switched", "Fixture heading"),
                                   ("failed", RETRY), ("recovered", RETRY)):
            (spoken,) = texts[private[summary[scenario]["id"]]["threadId"]]
            assert spoken.startswith(expected)
        assert not groups.get("turn/start")
        print("Verified segmented response playback, repeat, Stop Reading, chat retirement, and provider failure recovery")


if __name__ == "__main__":
    main()
