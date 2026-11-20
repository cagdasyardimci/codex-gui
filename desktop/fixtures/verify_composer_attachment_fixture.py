"""Verify draft attachment ownership in the packaged desktop app."""

import argparse
from base64 import b64decode
from contextlib import closing
import json
import os
from pathlib import Path
import sqlite3
import struct
import subprocess
from tempfile import TemporaryDirectory
import zlib

from mock_backend import ENTRY_POINT
from verify_coding_probe import fixture_executable

PIXEL = b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGMQSTnxHwAEEAJAKtk0QwAAAABJRU5ErkJggg==")


def colored_pixel(rgb):
    def chunk(kind, payload):
        return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload))

    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">2I5B", 1, 1, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(bytes([0, *rgb, 255]))) + chunk(b"IEND", b""))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    options = parser.add_mutually_exclusive_group()
    for name in ("annotations", "context", "settings", "project-context", "slash-commands"):
        options.add_argument(f"--{name}", dest="mode", action="store_const", const=name)
    parser.set_defaults(mode="attachments")
    args = parser.parse_args()
    executable = args.app.resolve(strict=True)
    with TemporaryDirectory(prefix="codex-gui-composer-attachments-") as directory:
        root = Path(directory).resolve()
        checkout = root / "Attachment checkout café"
        checkout.mkdir()
        (checkout / "picked.png").write_bytes(PIXEL)
        colors = [PIXEL, colored_pixel((20, 220, 50)), colored_pixel((210, 30, 100))]
        (checkout / "unannotated.png").write_bytes(colors[1])
        (checkout / "last.png").write_bytes(colors[2])
        (checkout / "notes.txt").write_text("Fixture note\nCafé code\nInspect this line\n", encoding="utf-8")
        (checkout / "skill").mkdir()
        (checkout / "skill" / "SKILL.md").write_text("# Review fixture\n", encoding="utf-8")
        profile = root / "codex-home"
        profile.mkdir()
        data = root / "desktop"
        state = root / "backend.json"
        trace = root / "trace.jsonl"
        scenario = ENTRY_POINT.parent / "mock_backend" / "scenarios" / "desktop-history.json"
        threads = json.loads(scenario.read_text(encoding="utf-8"))["threads"]
        first = next(thread for thread in threads if thread["id"] == "history-first")
        first["turns"][0]["items"].append({
            "id": "recorded-file", "type": "userMessage", "content": [
                {"type": "mention", "name": "notes.txt", "path": "notes.txt"},
            ],
        })
        backend_state = {"threads": threads}
        if args.mode == "project-context":
            first["turns"].extend({
                "id": f"recent-context-{number}",
                "status": "completed",
                "items": [{"id": f"recent-answer-{number}", "type": "agentMessage", "text": f"More recent turn {number}."}],
            } for number in range(105))
        if args.mode in ("settings", "project-context", "slash-commands"):
            backend_state["config"] = {"model": "baseline-model", "model_reasoning_effort": "low", "service_tier": "default",
                                       "approval_policy": "untrusted", "sandbox_mode": "read-only", "approvals_reviewer": "user"}
        state.write_text(json.dumps(backend_state, ensure_ascii=True), encoding="utf-8")
        fixture, scenario, expected = {
            "attachments": ("--verify-attachments", "desktop-attachments", "Verified installed draft attachment capture"),
            "annotations": ("--verify-annotations", "desktop-attachments", "Verified installed image annotation placement"),
            "context": ("--verify-composer-context", "desktop-context", "Verified installed composer context"),
            "settings": ("--verify-composer-settings", "desktop-composer-settings", "Verified installed composer settings"),
            "project-context": ("--verify-project-context", "desktop-project-context", "Verified installed Project Context"),
            "slash-commands": ("--verify-slash-commands", "desktop-slash-commands", "Verified installed slash commands"),
        }[args.mode]
        result = subprocess.run(
            [str(executable), fixture, str(data), str(checkout)],
            env={**os.environ, "CODEX_HOME": str(profile), "CODEX_EXECUTABLE": str(fixture_executable(root)),
                 "CODEX_GUI_QA_SCENARIO": scenario, "CODEX_GUI_QA_STATE": str(state),
                 "CODEX_GUI_QA_TRACE": str(trace), "PYTHONIOENCODING": "utf-8"},
            encoding="utf-8", capture_output=True, errors="replace", timeout=75,
        )
        print(result.stdout, end="")
        if result.returncode or expected not in result.stdout:
            raise SystemExit(result.stderr or "The desktop attachment fixture did not complete")
        records = [json.loads(line) for line in trace.read_text(encoding="utf-8").splitlines()]
        requests = [event for event in records if event["direction"] == "request"]
        starts = [event for event in requests if event["method"] == "turn/start"]
        assert not list(profile.iterdir())
        if args.mode == "settings":
            verify_settings_inputs(starts)
            return
        if args.mode == "project-context":
            verify_project_context(starts, requests, checkout, data)
            return
        if args.mode == "slash-commands":
            verify_slash_commands(starts, records, checkout, data)
            return
        assert len(starts) == 1 and starts[0]["threadId"] == "history-first", starts
        inputs = starts[0]["input"]
        if args.mode == "context":
            verify_context_inputs(inputs, checkout)
            return
        if args.mode == "annotations":
            verify_annotation_inputs(inputs, colors, data)
            return
        assert len(inputs) == 1 and inputs[0]["type"] == "localImage", inputs
        sent_path = Path(inputs[0]["path"]).resolve(strict=True)
        assert any(parent.samefile(data) for parent in sent_path.parents), sent_path
        assert sent_path.read_bytes() == PIXEL, sent_path
        with closing(sqlite3.connect(data / "workspace.sqlite3")) as database:
            draft = database.execute(
                "SELECT d.text, d.context FROM drafts AS d JOIN thread_drafts AS t ON t.draft_id = d.id "
                "WHERE t.thread_id = 'history-first'"
            ).fetchone()
            assert draft and draft[0] == "Keep this text when reusing attachments.", draft
            context = json.loads(draft[1])
            assert [item["kind"] for item in context] == ["image", "fileReference"], context
            assert Path(context[0]["path"]).samefile(sent_path) and context[1]["path"] == "notes.txt", context
        print("Verified one image-only send with identical stored bytes and retained reused references")


def verify_annotation_inputs(inputs, colors, data):
    assert [item["type"] for item in inputs] == ["text", "localImage", "localImage", "localImage"], inputs
    summary = inputs[0]["text"]
    assert summary.startswith("Review the selected images.\n\nImage 1:\n1. (x: "), summary
    assert "\n\nImage 3:\n1. (x: " in summary and "Image 2:" not in summary, summary
    assert [line.split("%) ")[-1] for line in summary.splitlines() if line.startswith(("1. ", "2. "))] == [
        "Review the upper left.", "Review the top edge.", "Review the center separately.",
    ], summary
    for image, expected in zip(inputs[1:], colors):
        path = Path(image["path"]).resolve(strict=True)
        assert any(parent.samefile(data) for parent in path.parents), path
        assert path.read_bytes() == expected, path
    print("Verified one annotated send with original attachment order and bytes across three images")


def verify_context_inputs(inputs, checkout):
    assert [item["type"] for item in inputs] == ["text", "mention", "skill"], inputs
    assert inputs[0]["text"] == (
        "Before 👩🏽‍💻  after\n\nFile reference: notes.txt\n\nSelected code from notes.txt, lines 2–3:"
        "\n2: Café code\n3: Inspect this line\n\nProject note\nUse the local fixture only."
    ), inputs
    assert inputs[1]["name"] == "notes.txt" and Path(inputs[1]["path"]).samefile(checkout / "notes.txt"), inputs
    assert inputs[2]["name"] == "Review fixture" and Path(inputs[2]["path"]).samefile(checkout / "skill" / "SKILL.md"), inputs
    print("Verified one turn with the exact replaced token, file mention, selected lines, project note, and skill")


def verify_settings_inputs(starts):
    assert len(starts) == 3 and all(turn["threadId"] == "history-first" for turn in starts), starts
    actual = [(turn["model"], turn["effort"], turn["serviceTierForTurn"], turn["approvalPolicy"],
               turn["approvalsReviewer"], turn["sandboxPolicy"]["type"]) for turn in starts]
    assert actual == [
        ("alternative-model", "high", "fixture-turbo", "on-request", "auto_review", "workspaceWrite"),
        ("alternative-model", "high", "default", "never", "user", "dangerFullAccess"),
        ("baseline-model", "low", "default", "untrusted", "user", "readOnly"),
    ], actual
    assert [turn["input"][0]["text"] for turn in starts] == [
        "Capture the first settings.", "Use confirmed Full Access.", "Use configured permissions.",
    ], starts
    print("Verified immutable admitted settings and explicit transitions between the permission preset and configured policy")


def verify_project_context(starts, requests, checkout, data):
    assert len(starts) == 1 and starts[0]["threadId"] == "history-first", starts
    turn = starts[0]
    assert (turn["model"], turn["effort"]) == ("alternative-model", "high"), turn
    assert [item["type"] for item in turn["input"]] == ["text", "skill"], turn["input"]
    assert turn["input"][0]["text"] == (
        "Keep this draft.\n\nReview the migration boundaries.\n\nProject context selected for this request:"
        "\n[decision] Release design\nFile: notes.txt\nQualify the captured build."
    ), turn["input"]
    skill = turn["input"][1]
    assert skill["name"] == "Review fixture" and Path(skill["path"]).samefile(checkout / "skill" / "SKILL.md")
    assert any(request["method"] == "thread/turns/list" and request["threadId"] == "history-first"
               and request["itemsView"] == "notLoaded" and request.get("cursor") for request in requests)
    assert not any(request["method"] == "thread/turns/list" and request["itemsView"] == "full"
                   and request.get("cursor") for request in requests)
    targeted = [request for request in requests if request["method"] == "thread/items/list"]
    assert [(request["threadId"], request["turnId"]) for request in targeted] == [
        ("history-first", "first-saved-turn"),
    ], targeted
    with closing(sqlite3.connect(data / "workspace.sqlite3")) as database:
        ((path, revision, content),) = database.execute("SELECT checkout_path, revision, content FROM project_contexts")
    assert Path(path).samefile(checkout) and revision > 1
    context = json.loads(content)
    assert [(item["title"], item["isIncluded"]) for item in context["items"]] == [("Release design", True)], context
    assert [prompt["title"] for prompt in context["savedPrompts"]] == ["Release review"], context
    assert context["bookmarks"][0]["itemID"] == "first-history", context
    print("Verified the exact native context document, one explicit Send, and scoped reads of a nonresident bookmark")


def verify_slash_commands(starts, records, checkout, data):
    assert len(starts) == 2 and all(turn["threadId"] == "history-first" for turn in starts), starts
    for turn in starts:
        assert (turn["model"], turn["effort"], turn["serviceTierForTurn"], turn["approvalsReviewer"]) == (
            "alternative-model", "high", "priority", "auto_review",
        ), turn
        assert turn["collaborationMode"] == {"mode": "plan", "settings": {
            "model": "alternative-model", "reasoning_effort": "high", "developer_instructions": None,
        }}, turn
    literal, skill = starts[0]["input"]
    assert literal["type"] == "text" and literal["text"] == "  /status literal café", literal
    assert skill["type"] == "skill" and skill["name"] == "Review fixture", skill
    assert Path(skill["path"]).samefile(checkout / "skill" / "SKILL.md"), skill
    (prompt,) = starts[1]["input"]
    assert prompt["type"] == "text" and prompt["text"] == "  Preserve this plan prompt.", prompt
    plan_updates = [record for record in records if record["direction"] == "request"
                    and record["method"] == "thread/settings/update"]
    assert [(update["threadId"], update["collaborationMode"]["mode"]) for update in plan_updates] == [
        ("history-first", "plan"), ("history-first", "default"),
        ("history-first", "plan"), ("history-first", "default"),
    ], plan_updates
    lost = records.index(plan_updates[2])
    recovered = records.index(plan_updates[3])
    reconnected = next(index for index in range(lost + 1, recovered)
                       if records[index].get("method") == "initialize" and records[index]["direction"] == "request")
    assert not any(record["direction"] == "response" and record["id"] == plan_updates[2]["id"]
                   for record in records[lost + 1:reconnected])
    (compact,) = [record for record in records if record["direction"] == "request"
                  and record["method"] == "thread/compact/start"]
    (end,) = [record for record in records if record["direction"] == "event" and record["method"] == "thread/compacted"]
    acknowledged = next(record for record in records[records.index(compact) + 1:]
                        if record["direction"] == "response" and record["id"] == compact["id"])
    assert acknowledged["time"] < end["time"] and compact["threadId"] == end["threadId"] == "history-first"
    with closing(sqlite3.connect(data / "workspace.sqlite3")) as database:
        ((mode,),) = database.execute("SELECT state FROM composer_plan_modes WHERE thread_id = 'history-first'")
    assert json.loads(mode) == {"enabled": False, "pending": None}, mode
    print("Verified two exact prompts, scoped compaction, and explicit recovery of an unacknowledged update")


if __name__ == "__main__":
    main()
