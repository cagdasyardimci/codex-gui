# Tauri diagnostic packages

Build the diagnostic beta on each target operating system using the [desktop prerequisites](validation.md#tauri-diagnostic-shell). The build embeds the frontend and the fixture. The [bundle configuration](../desktop/src-tauri/tauri.conf.json) supplies the shared license notices to each installer.

```sh
pnpm --dir desktop/frontend install --frozen-lockfile
pnpm --dir desktop/frontend tauri build --debug --ci -- --locked
```

On macOS set `APPLE_SIGNING_IDENTITY=-` for a local ad hoc signature. Open the resulting disk image and copy the beta application to the desired Applications folder before launching it from Finder. On Windows run the per-user NSIS installer, then use the Start menu entry. The installer can download WebView2 when it is missing, which requires network access. On Ubuntu install the Debian package with `sudo apt install ./package.deb` and launch Codex GUI Beta from the application menu.

## Support and ownership

The initial beta matrix covers macOS 14 or later on Apple Silicon, Windows 11 x64, and Ubuntu 24.04 LTS x64. Intel Macs are outside the initial beta matrix. The repository maintainer owns any support expansion and the platform signing credentials. Release distribution uses a Developer ID signature and notarization on macOS and a signed installer on Windows.

[Desktop CI](../.github/workflows/desktop-core.yml) builds and verifies the Apple Silicon disk image, the installer on Windows Server 2025, and the Debian package on Ubuntu 24.04. CI artifacts serve packaging and fixture checks. Run installed acceptance on an interactive Apple Silicon Mac, a Windows 11 x64 desktop with a fresh standard-user profile, and an Ubuntu 24.04 graphical session. Use disposable checkouts and isolated Codex profiles for live CLI and provider checks. [Native and live acceptance](validation.md#native-and-live-acceptance)
