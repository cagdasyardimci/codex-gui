"""Launch the frontend and require its WebView to confirm fixture delivery."""

import argparse
from pathlib import Path
import subprocess
import sys


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--media", action="store_true")
    args = parser.parse_args()
    argument, confirmation = (
        ("--verify-media", "WebView media evidence:")
        if args.media else ("--verify-fixture", "ordered fixture deltas and exact WebView text")
    )

    result = subprocess.run(
        [str(args.app.resolve(strict=True)), argument],
        capture_output=True,
        encoding="utf-8",
        errors="replace",
        timeout=60,
    )
    print(result.stdout, end="")
    print(result.stderr, end="", file=sys.stderr)
    if result.returncode != 0 or confirmation not in result.stdout:
        raise SystemExit("The WebView verification failed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
