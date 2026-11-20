"""Verify stable Mac packaging, profile selection and a native beta upgrade."""

import argparse
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
from tempfile import TemporaryDirectory

from verify_appearance_fixture import run
from verify_bundle_notices import NOTICES
from verify_coding_probe import fixture_executable


BUNDLE = "local.codexgui.tauri.beta"


def executable(app):
    contents = app / "Contents"
    info = plistlib.loads((contents / "Info.plist").read_bytes())
    return contents / "MacOS" / info["CFBundleExecutable"]


def inspect(app, stable, developer_id):
    contents = app / "Contents"
    info = plistlib.loads((contents / "Info.plist").read_bytes())
    assert info["CFBundleIdentifier"] == BUNDLE
    assert info["CFBundleName"] == ("Codex GUI" if stable else "Codex GUI Beta"), info["CFBundleName"]
    assert info["LSMinimumSystemVersion"].startswith("14.")
    assert info["NSMicrophoneUsageDescription"].strip()
    subprocess.run(["codesign", "--verify", "--strict", "--deep", app], check=True)
    if developer_id:
        details = subprocess.run(["codesign", "--display", "--verbose=4", app], check=True,
                                 capture_output=True, text=True, timeout=20).stderr
        assert "Authority=Developer ID Application:" in details and "runtime" in details and "Timestamp=" in details
        subprocess.run(["xcrun", "stapler", "validate", app], check=True, timeout=30)
        subprocess.run(["spctl", "--assess", "--type", "execute", app], check=True, timeout=30)
    entitlements = subprocess.check_output(["codesign", "--display", "--entitlements", "-", "--xml", app], timeout=20)
    assert plistlib.loads(entitlements)["com.apple.security.device.audio-input"] is True
    for name, origin in NOTICES.items():
        assert (contents / "Resources" / "notices" / name).read_bytes() == origin.read_bytes(), name
    data = json.loads(subprocess.check_output([executable(app), "--describe-package-profile"], timeout=30))
    assert data["bundleId"] == BUNDLE and Path(data["dataDirectory"]).name == BUNDLE, data
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("beta", type=Path)
    parser.add_argument("stable_dmg", type=Path)
    parser.add_argument("--require-notarization", action="store_true")
    args = parser.parse_args()
    beta, disk = (path.resolve(strict=True) for path in (args.beta, args.stable_dmg))
    subprocess.run(["hdiutil", "verify", disk], check=True, timeout=60)
    if args.require_notarization:
        subprocess.run(["xcrun", "stapler", "validate", disk], check=True, timeout=30)
        subprocess.run(["spctl", "--assess", "--type", "open", "--context", "context:primary-signature", disk],
                       check=True, timeout=30)
    with TemporaryDirectory(prefix="codex-gui-release-mount-") as mount:
        subprocess.run(["hdiutil", "attach", "-nobrowse", "-readonly", "-mountpoint", mount, disk],
                       check=True, timeout=60)
        try:
            qualify(beta, Path(mount) / "Codex GUI.app", args.require_notarization)
        finally:
            subprocess.run(["hdiutil", "detach", mount], check=True, timeout=30)


def qualify(beta, stable, require_notarization):
    assert inspect(beta, False, False) == inspect(stable, True, require_notarization)
    with TemporaryDirectory(prefix="codex-gui-mac-upgrade-") as temporary:
        root = Path(temporary).resolve()
        applications, project, profile, codex_home, fresh = (root / name for name in (
            "Applications", "Project", "Beta profile", "Disposable Codex home", "Clean profile"))
        for folder in (applications, project, profile, codex_home, fresh):
            folder.mkdir()
        account = root / "account-fixture.json"
        account.write_text('{"profile": "first"}', encoding="utf-8")
        environment = {
            **os.environ, "CODEX_HOME": str(codex_home), "CODEX_EXECUTABLE": str(fixture_executable(root)),
            "CODEX_GUI_QA_SCENARIO": "desktop-settings", "CODEX_GUI_QA_SETTINGS": str(account),
            "PYTHONIOENCODING": "utf-8",
        }
        installed_beta = applications / beta.name
        shutil.copytree(beta, installed_beta, symlinks=True)
        run(executable(installed_beta), "appearance", profile, project, environment)
        installed_beta.rename(root / beta.name)
        installed_stable = applications / stable.name
        shutil.copytree(stable, installed_stable, symlinks=True)
        run(executable(installed_stable), "appearance", fresh, project, environment)
        upgraded = run(executable(installed_stable), "appearance-restore", profile, project, environment)
        installed_stable.rename(root / stable.name)
        shutil.copytree(stable, installed_stable, symlinks=True)
        repaired = run(executable(installed_stable), "appearance-restore", profile, project, environment)
        assert upgraded["zoom"] == repaired["zoom"] == 110
    print("Verified stable bundle identity, clean installation, beta profile upgrade and reinstallation")


if __name__ == "__main__":
    main()
