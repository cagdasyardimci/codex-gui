#!/usr/bin/env python3
"""Run Swift Testing, optionally selecting an exact manifest of functions."""

import argparse
from pathlib import Path
import re
import subprocess
import sys


def main():
    arguments = sys.argv[1:]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--selection-file", type=Path)
    if "--" in arguments:
        separator = arguments.index("--")
        options = parser.parse_args(arguments[:separator])
        command = arguments[separator + 1 :]
    else:
        options = parser.parse_args([])
        command = arguments
    if not command:
        parser.error("expected -- followed by a test command")

    expected_count = None
    if options.selection_file is not None:
        try:
            functions = [
                line.strip()
                for line in options.selection_file.read_text().splitlines()
                if line.strip() and not line.lstrip().startswith("#")
            ]
        except OSError as error:
            parser.error(str(error))
        if not functions or len(set(functions)) != len(functions):
            parser.error("selection must contain nonempty, unique function IDs")
        if any(
            re.fullmatch(r"CodexGUITests\.[^/\s]+/[^/\s]+\([^/\s]*\)", function) is None
            for function in functions
        ):
            parser.error("selection must contain fully qualified Swift Testing function IDs")
        if any(argument == "--filter" or argument.startswith("--filter=") for argument in command):
            parser.error("a selection file cannot be combined with --filter")
        expression = "|".join("^" + re.escape(function) + "($|/)" for function in functions)
        command.extend(["--filter", expression])
        expected_count = len(functions)

    completed_count = None
    process = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        errors="replace",
    )
    for line in process.stdout:
        sys.stdout.write(line)
        sys.stdout.flush()
        summary = re.match(r"✔ Test run with ([1-9]\d*) tests?\b.*\bpassed\b", line)
        if summary:
            completed_count = int(summary.group(1))

    return_code = process.wait()
    if return_code != 0:
        return return_code if return_code > 0 else 128 - return_code
    if completed_count is None:
        print("Swift Testing did not report a successful, nonempty completion.", file=sys.stderr)
        return 1
    if expected_count is not None and completed_count != expected_count:
        print(
            f"Selection expected {expected_count} test functions, but {completed_count} passed. "
            "Check the selection for renamed or missing functions.",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
