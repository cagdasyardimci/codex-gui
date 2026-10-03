#!/usr/bin/env python3
"""Render offline AppKit design comparisons in a focused Swift Testing host."""

import argparse
import os
from pathlib import Path
import shlex
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--skip-build", action="store_true")
    arguments = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    # Resolve the actual Makefile flags instead of maintaining a second toolchain recipe.
    flags = subprocess.run(
        ["make", "--no-print-directory", "-f", "Makefile", "-f", "-",
         "design-preview-test-flags"],
        input="design-preview-test-flags:\n\t@printf '%s\\n' '$(TEST_FLAGS)'\n",
        text=True, stdout=subprocess.PIPE, check=True, cwd=root,
    ).stdout.strip()
    command = [
        sys.executable, "scripts/run-swift-tests.py", "--", "swift", "test",
        *shlex.split(flags), "--no-parallel", "--filter",
        "GitReviewDesignPreviewTests|FileIconDesignPreviewTests",
    ]
    if arguments.skip_build:
        command.append("--skip-build")
    environment = os.environ.copy()
    environment["CODEX_DESIGN_PREVIEW_DIR"] = str(arguments.output.resolve())
    return subprocess.run(command, cwd=root, env=environment).returncode


if __name__ == "__main__":
    sys.exit(main())
