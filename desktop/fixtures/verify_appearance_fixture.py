"""Exercise native menu actions and appearance and layout restoration in an installed bundle."""

import argparse
import json
import os
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory

from verify_coding_probe import fixture_executable


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    arguments = parser.parse_args()
    app = arguments.app.resolve(strict=True)
    with TemporaryDirectory(prefix="codex-gui-appearance-") as scratch:
        root = Path(scratch).resolve()
        data, profile, checkout = (root / name for name in ("desktop", "isolated Codex profile", "Appearance fixture"))
        for folder in (data, profile, checkout):
            folder.mkdir()
        account = data / "fixture-account.json"
        account.write_text('{"profile": "first"}', encoding="utf-8")
        environment = {
            **os.environ, "CODEX_HOME": str(profile), "CODEX_EXECUTABLE": str(fixture_executable(root)),
            "CODEX_GUI_QA_SCENARIO": "desktop-settings", "CODEX_GUI_QA_SETTINGS": str(account),
            "PYTHONIOENCODING": "utf-8",
        }
        edited = run(app, "appearance", data, checkout, environment)
        before = json.loads((data / "presentation.json").read_text(encoding="utf-8"))
        restored = run(app, "appearance-restore", data, checkout, environment)
        assert before["appearance"]["mode"] == "dark"
        assert before["appearance"]["light"]["sizes"]["content"] == 19
        assert before["appearance"]["light"]["fonts"]["code"] == "Codex Fixture Uninstalled Typeface"
        assert before["appearance"]["dark"]["fonts"] == {"ui": None, "content": None, "code": None}
        assert before["zoomPercent"] == edited["zoomed"]["zoom"] == restored["zoom"] == 110
        assert abs(before["layout"]["width"] - restored["width"]) <= 2
        assert abs(before["layout"]["height"] - restored["height"]) <= 2
        copied = (data / "Copied Theme.json").read_bytes()
        assert (data / "Theme.json").read_bytes() == copied
        assert json.loads(copied) == {
            "background": 0xFFFFFF, "foreground": 0x223344, "accent": 0x0169CC, "contrast": 45,
            "diffAdded": 0x00A240, "diffRemoved": 0xE02E2A, "skill": 0x751ED9,
            "colorizeMessages": True, "opaqueWindows": False, "hasCustomFonts": True,
            "uiFontFamily": edited["font"],
            "codeFontFamily": "Codex Fixture Uninstalled Typeface",
        }
        print("Verified installed native menus, fullscreen, zoom, normal layout, and captured clipboard and export bytes")
        print("Verified Settings search, resolved typography, and per-appearance preferences across restart")


def run(app, phase, data, checkout, environment):
    completed = subprocess.run(
        [app, f"--verify-{phase}", data, checkout], env=environment,
        capture_output=True, encoding="utf-8", errors="replace", timeout=75,
    )
    print(completed.stdout, end="")
    prefix = "Verified installed desktop appearance and layout: "
    lines = [line.removeprefix(prefix) for line in completed.stdout.splitlines() if line.startswith(prefix)]
    if completed.returncode or len(lines) != 1:
        raise SystemExit(completed.stderr or f"The installed {phase} fixture did not finish")
    return json.loads(lines[0])


if __name__ == "__main__":
    main()
