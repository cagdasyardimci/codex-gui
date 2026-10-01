#!/usr/bin/env python3
"""Check that the official test runner rejects incomplete and failed invocations."""

import importlib.util
import io
from pathlib import Path
import sys
import unittest


SPEC = importlib.util.spec_from_file_location(
    "run_swift_tests", Path(__file__).with_name("run-swift-tests.py")
)
RUNNER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUNNER)


class SwiftTestCompletionTests(unittest.TestCase):
    def run_child(self, source):
        output = io.BytesIO()
        status = RUNNER.run_test_command([sys.executable, "-c", source], output)
        return status, output.getvalue().decode()

    def test_completed_singular_and_plural_runs_preserve_output(self):
        for counts in ["1 test in 1 suite", "490 tests in 63 suites"]:
            with self.subTest(counts=counts):
                summary = f"✔ Test run with {counts} passed after 0.024 seconds."
                status, output = self.run_child(f"print('Unicode 😀'); print({summary!r})")
                self.assertEqual(status, 0)
                self.assertIn("Unicode 😀\n" + summary, output)
                self.assertIn("SwiftPM child return code: 0", output)

    def test_zero_exit_without_completion_fails(self):
        status, output = self.run_child("print('◇ Test incomplete() started.')")
        self.assertEqual(status, 1)
        self.assertIn("final completion summary is missing", output)

    def test_earlier_summary_does_not_hide_subsequent_incomplete_activity(self):
        status, _ = self.run_child(
            "print('✔ Test run with 1 test in 1 suite passed after 0.001 seconds.');"
            "print('◇ Test incomplete() started.')"
        )
        self.assertEqual(status, 1)

    def test_failed_child_status_wins_over_a_summary(self):
        status, output = self.run_child(
            "import sys; print('✔ Test run with 1 test in 1 suite passed after 0.001 seconds.');"
            "sys.exit(7)"
        )
        self.assertEqual(status, 7)
        self.assertIn("SwiftPM child return code: 7", output)

    def test_child_signal_status_is_reported_and_propagated(self):
        status, output = self.run_child("import os, signal; os.kill(os.getpid(), signal.SIGTERM)")
        self.assertEqual(status, 143)
        self.assertIn("SwiftPM child return code: -15", output)

    def test_empty_invocation_is_rejected(self):
        self.assertEqual(RUNNER.main([]), 2)


if __name__ == "__main__":
    unittest.main()
