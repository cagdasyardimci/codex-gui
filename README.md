# Codex GUI for macOS

A native AppKit client for local Codex coding conversations. It runs an installed `codex app-server` process and keeps Codex as the owner of conversation history.

## Requirements

- macOS 13 or later and Apple Command Line Tools. This repository was built and observed on macOS 26 with Swift 6.3.1.
- Codex CLI 0.153.2 or later, available through `PATH`, a common Homebrew or nvm path, or `CODEX_EXECUTABLE`. Version 0.153.2 is the tested protocol baseline; later versions may change the experimental app-server interface.
- A Codex account signed in through the CLI or the app's **Sign In…** button.

## Build, check, and run

```sh
make check
./scripts/bundle.sh
open .build/CodexGUI.app
```

`make check` runs the style driver regression checks, strict formatting validation, `swift build`, and Swift Testing. Formatting requires SwiftFormat 0.63.0 or later (`brew install swiftformat`) and Python 3. `make format` applies the checked-in style rules. The installed Command Line Tools on this machine place Swift Testing outside SwiftPM's default search path, so the Makefile supplies the framework and macro paths. Its Testing framework targets macOS 14; the application target remains macOS 13. Tests on macOS 13 have not been verified. See [conventions](CONVENTIONS.md) for naming and component rules.

For development, `swift run CodexGUI` starts the executable directly with desktop notifications unavailable. macOS notification access requires an app bundle identity; `scripts/bundle.sh` creates and ad hoc signs that bundle. Settings shows the notification status for the current launch.

In VS Code, use `./scripts/bundle.sh` as the pre-launch task and `${workspaceFolder}/.build/CodexGUI.app/Contents/MacOS/CodexGUI` as the launch program for both debugging and **Run Without Debugging**. A Run task can use `open .build/CodexGUI.app` after bundling. Swift extension launch configurations that run the bare executable remain usable with notifications unavailable. IDE configuration stays local and is ignored by Git.

## Project structure

`Sources/CodexGUI/` groups code by responsibility: `App`, `Application`, `CodexClient`,
`Persistence`, `Workspaces`, and `Features/<feature>`. Tests mirror those groups under
`Tests/CodexGUITests/`. See [conventions](CONVENTIONS.md) for component ownership and
[architecture](docs/architecture.md) for state and execution contracts.

Within `Application/`, `State/` holds shared values and actions, `Runtime/` holds stores and
effect execution, `Reducers/<feature>/` groups feature transitions and their supporting values,
`Composition/` coordinates related feature transitions, `Presentation/` holds selectors and
snapshot helpers, and `Services/` defines the backend interface. Tests follow these groups.
Feature presentation types live beside their views; `Features/Shared/` holds presentation ownership
shared across features. Durable task records belong to `Persistence/`; checkout lifecycle remains
in `Workspaces/`. Files named `OwnerType+Concern.swift` extend that owner rather than declaring
a separate controller or runtime component.

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

If a request or connection fails after sending, the app keeps the draft and blocks another Send until the conversation is read again. Use **Refresh** or **Reconnect**, or open the conversation from the chat list. The app never resends the prompt automatically. **New Task Checkout…** creates a separate Git worktree from committed `HEAD`; source edits stay in place. The task picker switches between independent running tasks and their approvals, context, progress, and reviews. Task Actions removes only a verified, clean checkout after its execution and command outcomes are known; its branch remains. Quitting during work offers to keep the app open or request a stop, and an unknown command outcome keeps the app open.

## Validation

Run `make check` for strict formatting, build, and automated regression coverage. The suite covers protocol and recovery behavior, diagnostics, conversation rendering, persisted context, conversation management, and editor handoff. Follow the [native QA guide](docs/native-qa.md) for repeatable interaction and layout checks using a synthetic backend without model calls.

The automated suite covers implemented protocol, runtime and presentation behavior. Native
and live acceptance requirements are listed in the [validation guide](docs/validation.md).
Execution on macOS 13 remains unverified. See the [CLI compatibility policy](docs/cli-compatibility.md) for protocol assumptions and limits.

## License

The project's original source code is licensed under the [MIT License](LICENSE.md), copyright (c) 2026 Çağdaş Yardımcı. Third-party dependencies and assets remain subject to their respective licenses and notices.
