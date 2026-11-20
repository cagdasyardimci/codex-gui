"""Verify Settings with an isolated account, provider changes, and delayed usage."""

import argparse
import json
import os
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory

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
        assert json.loads(account.read_text(encoding="utf-8")) == {"profile": "second", "signedOut": True}
        requests = [event for event in map(json.loads, trace.read_text(encoding="utf-8").splitlines())
                    if event["direction"] == "request"]
        starts = [entry["params"]["clientInfo"]["name"] for entry in requests if entry["method"] == "initialize"]
        assert starts.count("codex_gui") >= 2 and starts.count("codex_gui_settings") >= 6, starts
        logout = [entry for entry in requests if entry["method"] == "account/logout"]
        assert len(logout) == 1 and logout[0]["params"] == {}, logout
        assert not list(profile.iterdir())
        print("Verified provider and policy rotation, stale sensitive reads, one captured sign-out, and restarted workspace credentials")


if __name__ == "__main__":
    main()
