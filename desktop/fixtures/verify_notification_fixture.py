"""Verify installed notification routing, policy, and custom audio with an isolated delivery sink."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
from tempfile import TemporaryDirectory
import wave

from verify_coding_probe import fixture_executable

RATE = 8000
SAMPLES = [1000, -1000, 0, 250] * 200


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    arguments = parser.parse_args()
    app = arguments.app.resolve(strict=True)
    with TemporaryDirectory(prefix="codex-gui-notifications-") as scratch:
        root = Path(scratch).resolve()
        data, home, checkout = (root / name for name in ("desktop", "isolated Codex profile", "Notification fixture"))
        for directory in (data, home, checkout):
            directory.mkdir()
        write_sounds(data)
        backend_state = root / "mock.json"
        backend_state.write_text('{"config":{"model_provider":"openai","model":"fixture-default"}}', encoding="utf-8")
        trace = root / "trace.jsonl"
        result = subprocess.run(
            [app, "--verify-notifications", data, checkout],
            env={**os.environ, "CODEX_HOME": str(home), "CODEX_EXECUTABLE": str(fixture_executable(root)),
                 "CODEX_GUI_QA_SCENARIO": "desktop-turn", "CODEX_GUI_QA_STATE": str(backend_state),
                 "CODEX_GUI_QA_TRACE": str(trace), "PYTHONIOENCODING": "utf-8"},
            capture_output=True, encoding="utf-8", errors="replace", timeout=100,
        )
        print(result.stdout, end="")
        prefix = "Verified installed desktop notifications: "
        summaries = [line.removeprefix(prefix) for line in result.stdout.splitlines() if line.startswith(prefix)]
        if result.returncode or len(summaries) != 1:
            raise SystemExit(result.stderr or "The installed notifications fixture did not finish")
        summary = json.loads(summaries[0])
        assert summary["denied"] == 1
        notifications = summary["delivered"]
        assert [alert["category"] for alert in notifications] == ["question", "permission", "completion"]
        requests = [json.loads(line) for line in trace.read_text(encoding="utf-8").splitlines()]
        starts = [record["params"] for record in requests if record.get("method") == "turn/start"]
        assert len(starts) == 2 and starts[0]["threadId"] == starts[1]["threadId"]
        assert all(alert["key"]["chatId"] == starts[0]["threadId"] for alert in notifications)
        assert len({alert["key"]["projectId"] for alert in notifications}) == 1
        assert [alert["title"] for alert in notifications] == ["Answer needed", "Approval needed", "Task completed"]
        preferences = json.loads((data / "notifications.json").read_text(encoding="utf-8"))
        assert preferences["questions"] is True and preferences["permissions"] is True
        assert preferences["completions"] == "whenUnfocused" and preferences["sound"] == "custom"
        (archive,) = (data / "notification-sounds").iterdir()
        assert archive.stem == preferences["custom"]["digest"] == hashlib.sha256(archive.read_bytes()).hexdigest()
        assert preferences["custom"]["name"] == "Fixture CAF"
        with wave.open(str(archive), "rb") as selected:
            assert selected.getframerate() == RATE and selected.getnchannels() == 1 and selected.getsampwidth() == 2
            assert selected.readframes(selected.getnframes()) == struct.pack(f"<{len(SAMPLES)}h", *SAMPLES)
        print("Verified one denied alert, category preferences, hidden-chat activation, and no replay")
        print("Verified exact WAV, AIFF, and CAF normalization and selection retention after invalid or cancelled import")


def write_sounds(folder):
    pcm = struct.pack(f"<{len(SAMPLES)}h", *SAMPLES)
    write_wave(folder / "Fixture WAV.wav", pcm)
    write_wave(folder / "Long.wav", b"\0\0" * RATE * 31)
    (folder / "Invalid.wav").write_bytes(b"RIFF\x10\0\0\0WAVEinvalid")

    def aiff_chunk(name, body):
        return name + struct.pack(">I", len(body)) + body

    aiff = b"AIFF"
    rate_as_extended = bytes.fromhex("400bfa00000000000000")
    aiff += aiff_chunk(b"COMM", struct.pack(">hIh", 1, len(SAMPLES), 16) + rate_as_extended)
    aiff += aiff_chunk(b"SSND", b"\0" * 8 + struct.pack(f">{len(SAMPLES)}h", *SAMPLES))
    (folder / "Fixture AIFF.aiff").write_bytes(aiff_chunk(b"FORM", aiff))

    def caf_chunk(name, body):
        return name + struct.pack(">q", len(body)) + body

    caf = b"caff" + struct.pack(">HH", 1, 0)
    caf += caf_chunk(b"desc", struct.pack(">d4sIIIII", RATE, b"lpcm", 2, 2, 1, 1, 16))
    caf += caf_chunk(b"data", b"\0" * 4 + pcm)
    (folder / "Fixture CAF.caf").write_bytes(caf)


def write_wave(path, pcm):
    with wave.open(str(path), "wb") as target:
        target.setnchannels(1)
        target.setsampwidth(2)
        target.setframerate(RATE)
        target.writeframes(pcm)


if __name__ == "__main__":
    main()
