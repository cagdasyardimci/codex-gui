"""Exercise the same disposable CLI profile with pinned AppKit code and the installed Tauri app."""

import argparse
from contextlib import closing
from hashlib import sha256
import json
import os
from pathlib import Path
import plistlib
import shutil
import sqlite3
import subprocess
from tempfile import TemporaryDirectory

from mock_backend import ENTRY_POINT
from verify_coding_probe import fixture_executable


APPKIT_REF = "c0824558b060d90a6486c3aef743877677f0d4f1"
SWIFT_TEST = Path(__file__).parent / "appkit" / "SharedCodexProfileTests.swift"


def run(arguments, environment, timeout, completion):
    result = subprocess.run(arguments, env=environment, capture_output=True, text=True,
                            encoding="utf-8", errors="replace", timeout=timeout)
    if result.returncode or completion not in result.stdout:
        raise AssertionError(result.stdout[-8000:] + result.stderr[-8000:])
    print(completion)
    return result.stdout


def export_appkit(repository, destination):
    archive = destination.parent / "appkit.tar"
    subprocess.run(["git", "-C", repository, "archive", "--format=tar", "-o", archive, APPKIT_REF], check=True)
    subprocess.run(["tar", "-xf", archive, "-C", destination], check=True)
    shutil.copyfile(SWIFT_TEST, destination / "Tests" / "CodexGUITests" / SWIFT_TEST.name)
    subprocess.run(["make", "-C", destination, "resources"], check=True, timeout=180)
    dependencies = repository / ".build" / "checkouts"
    for pin in json.loads((destination / "Package.resolved").read_text())["pins"]:
        cached = next((path for path in dependencies.iterdir()
                       if path.name.lower() == pin["identity"]), None) if dependencies.is_dir() else None
        if cached is None:
            continue
        revision = pin["state"]["revision"]
        available = subprocess.run(["git", "-C", cached, "cat-file", "-e", revision + "^{commit}"],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if available.returncode == 0:
            subprocess.run(["swift", "package", "--package-path", destination, "config", "set-mirror",
                            "--original", pin["location"], "--mirror", cached.as_uri()], check=True)


def bytes_of(files):
    return {file.name: sha256(file.read_bytes()).hexdigest() for file in files}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--appkit-repository", type=Path, help="include the pinned Swift reference check")
    parser.add_argument("--swift-jobs", type=int, default=6)
    args = parser.parse_args()
    app = args.app.resolve(strict=True)
    with TemporaryDirectory(prefix="codex-gui-shared-profile-") as temporary:
        root = Path(temporary).resolve()
        reference, profile, checkout, staged, tauri = (root / name for name in (
            "AppKit reference", "Codex profile", "Project café", "AppKit copy", "Tauri data"))
        for directory in (reference, profile, checkout, staged, tauri):
            directory.mkdir()
        if args.appkit_repository:
            export_appkit(args.appkit_repository.resolve(strict=True), reference)
        executable = fixture_executable(root)
        (profile / ".shared-profile-fixture").write_bytes(b"codex-gui-fixture\n")
        authorization = profile / "fixture-account.json"
        config = profile / "config.toml"
        if args.appkit_repository:
            authorization.write_text('{"email":"appkit@example.invalid"}\n', encoding="utf-8")
            config.write_text('model_verbosity = "low"\n', encoding="utf-8")
        else:
            config.write_text('model_verbosity = "high"\n', encoding="utf-8")
        fixture_history = profile / "fixture-history.json"
        scenario = ENTRY_POINT.parent / "mock_backend" / "scenarios" / "desktop-history.json"
        base = json.loads(scenario.read_text(encoding="utf-8"))
        for thread in base["threads"]:
            thread["cwd"] = str(checkout)
        fixture_history.write_text(json.dumps({"threads": base["threads"]}, ensure_ascii=True), encoding="utf-8")
        history_bytes = fixture_history.read_bytes()
        trace = root / "shared-codex-trace.jsonl"
        environment = {
            **os.environ, "CODEX_EXECUTABLE": str(executable), "CODEX_HOME": str(profile),
            "CODEX_GUI_QA_SCENARIO": "desktop-shared-profile", "CODEX_GUI_QA_TRACE": str(trace),
            "CODEX_GUI_QA_STATE": str(fixture_history), "CODEX_GUI_QA_READ_ONLY_STATE": "1",
            "CODEX_GUI_QA_SHARED_CHECKOUT": str(checkout), "PYTHONIOENCODING": "utf-8",
        }
        swift = ["swift", "test", "--package-path", reference, "--jobs", str(args.swift_jobs),
                 "--filter", "SharedCodexProfileTests"]
        if args.appkit_repository:
            run(swift, {**environment, "CODEX_GUI_QA_SHARED_PHASE": "before"}, 900,
                "Verified AppKit shared Codex profile before")
        assert not authorization.exists()
        assert config.read_text(encoding="utf-8") == 'model_verbosity = "high"\n'
        run([app, "--verify-shared-codex-profile", profile, checkout, executable],
            environment, 45, "Verified Tauri shared Codex profile and retired account read")
        if args.appkit_repository:
            run([*swift, "--skip-build"], {**environment, "CODEX_GUI_QA_SHARED_PHASE": "after"}, 90,
                "Verified AppKit shared Codex profile after")
        current = bytes_of([authorization, config, fixture_history])
        assert fixture_history.read_bytes() == history_bytes

        preferences = {"recentProject": str(checkout), "draft": "AppKit draft remains GUI-owned"}
        (staged / "preferences.plist").write_bytes(plistlib.dumps(preferences))
        (staged / "auth.json").write_text('{"email":"retired@example.invalid"}\n', encoding="utf-8")
        (staged / "config.toml").write_text('model_verbosity = "low"\n', encoding="utf-8")
        for expected in ('"drafts":1', '"drafts":0'):
            run([app, "--import-appkit", staged, root / "original DraftImages", tauri],
                environment, 30, expected)
            assert bytes_of([authorization, config, fixture_history]) == current
        with closing(sqlite3.connect(tauri / "workspace.sqlite3")) as database:
            assert database.execute("SELECT text FROM drafts").fetchall() == [("AppKit draft remains GUI-owned",)]
        assert not list(tauri.glob("*.toml")) and not (tauri / "auth.json").exists()

        requests = [event for event in map(json.loads, trace.read_text(encoding="utf-8").splitlines())
                    if event["direction"] == "request"]
        clients = [event["clientInfo"]["name"] for event in requests if event["method"] == "initialize"]
        expected_clients = ["codex_gui", "codex_gui"]
        if args.appkit_repository:
            expected_clients = ["codex_gui_appkit", *expected_clients, "codex_gui_appkit"]
        assert clients == expected_clients, clients
        mutations = [event["method"] for event in requests if event["method"] in {
            "config/batchWrite", "config/value/write", "account/logout", "account/login/start"}]
        expected_mutations = ["account/login/start", "config/value/write"]
        if args.appkit_repository:
            expected_mutations = ["config/batchWrite", "account/logout", *expected_mutations]
        assert mutations == expected_mutations, mutations
        print("Verified isolated GUI storage and that import preserves shared Codex state")


if __name__ == "__main__":
    main()
