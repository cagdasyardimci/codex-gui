"""Exercise installed worktree retirement with the pinned Swift store in separate processes."""

import argparse
import json
from pathlib import Path
import select
import subprocess
from tempfile import TemporaryDirectory
from uuid import UUID

from verify_shared_codex_profile import APPKIT_REF


SWIFT_SOURCES = (
    "Persistence/TaskWorkspaceStore.swift",
    "Workspaces/TaskWorkspace.swift",
    "Workspaces/TaskWorkspaceLocations.swift",
)


def native_probe(repository, root):
    sources = []
    for relative in SWIFT_SOURCES:
        target = root / Path(relative).name
        target.write_bytes(subprocess.check_output([
            "git", "-C", repository, "show", f"{APPKIT_REF}:Sources/CodexGUI/{relative}",
        ]))
        sources.append(target)
    driver = Path(__file__).parent / "appkit" / "LegacyWorkspaceLockProbe.swift"
    executable = root / "AppKitLockQA"
    subprocess.run(["swiftc", "-swift-version", "6", "-o", executable, driver, *sources], check=True, timeout=60)
    return executable


def result(arguments):
    return subprocess.run(arguments, capture_output=True, text=True, check=False, timeout=15)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--appkit-repository", type=Path, required=True)
    args = parser.parse_args()
    app = args.app.resolve(strict=True)
    with TemporaryDirectory(prefix="codex-gui-appkit-retirement-") as temporary:
        root = Path(temporary).resolve()
        swift = native_probe(args.appkit_repository.resolve(strict=True), root)
        (root / ".appkit-retirement-fixture").symlink_to("fixture")
        records = root / "records"
        records.mkdir()
        bundle = root / "Legacy.app"
        bundle.mkdir()
        identity = UUID(int=1)
        record = records / f"{identity}.json"
        record.write_text(json.dumps({"version": 1, "workspace": {
            "id": str(identity).upper(), "taskID": "retirement-fixture",
            "sourceProjectPath": str(root / "source"), "repositoryGitDirectory": str(root / "source/.git"),
            "branch": f"codex/task/retirement-fixture-{identity}", "checkoutPath": str(root / "checkout"),
            "baseCommit": "a" * 40, "sourceWasDirty": True, "createdAt": 1, "phase": "active",
        }}), encoding="utf-8")
        legacy = [swift, records]
        retired = [app, "--verify-appkit-retirement", root, bundle]
        first = result([*legacy, "write"])
        assert first.returncode == 0, first.stderr
        snapshot = record.read_bytes()
        has_bundle = result(retired)
        assert has_bundle.returncode != 0 and "retire the AppKit bundle" in has_bundle.stderr, has_bundle.stderr
        bundle.rename(root / "Legacy archive.app")

        for mode, expected in (("running", "quit the legacy AppKit process"), ("holding", "record lock")):
            with subprocess.Popen([*legacy, mode], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  text=True, encoding="utf-8") as process:
                try:
                    assert select.select([process.stdout], [], [], 10)[0] and process.stdout.readline() == "ready\n"
                    still_managed = result(retired)
                    assert still_managed.returncode != 0 and expected in still_managed.stderr, still_managed.stderr
                    assert (records / ".lock").is_file() and record.read_bytes() == snapshot
                finally:
                    process.communicate("\n", timeout=10)

        sealed = result(retired)
        assert sealed.returncode == 0 and "Verified durable AppKit management retirement" in sealed.stdout, sealed.stderr
        assert (records / ".lock").readlink() == Path(".retired-by-tauri") / str(identity)
        restarted = result([*legacy, "write"])
        assert restarted.returncode == 23 and record.read_bytes() == snapshot, restarted.stderr
        assert (records / ".lock").is_symlink()
        print("Verified Mac installer preflight, contended native locks, and rejection of a relaunched AppKit writer")


if __name__ == "__main__":
    main()
