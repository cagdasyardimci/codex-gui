"""Qualify completed coding and interrupted turns in separate installed runs."""

import argparse
from contextlib import closing
import json
import os
from pathlib import Path
import sqlite3
import subprocess
from tempfile import TemporaryDirectory
from uuid import UUID

from verify_coding_probe import fixture_executable
from verify_diff_fixture import git


def verify(executable: Path, *, active: bool) -> None:
    with TemporaryDirectory(prefix="codex-gui-turn-") as scratch:
        root = Path(scratch).resolve()
        data = root / "beta data"
        checkout = root / "Checkout café"
        checkout.mkdir()
        codex_home = root / "codex home"
        codex_home.mkdir()
        trace = root / "trace.jsonl"
        git_trace = root / "git.jsonl"
        target = checkout / "workflow-notes.txt"
        if not active:
            git(checkout, "init", "--quiet", "--template=")
            git(checkout, "config", "--local", "core.autocrlf", "false")
            target.write_bytes(b"Before fixture approval\n")
            git(checkout, "add", "--", target.name)
            git(checkout, "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                "-c", "commit.gpgSign=false", "commit", "--quiet", "-m", "Create workflow fixture")
            index = checkout / ".git" / "index"
            saved_index = index.read_bytes()
        mode = "--verify-active-turn" if active else "--verify-turn"
        confirmation = "Verified installed active-turn Stop" if active else "Verified installed Send"
        result = subprocess.run(
            [str(executable), mode, str(data), str(checkout)],
            env={
                **os.environ,
                "CODEX_EXECUTABLE": str(fixture_executable(root)),
                "CODEX_HOME": str(codex_home),
                "CODEX_GUI_QA_SCENARIO": "desktop-turn" if active else "desktop-workflow",
                "CODEX_GUI_QA_STATE": str(root / "state.json"),
                "CODEX_GUI_QA_TRACE": str(trace),
                "GIT_TRACE2_EVENT": str(git_trace),
                "PYTHONIOENCODING": "utf-8",
            },
            timeout=60, capture_output=True, encoding="utf-8", errors="replace",
        )
        print(result.stdout, end="")
        if result.returncode or confirmation not in result.stdout:
            raise SystemExit(result.stderr or "The installed workspace did not confirm the turn fixture")
        entries = [json.loads(line) for line in trace.read_text().splitlines()]
        requests = [item for item in entries if item["direction"] == "request"]
        starts = [item["params"] for item in requests if item["method"] == "turn/start"]
        prompts = ["Hold this fixture turn"] if active else ["Recover this fixture receipt", "Fixture mixed questions"]
        assert [item["input"] for item in starts] == [
            [{"type": "text", "text": prompt}] for prompt in prompts
        ], starts
        assert len({UUID(item["clientUserMessageId"]) for item in starts}) == len(prompts)
        assert sum(item["method"] == "thread/start" for item in requests) == 1
        owner = starts[0]["threadId"]
        assert all(item["threadId"] == owner and Path(item["cwd"]).samefile(checkout) for item in starts)
        stops = [item["params"] for item in requests if item["method"] == "turn/interrupt"]
        approvals = [item["result"] for item in entries if item["direction"] == "command-approval-response"]
        questions = [item["result"] for item in entries if item["direction"] == "question-response"]
        terminals = [item for item in entries if item["direction"] == "event"
                     and item.get("method") == "turn/completed"]
        [terminal] = terminals
        assert terminal["threadId"] == owner
        if active:
            assert stops == [{"threadId": owner, "turnId": terminal["turnId"]}], stops
            assert terminal["status"] == "interrupted" and not approvals and not questions
        else:
            assert terminal["status"] == "completed" and not stops
            assert approvals == [{"decision": "accept"}]
            assert questions == [
                {"answers": {"details": {"answers": ["Faster typing 日本語"]},
                             "area": {"answers": ["Composer", "Settings"]}}},
            ]
            git_commands = [json.loads(line) for line in git_trace.read_text(encoding="utf-8").splitlines()]
            patches = [entry["argv"] for entry in git_commands if entry.get("event") == "start"
                       and "diff" in entry["argv"] and "--name-status" not in entry["argv"]]
            assert len(patches) == 1 and patches[0][-1] == target.name, patches
            assert target.read_bytes() == "After fixture approval 日本語\n".encode()
            assert index.read_bytes() == saved_index
        expected_draft = "Draft retained while a background turn runs 日本語" if active else ""
        with closing(sqlite3.connect(data / "workspace.sqlite3")) as database:
            assert database.execute("SELECT thread_id FROM desktop_selection").fetchone() == (owner,)
            assert database.execute("SELECT COUNT(*) FROM submission_outcomes").fetchone() == (len(prompts),)
            assert database.execute(
                "SELECT drafts.text FROM thread_drafts JOIN drafts ON drafts.id = thread_drafts.draft_id "
                "WHERE thread_id = ?", [owner]
            ).fetchone() == (expected_draft,)
        assert not list(codex_home.iterdir())


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    executable = parser.parse_args().app.resolve(strict=True)
    verify(executable, active=False)
    verify(executable, active=True)
    print("Verified separate installed runs with no replay and the original active chat’s draft intact")


if __name__ == "__main__":
    main()
