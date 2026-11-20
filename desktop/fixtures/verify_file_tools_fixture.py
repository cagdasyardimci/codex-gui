"""Verify per-chat file tools and settle hidden buffers through installed Close and Quit."""

import argparse
from base64 import b64decode
import json
import os
from pathlib import Path
import struct
import subprocess
from tempfile import TemporaryDirectory
from urllib.parse import quote

from verify_coding_probe import fixture_executable

PIXEL = b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGMQSTnxHwAEEAJAKtk0QwAAAABJRU5ErkJggg==")
GUIDE = "Guide café #.md"


def colored_pdf():
    objects = [b"<< /Type /Catalog /Pages 2 0 R >>", b"<< /Type /Pages /Kids [3 0 R 5 0 R] /Count 2 >>"]
    for stream in (b"1 0 0 rg 0 0 120 80 re f", b"0 0 1 rg 0 0 120 80 re f"):
        page = len(objects) + 1
        objects.append(f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 120 80] /Resources << >> /Contents {page + 1} 0 R >>".encode())
        objects.append(f"<< /Length {len(stream)} >>\nstream\n".encode() + stream + b"\nendstream")
    output = b"%PDF-1.4\n"
    offsets = []
    for index, body in enumerate(objects, 1):
        offsets.append(len(output))
        output += f"{index} 0 obj\n".encode() + body + b"\nendobj\n"
    index = len(output)
    output += f"xref\n0 {len(objects) + 1}\n0000000000 65535 f \n".encode()
    output += b"".join(f"{offset:010d} 00000 n \n".encode() for offset in offsets)
    return output + f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\nstartxref\n{index}\n%%EOF\n".encode()


def bitmap():
    pixels = (b"\x00\xff\x00" * 2 + b"\x00\x00") * 2
    header = b"BM" + struct.pack("<IHHI", 54 + len(pixels), 0, 0, 54)
    info = struct.pack("<IiiHHIIiiII", 40, 2, 2, 1, 24, 0, len(pixels), 0, 0, 0, 0)
    return header + info + pixels


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    args = parser.parse_args()
    with TemporaryDirectory(prefix="codex-gui-file-tools-") as scratch:
        root = Path(scratch).resolve()
        checkout = root / "Files checkout"
        profile = root / "codex home"
        data = root / "desktop"
        (checkout / "folder").mkdir(parents=True)
        profile.mkdir()
        for name, contents in {
            "folder/alpha.txt": b"Alpha\n",
            "beta.txt": b"Original beta\r\n",
            "adopt.txt": b"Original adoption\n",
            "conflict.txt": b"Original conflict\n",
            "search.txt": ("Heading\r\n" + "".join(f"Café marker {line:02d}\r\n" for line in range(1, 30))).encode("utf-8"),
            "filtered.log": "Café marker from an excluded log\n".encode("utf-8"),
            "replace.txt": b"Unique replacement target\n",
            GUIDE: b"# Local guide\r\n\r\nAlpha first.\r\nALPHA second.\r\n",
            "pages.pdf": colored_pdf(),
            "picture.bmp": bitmap(),
            "graphic.svg": b'<svg xmlns="http://www.w3.org/2000/svg" width="40" height="20">'
                           b'<script>window.invalidSvgContent=true</script><rect width="40" height="20" fill="green"/></svg>',
            "unsupported.heic": b"\x00\x00\x00\x18ftypheic\x00\x00\x00\x00mif1heic",
            "folder/rich.md": b"---\ntitle: Local reference\ntags:\n  - alpha\n  - beta\n---\n# Nested document\n\n"
                              b"![Nested pixel](../pixel.png)\n\n![Remote pixel](https://example.invalid/not-loaded.png)\n\n"
                              b"[Recorded link](https://example.invalid/guide)\n\n"
                              b"```mermaid\nflowchart LR\n  A[Local] --> B[Export]\n```\n",
            "pixel.png": PIXEL,
            "pixel2.png": PIXEL,
        }.items():
            (checkout / name).write_bytes(contents)
        git = ["git", "-C", str(checkout), "-c", "user.name=File Fixture", "-c", "user.email=fixtures@example.invalid",
               "-c", "core.autocrlf=false", "-c", "commit.gpgsign=false"]
        subprocess.run([*git, "init", "-q"], check=True, capture_output=True)
        subprocess.run([*git, "add", "--", GUIDE], check=True, capture_output=True)
        subprocess.run([*git, "commit", "-qm", "Recorded guide"], check=True, capture_output=True)
        subprocess.run([*git, "remote", "add", "origin", "git@github.com:example/files.git"], check=True, capture_output=True)
        head = subprocess.check_output([*git, "rev-parse", "HEAD"], text=True).strip()
        trace = root / "trace.jsonl"
        result = subprocess.run(
            [args.app.resolve(strict=True), "--verify-file-tools", data, checkout],
            env={**os.environ, "CODEX_HOME": str(profile), "CODEX_EXECUTABLE": str(fixture_executable(root)),
                 "CODEX_GUI_QA_SCENARIO": "desktop-attachments", "CODEX_GUI_QA_TRACE": str(trace),
                 "CODEX_GUI_QA_STATE": str(root / "state.json"), "PYTHONIOENCODING": "utf-8"},
            capture_output=True, encoding="utf-8", errors="replace", timeout=85,
        )
        print(result.stdout, end="")
        if result.returncode or "Verified installed file tools and hidden-tab quit settlement" not in result.stdout:
            raise SystemExit(result.stderr or "The installed file tools fixture did not complete")
        assert (checkout / "beta.txt").read_bytes() == b"The first chat owns this file.\r\n"
        assert (checkout / "adopt.txt").read_bytes() == b"Keep the new chat file.\n"
        assert (checkout / "conflict.txt").read_bytes() == b"An external change\n"
        assert (checkout / "folder" / "alpha.txt").read_bytes() == b"Alpha\n"
        assert (checkout / "replace.txt").read_bytes() == (checkout / "retired-search.txt").read_bytes() == b"Unique replacement target\n"
        saved_guide = "# Saved guide\r\n\r\nPreserve café from the first chat.\r\n".encode("utf-8")
        assert (checkout / GUIDE).read_bytes() == (data / "copied-file").read_bytes() == (data / "exported-file").read_bytes() == saved_guide
        for name in ("picture.bmp", "graphic.svg", "pixel.png"):
            assert (data / f"preview-{name}").read_bytes() == (checkout / name).read_bytes()
        diagram = (data / "preview-Diagram.png").read_bytes()
        assert diagram[:16] == b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR"
        assert all(10 < edge <= 2400 for edge in struct.unpack_from(">II", diagram, 16))
        actions = [json.loads(line) for line in (data / "file-actions.jsonl").read_text(encoding="utf-8").splitlines()]
        assert [action["action"] for action in actions] == ["reveal", "default", "editor", "github", "default"], actions
        assert all(Path(action["target"]).samefile(checkout / GUIDE) for action in actions[:3]), actions
        assert actions[2]["editor"] == "vscode", actions
        assert actions[3]["target"] == f"https://github.com/example/files/blob/{head}/{quote(GUIDE)}", actions
        assert Path(actions[4]["target"]).samefile(checkout / "unsupported.heic"), actions
        assert not list(profile.iterdir())
        records = [json.loads(line) for line in trace.read_text(encoding="utf-8").splitlines()]
        requests = [entry for entry in records if entry["direction"] == "request"]
        starts = [entry for entry in requests if entry["method"] == "turn/start"]
        assert len(starts) == 1 and starts[0]["input"] == [
            {"type": "text", "text": "Start a chat with its existing file tab."},
        ], starts
        assert Path(starts[0]["resolvedCwd"]).samefile(checkout)
        print("Verified exact save, copy and export bytes, captured destinations, and file settlement after close and quit")
        print("Verified original image downloads, expanded preview focus and zoom, and bounded PNG diagram export")


if __name__ == "__main__":
    main()
