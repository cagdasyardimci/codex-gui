# Codex GUI for macOS

Codex GUI is a native macOS app for working with Codex in your local Git repositories. Start coding conversations, attach files and images, follow command activity, and review changes from one interface.

The app uses AppKit and connects to your installed Codex CLI through `codex app-server`. Codex manages the conversation history.

## Getting started

1. Check the requirements below, then build and open the app.
2. Sign in through the Codex CLI or the app's **Sign In…** button.
3. Choose **Open Project…** to open a Git repository, or select a recent project.
4. Choose **New Chat** or open a saved chat.
5. Enter a prompt and press **Send** or **Command-Return**.

## Requirements

- **macOS 14 or later.**
- **Apple Command Line Tools and Swift 6.2 or later.** Swift Markdown 0.9.0 requires this Swift version.
- **A Swift toolchain with the Swift Build backend** for app bundling. It must support `swift build --build-system swiftbuild`; the Swift language version alone does not establish backend availability.
- **An installed Codex CLI** that meets the [compatibility policy](docs/cli-compatibility.md#current-policy). That guide also covers executable selection and version verification.
- **A Codex account** signed in through the CLI or the app.

## Build, check, and run

From the repository directory, run:

```sh
make check
./scripts/bundle.sh
open .build/CodexGUI.app
```

`make check` runs the automated checks. See [formatter prerequisites](CONVENTIONS.md#formatting-and-tooling) before running it, and the [validation guide](docs/validation.md#automated-checks) for test completion requirements and safeguards when sharing a build directory.

The bundle script builds a debug app by default. For an optimized release build, use:

```sh
./scripts/bundle.sh release
open .build/CodexGUI.app
```

Both configurations use `.build/CodexGUI.app`. Launch the app bundle to provide the identity macOS needs for window tabs and notifications. Launching the bare `.build/release/CodexGUI` executable does not provide that identity.

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

## Using the app

### Add context to a prompt

The composer supports project-file search, `@file` completion, image paste and attachments, selected code ranges, and reusable references. You can inspect or remove supplied context before sending. Model and reasoning options come from the connected backend.

Pasting multiple clipboard images or copied image files adds each image in clipboard order and preserves your draft text. Thumbnails wrap into rows as needed. Click a thumbnail to expand it; its close button appears at the top right on hover or keyboard focus.

### Follow and steer the work

Conversations show streamed messages, reported plans, command and tool activity, and requests for approval or answers.

- **Steer** sends a follow-up to the active turn.
- **Stop** waits for the agent to report an outcome and for known commands to report their outcomes. Interrupting an agent turn does not guarantee that its commands are cancelled.
- **Changes** lets you select historical turns, open changed files, and prepare targeted revision requests. It also shows observed command results, including their source and freshness.

Read, search, and command actions appear in compact activity groups. Expand a group to see its list, then expand an individual command to see selectable Shell details. The chevrons appear when you hover over a row; the controls also support keyboard access.

File links open the reported file in its system application. Viewed images have local thumbnail previews, and turn durations use reported timestamps. See [activity presentation](docs/activity-presentation-design.md) for grouping and streaming details.

### Recover from a connection failure

If a request or connection fails after sending, the app keeps the draft and blocks another **Send** until it reads the conversation again. Use **Refresh**, **Reconnect**, or reopen the conversation from the chat list.

The app never resends your prompt automatically.

### Work on separate tasks

**New Task Checkout…** creates a separate Git worktree—a checkout with its own working files—from committed `HEAD`. Your existing source edits stay in place.

Use the task picker to switch between independent running tasks and their approvals, context, progress, and reviews. Task Actions removes a checkout only after verifying that it is clean and that execution and command outcomes are known. The branch remains.

If you quit during work, the app offers to stay open or request a stop. An unknown command outcome keeps the app open.

### Read formatted responses

Messages support selectable headings, nested and task lists, emphasis, strikethrough, quotes, links, and aligned tables. Code blocks have language headers, syntax coloring where supported, and copy controls.

| Content | Display behavior |
| --- | --- |
| Display math | Closed blocks using `$$` or `\[...\]` render with SwiftMath. |
| Mermaid diagrams | A limited native `flowchart`/`graph` subset supports simple nodes and `-->` edges. Other types and syntax appear as readable source. |
| Incomplete or unsupported content | Malformed or unsupported math and diagrams, and open streaming fences, retain readable text. |
| HTML and inline math | HTML and inline `$...$` math remain literal text. |
| Markdown images | Images appear as labels with their source. |
| Command and tool output | Output retains its literal text. |

## Development

### Launching from the command line or VS Code

For development, `swift run CodexGUI` starts the executable directly, with desktop notifications unavailable. Notifications require a stable app bundle identity.

In VS Code, configure:

- **Pre-launch task:** `./scripts/bundle.sh`
- **Launch program:** `${workspaceFolder}/.build/CodexGUI.app/Contents/MacOS/CodexGUI` for both debugging and **Run Without Debugging**
- **Run task:** `open .build/CodexGUI.app` after bundling

Swift extension configurations that launch the bare executable remain usable with notifications unavailable. IDE configuration stays local and is ignored by Git.

### Implementation notes

Messages use Swift Markdown's CommonMark/GFM parser and native AppKit attributed text. Parsing runs outside the main actor; AppKit creates text, table attributes, and rich attachments on the main actor. The transcript has no web view or SwiftUI host.

Drafts and unresolved command identities are stored per project and chat in `UserDefaults`. Conversation records stay with Codex.

### Project guides and validation

Start agent work at [AGENTS.md](AGENTS.md). The [documentation map](docs/agent-workflow.md#documentation-map) identifies the owning guide for each topic.

| Guide | What it covers |
| --- | --- |
| [Conventions](CONVENTIONS.md) | Formatting, file placement, and code ownership |
| [Architecture](docs/architecture.md) | State and execution contracts |
| [Validation](docs/validation.md) | Automated checks and acceptance requirements |
| [Native QA](docs/native-qa.md) | Isolated synthetic app preparation and interaction checks |
| [CLI compatibility](docs/cli-compatibility.md) | Backend version assessment |

## Interface dependencies

Dependency versions are pinned. The app bundle includes license and notice files for the rendering libraries under `Contents/Resources/ThirdPartyLicenses`.

| Dependency | Purpose | Version and license |
| --- | --- | --- |
| [DiceBear Gaze Geometric](https://www.dicebear.com/styles/gaze/presets/) | Subagent avatars | CC0 1.0; static SVGs bundled for offline use |
| [Apps SDK UI Swift port](https://github.com/Pmen225/apps-sdk-ui-swift) | Interface icons | Commit `07cd708b3670948155d913f863ed4f0d8529ab2e`; MIT |
| [Swift Markdown](https://github.com/swiftlang/swift-markdown) | Markdown parsing, with its Swift cmark dependency | 0.9.0; Apache 2.0 with the Runtime Library Exception |
| [HighlighterSwift](https://github.com/smittytone/HighlighterSwift) | Code coloring | 3.1.0; MIT, with BSD 3-Clause Highlight.js assets |
| [SwiftMath](https://github.com/mgriebling/SwiftMath) | Display math | 1.7.3; MIT, with separate math-font notices |
| [swift-mermaid](https://github.com/Australware/swift-mermaid) | Native flowchart layout | 0.3.0; MIT, including its vendored MermaidLayoutDagre notice |

The [avatar notice](Sources/CodexGUI/Resources/SubagentAvatars/NOTICE.txt) credits DiceBear and identifies the artwork license. No DiceBear service or runtime library is required.

The icon port is unofficial; the original artwork comes from OpenAI. `DesktopIcons` supplies independent template images to AppKit controls and handles tinting for custom drawing. The bundle includes the package's SVG resources and license notices. Although the port includes SwiftUI components, this app uses AppKit controls.

## License

The project's original source code is licensed under the [MIT License](LICENSE.md), copyright (c) 2026 Çağdaş Yardımcı. Third-party dependencies and assets remain subject to their respective licenses and notices.
