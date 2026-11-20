"""Verify ephemeral title helpers and scope across installed chat switches and renames."""

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
    with TemporaryDirectory(prefix="codex-gui-automatic-titles-") as scratch:
        root = Path(scratch).resolve()
        project = root / "Title checkout"
        profile = root / "codex home"
        project.mkdir()
        profile.mkdir()
        trace = root / "trace.jsonl"
        state = root / "backend.json"
        result = subprocess.run(
            [args.app.resolve(strict=True), "--verify-automatic-titles", root / "desktop", project],
            env={
                **os.environ,
                "CODEX_HOME": str(profile),
                "CODEX_EXECUTABLE": str(fixture_executable(root)),
                "CODEX_GUI_QA_SCENARIO": "desktop-automatic-titles",
                "CODEX_GUI_QA_TRACE": str(trace),
                "CODEX_GUI_QA_STATE": str(state),
                "PYTHONIOENCODING": "utf-8",
            },
            capture_output=True, encoding="utf-8", errors="replace", timeout=70,
        )
        print(result.stdout, end="")
        if result.returncode or "Verified installed scoped automatic chat titles" not in result.stdout:
            raise SystemExit(result.stderr or "The installed title fixture did not complete")

        requests = [record for line in trace.read_text(encoding="utf-8").splitlines()
                    if (record := json.loads(line))["direction"] == "request"]
        starts = [record["params"] for record in requests if record["method"] == "thread/start" and record["params"].get("ephemeral")]
        assert len(starts) == 2, starts
        for helper in starts:
            assert helper["sandbox"] == "read-only" and helper["approvalPolicy"] == "never"
            assert helper["config"] == {"web_search": "disabled", "features.shell_tool": False}
            assert Path(helper["cwd"]).samefile(project)
        turns = [record["params"] for record in requests if record["method"] == "turn/start"]
        ordinary = [turn for turn in turns if not turn["threadId"].startswith("title-helper-")]
        helpers = [turn for turn in turns if turn["threadId"].startswith("title-helper-")]
        assert len(ordinary) == len(helpers) == 2
        first, second = [turn["threadId"] for turn in ordinary]
        original = "Refactor the message stream\n" + "é" * 4_100
        assert ordinary[0]["input"][0]["text"] == original
        assert helpers[0]["input"] == [{"type": "text", "text": original[:4_000]}]
        assert helpers[1]["input"] == [{"type": "text", "text": "Keep the manual chat title"}]
        for helper in helpers:
            assert helper["effort"] == "low" and helper["outputSchema"]["required"] == ["title"]
        assert [record["params"] for record in requests if record["method"] == "thread/name/set"] == [
            {"threadId": first, "name": "Réparer le flux"},
            {"threadId": second, "name": "Manual chat title"},
        ]
        generated = next(index for index, request in enumerate(requests) if request["method"] == "thread/name/set")
        assert any(record["method"] == "thread/resume" and record.get("threadId") == "history-first"
                   for record in requests[:generated])
        assert any(record["method"] == "thread/unsubscribe" and record.get("threadId") == helpers[0]["threadId"]
                   for record in requests)
        saved = json.loads(state.read_text(encoding="utf-8"))["threads"]
        names = {thread["id"]: thread["name"] for thread in saved}
        assert names[first] == "Réparer le flux" and names[second] == "Manual chat title"
        assert names["history-first"] == "First fixture chat" and not any(key.startswith("title-helper-") for key in names)
        assert not list(profile.iterdir())
        print("Verified bounded prompt, read-only ephemeral turn, captured title update, and manual rename precedence")


if __name__ == "__main__":
    main()
