"""Check canonical and legacy speech in the installed paged transcript."""

import argparse
import json
import os
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory

from verify_coding_probe import fixture_executable


def message(id_, kind, text):
    if kind == "userMessage":
        return {"id": id_, "type": kind, "content": [{"type": "text", "text": text}]}
    return {"id": id_, "type": kind, "text": text}


def turn(id_, items):
    return {"id": id_, "status": "completed", "items": items}


def speaker(id_, role, text):
    return {"type": "realtime", "item": {"type": "transcriptSegment", "id": id_, "role": role, "text": text}}


def timeline(entries, next_=None):
    return {"data": entries, "nextCursor": next_, "activeRealtimeSessionAtPageStart": None}


def seed():
    delegation = (
        "<realtime_delegation>\n"
        "  <input>Fixture speech</input>\n"
        "  <transcript_delta>user: Legacy speech says &lt;hello&gt;.</transcript_delta>\n"
        "</realtime_delegation>"
    )
    mixed = [turn(f"coding-{index:02d}", [message("prompt", "userMessage", f"Coding prompt {index:02d}.")])
             for index in range(27)]
    mixed[-1]["items"].extend([
        message("backend-delegation", "userMessage", delegation),
        message("hidden", "agentMessage", "[STATUS] Do not display this voice status"),
        message("shared", "agentMessage", "[COMPLETE] ::codex-realtime-inline{}\nShared **in chat**."),
    ])
    legacy = [turn("legacy-voice", [message("record", "userMessage", delegation),
                                   message("hidden", "agentMessage", "[STATUS] Do not display this voice status")])]
    latest = [{"type": "turnStarted", "turnId": item["id"]} for item in mixed[7:26]]
    latest.extend([
        {"type": "realtime", "item": {"type": "realtimeSessionStarted"}},
        {"type": "turnStarted", "turnId": "coding-26"},
        speaker("recent", "assistant", "A recent spoken reply."),
        {"type": "turnCompleted", "turnId": "coding-26"},
        {"type": "realtime", "item": {"type": "realtimeSessionClosed"}},
    ])
    earlier = [speaker("opening", "user", "First words before any coding turn.")]
    earlier.extend({"type": "turnStarted", "turnId": item["id"]} for item in mixed[:7])
    earlier.append(speaker("older", "assistant", "An earlier spoken reply."))
    voice_recent = speaker("voice-only-recent", "user", "The latest voice-only exchange.")
    voice_live = speaker("voice-only-live", "assistant", "Another voice-only utterance.")
    return {
        "threads": [
            {"id": "history-first", "name": "Mixed voice history", "preview": "", "historyMode": "paginated", "turns": mixed},
            {"id": "history-second", "name": "Legacy voice history", "preview": "", "historyMode": "legacy", "turns": legacy},
            {"id": "voice-only", "name": "Voice-only history", "preview": "", "historyMode": "paginated", "turns": []},
        ],
        "fixtureLiveSpeech": voice_live,
        "fixtureVoiceTimeline": {
            "history-first": {"latest": timeline(latest, "mixed-earlier"), "mixed-earlier": timeline(earlier)},
            "voice-only": {
                "latest": timeline([voice_recent], "voice-earlier"),
                "voice-earlier": timeline([speaker("voice-only-first", "assistant", "The first voice-only exchange."), voice_recent]),
            },
        },
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    app = parser.parse_args().app.resolve(strict=True)
    with TemporaryDirectory(prefix="codex-gui-voice-history-") as scratch:
        root = Path(scratch).resolve()
        data, profile, checkout = (root / name for name in ("desktop", "isolated Codex profile", "Voice history fixture"))
        for folder in (data, profile, checkout):
            folder.mkdir()
        subprocess.run(["git", "init", "--quiet", checkout], check=True)
        state = root / "backend.json"
        state.write_text(json.dumps(seed()), encoding="utf-8")
        trace = root / "trace.jsonl"
        environment = {
            **os.environ, "CODEX_HOME": str(profile), "CODEX_EXECUTABLE": str(fixture_executable(root)),
            "CODEX_GUI_QA_SCENARIO": "desktop-voice-history", "CODEX_GUI_QA_STATE": str(state),
            "CODEX_GUI_QA_TRACE": str(trace), "PYTHONIOENCODING": "utf-8",
        }
        for mode in ("voice-history", "voice-history-restore"):
            result = subprocess.run([app, f"--verify-{mode}", data, checkout], env=environment,
                                    capture_output=True, encoding="utf-8", errors="replace", timeout=90)
            print(result.stdout, end="")
            prefix = "Verified installed desktop voice: "
            replies = [line.removeprefix(prefix) for line in result.stdout.splitlines() if line.startswith(prefix)]
            if result.returncode or len(replies) != 1:
                raise SystemExit(result.stderr or "The installed speech-history fixture did not finish")
            assert len(json.loads(replies[0])["speech"]) == 3
        records = [json.loads(line) for line in trace.read_text(encoding="utf-8").splitlines()]
        timeline_requests = [row["params"] for row in records
                             if row["direction"] == "request" and row["method"] == "thread/timeline/list"]
        assert [(r["threadId"], r.get("cursor")) for r in timeline_requests] == [
            ("history-first", None), ("history-first", "mixed-earlier"),
            ("voice-only", None), ("voice-only", "voice-earlier"),
            ("voice-only", None), ("voice-only", "voice-earlier"),
        ]
        print("Verified speech placement, legacy decoding, coordination filtering, paging, and process-restart restoration")


if __name__ == "__main__":
    main()
