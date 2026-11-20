"""Verify Settings with an isolated account, provider changes, and delayed usage."""

import argparse
from contextlib import closing
import json
import os
import sqlite3
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory
from uuid import UUID

from verify_coding_probe import fixture_executable


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    args = parser.parse_args()
    with TemporaryDirectory(prefix="codex-gui-settings-") as scratch:
        root = Path(scratch).resolve()
        checkout = root / "Settings checkout"
        profile = root / "isolated Codex profile"
        data = root / "desktop"
        for directory in (checkout, profile, data):
            directory.mkdir()
        (profile / "fixture-memory.txt").write_bytes(b"Isolated synthetic Codex memory\n")
        account = data / "fixture-account.json"
        account.write_text(json.dumps({"profile": "first"}), encoding="utf-8")
        trace = root / "trace.jsonl"
        result = subprocess.run(
            [str(args.app.resolve(strict=True)), "--verify-settings", str(data), str(checkout)],
            env={**os.environ, "CODEX_HOME": str(profile), "CODEX_EXECUTABLE": str(fixture_executable(root)),
                 "CODEX_GUI_QA_SCENARIO": "desktop-settings", "CODEX_GUI_QA_TRACE": str(trace),
                 "CODEX_GUI_QA_SETTINGS": str(account), "PYTHONIOENCODING": "utf-8"},
            capture_output=True, encoding="utf-8", errors="replace", timeout=75,
        )
        print(result.stdout, end="")
        if result.returncode or "Verified installed account, usage, configuration" not in result.stdout:
            raise SystemExit(result.stderr or "The installed Settings verification did not complete")
        assert json.loads(account.read_text(encoding="utf-8")) == {
            "profile": "second", "signedOut": True, "usedCredit": True,
        }
        requests = [event for event in map(json.loads, trace.read_text(encoding="utf-8").splitlines())
                    if event["direction"] == "request"]
        starts = [entry["params"]["clientInfo"]["name"] for entry in requests if entry["method"] == "initialize"]
        assert starts.count("codex_gui") >= 2 and starts.count("codex_gui_settings") >= 6, starts
        logout = [entry for entry in requests if entry["method"] == "account/logout"]
        assert len(logout) == 1 and logout[0]["params"] == {}, logout
        writes = [entry["params"] for entry in requests if entry["method"] == "config/value/write"]
        assert [(entry["keyPath"], entry["value"], entry["expectedVersion"]) for entry in writes] == [
            ("model_verbosity", "high", "layer-first-0"),
            ("features.local_thread_store_compression", True, "layer-first-1"),
            ("model_reasoning_summary", "concise", "layer-first-2"),
            ("memories.disable_on_external_context", True, "layer-first-1"),
        ], writes
        assert all(Path(entry["filePath"]).samefile(account) for entry in writes)
        (reset,) = [entry["params"] for entry in requests if entry["method"] == "account/rateLimitResetCredit/consume"]
        assert reset["creditId"] == "credit-full"
        with closing(sqlite3.connect(data / "workspace.sqlite3")) as database:
            assert database.execute("SELECT effort FROM desktop_hidden_reasoning_efforts").fetchall() == [("minimal",)]
            assert database.execute("SELECT credit, attempt FROM desktop_usage_reset_attempts").fetchall() == [
                ("named:credit-full", UUID(reset["idempotencyKey"]).bytes),
            ]
        (memory_write,) = [entry["params"] for entry in requests if entry["method"] == "config/batchWrite"]
        assert memory_write["expectedVersion"] == "layer-first-0" and Path(memory_write["filePath"]).samefile(account)
        assert [edit["keyPath"] for edit in memory_write["edits"]] == [
            "features.memories", "memories.generate_memories", "memories.use_memories",
        ]
        assert sum(entry["method"] == "memory/reset" for entry in requests) == 1
        assert [path.name for path in profile.iterdir()] == ["AGENTS.md"]
        assert (profile / "AGENTS.md").read_bytes() == "\ufeff# Final Codex instructions\r\nPreserve café and 日本語.\r\n".encode("utf-8")
        print("Verified provider and policy rotation, stale sensitive reads, one captured sign-out, and restarted workspace credentials")
        print("Verified versioned writes, newer configuration after lost acknowledgement, and persistent effort visibility")
        print("Verified atomic memory preferences, one confirmed reset, and revision-checked global instructions")
        print("Verified reset confirmation, stale account and expiry, refreshed usage, and durable duplicate protection")


if __name__ == "__main__":
    main()
