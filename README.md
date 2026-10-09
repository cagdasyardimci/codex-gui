# Codex GUI for macOS

A native AppKit client for local Codex coding conversations. It runs an installed `codex app-server` process and keeps Codex as the owner of conversation history.

## Requirements

- macOS 14 or later, Apple Command Line Tools, and Swift 6.2 or later (required by Swift Markdown 0.9.0).
- App bundling requires a Swift toolchain with the Swift Build backend (`swift build --build-system swiftbuild`); the language version alone does not establish backend availability.
- An installed Codex CLI meeting the [compatibility policy](docs/cli-compatibility.md#current-policy). Executable selection and version verification are documented in that guide.
- A Codex account signed in through the CLI or the app's **Sign In…** button.

## Build, check, and run

```sh
make check
./scripts/bundle.sh
open .build/CodexGUI.app
```

For an optimized release bundle, run `./scripts/bundle.sh release`, then `open .build/CodexGUI.app`. The script defaults to a debug build; both configurations use the same bundle path. Launching the bare `.build/release/CodexGUI` executable does not provide the bundle identity required by macOS window tabs and notifications.

See [validation](docs/validation.md#automated-checks) for the test gate, runner completion requirements and shared-build safeguards. See [conventions](CONVENTIONS.md#formatting-and-tooling) for formatter prerequisites and usage, and [native QA](docs/native-qa.md) for synthetic app preparation and interaction checks.

For development, `swift run CodexGUI` starts the executable directly with desktop notifications unavailable. macOS notification access requires a stable app bundle identity. `scripts/bundle.sh` signs the bundle with the single valid Apple Development identity available to `codesign`.

Xcode can create this identity at no cost for a Personal Team: sign in under **Xcode > Settings > Apple Accounts**, select the Personal Team, and use a macOS app target with **Automatically manage signing** enabled. Keep the bundle identifier and signing identity the same on later builds so macOS continues to recognize the app and its permission grants. A Personal Team identity supports local development signing; it does not enable app distribution or notarization.

The bundle script stops with setup guidance if the identity is missing or multiple Apple Development identities are available. Set `CODEX_GUI_SIGNING_IDENTITY` to an exact certificate name or SHA-1 hash to select an identity explicitly. Run `security find-identity -v -p codesigning` to list identities available to `codesign`. Settings shows the notification status for the current launch.

In VS Code, use `./scripts/bundle.sh` as the pre-launch task and `${workspaceFolder}/.build/CodexGUI.app/Contents/MacOS/CodexGUI` as the launch program for both debugging and **Run Without Debugging**. A Run task can use `open .build/CodexGUI.app` after bundling. Swift extension launch configurations that run the bare executable remain usable with notifications unavailable. IDE configuration stays local and is ignored by Git.

## Interface dependencies

Subagent avatars use DiceBear's [Gaze Geometric preset](https://www.dicebear.com/styles/gaze/presets/), dedicated to the public domain under CC0 1.0. Static SVGs are bundled for offline use; no DiceBear service or runtime library is required. The [avatar notice](Sources/CodexGUI/Resources/SubagentAvatars/NOTICE.txt) credits DiceBear and identifies the artwork license.

Interface icons use the MIT-licensed, unofficial [Apps SDK UI Swift port](https://github.com/Pmen225/apps-sdk-ui-swift), pinned to commit `07cd708b3670948155d913f863ed4f0d8529ab2e`. The original artwork comes from OpenAI. `DesktopIcons` supplies independent template images to AppKit controls and handles tinting for custom drawing. The app bundle includes the package's SVG resources and licence notices. The port also contains SwiftUI components; the application continues to use AppKit controls.

Markdown parsing uses [Swift Markdown](https://github.com/swiftlang/swift-markdown) 0.9.0, licensed under Apache 2.0 with the Runtime Library Exception, and its Swift cmark dependency. Code coloring uses [HighlighterSwift](https://github.com/smittytone/HighlighterSwift) 3.1.0 (MIT, with BSD 3-Clause Highlight.js assets). Display math uses [SwiftMath](https://github.com/mgriebling/SwiftMath) 1.7.3 (MIT, with separate math-font notices). Native flowchart layout uses [swift-mermaid](https://github.com/Australware/swift-mermaid) 0.3.0 (MIT, including its vendored MermaidLayoutDagre notice). These versions are pinned; the app bundle includes their license and notice files under `Contents/Resources/ThirdPartyLicenses`.

## Project structure

Start agent work at [AGENTS.md](AGENTS.md). The [documentation map](docs/agent-workflow.md#documentation-map) assigns each topic to its owning guide. [Conventions](CONVENTIONS.md#file-organization-and-ownership) define file placement; [architecture](docs/architecture.md) defines state and execution contracts.

## Using the app

Open a Git repository with **Open Project…** or choose a recent project. Select a saved chat or choose **New Chat**. Enter a prompt and press **Send** or Command-Return. The composer supports project-file search and `@file` completion, image paste and attachments, selected code ranges, and reusable references. Pasting multiple clipboard images or copied image files adds each image in clipboard order, preserving the draft text. Image thumbnails share rows and wrap to the available composer width. Click an attached image thumbnail to expand it. Its close button appears at the top right on hover or keyboard focus. Other supplied context can be inspected or removed before sending. Model and reasoning options come from the connected backend.

The conversation shows streamed messages, reported plans, command and tool activity, and approval or question requests. **Steer** sends a follow-up to the active turn. **Stop** waits for a reported agent outcome and any known commands to report their outcomes; an interrupted agent turn does not guarantee command cancellation. The Changes pane selects historical turns, opens changed files, prepares targeted revision requests, and shows observed command results with their source and freshness. Drafts and unresolved command identities are stored per project and chat in `UserDefaults`; conversation records stay with Codex.

User and agent messages use Swift Markdown's CommonMark/GFM parser and native AppKit attributed text. Headings, nested and task lists, emphasis, strikethrough, quotes, links, code blocks, and aligned tables are selectable. Code blocks use native cards with language headers, syntax coloring where supported, and copy controls. Closed display-math blocks using `$$` or `\[...\]` render with SwiftMath. Mermaid fences support a bounded native `flowchart`/`graph` subset with simple nodes and `-->` edges; other diagram types and syntax remain readable source. Unsupported or malformed math/diagrams and open streaming fences retain readable text. HTML and inline `$...$` math remain literal, and Markdown images appear as labels with their source. Parsing runs outside the main actor; AppKit creates the text, table attributes, and rich attachments on the main actor. The transcript has no web view or SwiftUI host. Command and tool output retains its literal text.

Read, search, and command actions appear in compact activity groups. A group's disclosure controls its list; each command's disclosure independently opens selectable Shell details. Chevrons appear while hovering the row; disclosure controls also support keyboard access. File links open the reported file in its system application, and viewed images have local thumbnail previews. Turn durations use reported timestamps. See the [activity presentation design](docs/activity-presentation-design.md) for grouping, identity, and streaming behavior.

If a request or connection fails after sending, the app keeps the draft and blocks another Send until the conversation is read again. Use **Refresh** or **Reconnect**, or open the conversation from the chat list. The app never resends the prompt automatically. **New Task Checkout…** creates a separate Git worktree from committed `HEAD`; source edits stay in place. The task picker switches between independent running tasks and their approvals, context, progress, and reviews. Task Actions removes only a verified, clean checkout after its execution and command outcomes are known; its branch remains. Quitting during work offers to keep the app open or request a stop, and an unknown command outcome keeps the app open.

## Validation

Follow the [validation guide](docs/validation.md) for automated checks and acceptance requirements, [native QA](docs/native-qa.md) for isolated interaction checks, and [CLI compatibility](docs/cli-compatibility.md) for backend version assessment.

## License

The project's original source code is licensed under the [MIT License](LICENSE.md), copyright (c) 2026 Çağdaş Yardımcı. Third-party dependencies and assets remain subject to their respective licenses and notices.
