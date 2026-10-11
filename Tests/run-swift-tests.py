#!/usr/bin/env python3
"""Require a successful, nonempty Swift Testing completion summary."""

import re
import subprocess
import sys


def main():
    command = sys.argv[1:]
    if command[:1] == ["--"]:
        command = command[1:]
    if not command:
        print("Usage: run-swift-tests.py -- swift test ...", file=sys.stderr)
        return 2

    completed = False
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
        if re.match(r"✔ Test run with [1-9]\d* tests?\b.*\bpassed\b", line):
            completed = True

    return_code = process.wait()
    if return_code != 0:
        return return_code if return_code > 0 else 128 - return_code
    if not completed:
        print("Swift Testing did not report a successful, nonempty completion.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
