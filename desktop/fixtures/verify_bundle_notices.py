"""Check the shared license notices in an installed diagnostic bundle."""

import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FRONTEND_PACKAGES = ROOT / "desktop" / "frontend" / "node_modules"
NOTICES = {
    "LICENSE.md": ROOT / "LICENSE.md",
    "Tauri-MIT.txt": FRONTEND_PACKAGES / "@tauri-apps" / "api" / "LICENSE-MIT",
    "Svelte-MIT.md": FRONTEND_PACKAGES / "svelte" / "LICENSE.md",
    "frontend-licenses.md": FRONTEND_PACKAGES.parent / "dist" / "frontend-licenses.md",
}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("notices", type=Path)
    args = parser.parse_args()
    for name, source in NOTICES.items():
        installed = args.notices / name
        if not installed.is_file() or installed.read_bytes() != source.read_bytes():
            raise SystemExit(f"Missing or changed bundle notice: {installed}")
    print(f"Verified {len(NOTICES)} shared bundle notices")


if __name__ == "__main__":
    main()
