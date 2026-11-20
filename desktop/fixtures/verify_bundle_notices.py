"""Check the shared license notices in an installed diagnostic bundle."""

import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FRONTEND_PACKAGES = ROOT / "desktop" / "frontend" / "node_modules"
NOTICES = {
    "LICENSE.md": ROOT / "LICENSE.md",
    "Tauri-MIT.txt": FRONTEND_PACKAGES / "@tauri-apps" / "api" / "LICENSE-MIT",
    "Svelte-MIT.md": FRONTEND_PACKAGES / "svelte" / "LICENSE.md",
    "Inter-OFL.txt": FRONTEND_PACKAGES.parent / "src" / "assets" / "Inter-LICENSE.txt",
    "GStreamer-Rust-MIT.txt": ROOT / "desktop" / "src-tauri" / "notices" / "GStreamer-Rust-MIT.txt",
    "Symphonia-MPL-2.0.txt": ROOT / "desktop" / "src-tauri" / "notices" / "Symphonia-MPL-2.0.txt",
    "Whisper-MIT.txt": ROOT / "desktop" / "src-tauri" / "notices" / "Whisper-MIT.txt",
    "Whisper-Rust-Unlicense.txt": ROOT / "desktop" / "src-tauri" / "notices" / "Whisper-Rust-Unlicense.txt",
    "QRCode-Rust-MIT.txt": ROOT / "desktop" / "src-tauri" / "notices" / "QRCode-Rust-MIT.txt",
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
    if "pdfjs-dist" not in (args.notices / "frontend-licenses.md").read_text(encoding="utf-8"):
        raise SystemExit("The installed frontend notices omit PDF.js")
    print(f"Verified {len(NOTICES)} shared bundle notices")


if __name__ == "__main__":
    main()
