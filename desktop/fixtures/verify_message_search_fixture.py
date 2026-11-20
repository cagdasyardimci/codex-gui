"""Verify incremental search and exact jumps across installed paged chat history."""

import argparse
import json
import os
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory

from verify_coding_probe import fixture_executable


def response(identity, text):
    return {"id": identity, "type": "agentMessage", "text": text}


def first_history():
    turns = []
    for number in range(1, 96):
        items = [response(f"filler-{index}", f"Ordinary filler for turn {number} and item {index}.")
                 for index in range(10)]
        if number == 4:
            items.append(response("needle", "Before Hidden target café quadrant after."))
        elif number == 95:
            items.append(response("needle", "Preceding words. " * 16 + "Café waterline" + " Following words." * 16))
        turns.append({"id": f"search-turn-{number:02d}", "status": "completed", "items": items})
    return turns


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    args = parser.parse_args()
    with TemporaryDirectory(prefix="codex-gui-message-search-") as scratch:
        root = Path(scratch).resolve()
        project = root / "Search checkout"
        profile = root / "codex home"
        project.mkdir()
        profile.mkdir()
        trace = root / "trace.jsonl"
        state = root / "backend.json"
        threads = [
            {"id": "history-first", "name": "First fixture chat", "preview": "", "turns": first_history()},
            {"id": "history-second", "name": "Second fixture chat", "preview": "", "turns": [
                {"id": "second-search-turn", "status": "completed", "items": [
                    response("needle", "The Cross chat amber phrase has its own context."),
                ]},
            ]},
        ]
        state.write_text(json.dumps({"threads": threads}), encoding="utf-8")
        result = subprocess.run(
            [args.app.resolve(strict=True), "--verify-message-search", root / "desktop", project],
            env={
                **os.environ,
                "CODEX_HOME": str(profile),
                "CODEX_EXECUTABLE": str(fixture_executable(root)),
                "CODEX_GUI_QA_SCENARIO": "desktop-message-search",
                "CODEX_GUI_QA_TRACE": str(trace),
                "CODEX_GUI_QA_STATE": str(state),
                "PYTHONIOENCODING": "utf-8",
            },
            capture_output=True, encoding="utf-8", errors="replace", timeout=85,
        )
        print(result.stdout, end="")
        if result.returncode or "Verified installed incremental paged message search" not in result.stdout:
            raise SystemExit(result.stderr or "The installed search fixture did not complete")
        requests = [request for line in trace.read_text(encoding="utf-8").splitlines()
                    if (request := json.loads(line))["direction"] == "request"]
        assert any(request["method"] == "thread/list" and request.get("cursor") == "search-chat-directory-next"
                   for request in requests)
        second = [request for request in requests if request.get("threadId") == "history-second"]
        assert second[0]["method"] == "thread/read" and second[0]["params"]["includeTurns"] is False
        assert second[1]["method"] == "thread/turns/list" and second[1]["params"]["itemsView"] == "full"
        assert any(request["method"] == "thread/items/list" and request.get("turnId") == "search-turn-04"
                   for request in requests)
        starts = [request["params"] for request in requests if request["method"] == "turn/start"]
        assert len(starts) == 1 and starts[0]["threadId"] == "history-first"
        assert not list(profile.iterdir())
        print("Verified cross-chat and older-item jumps, canceled search, Unicode snippets, and eviction coverage")


if __name__ == "__main__":
    main()
