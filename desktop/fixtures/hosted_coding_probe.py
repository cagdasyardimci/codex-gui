"""Run the installed probe with subscription sign-in on an opted-in hosted runner."""

import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

VERSION = "0.163.0"
AUTH_URL = "https://auth.openai.com/codex/device"
DEVICE_CODE = re.compile(r"\b[A-Z0-9]{4,6}-[A-Z0-9]{4,8}\b")
ANSI_ESCAPE = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")


def cli_in(distribution: Path) -> Path:
    name = "codex.exe" if os.name == "nt" else "codex"
    files = [path for path in distribution.rglob(name) if path.is_file() and "vendor" in path.parts]
    if len(files) != 1:
        raise RuntimeError("Expected one pinned native Codex executable")
    return files[0]


def probe_env(stage: Path) -> dict[str, str]:
    environment = {
        **os.environ,
        "CODEX_HOME": str(stage / "profile"),
        "CODEX_EXECUTABLE": str(cli_in(stage / "cli")),
    }
    for name in ("OPENAI_API_KEY", "CODEX_API_KEY", "CODEX_ACCESS_TOKEN"):
        environment.pop(name, None)
    return environment


def seal_code(stage: Path, code: str) -> None:
    key = stage / "handoff-public.pem"
    key.write_text(os.environ["CODEX_GUI_DEVICE_PUBLIC_KEY"], encoding="ascii")
    openssl = shutil.which("openssl")
    if openssl is None and os.name == "nt":
        openssl = str(Path(os.environ["ProgramFiles"]) / "Git/usr/bin/openssl.exe")
    if openssl is None:
        raise RuntimeError("OpenSSL is required to protect the device handoff")
    subprocess.run(
        [openssl, "pkeyutl", "-encrypt", "-pubin", "-inkey", str(key),
         "-pkeyopt", "rsa_padding_mode:oaep", "-pkeyopt", "rsa_oaep_md:sha256",
         "-out", str(stage / "device.enc")],
        input=code.encode("ascii"),
        timeout=15,
        check=True,
    )


def prepare(stage: Path) -> None:
    profile = stage / "profile"
    profile.mkdir()
    environment = probe_env(stage)
    cli = environment["CODEX_EXECUTABLE"]

    if os.name == "nt":
        checkout = stage / "sandbox checkout"
        checkout.mkdir()
        probe = Path("desktop/target/debug/examples/windows_sandbox.exe").resolve(strict=True)
        subprocess.run([probe, cli, checkout], env=environment, check=True, timeout=210)

    output = stage / "private-login.log"
    with output.open("xb") as login_output:
        login = subprocess.Popen(
            [cli, "login", "--device-auth"],
            stdin=subprocess.DEVNULL,
            stdout=login_output,
            stderr=subprocess.STDOUT,
            env=environment,
            **({"creationflags": subprocess.CREATE_NEW_PROCESS_GROUP} if os.name == "nt"
               else {"start_new_session": True}),
        )

    deadline = time.monotonic() + 45
    while time.monotonic() < deadline:
        content = ANSI_ESCAPE.sub("", output.read_text(encoding="utf-8", errors="replace"))
        code = next((line.strip() for line in content.splitlines()
                     if DEVICE_CODE.fullmatch(line.strip())), None)
        if AUTH_URL in content and code:
            seal_code(stage, code)
            print("Encrypted the one-time ChatGPT device code")
            return
        if login.poll() is not None:
            raise RuntimeError("Codex exited before issuing a device code")
        time.sleep(0.5)
    login.terminate()
    raise RuntimeError("Codex did not issue a device code")


def await_login(environment: dict[str, str]) -> None:
    cli = environment["CODEX_EXECUTABLE"]
    deadline = time.monotonic() + 12 * 60
    while time.monotonic() < deadline:
        process = subprocess.run(
            [cli, "login", "status"], env=environment, capture_output=True, timeout=15,
        )
        if process.returncode == 0 and b"ChatGPT" in process.stdout + process.stderr:
            return
        time.sleep(3)
    raise RuntimeError("The hosted ChatGPT device authorization did not complete")


def launch_windows(report: Path, environment: dict[str, str]) -> None:
    programs = Path(environment["APPDATA"]) / "Microsoft/Windows/Start Menu/Programs"
    shortcuts = list(programs.rglob("Codex GUI Beta.lnk"))
    if len(shortcuts) != 1:
        raise RuntimeError("Expected one installed Codex GUI Beta Start menu shortcut")
    os.environ.update(environment)
    os.startfile(str(shortcuts[0]), arguments=subprocess.list2cmdline(["--verify-coding-turn", str(report)]))


def launch_ubuntu(report: Path, environment: dict[str, str], stage: Path) -> None:
    applications = Path("/usr/share/applications")
    installed = None
    for desktop in applications.glob("*.desktop"):
        lines = desktop.read_text(encoding="utf-8", errors="replace").splitlines()
        if any(line.startswith("Exec=") and "codex-gui-desktop" in line for line in lines):
            installed = (desktop.name, lines)
            break
    if installed is None:
        raise RuntimeError("The installed app launcher entry was not found")
    name, lines = installed
    user_data = stage / "launcher"
    user_applications = user_data / "applications"
    user_applications.mkdir(parents=True)
    executable = shutil.which("codex-gui-desktop")
    if executable is None:
        raise RuntimeError("The installed Debian executable was not found")
    quoted_report = '"' + str(report).replace("\\", "\\\\").replace('"', '\\"') + '"'
    content = "\n".join(
        f"Exec={executable} --verify-coding-turn {quoted_report}" if line.startswith("Exec=") else line
        for line in lines
    )
    (user_applications / name).write_text(content + "\n", encoding="utf-8")
    subprocess.run(
        ["gtk-launch", name.removesuffix(".desktop")],
        env={**environment, "XDG_DATA_HOME": str(user_data)},
        check=True, timeout=30,
    )


def finish(stage: Path) -> None:
    environment = probe_env(stage)
    try:
        await_login(environment)
        report = stage / "coding-turn.txt"
        if os.name == "nt":
            launch_windows(report, environment)
        else:
            launch_ubuntu(report, environment, stage)
        deadline = time.monotonic() + 230
        while time.monotonic() < deadline:
            if report.is_file():
                lines = report.read_text(encoding="utf-8").splitlines()
                if len(lines) == 3 and lines[0] == "Default-policy coding probe completed":
                    if lines[2] != f"Codex CLI version: {VERSION}":
                        raise RuntimeError("The installed app used an unexpected Codex CLI release")
                    print("Hosted default-policy coding probe completed with ChatGPT sign-in")
                    return
                if lines and lines[0].startswith("Coding probe failed:"):
                    raise RuntimeError("The installed app reported a coding probe failure")
            time.sleep(1)
        raise RuntimeError("The launcher did not produce a completed coding probe report")
    finally:
        subprocess.run(
            [environment["CODEX_EXECUTABLE"], "logout"],
            env=environment, capture_output=True, timeout=15,
        )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phase", choices=["prepare", "finish"])
    args = parser.parse_args()
    if os.environ.get("GITHUB_ACTIONS") != "true" or sys.platform not in ("win32", "linux"):
        raise SystemExit("Use a disposable hosted Windows or Ubuntu runner")
    stage = Path(os.environ["RUNNER_TEMP"]).resolve() / "codex-gui-hosted-turn"
    if args.phase == "prepare":
        prepare(stage)
    else:
        finish(stage)


if __name__ == "__main__":
    main()
