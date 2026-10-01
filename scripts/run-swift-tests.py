#!/usr/bin/env python3
"""Require Swift Testing completion as well as the SwiftPM process exit status."""

import re
import subprocess
import sys


COMPLETION = re.compile(
    rb"^\xe2\x9c\x94 Test run with [1-9][0-9]* tests? in [1-9][0-9]* suites? "
    rb"passed after [0-9]+(?:\.[0-9]+)? seconds\.\s*$"
)


def run_test_command(command, output):
    last_line = b""
    with subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT) as child:
        for line in child.stdout:
            output.write(line)
            output.flush()
            if line.strip():
                last_line = line
        return_code = child.wait()

    output.write(f"\nSwiftPM child return code: {return_code}\n".encode())
    if return_code != 0:
        output.flush()
        return return_code if return_code > 0 else 128 - return_code
    if not COMPLETION.fullmatch(last_line):
        output.write(b"error: Swift Testing final completion summary is missing.\n")
        output.flush()
        return 1
    output.flush()
    return 0


def main(arguments):
    if arguments[:1] == ["--"]:
        arguments = arguments[1:]
    if not arguments:
        print("Usage: run-swift-tests.py -- swift test <options>", file=sys.stderr)
        return 2
    return run_test_command(arguments, sys.stdout.buffer)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
