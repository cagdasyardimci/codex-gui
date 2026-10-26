# Codex GUI for macOS

Codex GUI is a native AppKit app for working with Codex in local Git repositories. Start conversations, attach context, follow command activity and review changes. The app connects to the installed Codex CLI through `codex app-server`; Codex owns conversation history.

## Getting started

1. Build and open the app using the instructions below.
2. Sign in through the Codex CLI or the app.
3. Choose **Open Project…**, then **New Chat** or a saved chat.
4. Enter a prompt and press **Send** or **Command-Return**. Use **Shift-Return** to start a multiline draft.

Use the composer's `/` menu to discover commands and skills; see [slash-command semantics](docs/slash-commands.md). [Remote access](docs/remote-access.md#setup-and-device-management) covers pairing another device, and [Settings](docs/settings.md) explains configuration ownership and notification preferences.

## Requirements

Use macOS 14 or later, Apple Command Line Tools, SwiftPM and Swift 6.2 or later for the selected dependencies. [Package.swift](Package.swift) is authoritative for deployment targets and dependency pins. Install a Codex CLI meeting the [compatibility policy](docs/cli-compatibility.md#current-policy) and sign in with a Codex account. That guide explains how to verify the executable actually selected by the app.

## Build, check, and run

From the repository directory:

```sh
make check
make build:bundle
open .build/CodexGUI.app
```

See [formatter prerequisites](CONVENTIONS.md#formatting-and-tooling) and [validation](docs/validation.md) before running checks. Use `make help` for available commands and `make build:bundle:release` for an optimized bundle. Both build configurations write `.build/CodexGUI.app`.

Launch the bundle to provide the identity macOS needs for window tabs and notifications. A bare `swift run CodexGUI` launch lacks that identity. For VS Code, bundle before launch and use `${workspaceFolder}/.build/CodexGUI.app/Contents/MacOS/CodexGUI` as the program; keep IDE configuration local.

### Signing setup

An Apple Development certificate is optional. The bundle script uses one when exactly one valid Apple Development identity is available. Otherwise, if none is available, it uses **ad hoc signing**: a local signature that needs no certificate or Apple Developer account.

To use ad hoc signing explicitly, even when a certificate is available:

```sh
CODEX_GUI_SIGNING_IDENTITY=- ./scripts/bundle.sh
```

Ad hoc signing lets you build the app locally, but macOS permission grants may need to be approved again after rebuilds. For a consistent certificate identity across builds, use Apple Development signing.

To create a free local development identity in Xcode:

1. Sign in under **Xcode > Settings > Apple Accounts**.
2. Select your **Personal Team**.
3. Use a macOS app target with **Automatically manage signing** enabled.

A Personal Team identity supports local development signing. It does not enable app distribution or notarization.

To list the identities available to `codesign`, run:

```sh
security find-identity -v -p codesigning
```

If multiple identities are available, the script asks you to choose one. Set `CODEX_GUI_SIGNING_IDENTITY` to its exact certificate name or SHA-1 hash, or use `-` for ad hoc signing. An explicitly selected certificate must be valid; the script reports an error if it cannot find a unique match.

When using a certificate, keep the bundle identifier and signing identity the same on later builds so macOS can continue to recognize the app and its permission grants. The app's Settings shows notification status for the current launch.

## Development

Start at [AGENTS.md](AGENTS.md). The [documentation map](docs/agent-workflow.md#documentation-map) routes each topic to its owning guide; source and tests define implementation details.

## Third-party notices

Bundled notices are installed under `Contents/Resources/ThirdPartyLicenses`.

| Dependency or asset | License and notices |
| --- | --- |
| [DiceBear Gaze Geometric](https://www.dicebear.com/styles/gaze/presets/) | CC0 1.0; [avatar notice](Sources/CodexGUI/Resources/SubagentAvatars/NOTICE.txt) |
| [Apps SDK UI Swift port](https://github.com/Pmen225/apps-sdk-ui-swift) | MIT; unofficial port of original OpenAI artwork |
| [Swift Markdown](https://github.com/swiftlang/swift-markdown) | Apache 2.0 with the Runtime Library Exception, including its cmark dependency |
| [HighlighterSwift](https://github.com/smittytone/HighlighterSwift) | MIT, with BSD 3-Clause Highlight.js assets |
| [SwiftMath](https://github.com/mgriebling/SwiftMath) | MIT, with separate math-font notices |
| [Mermaid and ELK](Sources/CodexGUI/Resources/Mermaid/README.md) | Resource provenance, rebuild procedure and bundled license notices |

## License

The project's original source code is licensed under the [MIT License](LICENSE.md), copyright (c) 2026 Çağdaş Yardımcı. Third-party dependencies and assets remain subject to their respective licenses and notices.
