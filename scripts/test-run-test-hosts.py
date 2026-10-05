#!/usr/bin/env python3
"""Check host selection, ordering, and failure propagation without running Swift."""

import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location(
    "run_test_hosts", Path(__file__).with_name("run-test-hosts.py")
)
RUNNER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUNNER)


class TestHostPlanTests(unittest.TestCase):
    def test_host_selection_preserves_flags_and_order(self):
        command = ["swift", "test", "-Xswiftc", "-F", "-Xswiftc", "/path with spaces", "--no-parallel"]
        commands = RUNNER.test_commands(command)
        filters = [
            "^CodexGUITests.WindowLayoutTests",
            "TaskWorkspaceWindowLayoutTests",
            "DesktopLayoutTests",
            "closedWindowDetachesItsStorePublicationObserver",
            "shownWindowHoverUsesSettledHeaderGeometryAfterRepositioning",
            "terminalCopyHoverShowsTooltipAndDismissesWithoutTakingFocus",
            "taskTitleScrollsOnceAndHoverCardUsesMetadataForItsOwnRow",
            "railJumpsBookmarksAndClearsOnChatSwitch",
            "searchSheetKeepsConversationChangesAndDismissesItsPreviousStoreOnRebinding",
            "MessageSearchSheetLifecycleTests",
            "inlineImagesOpenInANativePanelAndReuseOrDetachDismissesIt",
        ]
        self.assertEqual(commands[1:], [command + ["--filter", value] for value in filters])
        self.assertEqual(commands[0], command + ["--skip", "|".join(["WindowLayoutTests", *filters[2:]])])
        self.assertEqual(command[-1], "--no-parallel")

    def test_all_hosts_use_completion_checker(self):
        with patch.object(RUNNER.subprocess, "call", return_value=0) as call:
            self.assertEqual(RUNNER.main(["--", "swift", "test", "--no-parallel"]), 0)
        self.assertEqual(call.call_count, 12)
        for invocation in call.call_args_list:
            self.assertEqual(Path(invocation.args[0][1]).name, "run-swift-tests.py")
            self.assertEqual(invocation.args[0][2:5], ["--", "swift", "test"])

    def test_failed_host_stops_subsequent_hosts(self):
        with patch.object(RUNNER.subprocess, "call", side_effect=[0, 7]) as call:
            self.assertEqual(RUNNER.main(["swift", "test"]), 7)
        self.assertEqual(call.call_count, 2)

    def test_empty_command_is_rejected(self):
        self.assertEqual(RUNNER.main([]), 2)


if __name__ == "__main__":
    unittest.main()
