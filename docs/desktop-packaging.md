# Tauri diagnostic packages

Build the diagnostic beta on each target operating system using the [desktop prerequisites](validation.md#tauri-diagnostic-shell). The build embeds the frontend and the fixture. The [bundle configuration](../desktop/src-tauri/tauri.conf.json) supplies the shared license notices to each installer.

```sh
pnpm --dir desktop/frontend install --frozen-lockfile
pnpm --dir desktop/frontend tauri build --debug --ci -- --locked
```

On macOS set `APPLE_SIGNING_IDENTITY=-` for a local ad hoc signature. Open the resulting disk image and copy the beta application to the desired Applications folder before launching it from Finder. On Windows run the per-user NSIS installer, then use the Start menu entry. The installer can download WebView2 when it is missing, which requires network access. On Ubuntu the Debian package pulls in the GStreamer WebRTC and ICE plugins. Install it with `sudo apt install ./package.deb` and launch Codex GUI Beta from the application menu.

## Support and ownership

The initial beta matrix covers macOS 14 or later on Apple Silicon, Windows 11 x64, and Ubuntu 24.04 LTS x64. Intel Macs are outside the initial beta matrix. The repository maintainer owns any support expansion and the platform signing credentials. Release distribution uses a Developer ID signature and notarization on macOS and a signed installer on Windows.

[Desktop CI](../.github/workflows/desktop-core.yml) builds and verifies the Apple Silicon disk image, the installer on Windows Server 2025, and the Debian package on Ubuntu 24.04. CI artifacts serve packaging and fixture checks. Run migration feasibility on an interactive Apple Silicon Mac, a hosted Windows Server 2025 x64 runner with a fresh standard-user profile, and an Ubuntu 24.04 graphical session. Run Windows desktop release acceptance on Windows 11 x64. Use disposable checkouts and isolated Codex profiles for live CLI and provider checks. [Native and live acceptance](validation.md#native-and-live-acceptance)

## Mac identity and cutover

During beta, launch Codex GUI Beta alongside the Swift reference. Launch Services identifies the beta by `local.codexgui.tauri.beta` and the Swift app by `local.codexgui.appkit`. Use the separate bundle names and inspect the identity of each running process when verifying coexistence.

The stable Mac app will use the display name Codex GUI and retain `local.codexgui.tauri.beta`. Keep beta data in `~/Library/Application Support/local.codexgui.tauri.beta` so the stable build can open it in place. The release maintainer configures `APPLE_SIGNING_IDENTITY` with the exact Developer ID Application certificate on the release Apple Developer team and keeps that signing identity consistent for upgrades. [Apple code-signing requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)

Request notification authorization and microphone access for the Tauri app when those features need them. The WebView requests microphone access for the active app origin. Users who selected protected folders or granted additional macOS access to AppKit may need to select folders or grant that access to Tauri again. Recheck those permissions after switching from ad hoc beta signing to the release signature. Keep host privacy permissions out of imported data. [Notification authorization](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications) · [Microphone purpose string](https://developer.apple.com/documentation/bundleresources/information-property-list/nsmicrophoneusagedescription)

At stable cutover, quit the beta and replace its bundle in Applications with Codex GUI from the release disk image. Quit AppKit before importing its local data. After Tauri validates the import and checkout handoff, remove the AppKit bundle from Applications. Keep the original import data and the final Swift source tag for historical reference and Tauri recovery. [AppKit maintenance through cutover](agent-workflow.md#appkit-maintenance-through-cutover)


## Windows sandbox feasibility

The [Windows sandbox probe](../desktop/core/examples/windows_sandbox.rs) runs Codex under a fresh standard-user profile through the [desktop CI harness](../desktop/fixtures/verify_windows_sandbox.ps1). On a disposable Windows runner, the harness stages the pinned CLI and creates an account in the local Users group. The probe requests Codex’s unelevated setup and verifies that readiness persists after reconnecting. This check exercises provisioning before the installed coding-turn check.

## Installed coding probe

Use a fresh OS profile and an existing empty directory as `CODEX_HOME`. Establish Codex sign-in in that profile, then launch the installed diagnostic shell with `--verify-coding-turn <absolute-new-report-path>` and the same profile environment. The app discovers Codex and Git, creates a disposable checkout, and starts a turn using the backend's default policy. The diagnostic can grant one command approval for its own marker read in the captured checkout. A passing report names the selected CLI and version after a successful command emits the checkout marker and the matching turn completes. [Codex authentication](https://developers.openai.com/codex/auth)

The [package workflow](../.github/workflows/desktop-core.yml) runs the [coding fixture](../desktop/fixtures/verify_coding_probe.py) from each packaged application. Use a signed-in Codex process for live acceptance.

For a hosted Windows or Ubuntu live run, the repository maintainer can set the Actions variable `CODEX_GUI_DEVICE_PUBLIC_KEY` to a temporary RSA public key and push the migration branch. Set `CODEX_GUI_DEVICE_TARGET` to `Windows` or `Linux` to enable only that runner. The [hosted probe](../desktop/fixtures/hosted_coding_probe.py) publishes only encrypted one-time codes. Decrypt them locally, authorize each disposable Codex profile through ChatGPT, and clear the temporary Actions variables when the test ends.
