import json
import os
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory
from unittest import TestCase
from unittest.mock import patch

from mock_backend import launch_mock_backend


class MockBackendTests(TestCase):
    def test_launch_preserves_checkout_identity_and_isolates_backend_files(self):
        with TemporaryDirectory(prefix="codex-gui-fixture-") as temporary:
            root = Path(temporary).resolve()
            checkout = root / "project café"
            checkout.mkdir()
            state_directory = root / "fixture state"
            inherited = {
                "CODEX_GUI_QA_STATE": str(root / "unrelated state.json"),
                "CODEX_GUI_QA_TRACE": str(root / "unrelated trace.jsonl"),
                "CODEX_GUI_QA_SCENARIO": "unrelated-scenario",
                "LC_ALL": "C",
                "PYTHONCOERCECLOCALE": "0",
                "PYTHONUTF8": "0",
            }
            requests = [
                {"id": 1, "method": "initialize", "params": {}},
                {"method": "initialized"},
                {"id": 2, "method": "thread/start", "params": {"cwd": str(checkout)}},
            ]
            payload = "".join(json.dumps(request) + "\n" for request in requests).encode()

            with patch.dict(os.environ, inherited):
                child = launch_mock_backend(checkout, state_directory, "streaming")
            with child:
                try:
                    stdout, stderr = child.communicate(payload, timeout=15)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.communicate()
                    raise

            self.assertEqual(child.returncode, 0, stderr.decode("utf-8", errors="replace"))
            initialize, started = [json.loads(line) for line in stdout.splitlines()]
            self.assertEqual(initialize, {"id": 1, "result": {"userAgent": "structured-qa-backend/1"}})
            self.assertEqual(started["id"], 2)
            thread = started["result"]["thread"]
            self.assertEqual(thread["cwd"], str(checkout))

            state = json.loads((state_directory / "state.json").read_text(encoding="utf-8"))
            self.assertIn(thread["id"], [saved["id"] for saved in state["threads"]])
            trace = [
                json.loads(line)
                for line in (state_directory / "trace.jsonl").read_text(encoding="utf-8").splitlines()
            ]
            self.assertEqual(trace[0]["scenario"], "streaming")
            self.assertFalse(trace[0]["modelCalls"])
            self.assertFalse(Path(inherited["CODEX_GUI_QA_STATE"]).exists())
            self.assertFalse(Path(inherited["CODEX_GUI_QA_TRACE"]).exists())
