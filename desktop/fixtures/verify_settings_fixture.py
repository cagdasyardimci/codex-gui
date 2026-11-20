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
        for folder in (profile / "skills" / "fixture", profile / "skills" / ".system", checkout):
            folder.mkdir(parents=True, exist_ok=True)
            (folder / "SKILL.md").write_text("# Fixture skill\n", encoding="utf-8")
        account = data / "fixture-account.json"
        account.write_text(json.dumps({"profile": "first"}), encoding="utf-8")
        trace = root / "trace.jsonl"
        result = subprocess.run(
            [str(args.app.resolve(strict=True)), "--verify-settings", str(data), str(checkout)],
            env={**os.environ, "CODEX_HOME": str(profile), "CODEX_EXECUTABLE": str(fixture_executable(root)),
                 "CODEX_GUI_QA_SCENARIO": "desktop-settings", "CODEX_GUI_QA_TRACE": str(trace),
                 "CODEX_GUI_QA_SETTINGS": str(account), "PYTHONIOENCODING": "utf-8"},
            capture_output=True, encoding="utf-8", errors="replace", timeout=120,
        )
        print(result.stdout, end="")
        if result.returncode or "Verified installed account, usage, configuration" not in result.stdout:
            raise SystemExit(result.stderr or "The installed Settings verification did not complete")
        assert json.loads(account.read_text(encoding="utf-8")) == {
            "profile": "second", "signedOut": True, "usedCredit": True,
            "version": 12, "config": {"features": {"browser_use": True}},
        }
        requests = [event for event in map(json.loads, trace.read_text(encoding="utf-8").splitlines())
                    if event["direction"] == "request"]
        starts = [entry["params"]["clientInfo"]["name"] for entry in requests if entry["method"] == "initialize"]
        assert starts.count("codex_gui") >= 2 and starts.count("codex_gui_settings") >= 6, starts
        logout = [entry for entry in requests if entry["method"] == "account/logout"]
        assert len(logout) == 1 and logout[0]["params"] == {}, logout
        writes = [entry["params"] for entry in requests if entry["method"] == "config/value/write"
                  and entry["params"]["expectedVersion"].startswith("layer-first-")]
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
        assert sorted(path.name for path in profile.iterdir()) == ["AGENTS.md", "skills"]
        assert (profile / "AGENTS.md").read_bytes() == "\ufeff# Final Codex instructions\r\nPreserve café and 日本語.\r\n".encode("utf-8")
        verify_integration_trace(requests, account, profile)
        print("Verified provider and policy rotation, stale sensitive reads, one captured sign-out, and restarted workspace credentials")
        print("Verified versioned writes, newer configuration after lost acknowledgement, and persistent effort visibility")
        print("Verified atomic memory preferences, one confirmed reset, and revision-checked global instructions")
        print("Verified reset confirmation, stale account and expiry, refreshed usage, and durable duplicate protection")
        print("Verified MCP draft recovery and reload, refreshed plugin, skill and hook catalogs, and site-origin policy writes")


def verify_integration_trace(requests, account, profile):
    writes = [request["params"] for request in requests if request["method"] == "config/value/write"
              and request["params"]["expectedVersion"].startswith("layer-second-")]
    assert all(Path(write["filePath"]).samefile(account) and write["mergeStrategy"] == "replace" for write in writes)
    mcp = [write for write in writes if write["keyPath"] == "mcp_servers"]
    first, retry, changed, disabled, removed = mcp
    assert first == retry and first["expectedVersion"] == "layer-second-0"
    assert retry["value"] == {"fixture.local": {
        "command": "fixture-stdio", "args": ["--one", "argument with spaces"],
        "env": {"FIXTURE_TEST": "isolated"}, "env_vars": ["FIXTURE_ENV"],
    }}
    http = {
        "url": "https://example.invalid/fixture/mcp", "http_headers": {"X-Fixture": "isolated"},
        "env_http_headers": {"X-Token": "FIXTURE_TOKEN"}, "bearer_token_env_var": "FIXTURE_TOKEN",
    }
    assert changed["value"] == {"fixture.local": http}
    assert disabled["value"] == {"fixture.local": {**http, "enabled": False}}
    assert removed["value"] == {}

    operations = [request["method"] for request in requests]
    assert operations.count("config/mcpServer/reload") == 4
    assert [request["params"] for request in requests if request["method"] == "mcpServer/oauth/login"] == [
        {"name": "fixture.local"},
    ]
    assert [operation for operation in operations if operation.startswith("marketplace/") or operation in {
        "plugin/install", "plugin/uninstall",
    }] == ["plugin/install", "plugin/uninstall", "marketplace/add", "marketplace/upgrade", "marketplace/remove"]
    assert operations.count("plugin/list") >= 10
    (skill,) = [request["params"] for request in requests if request["method"] == "skills/config/write"]
    assert skill["enabled"] is False and Path(skill["path"]).samefile(profile / "skills" / "fixture" / "SKILL.md")
    assert operations.count("hooks/list") >= 5
    hook = [(write["keyPath"], write["value"]) for write in writes if write["keyPath"].startswith("hooks.")]
    assert hook == [('hooks.state."fixture.hook|file".trusted_hash', "fixture-hash-v2"),
                    ('hooks.state."fixture.hook|file".enabled', False)]
    origin = "https://one.mixed.test:443"
    preserve = {"https://preserve.some.test:443": {"downloads": "deny", "persistent_approval": False}}
    assert [write["value"] for write in writes if write["keyPath"] == "browser_use.origins"] == [
        {**preserve, origin: {"access": "allow"}},
        {**preserve, origin: {"access": "allow", "uploads": "deny"}},
        preserve,
    ]


if __name__ == "__main__":
    main()
