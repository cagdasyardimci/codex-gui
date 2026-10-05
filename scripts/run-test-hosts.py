#!/usr/bin/env python3
"""Run the shared and isolated SwiftPM test hosts in their required order."""

from pathlib import Path
import subprocess
import sys


# Each pair supplies a shared-host exclusion and its isolated-host filter.
# WindowLayoutTests excludes both layout suites; their filters intentionally differ.
ISOLATED_HOSTS = (
    ("WindowLayoutTests", "^CodexGUITests.WindowLayoutTests"),
    ("WindowLayoutTests", "TaskWorkspaceWindowLayoutTests"),
    ("DesktopLayoutTests",) * 2,
    ("closedWindowDetachesItsStorePublicationObserver",) * 2,
    ("shownWindowHoverUsesSettledHeaderGeometryAfterRepositioning",) * 2,
    ("terminalCopyHoverShowsTooltipAndDismissesWithoutTakingFocus",) * 2,
    ("taskTitleScrollsOnceAndHoverCardUsesMetadataForItsOwnRow",) * 2,
    ("railJumpsBookmarksAndClearsOnChatSwitch",) * 2,
    ("searchSheetKeepsConversationChangesAndDismissesItsPreviousStoreOnRebinding",) * 2,
    ("MessageSearchSheetLifecycleTests",) * 2,
    ("inlineImagesOpenInANativePanelAndReuseOrDetachDismissesIt",) * 2,
)


def test_commands(command):
    exclusions = "|".join(dict.fromkeys(exclusion for exclusion, _ in ISOLATED_HOSTS))
    return [command + ["--skip", exclusions]] + [
        command + ["--filter", test_filter] for _, test_filter in ISOLATED_HOSTS
    ]


def main(arguments):
    if arguments[:1] == ["--"]:
        arguments = arguments[1:]
    if not arguments:
        print("Usage: run-test-hosts.py -- swift test <options>", file=sys.stderr)
        return 2
    runner = str(Path(__file__).with_name("run-swift-tests.py"))
    for command in test_commands(arguments):
        status = subprocess.call([sys.executable, runner, "--", *command])
        if status:
            return status if status > 0 else 128 - status
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
