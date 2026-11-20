"""Exercise server-owned and local queues in independent installed profiles."""

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


HELD = "Hold this fixture turn"
FIRST = "First queued follow-up"
EDITED = "Edited queued follow-up 日本語"
DELETED = "Delete this follow-up"
STRAIGHT = "Steer directly into this turn"
LAST = "Resume from the empty composer"


def verify(executable: Path, legacy: bool) -> None:
    with TemporaryDirectory(prefix="codex-gui-queue-") as scratch:
        root = Path(scratch).resolve()
        checkout = root / "Checkout café"
        checkout.mkdir()
        profile = root / "isolated codex home"
        profile.mkdir()
        data = root / "beta data"
        trace = root / "queue.jsonl"
        result = subprocess.run(
            [str(executable), "--verify-queue", str(data), str(checkout)],
            env={
                **os.environ,
                "CODEX_EXECUTABLE": str(fixture_executable(root)),
                "CODEX_HOME": str(profile),
                "CODEX_GUI_QA_SCENARIO": "desktop-legacy-queue" if legacy else "desktop-queue",
                "CODEX_GUI_QA_STATE": str(root / "state.json"),
                "CODEX_GUI_QA_TRACE": str(trace),
                "PYTHONIOENCODING": "utf-8",
            },
            timeout=80, capture_output=True, encoding="utf-8", errors="replace",
        )
        print(result.stdout, end="")
        if result.returncode or "Verified installed queue controls" not in result.stdout:
            if trace.is_file():
                frames = [json.loads(line) for line in trace.read_text(encoding="utf-8").splitlines()]
                recent = [frame for frame in frames if frame["direction"] == "request"][-18:]
                print(json.dumps(recent, ensure_ascii=True))
            raise SystemExit(result.stderr or "The installed app did not complete the queue fixture")
        frames = [json.loads(line) for line in trace.read_text(encoding="utf-8").splitlines()]
        requests = [frame for frame in frames if frame["direction"] == "request"]

        def params(method):
            return [frame["params"] for frame in requests if frame["method"] == method]

        starts = params("turn/start")
        [thread] = params("thread/start")
        assert Path(thread["cwd"]).samefile(checkout)
        owner = starts[0]["threadId"]
        assert [row["input"][0]["text"] for row in starts] == ([HELD, HELD, LAST] if legacy else [HELD])
        assert all(Path(row["cwd"]).samefile(checkout) for row in starts)
        steered = params("turn/steer")
        assert [row["input"][0]["text"] for row in steered] == [EDITED, STRAIGHT]
        assert len({row["expectedTurnId"] for row in steered}) == 1
        interrupts = params("turn/interrupt")
        assert len(interrupts) == 2 and interrupts[0]["turnId"] == steered[0]["expectedTurnId"]
        assert interrupts[0]["turnId"] != interrupts[1]["turnId"]
        assert UUID(steered[0]["clientUserMessageId"]) != UUID(steered[1]["clientUserMessageId"])
        for method in ("thread/queue/add", "thread/queue/update", "thread/queue/reorder",
                       "thread/queue/delete", "thread/queue/start", "turn/steer", "turn/start", "turn/interrupt"):
            assert all(row["threadId"] == owner for row in params(method)), method
        if legacy:
            assert not any(row["method"].startswith("thread/queue/") and row["method"] != "thread/queue/list"
                           for row in requests)
            assert len({UUID(row["clientUserMessageId"]) for row in starts}) == 3
        else:
            added = params("thread/queue/add")
            assert [row["input"][0]["text"] for row in added] == [FIRST, DELETED, HELD, LAST]
            assert len({UUID(row["clientUserMessageId"]) for row in added}) == 4
            [updated] = params("thread/queue/update")
            [reordered] = params("thread/queue/reorder")
            removed = params("thread/queue/delete")
            resumed = params("thread/queue/start")
            assert updated["input"][0]["text"] == EDITED
            assert steered[0]["clientUserMessageId"] == added[0]["clientUserMessageId"]
            assert [row["queuedSubmissionId"] for row in reversed(removed)] == reordered["queuedSubmissionIds"]
            assert removed[0]["queuedSubmissionId"] == updated["queuedSubmissionId"]
            assert len(resumed) == 2 and len({row["queuedSubmissionId"] for row in resumed}) == 2
        with closing(sqlite3.connect(data / "workspace.sqlite3")) as database:
            assert database.execute("SELECT thread_id, enabled FROM queue_preferences").fetchall() == [(owner, 0)]
            assert database.execute("SELECT COUNT(*) FROM queue_edits").fetchone() == (0,)
            assert database.execute("SELECT COUNT(*) FROM queue_steering").fetchone() == (0,)
        assert not list(profile.iterdir())
        print(f"Verified unique {'local' if legacy else 'server'} queue receipts, both Resume controls, and captured steering")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    executable = parser.parse_args().app.resolve(strict=True)
    verify(executable, legacy=False)
    verify(executable, legacy=True)


if __name__ == "__main__":
    main()
