"""Verify installed offline dictation and captured question ownership."""

import argparse
from hashlib import sha256
import json
import os
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory
import wave

from verify_coding_probe import fixture_executable
from verify_diff_fixture import git

EXAMPLE = "59dfb9a4acb36fe2a2affc14bacbee2920ff435cb13cc314a08c13f66ba7860e"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("example", type=Path)
    args = parser.parse_args()
    app = args.app.resolve(strict=True)
    assert sha256(args.example.read_bytes()).hexdigest() == EXAMPLE
    with TemporaryDirectory(prefix="codex-gui-dictation-") as scratch:
        root = Path(scratch).resolve()
        data, profile, checkout = (root / name for name in ("desktop", "isolated Codex profile", "Question checkout"))
        for folder in (data, profile, checkout):
            folder.mkdir()
        git(checkout, "init", "--quiet", "--template=")
        (checkout / "workflow-notes.txt").write_bytes(b"Before fixture approval\n")
        git(checkout, "add", "--", "workflow-notes.txt")
        git(checkout, "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
            "-c", "commit.gpgSign=false", "commit", "--quiet", "-m", "Create question fixture")
        trace, pcm = (root / name for name in ("trace.jsonl", "offline-sample.pcm"))
        with wave.open(str(args.example), "rb") as audio:
            assert (audio.getframerate(), audio.getsampwidth(), audio.getnchannels()) == (16000, 2, 1)
            pcm.write_bytes(audio.readframes(audio.getnframes()))
        result = subprocess.run([app, "--verify-question-dictation", data, checkout], env={
            **os.environ, "CODEX_HOME": str(profile), "CODEX_EXECUTABLE": str(fixture_executable(root)),
            "CODEX_GUI_QA_SCENARIO": "desktop-workflow", "CODEX_GUI_QA_STATE": str(root / "backend.json"),
            "CODEX_GUI_QA_TRACE": str(trace), "CODEX_GUI_QA_DICTATION_PCM": str(pcm), "PYTHONIOENCODING": "utf-8",
        }, capture_output=True, encoding="utf-8", errors="replace", timeout=100)
        print(result.stdout, end="")
        prefix = "Verified installed desktop voice: "
        summaries = [json.loads(line.removeprefix(prefix)) for line in result.stdout.splitlines() if line.startswith(prefix)]
        if result.returncode or len(summaries) != 1:
            raise SystemExit(result.stderr or "The installed dictation fixture did not finish")
        (summary,) = summaries
        records = [json.loads(line) for line in trace.read_text(encoding="utf-8").splitlines()]
        responses = [record["result"] for record in records if record["direction"] == "question-response"]
        assert responses == [{"answers": {"details": {"answers": ["Typed answer on the first question"]},
                                          "area": {"answers": [summary["speech"]]}}}]
        (completed,) = [record for record in records if record["direction"] == "event" and record.get("method") == "turn/completed"]
        assert completed["threadId"] == summary["owner"]
        assert not any(record.get("method", "").startswith("thread/realtime/")
                       and record["method"] != "thread/realtime/listVoices" for record in records)
        assert not list(profile.iterdir())
        print("Verified bundled local recognition, denied capture, retired questions, and exact submitted answers")


if __name__ == "__main__":
    main()
