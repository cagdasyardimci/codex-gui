"""Drive the installed Mac fixture pair with native input and retain comparable evidence."""

import argparse
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import plistlib
import statistics
import subprocess
import time
from uuid import uuid4


REPOSITORY = Path(__file__).resolve().parents[2]
SCENARIO = "desktop-visual-parity"
CHAT = "qa-reading"
CHAT_TITLE = "Paired visual fixture"
HISTORY = "Paired reference conversation"
PROMPT = "Inspect the paired fixture."
STREAM = "Paired streaming response."
WINDOW = (156, 66, 1200, 760)
DIFF_FILE = "visual-diff.txt"


def write(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def read(path):
    return json.loads(path.read_text(encoding="utf-8"))


def until(description, observe, timeout=15):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        result = observe()
        if result:
            return result
        time.sleep(0.15)
    raise AssertionError(description)


def native(directory, name, *arguments):
    report = directory / f"{name}.json"
    result = subprocess.run(
        ["peekaboo", *arguments, "--json"], capture_output=True,
        encoding="utf-8", timeout=30,
    )
    report.write_text(result.stdout, encoding="utf-8")
    if result.returncode:
        raise RuntimeError(f"Native action {name} failed. See {report}: {result.stderr}")
    response = read(report)
    assert response["success"], response
    return response["data"]


def text_of(node):
    return " ".join(str(node.get(key, "")) for key in ("title", "label", "description", "value")).casefold()


def node(snapshot, name, role=None):
    return next((item for item in snapshot["ui_elements"] if name.casefold() in text_of(item)
                 and (role is None or item["role"] == role)), None)


def see(directory, name, window_id):
    return native(directory, name, "see", "--window-id", str(window_id), "--fresh",
                  "--web-focus", "--path", str(directory / f"{name}.png"))


def input_at(directory, name, snapshot, element):
    assert element is not None, name
    native(directory, name, "click", "--window-id", str(snapshot["coordinate_context"]["window"]["window_id"]),
           "--on", element["id"], "--snapshot", snapshot["snapshot_id"], "--foreground")


def windows(directory, name, pid):
    snapshot = native(directory, name, "window", "list", "--pid", str(pid))
    assert snapshot["target_application_info"]["pid"] == pid
    return [window for window in snapshot["windows"] if window["is_on_screen"]]


def json_lines(path):
    if not path.exists():
        return []
    lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
    return [json.loads(line) for line in lines if line.endswith("\n")]


def trace(directory):
    return json_lines(directory / "backend.jsonl")


def fixture_state(project):
    turn = {
        "id": "paired-history", "status": "completed", "startedAt": 100, "completedAt": 101,
        "items": [{"id": "paired-message", "type": "agentMessage",
                   "text": f"{HISTORY}\n\nA shared Markdown paragraph."}],
    }
    return {"threads": [{"id": CHAT, "name": CHAT_TITLE, "cwd": str(project),
                         "preview": "Shared conversation", "turns": [turn]}],
            "config": {"model": "qa-model", "approval_policy": "on-request", "sandbox_mode": "workspace-write"}}


def executable(bundle):
    info = plistlib.loads((bundle / "Contents/Info.plist").read_bytes())
    return bundle / "Contents/MacOS" / info["CFBundleExecutable"]


@contextmanager
def fixture_app(bundle, directory, project, edition):
    folders = {name: directory / name for name in ("codex", "support", "workspaces")}
    for folder in folders.values():
        folder.mkdir()
    state = directory / "backend.json"
    write(state, fixture_state(project))
    environment = {
        **os.environ, "CODEX_EXECUTABLE": str(REPOSITORY / "Tests/E2E/MockBackend/qa-backend"),
        "CODEX_HOME": str(folders["codex"]), "CODEX_GUI_QA_SCENARIO": SCENARIO,
        "CODEX_GUI_QA_STATE": str(state), "CODEX_GUI_QA_TRACE": str(directory / "backend.jsonl"),
        "PYTHONIOENCODING": "utf-8",
    }
    binary = executable(bundle)
    arguments = [binary]
    suite = None
    if edition == "swift":
        suite = "local.codexgui.visual." + uuid4().hex
        subprocess.run(["defaults", "write", suite, "CodexGUI.recentProjects", "-array", project], check=True)
        subprocess.run(["defaults", "write", suite, "CodexGUI.selectedThreads", "-dict", project, CHAT], check=True)
        environment.update({
            "CODEX_GUI_PREFERENCES_SUITE": suite, "CODEX_GUI_SUPPORT_ROOT": str(folders["support"]),
            "CODEX_GUI_WORKSPACE_ROOT": str(folders["workspaces"]), "CODEX_GUI_E2E_APPEARANCE": "Light",
            "CODEX_GUI_E2E_STATE": str(directory / "swift-state.json"),
        })
    else:
        write(folders["support"] / "presentation.json", {"appearance": {"mode": "light"}})
        arguments += ["--visual-parity-fixture", folders["support"], project]
    with (directory / "app.log").open("w", encoding="utf-8") as log:
        process = subprocess.Popen(arguments, env=environment, stdout=log, stderr=subprocess.STDOUT)
        try:
            yield process
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
            if suite:
                subprocess.run(["defaults", "delete", suite], capture_output=True, check=True)


def open_workspace(directory, process, edition):
    until("The fixture backend did not initialize", lambda: trace(directory))
    main = until("The workspace window did not appear", lambda: next(
        (window for window in windows(directory, "window-list", process.pid)
         if window.get("subrole") == "AXStandardWindow"), None))
    window_id = str(main["window_id"])
    x, y, width, height = WINDOW
    native(directory, "window-placement", "window", "set-bounds", "--window-id", window_id,
           "--x", str(x), "--y", str(y), "--width", str(width), "--height", str(height))
    if edition == "tauri":
        initial = until("The fixture chat did not appear", lambda:
                        (shot if node(shot := see(directory, "chat-list", window_id), CHAT_TITLE, "button") else None))
        input_at(directory, "open-chat", initial, node(initial, CHAT_TITLE, "button"))
    ready = until("The expected transcript did not render", lambda:
                  (shot if node(shot := see(directory, "ready", window_id), HISTORY) else None))
    assert ready["coordinate_context"]["logical_bounds"] == [[x, y], [width, height]]
    assert any(row.get("method") == "thread/resume" and row.get("threadId") == CHAT for row in trace(directory))
    return window_id, ready


def editor_in(snapshot, edition):
    label = "Message to Codex" if edition == "swift" else "Message"
    return next((item for item in snapshot["ui_elements"] if item["role"] == "textField"
                 and item.get("label") == label), None)


def focused_control(evidence_helper, pid, element):
    if not element:
        return None
    focused = json.loads(subprocess.check_output([evidence_helper, "focus", str(pid)], text=True, timeout=5))
    bounds = element["bounds"]
    frame = [[bounds["x"], bounds["y"]], [bounds["width"], bounds["height"]]]
    return focused if focused and focused["frame"] == frame else None


def stream_fixture(directory, window_id, entry, edition, project):
    input_at(directory, "focus-composer", entry, editor_in(entry, edition))
    native(directory, "type-fixture", "type", PROMPT, "--window-id", window_id,
           "--foreground", "--accept-dispatched")
    typed = until("The composer did not receive the fixture prompt", lambda:
                  (shot if node(shot := see(directory, "draft", window_id), PROMPT, "textField") else None))
    send = node(typed, "Send message" if edition == "swift" else "Send", "button")
    assert send and send.get("is_enabled", True), "The paired fixture did not make Send available"
    input_at(directory, "send-fixture", typed, send)
    active = until("The paired turn did not stream visibly", lambda:
                   (shot if node(shot := see(directory, "active-turn", window_id), STREAM) else None))
    requests = trace(directory)
    (sent,) = [row for row in requests if row.get("method") == "turn/start" and row["direction"] == "request"]
    assert sent["threadId"] == CHAT and Path(sent["resolvedCwd"]).samefile(project)
    assert sent["approvalPolicy"] == "on-request" and sent["sandboxPolicy"]["type"] == "workspaceWrite"
    assert is_streaming(directory)
    assert any(row.get("direction") == "fixture" and row.get("modelCalls") is False for row in requests)
    return active


def is_streaming(directory):
    thread = next(thread for thread in read(directory / "backend.json")["threads"] if thread["id"] == CHAT)
    return thread["turns"][-1]["status"] == "inProgress"


def capture(bundle, directory, project, edition, evidence_helper):
    with fixture_app(bundle, directory, project, edition) as process:
        window_id, ready = open_workspace(directory, process, edition)
        editor = editor_in(ready, edition)
        anchor = node(ready, "Approval policy:" if edition == "swift" else "Permissions", "button")
        assert editor and anchor, "Missing paired composer controls"

        before = {window["window_id"] for window in windows(directory, "before-menu", process.pid)}
        input_at(directory, "open-permissions", ready, anchor)
        menu = see(directory, "menu-elements", window_id)
        options = [item for item in menu["ui_elements"] if "approve for me" in text_of(item)]
        child = [window for window in windows(directory, "menu-windows", process.pid) if window["window_id"] not in before]
        assert options or child, "The permission action did not present an anchored menu"
        native(directory, "menu-composed", "see", "--mode", "area", "--no-elements",
               "--region", ",".join(map(str, WINDOW)), "--path", str(directory / "permission-menu.png"))
        native(directory, "dismiss-permissions", "press", "escape", "--window-id", window_id, "--foreground")
        entry = see(directory, "after-menu", window_id)
        assert not node(entry, "Approve for me"), "The keyboard did not dismiss the menu"

        active = stream_fixture(directory, window_id, entry, edition, project)

        native(directory, "open-search", "press", "cmd+shift+f", "--window-id", window_id, "--foreground")
        search_label = "Search loaded message contents" if edition == "swift" else "Search Message Contents"

        def focused_search():
            shot = see(directory, "keyboard-focus", window_id)
            field = node(shot, search_label, "textField" if edition == "swift" else "other")
            return focused_control(evidence_helper, process.pid, field)

        focus = until("The search shortcut did not focus the native search field", focused_search)
        write(directory / "focus-owner.json", focus)
        native(directory, "focus-composed", "see", "--mode", "area", "--no-elements",
               "--region", ",".join(map(str, WINDOW)), "--path", str(directory / "focused-search.png"))
        return {
            "windowBounds": ready["coordinate_context"]["logical_bounds"],
            "nativeDisplayScale": ready["coordinate_context"]["native_scale"],
            "composerBounds": editor["bounds"], "menuAnchorBounds": anchor["bounds"],
            "menuOptionBounds": [item["bounds"] for item in options],
            "menuWindowBounds": [window["bounds"] for window in child],
            "searchFocusBounds": focus["frame"],
            "streamTextBounds": node(active, STREAM)["bounds"],
        }


def sampled_action(directory, case, evidence_helper, process, window_id, region, command, points, verify=None):
    path = directory / f"{case}-frames.jsonl"
    with path.open("w", encoding="utf-8") as frames, (directory / f"{case}-capture.log").open("w") as log:
        capture = subprocess.Popen(
            [evidence_helper, "frames", str(process.pid), window_id, "2700", *map(str, region)],
            stdout=frames, stderr=log,
        )
        try:
            until("The fixture window did not provide its first native frame", lambda: json_lines(path), 5)
            time.sleep(0.65)
            stamp = json.loads(subprocess.check_output(
                [evidence_helper, command, str(process.pid), *map(str, points)], text=True, timeout=5,
            ))
            assert capture.wait(timeout=6) == 0, log.name
        finally:
            if capture.poll() is None:
                capture.terminate()
                capture.wait(timeout=5)
    write(directory / f"{case}-input.json", stamp)
    if verify:
        verify()
    samples = json_lines(path)
    before = {sample["fingerprint"] for sample in samples if sample["displayedAt"] < stamp["startedAt"]}
    changed = [sample for sample in samples if sample["displayedAt"] >= stamp["startedAt"]
               and sample["fingerprint"] not in before]
    assert before and changed, f"No post-input paint was observed in {case}"
    scale = stamp["timebaseNumer"] / stamp["timebaseDenom"] / 1_000_000
    result = {"inputToPaintMs": (changed[0]["displayedAt"] - stamp["startedAt"]) * scale}
    if command == "drag":
        displayed = []
        last = None
        for sample in changed:
            if sample["displayedAt"] <= stamp["endedAt"] and sample["fingerprint"] != last:
                displayed.append(sample["displayedAt"])
                last = sample["fingerprint"]
        intervals = [(following - previous) * scale for previous, following in zip(displayed, displayed[1:])]
        assert len(intervals) >= 4, "The resize produced too few visible frames"
        result["frameIntervalsMs"] = intervals
        result["medianFrameIntervalMs"] = statistics.median(intervals)
    return result


def timing(bundle, directory, project, edition, evidence_helper):
    with fixture_app(bundle, directory, project, edition) as process:
        window_id, ready = open_workspace(directory, process, edition)
        active = stream_fixture(directory, window_id, ready, edition, project)
        editor = editor_in(active, edition)
        write(directory / "draft-focus-owner.json", until("The streaming draft did not gain native focus",
              lambda: focus_draft(directory, evidence_helper, process.pid, window_id, edition), 8))
        x, y, width, height = WINDOW
        bounds = editor["bounds"]
        composer = (bounds["x"] - x + 2, bounds["y"] - y + 2, bounds["width"] - 4, bounds["height"] - 4)
        def verify_draft():
            typed = see(directory, "after-timed-typing", window_id)
            assert editor_in(typed, edition).get("value", "").casefold() == "a" and is_streaming(directory)

        typing = sampled_action(directory, "typing-to-paint", evidence_helper, process, window_id,
                                composer, "key", (), verify_draft)
        until("The fixture stream did not complete before the independent tool sample",
              lambda: not is_streaming(directory), 25)
        typed = see(directory, "before-tools", window_id)

        changes = node(typed, "Changes", "button")
        assert changes, "The Changes tool has no native activation target"
        bounds = changes["bounds"]
        pointer = (bounds["x"] + bounds["width"] / 2, bounds["y"] + bounds["height"] / 2)
        content = (380, 145, width - 415, height - 250)
        switched = sampled_action(directory, "tool-switch-to-paint", evidence_helper, process, window_id,
                                  content, "click", pointer)
        if edition == "swift":
            scoped = until("The Swift comparison scope did not appear", lambda:
                           (shot if node(shot := see(directory, "changes-scope", window_id),
                                         "Comparison scope:", "button") else None))
            scope = node(scoped, "Comparison scope:", "button")
            if "uncommitted" not in text_of(scope):
                input_at(directory, "choose-changes-scope", scoped, scope)
                native(directory, "select-uncommitted", "press", "u", "return", "--window-id", window_id, "--foreground")
        opened = until("The large diff did not become visible", lambda:
                       (shot if node(shot := see(directory, "opened-changes", window_id), DIFF_FILE, "button") else None))
        assert editor_in(opened, edition).get("value", "").casefold() == "a"
        if edition == "tauri":
            input_at(directory, "open-file-diff", opened, node(opened, DIFF_FILE, "button"))
        first_line = "Comparison fixture line 0000"
        until("The selected diff did not render its first source line", lambda:
              node(see(directory, "open-file-patch", window_id), first_line))
        resized = sampled_action(directory, "diff-resize-pacing", evidence_helper, process, window_id,
                                 content, "drag", (x + width - 1, y + height / 2, x + width - 181, y + height / 2))
        narrow = see(directory, "resized-changes", window_id)
        assert narrow["coordinate_context"]["logical_bounds"][1][0] < width - 100
        assert node(narrow, DIFF_FILE) and node(narrow, first_line), "Resizing moved away from the selected diff"
        return {"typing-to-paint": typing, "tool-switch-to-paint": switched, "diff-resize-pacing": resized}


def focus_draft(directory, evidence_helper, pid, window_id, edition):
    snapshot = see(directory, "streaming-draft", window_id)
    editor = editor_in(snapshot, edition)
    if not editor:
        return None
    input_at(directory, "focus-stream-draft", snapshot, editor)
    return focused_control(evidence_helper, pid, editor)


def prepare_checkout(project):
    project.mkdir(parents=True)
    subprocess.run(["git", "init", "--quiet", project], check=True)
    document = project / DIFF_FILE
    lines = [f"Comparison fixture line {index:04d} " + "long text for diff wrapping " * 4 for index in range(900)]
    document.write_text("\n".join(lines) + "\n", encoding="utf-8")
    subprocess.run(["git", "-C", project, "add", DIFF_FILE], check=True)
    subprocess.run(["git", "-C", project, "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                    "-c", "commit.gpgSign=false", "commit", "--quiet", "-m", "Visual fixture base"], check=True)
    for index in range(0, len(lines), 6):
        lines[index] = f"Changed {lines[index]}"
    document.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("swift_app", type=Path)
    parser.add_argument("tauri_app", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--repeat", type=int, default=2)
    parser.add_argument("--timing", action="store_true")
    args = parser.parse_args()
    if args.repeat < 1:
        parser.error("Repeat count must be positive")
    bundles = {"swift": args.swift_app.resolve(strict=True), "tauri": args.tauri_app.resolve(strict=True)}
    output = args.output.resolve()
    output.mkdir(parents=True)
    evidence_helper = output / "macos-visual-evidence"
    subprocess.run(["xcrun", "swiftc", "-O", "-parse-as-library",
                    Path(__file__).with_name("macos_visual_evidence.swift"), "-o", evidence_helper], check=True)
    evidence = {
        "kind": "installed apps with an isolated simulated backend and native input",
        "macOS": subprocess.check_output(["sw_vers"], text=True),
        "executables": {name: hashlib.sha256(executable(path).read_bytes()).hexdigest() for name, path in bundles.items()},
        "runs": [],
    }
    for index in range(1, args.repeat + 1):
        directory = output / f"run-{index}"
        project = directory / "Paired project"
        prepare_checkout(project)
        pair = {}
        for edition, bundle in bundles.items():
            results = directory / edition
            results.mkdir()
            pair[edition] = capture(bundle, results, project, edition, evidence_helper)
            print(f"Captured {edition} pair {index}: permission menu, streaming turn and focused search", flush=True)
            if args.timing:
                samples = directory / f"{edition}-timing"
                samples.mkdir()
                pair[edition]["timing"] = timing(bundle, samples, project, edition, evidence_helper)
        assert pair["swift"]["windowBounds"] == pair["tauri"]["windowBounds"]
        assert pair["swift"]["nativeDisplayScale"] == pair["tauri"]["nativeDisplayScale"]
        evidence["runs"].append(pair)
        write(output / "comparison.json", evidence)
    print(f"Verified {args.repeat} isolated Mac fixture pairs")


if __name__ == "__main__":
    main()
