# Codex GUI for macOS

A native AppKit client for local Codex coding conversations. It runs an installed `codex app-server` process and keeps Codex as the owner of conversation history.

## Requirements

- macOS 14 or later, Apple Command Line Tools, and Swift 6.2 or later (required by Swift Markdown 0.9.0). This repository was built and observed on macOS 26 with Swift 6.3.1.
- App bundling requires the Swift Build backend (`swift build --build-system swiftbuild`). This packaging path is verified with Swift 6.3.1; Swift 6.2 alone does not establish backend availability.
- Codex CLI 0.153.2 or later, available through `PATH`, a common Homebrew or nvm path, or `CODEX_EXECUTABLE`. Version 0.153.2 is the tested protocol baseline; later versions may change the experimental app-server interface.
- A Codex account signed in through the CLI or the app's **Sign In…** button.

## Build, check, and run

```sh
make check
./scripts/bundle.sh
open .build/CodexGUI.app
```

For an optimized release bundle, run `./scripts/bundle.sh release`, then
`open .build/CodexGUI.app`. The script defaults to a debug build; both configurations
use the same bundle path. Launching the bare `.build/release/CodexGUI` executable
does not provide the bundle identity required by macOS window tabs and notifications.

`make check` runs the style driver regression checks, strict formatting validation, `swift build`, and Swift Testing. Formatting requires SwiftFormat 0.63.0 or later (`brew install swiftformat`) and Python 3. `make format` applies the checked-in style rules. The installed Command Line Tools on this machine place Swift Testing outside SwiftPM's default search path, so the Makefile supplies the framework and macro paths. The application and testing framework both require macOS 14 or later. See [conventions](CONVENTIONS.md) for naming and component rules.

For development, `swift run CodexGUI` starts the executable directly with desktop notifications unavailable. macOS notification access requires an app bundle identity; `scripts/bundle.sh` creates and ad hoc signs that bundle. Settings shows the notification status for the current launch.

In VS Code, use `./scripts/bundle.sh` as the pre-launch task and `${workspaceFolder}/.build/CodexGUI.app/Contents/MacOS/CodexGUI` as the launch program for both debugging and **Run Without Debugging**. A Run task can use `open .build/CodexGUI.app` after bundling. Swift extension launch configurations that run the bare executable remain usable with notifications unavailable. IDE configuration stays local and is ignored by Git.

## Interface dependencies

Interface icons use the MIT-licensed, unofficial
[Apps SDK UI Swift port](https://github.com/Pmen225/apps-sdk-ui-swift), pinned to commit
`07cd708b3670948155d913f863ed4f0d8529ab2e`. The original artwork comes from OpenAI.
`DesktopIcons` supplies independent template images to AppKit controls and handles tinting
for custom drawing. The app bundle includes the package's SVG resources and licence notices.
The port also contains SwiftUI components; the application continues to use AppKit controls.

Markdown parsing uses [Swift Markdown](https://github.com/swiftlang/swift-markdown) 0.9.0,
licensed under Apache 2.0 with the Runtime Library Exception, and its Swift cmark dependency.
Code coloring uses [HighlighterSwift](https://github.com/smittytone/HighlighterSwift) 3.1.0
(MIT, with BSD 3-Clause Highlight.js assets). Display math uses
[SwiftMath](https://github.com/mgriebling/SwiftMath) 1.7.3 (MIT, with separate math-font notices).
Native flowchart layout uses [swift-mermaid](https://github.com/Australware/swift-mermaid) 0.3.0
(MIT, including its vendored MermaidLayoutDagre notice). These versions are pinned; the app
bundle includes their license and notice files under `Contents/Resources/ThirdPartyLicenses`.

## Project structure

`Sources/CodexGUI/` groups code by responsibility: `App`, `Application`, `CodexClient`,
`Persistence`, `Workspaces`, and `Features/<feature>`. Tests mirror those groups under
`Tests/CodexGUITests/`. See [conventions](CONVENTIONS.md) for component ownership and
[architecture](docs/architecture.md) for state and execution contracts.

Within `Application/`, `State/` holds shared values and actions, `Runtime/` holds stores and
effect execution, `Reducers/<feature>/` groups feature transitions and their supporting values,
`Composition/` coordinates related feature transitions, `Presentation/` holds selectors and
snapshot helpers, and `Services/` holds backend and filesystem service interfaces and implementations.
`Services/Git/` groups Git comparison, baseline capture and their implementation support;
`Runtime/Review/` groups Git review and summary execution. Tests follow these groups.
Feature presentation types live beside their views; `Features/Shared/` holds presentation ownership
shared across features. Durable task records belong to `Persistence/`; checkout lifecycle remains
in `Workspaces/`. Files named `OwnerType+Concern.swift` extend that owner rather than declaring
a separate controller or runtime component.

`Features/Conversation/Composer/` groups input controls and command menus;
`Transcript/` groups parsing, rendering, collection items and turn navigation.
`Features/Changes/RepositoryComparison/` owns repository comparison controls and navigation;
`ReportedChanges/` owns the reported-turn review UI; `Diff/` contains diff rendering and file
presentation helpers shared within Changes. Review models and analysis belong to
`Application/Reducers/Review/`. `Features/Usage/` owns usage presentation and controls, while
`App/WindowLayout/` groups window panes, split views and layout transitions.

Components split across several files use owner-named subfolders where this reduces directory
clutter. Each such folder keeps the main file and its extensions together; independent components
and shared support types remain in their responsibility groups. The broad `ApplicationStateTests`
suite follows the same arrangement within its runtime test group.

The application layer uses Model View Intent (MVI). Each checkout/session has a
`WorkspaceStateStore` containing reducer-owned feature state. AppKit callbacks dispatch captured
intents; feature reducers decide transitions and describe effects. `WorkspaceEffectRunner` runs
backend and persistence work and returns scoped results. Narrow read-only presentations drive
the panes while AppKit retains focus, scrolling and layout. Execution ownership remains
independent of the conversation displayed in the window.

`TaskWorkspaceCoordinator` retains the store registry and coordinates checkout lifecycle through
typed actions and `WorkspaceCoordinatorReducer`. Cleanup and quit wait for accepted work and
persisted writes, then revalidate the exact owners and unresolved command outcomes.

See [architecture](docs/architecture.md) for state transitions, effect execution and ownership
contracts.

## Using the app

Open a Git repository with **Open Project…** or choose a recent project. Select a saved chat or choose **New Chat**. Enter a prompt and press **Send** or Command-Return. The composer supports project-file search and `@file` completion, image paste and attachments, selected code ranges, and reusable references. Inspect or remove supplied context before sending. Model and reasoning options come from the connected backend.

The conversation shows streamed messages, reported plans, command and tool activity, and approval or question requests. **Steer** sends a follow-up to the active turn. **Stop** waits for a reported agent outcome and any known commands to report their outcomes; an interrupted agent turn does not guarantee command cancellation. The Changes pane selects historical turns, opens changed files, prepares targeted revision requests, and shows observed command results with their source and freshness. Drafts and unresolved command identities are stored per project and chat in `UserDefaults`; conversation records stay with Codex.

User and agent messages use Swift Markdown's CommonMark/GFM parser and native AppKit attributed text.
Headings, nested and task lists, emphasis, strikethrough, quotes, links, code blocks, and aligned
tables are selectable. Code blocks use native cards with language headers, syntax coloring
where supported, and copy controls. Closed display-math blocks using `$$` or `\[...\]` render
with SwiftMath.
Mermaid fences support a bounded native `flowchart`/`graph` subset with simple nodes and
`-->` edges; other diagram types and syntax remain readable source. Unsupported or malformed
math/diagrams and open streaming fences retain readable text. HTML and inline `$...$` math
remain literal, and Markdown images appear as labels with their source. Parsing runs outside
the main actor; AppKit creates the text, table attributes, and rich attachments on the main
actor. The transcript has no web view or SwiftUI host. Command and tool output retains its
literal text.

Read, search, and command actions appear in compact activity groups. A group's disclosure
controls its list; each command's disclosure independently opens selectable Shell details.
Chevrons appear while hovering the row; disclosure controls also support keyboard access.
File links open the reported file in its system application, and viewed images have local
thumbnail previews. Turn durations use reported timestamps. See the
[activity presentation design](docs/activity-presentation-design.md) for grouping, identity,
and streaming behavior.

If a request or connection fails after sending, the app keeps the draft and blocks another Send until the conversation is read again. Use **Refresh** or **Reconnect**, or open the conversation from the chat list. The app never resends the prompt automatically. **New Task Checkout…** creates a separate Git worktree from committed `HEAD`; source edits stay in place. The task picker switches between independent running tasks and their approvals, context, progress, and reviews. Task Actions removes only a verified, clean checkout after its execution and command outcomes are known; its branch remains. Quitting during work offers to keep the app open or request a stop, and an unknown command outcome keeps the app open.

## Validation

Run `make check` for strict formatting, build, and automated regression coverage. The suite covers protocol and recovery behavior, diagnostics, conversation rendering, persisted context, conversation management, and editor handoff. Follow the [native QA guide](docs/native-qa.md) for repeatable interaction and layout checks using a synthetic backend without model calls.

The automated suite covers implemented protocol, runtime and presentation behavior. Native
and live acceptance requirements are listed in the [validation guide](docs/validation.md).
Execution on the minimum macOS 14 target remains unverified. See the [CLI compatibility policy](docs/cli-compatibility.md) for protocol assumptions and limits.
