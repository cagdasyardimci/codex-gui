"""Verify staged macOS preference import with the installed Tauri executable."""

import argparse
from contextlib import closing
from hashlib import sha256
import json
import os
from pathlib import Path
import plistlib
import sqlite3
import subprocess
from tempfile import TemporaryDirectory
from uuid import UUID
import wave

from mock_backend import ENTRY_POINT
from verify_coding_probe import fixture_executable
from verify_composer_attachment_fixture import PIXEL
from verify_diff_fixture import git


PATCH = "@@ -1 +1 @@\n-Before\n+After\n"
TURN = "appkit-review-turn"
FIRST = "history-first"


def data(value):
    return json.dumps(value, ensure_ascii=False).encode("utf-8")


def fingerprint(value):
    value = value.encode("utf-8") + b"\xff"
    digest = 14695981039346656037
    for byte in value:
        digest = ((digest ^ byte) * 1099511628211) & ((1 << 64) - 1)
    return f"{digest:x}"


def run(app, arguments, environment=None):
    result = subprocess.run([app, *arguments], env=environment, check=False, capture_output=True,
                            text=True, encoding="utf-8", errors="replace", timeout=60)
    if result.returncode:
        raise AssertionError(result.stderr or result.stdout)
    return result.stdout


def record_state(root, source, project, extra, originals):
    for folder in ("project-context", "draft-images", "notification-sounds"):
        (source / folder).mkdir()
    image_name = f"{UUID(int=1)}.png"
    (source / "draft-images" / image_name).write_bytes(PIXEL)
    sound = source / "notification-sounds" / "CodexGUI-Alert.wav"
    with wave.open(str(sound), "wb") as output:
        output.setparams((1, 2, 8000, 0, "NONE", "not compressed"))
        output.writeframes(b"\x01\x00\xff\xff" * 200)
    subject = {"id": "hello", "title": "Saved prompt", "instructions": "Read the selected file"}
    bookmarks = [{"id": "bookmark-1", "threadID": FIRST, "turnID": "first-saved-turn", "itemID": "first-history",
                  "kind": "answer", "label": "Kept response"}]
    context = {"savedPrompts": [subject], "selectedPromptID": "hello", "bookmarks": bookmarks}
    for path in [project, extra]:
        document = {"version": 1, "projectPath": str(path), "context": context}
        (source / "project-context" / (sha256(os.fsencode(path)).hexdigest() + ".json")).write_bytes(data(document))
    (source / "remote-preferences.plist").write_bytes(plistlib.dumps({"CodexGUI.remoteAccessEnabled": False}))
    original_image = {"id": "image-one", "kind": "image", "title": "Copied image",
                      "path": str(originals / image_name),
                      "imageAnnotations": [{"id": "note", "x": 0.25, "y": 0.75, "text": "Copied annotation"}]}
    background = 0x23_31_42
    legacy = [str(project), FIRST, TURN, "notes.txt"]
    hunk = fingerprint(PATCH)
    source_values = {
        "CodexGUI.recentProjects": [str(project), str(extra)],
        "CodexGUI.removedProjects": [str(extra)],
        "CodexGUI.pinnedProjects": [str(project)],
        "CodexGUI.projectDisplayNames": {str(project): "Imported Project"},
        "CodexGUI.pinnedTasks": data([{"id": FIRST, "name": "First fixture chat", "cwd": str(project),
                                       "updatedAt": 123456, "status": "idle"}]),
        "CodexGUI.selectedThreads": {str(project): FIRST},
        "CodexGUI.drafts": {str(project): {f"thread:{FIRST}": "Imported thread draft",
                                          "new-chat": "Imported new chat draft"}},
        "CodexGUI.draftContext": data({str(project): {f"thread:{FIRST}": [original_image]}}),
        "CodexGUI.sentReferences": data([{"projectPath": str(project), "threadID": FIRST, "item": original_image}]),
        "CodexGUI.queuedMessages": {str(extra): {"thread:other-chat": data([
            {"id": str(UUID(int=2)), "text": "Keep queue paused", "context": []}
        ])}},
        "CodexGUI.activeExecutionThreads": {str(extra): ["other-chat"]},
        "CodexGUI.pendingCommands": {str(extra): data([
            {"threadID": "other-chat", "turnID": "execution", "itemID": "command"}
        ])},
        "reviewedChangeFingerprints.v1": {
            "\0".join([*legacy, ""]): fingerprint("\0".join(["notes.txt", "", "update", PATCH])),
            "\0".join([*legacy, f"1-{hunk}"]): hunk,
            "\0".join([*legacy, f"2-{hunk}"]): hunk,
        },
        "sidebar.organization": "oneList",
        "sidebar.sortOrder": "manual",
        "sidebar.manualThreadIDs": ["history-third-appkit", "history-second", FIRST],
        "settings.hiddenReasoningEfforts": ["minimal", "high"],
        "CodexGUI.modelPreference": {"model": "fixture-model", "effort": "medium"},
        "CodexGUI.runPreferences": data({"approvalMode": "askForApproval", "fastMode": True}),
        "appearance.colorTheme": data({"mode": "dark",
                                      "dark": {"background": background, "foreground": 0xf0f0f0,
                                               "accent": 0x325a66, "contrast": 60, "uiFontFamily": "Georgia"},
                                      "light": {"background": 0xfefefe, "foreground": 0x010101,
                                                "accent": 0x195c88, "contrast": 40}}),
        "appearance.typography": {"ui": 15, "content": 18, "code": 13},
        "CodexGUI.windowLayout": data({"frame": [[85, 60], [860, 560]], "navigationWidth": 232, "reviewWidth": 370,
                                       "navigationCollapsed": True, "reviewCollapsed": False,
                                       "paneGeometryVersion": 2, "reviewVisibility": "expanded"}),
        "taskNotificationCompletionMode": "whenUnfocused",
        "taskNotificationPermissionAlerts": False,
        "taskNotificationSoundID": "custom",
        "taskNotificationCustomSoundFilename": sound.name,
        "CodexGUI.remoteAccessEnabled": True,
    }
    (source / "preferences.plist").write_bytes(plistlib.dumps(source_values, fmt=plistlib.FMT_BINARY))
    scenario = ENTRY_POINT.parent / "mock_backend" / "scenarios" / "desktop-history.json"
    threads = json.loads(scenario.read_text(encoding="utf-8"))["threads"]
    first = next(thread for thread in threads if thread["id"] == FIRST)
    second = next(thread for thread in threads if thread["id"] == "history-second")
    second["updatedAt"] = 1_700_000_120
    threads.append({**second, "id": "history-third-appkit", "name": "Third fixture chat",
                    "updatedAt": second["updatedAt"] - 60, "turns": []})
    first["turns"].append({"id": TURN, "status": "completed", "items": [
        {"type": "fileChange", "id": "appkit-change", "status": "completed",
         "changes": [{"path": "notes.txt", "kind": {"type": "update"}, "diff": PATCH}]},
    ]})
    (root / "mock.json").write_bytes(data({"threads": threads}))
    return sound


def verify_current(app, root):
    source, profile, home, project, extra = (root / directory for directory in (
        "AppKit copy", "Tauri profile", "isolated Codex home", "Project café", "Removed project"))
    for folder in (source, profile, home, project, extra):
        folder.mkdir()
    git(project, "init", "--quiet", "--template=")
    (project / "notes.txt").write_text("Before\n", encoding="utf-8")
    git(project, "add", "notes.txt")
    git(project, "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
        "-c", "commit.gpgSign=false", "commit", "--quiet", "-m", "Create copied-data fixture")
    (project / "notes.txt").write_text("After\n", encoding="utf-8")
    originals = root / "unavailable originals" / "DraftImages"
    sound = record_state(root, source, project, extra, originals)
    source_before = {file: file.read_bytes() for file in source.rglob("*") if file.is_file()}
    command = ["--import-appkit", source, originals, profile]
    report = json.loads(run(app, command))
    assert report == {"projects": 1, "pinnedChats": 1, "contexts": 2, "drafts": 2, "sentReferences": 1,
                      "pausedEntries": 1, "queueReceipts": 0, "unresolvedCommands": 1, "activeThreads": 1,
                      "reviewMarkers": 3}, report
    stored = profile / "workspace.sqlite3"
    with closing(sqlite3.connect(stored)) as connection:
        assert connection.execute("SELECT path, title, pinned FROM desktop_projects").fetchall() == [
            (str(project), "Imported Project", 1)]
        assert connection.execute("SELECT thread_id, pinned FROM desktop_sidebar_chats").fetchall() == [(FIRST, 1)]
        assert connection.execute("SELECT thread_id FROM desktop_project_selections").fetchall() == [(FIRST,)]
        assert connection.execute("SELECT text FROM desktop_source_drafts JOIN drafts ON draft_id = id").fetchall() == [
            ("Imported new chat draft",)]
        assert connection.execute("SELECT thread_id, turn_id, item_id FROM appkit_unresolved_commands").fetchall() == [
            ("other-chat", "execution", "command")]
        assert connection.execute("SELECT effort FROM desktop_hidden_reasoning_efforts").fetchall() == [("minimal",)]
        assert "Kept response" in connection.execute("SELECT content FROM project_contexts WHERE checkout_path = ?", [str(project)]).fetchone()[0]
        selection = json.loads(connection.execute("SELECT selection FROM appkit_composer_preferences LIMIT 1").fetchone()[0])
        assert selection == {"modelId": "fixture-model", "effort": "medium", "serviceTier": "priority",
                             "permissions": "askForApproval"}
    alerts = json.loads((profile / "notifications.json").read_text(encoding="utf-8"))
    assert alerts["completions"] == "whenUnfocused" and not alerts["permissions"] and alerts["sound"] == "custom", alerts
    installed_sound = profile / "notification-sounds" / (alerts["custom"]["digest"] + ".wav")
    assert installed_sound.read_bytes() == sound.read_bytes()
    remote = json.loads((profile / "remote-host-v1.json").read_text(encoding="utf-8"))
    assert remote["source"]["path"] == str(project) and not remote["enabled"]
    trace = root / "trace.jsonl"
    environment = {**os.environ, "CODEX_EXECUTABLE": str(fixture_executable(root)), "CODEX_HOME": str(home),
                   "CODEX_GUI_QA_SCENARIO": "desktop-history", "CODEX_GUI_QA_STATE": str(root / "mock.json"),
                   "CODEX_GUI_QA_READ_ONLY_STATE": "1", "CODEX_GUI_QA_TRACE": str(trace),
                   "PYTHONIOENCODING": "utf-8"}
    evidence = run(app, ["--verify-appkit-import", profile], environment)
    prefix = "Verified installed desktop appearance and layout: "
    measured = json.loads(next(line[len(prefix):] for line in evidence.splitlines() if line.startswith(prefix)))
    assert abs(measured["width"] - 860) <= 2 and abs(measured["height"] - 560) <= 2, measured
    with closing(sqlite3.connect(stored)) as connection:
        assert connection.execute("SELECT hunk FROM desktop_review_markers").fetchall() == [(-1,)]
        assert connection.execute("SELECT hunk FROM appkit_review_markers").fetchall() == [
            (f"2-{fingerprint(PATCH)}",)]
        connection.execute("UPDATE desktop_projects SET title = 'Newer Tauri title'")
        connection.commit()
    notifications = (profile / "notifications.json").read_bytes()
    presentation = (profile / "presentation.json").read_bytes()
    assert json.loads(presentation)["panes"]["navigationCollapsed"] is False
    assert all(value == 0 for value in json.loads(run(app, command)).values())
    assert (profile / "presentation.json").read_bytes() == presentation
    assert (profile / "notifications.json").read_bytes() == notifications
    with closing(sqlite3.connect(stored)) as connection:
        assert connection.execute("SELECT title FROM desktop_projects").fetchall() == [("Newer Tauri title",)]
        assert connection.execute("SELECT hunk FROM desktop_review_markers").fetchall() == [(-1,)]
    requests = [row for row in map(json.loads, trace.read_text(encoding="utf-8").splitlines())
                if row["direction"] == "request"]
    assert requests and not any(row["method"] in {"turn/start", "turn/steer"}
                                or row.get("threadId") == "other-chat" for row in requests), requests
    assert all(file.read_bytes() == before for file, before in source_before.items())
    assert not originals.exists() and not list(home.iterdir())


def verify_legacy(app, root):
    source, project, profile = (root / directory for directory in ("legacy copy", "Legacy project", "Legacy profile"))
    for folder in (source, project, profile):
        folder.mkdir()
    (source / "preferences.plist").write_bytes(plistlib.dumps({
        "recentProject": str(project), "draft": "Original AppKit text",
        "taskNotificationSoundEnabled": False,
        "CodexGUI.windowLayout": data({"frame": [[5, 5], [800, 530]], "navigationWidth": 490,
                                       "reviewWidth": 700, "reviewCollapsed": True}),
    }))
    result = json.loads(run(app, ["--import-appkit", source, root / "original legacy images", profile]))
    assert result["projects"] == result["drafts"] == 1
    with closing(sqlite3.connect(profile / "workspace.sqlite3")) as connection:
        assert connection.execute("SELECT text FROM desktop_source_drafts JOIN drafts ON draft_id = id").fetchall() == [
            ("Original AppKit text",)]
    assert json.loads((profile / "notifications.json").read_bytes())["sound"] == "none"
    presentation = json.loads((profile / "presentation.json").read_bytes())
    assert presentation["panes"]["navigationWidth"] is None and presentation["panes"]["reviewExpanded"] is False


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    app = parser.parse_args().app.resolve(strict=True)
    with TemporaryDirectory(prefix="codex-gui-appkit-import-") as temporary:
        root = Path(temporary).resolve()
        verify_current(app, root)
        verify_legacy(app, root)
    print("Verified installed AppKit import, restart, compatible review marks and retry preservation")


if __name__ == "__main__":
    main()
