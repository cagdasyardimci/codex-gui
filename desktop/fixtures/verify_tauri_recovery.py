"""Verify a Tauri recovery copy with migrated and newly created managed work."""

import argparse
from contextlib import closing
import json
import plistlib
from pathlib import Path
import sqlite3
from tempfile import TemporaryDirectory
from uuid import UUID

from verify_appkit_transfer import attempt, registrations, setup
from verify_composer_attachment_fixture import PIXEL


def draft(profile):
    with closing(sqlite3.connect(profile / "workspace.sqlite3")) as database:
        return database.execute(
            "SELECT text FROM drafts JOIN thread_drafts ON draft_id = id WHERE thread_id = 'new-tauri-thread'"
        ).fetchone()


def replace_draft(profile, value):
    with closing(sqlite3.connect(profile / "workspace.sqlite3")) as database:
        database.execute(
            "UPDATE drafts SET text = ? WHERE id = "
            "(SELECT draft_id FROM thread_drafts WHERE thread_id = 'new-tauri-thread')", [value]
        )
        database.commit()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    args = parser.parse_args()
    app = args.app.resolve(strict=True)
    with TemporaryDirectory(prefix="codex-gui-tauri-recovery-") as temporary:
        root = Path(temporary).resolve()
        original, checkout, records, record, profile, staged, bundle = setup(root)
        home = root / "isolated Codex profile"
        home.mkdir()
        config = home / "config.toml"
        config.write_bytes(b'model_verbosity = "high"\n')
        auth = home / "auth.json"
        auth.write_bytes(b'{"fixture": "preserve newer Codex state"}\n')
        environment = {"CODEX_HOME": str(home)}
        before = {file.name: file.read_bytes() for file in (config, auth)}

        recovery = [app, "--tauri-recovery"]
        originals = root / "original images"
        import_command = [app, "--import-appkit", staged, originals, profile]
        preferences = staged / "preferences.plist"
        staged_preferences = plistlib.loads(preferences.read_bytes())
        image_name = f"{UUID(int=1)}.png"
        (staged / "draft-images").mkdir()
        (staged / "draft-images" / image_name).write_bytes(PIXEL)
        staged_preferences["CodexGUI.draftContext"] = json.dumps({str(checkout): {"thread:imported-thread": [{
            "id": "imported-image", "kind": "image", "title": "Owned migrated image",
            "path": str(originals / image_name)
        }]}}).encode("utf-8")
        preferences.write_bytes(plistlib.dumps(staged_preferences))
        attempt([*recovery, "verify-appkit", staged, originals], "Verified the staged AppKit source copy")
        unchanged = preferences.read_bytes()
        preferences.write_bytes(unchanged + b"\n")
        attempt(import_command, "differs from its verified manifest", success=False)
        preferences.write_bytes(unchanged)
        attempt(import_command, '"unresolvedCommands":1', extra_environment=environment)

        transfer = [app, "--transfer-appkit-worktrees"]
        attempt([*transfer, "prepare", profile, records, bundle], "Prepared the AppKit worktree handoff")
        bundle.rename(root / "Retired fixture.app")
        attempt([*transfer, "commit", profile], "Committed the one-way AppKit worktree handoff")
        imported = profile / "worktrees" / record.name
        assert imported.is_file()
        attempt([*recovery, "fixture-new-work", profile, original], "Created a new Tauri-managed fixture task")
        previous = "Tauri draft created after cutover"
        assert draft(profile) == (previous,)
        task = next(path for path in (profile / "worktrees").glob("*.json") if path != imported)
        new_checkout = Path(json.loads(task.read_bytes())["workspace"]["checkoutPath"])
        (new_checkout / "uncommitted.txt").write_bytes(b"Keep new working-tree bytes\n")
        git_records = registrations(original)
        owned_records = {path.name: path.read_bytes() for path in (imported, task)}
        recovery_dir = root / "Tauri recovery copy"
        attempt([*recovery, "backup", profile, recovery_dir], "Saved a verified Tauri recovery copy",
                extra_environment=environment)

        saved_database = recovery_dir / "workspace.sqlite3"
        saved_bytes = saved_database.read_bytes()
        saved_database.write_bytes(saved_bytes + b"changed")
        attempt([*recovery, "restore", recovery_dir, root / "corrupt restore"], "differs from its verified manifest",
                success=False)
        assert not (root / "corrupt restore").exists()
        saved_database.write_bytes(saved_bytes)

        newer = "A newer Tauri draft created after the recovery copy"
        replace_draft(profile, newer)
        attempt([*recovery, "restore", recovery_dir, profile], "Reopened the Tauri profile",
                extra_environment=environment)
        assert draft(profile) == (newer,)
        profile.rename(root / "Prior Tauri profile")
        profile.mkdir()
        attempt([*recovery, "restore", recovery_dir, profile], "Reopened the Tauri profile",
                extra_environment=environment)
        assert draft(profile) == (previous,)
        assert (profile / "worktrees" / ".authority").is_file()
        blobs = profile / "workspace.sqlite3.attachments" / "blobs"
        assert any(blob.is_file() and blob.read_bytes() == PIXEL for blob in blobs.rglob("*"))
        assert {name: (profile / "worktrees" / name).read_bytes() for name in owned_records} == owned_records
        assert registrations(original) == git_records
        assert (new_checkout / "uncommitted.txt").read_bytes() == b"Keep new working-tree bytes\n"
        assert (checkout / "new.txt").read_bytes() == b"Untracked data\n"
        with closing(sqlite3.connect(profile / "workspace.sqlite3")) as database:
            assert database.execute("SELECT thread_id, turn_id, item_id FROM exit_recovery").fetchall() == [
                ("imported-thread", "unfinished-turn", "existing-command")]
        assert {file.name: file.read_bytes() for file in (config, auth)} == before
        assert not (recovery_dir / "config.toml").exists() and not (recovery_dir / "auth.json").exists()
        print("Verified staged copy integrity, in-place repair, and recovery of migrated and new Tauri work")


if __name__ == "__main__":
    main()
