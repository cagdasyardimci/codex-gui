# Swift and AppKit conventions

These conventions apply to the Swift source and tests. Run `make format` to apply the style and `make check` to validate formatting, build, and tests. Install SwiftFormat 0.63.0 or later (`brew install swiftformat`); Python 3 runs the checked-in driver. `.swiftformat` enables only layout rules, avoiding automatic changes to declarations, expressions, or literals. Use the Makefile commands so the supplemental rules also run.

Use tabs for indentation, displayed at four columns, and keep code within 100 columns. Put every opening brace on its own line, including closure braces; place closure parameters or capture lists after that line. Keep fitting single-argument calls compact. Put every argument of a multi-argument call on a separate line, with the closing parenthesis on its own line. Wrap long single-argument calls as needed. Separate creation, styling, configuration, insertion, and other meaningful phases with blank lines; keep related statements together.

`scripts/swift-style.py` supplements SwiftFormat using its Swift tokens because ordinary Allman formatting leaves inline closures unchanged and argument wrapping otherwise depends on line length. It verifies that supplemental changes preserve non-whitespace tokens. String literals, their interpolation, and comment contents are preserved. Do not run Apple's `swift-format` over these files: its brace formatting conflicts with this style.

Review these rules manually: meaningful function responsibilities and phase boundaries; descriptive names; compound decisions named by their meaning when practical; explicit constructor types where `.init` obscures the created value; short intent comments; and shared geometry/constants between measurement and drawing. Keep obvious arithmetic inline, split calculations only when distinct decisions need explanation, and preserve existing numeric relationships. Extract repeated geometry or a small layout structure when it helps understanding. Verify unexplained coordinate adjustments before documenting their intent. The driver rejects any remaining line over 100 display columns. Wrap long text manually with concatenated fragments that preserve exact spaces, escapes, and interpolation; reflow comments and embedded fixtures without changing their behavior.

- Follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/): prefer clarity at the call site, name types with `UpperCamelCase`, name functions and values with `lowerCamelCase`, use informative argument labels, and document behavior that is not apparent from a declaration.
- Use [SwiftFormat](https://github.com/nicklockwood/SwiftFormat) through the checked-in driver for consistent layout. Its [rule reference](https://github.com/nicklockwood/SwiftFormat/blob/main/Rules.md) describes the configured layout rules. Choose descriptive names even when a shorter name would fit the formatter.
- Give each component one responsibility. The AppKit layer owns windows, controls, layout, selection, and accessibility. Workspace stores own application state, and reducers decide transitions. The Codex client owns the process and protocol. Persistence owns local drafts and recent projects. Views receive presentations and send intents; they do not decode protocol messages or directly edit Codex conversation files.
- Keep AppKit mutations on the main actor. Parse process output and prepare long message content away from the main actor. Use Auto Layout and standard macOS controls. Give interactive controls accessible labels and keyboard access; use system colors and appearance so light and dark modes both work.
- Keep source folders shallow and named by responsibility. Prefer small methods with explicit state transitions. Handle process failures and unsupported requests visibly rather than leaving the interface waiting.

Source ownership follows the same groups. `App/` owns application lifecycle and shared window
controls; `Features/<feature>/` owns feature views and their presentation helpers; `Application/`
owns workspace models, actions, reducers, effects and presentation selectors; `CodexClient/` owns `AppServer`, wire
models, framing, and diagnostics; `Persistence/` owns local stores, including review markers;
`Workspaces/` owns checkout lifecycle and task coordination. These folders compile into one
module, so responsibility boundaries remain a code-review concern rather than separate targets.

Within `Application/`, use `State/` for shared models, actions, intents, identity and eligibility;
`Runtime/` for stores, inputs, hydration, effect execution, persistence scheduling and operation
handles; `Reducers/<feature>/` for feature transitions and their supporting values;
`Composition/` for cross-feature transitions; `Presentation/` for selectors and snapshot helpers;
and `Services/` for backend and filesystem service interfaces and implementations. Keep these
groups shallow. `Services/Git/` owns Git comparison and baseline implementations, including
captured-tree storage models that are not workspace state. `Runtime/Review/` owns Git review
and summary execution. Feature-specific command models stay in `Reducers/Composer/`; review
models and analysis stay in `Reducers/Review/`. Shared baseline identities and references
remain in `State/`.
Canonical compact turn previews also belong to `State/`. Prepare Markdown through an injected
service before reducers accept preview values; feature rendering and reusable preparation
caches stay outside workspace model state. Pure reported-patch composition belongs to
`Reducers/Review/`; transcript preparation may cache its results beside the transcript views.
Feature-specific presentation types stay beside their views, with shared presentation ownership
in `Features/Shared/`. `Persistence/` also owns durable task workspace records; `Workspaces/`
retains checkout locations, Git lifecycle and coordination.

Within `Features/Conversation/`, use `Composer/` for input controls and command menus, and
`Transcript/` for parsing, rendering, collection items, preparation and turn navigation.
Within `Features/Changes/`, use `RepositoryComparison/` for repository comparison controls and
navigation, `ReportedChanges/` for reported-turn review UI, and `Diff/` for shared diff rendering
and file presentation helpers. Usage views and presentation values belong to `Features/Usage/`.
`Features/PinnedSummary/` owns the summary card and its compact section presentations;
`Features/Sources/` owns source inventory, details, result cards, audio metadata and tab hover
previews. `Features/Subagents/` owns the delegated-work list and its lifecycle projection. Shared subagent
avatars and attachment thumbnail preparation belong to `Features/Shared/`.
`CodexClient/InlineImageData.swift` identifies inline image payloads;
`Application/Services/LocalAttachmentURL.swift` resolves local attachment paths and file URLs.
Keep these shared values independent of feature views. `App/WindowLayout/` groups pane and split
view controls, layout policies and transitions. Keep window integration tests in
`Tests/CodexGUITests/App/`; tests of layout components may use its `WindowLayout/` subgroup.

Name extension-only source and test files `OwnerType+Concern.swift`, using the exact extended
type as the owner. Put extensions of different owners in separate files. A file defining a
primary type keeps that type's filename and may include related supporting extensions.
An extension split organizes one component; it does not establish a separate controller or
responsibility boundary. Keep independent types in files named for those types. Separate effect
descriptions from runtime schedulers and operation handles so each is discoverable by its name.

Use an owner-named subfolder when a component's main file and several extensions clutter a
directory shared with other components. Keep the main file and its extensions together, retaining
their explicit filenames. Apply this to `MainWindowController`, `NavigationViewController`,
`ConversationViewController`, `WorkspaceEffectRunner`, `AppServer`, `WorkspaceCoordinatorReducer`,
`TaskWorkspaceCoordinator`, `GitWorktreeManager`, and the `ApplicationStateTests` suite.
Keep shared support types outside owner folders. Do not add another owner folder where an existing
feature directory already groups the component clearly, or for a single small extension.

Cross-feature composition belongs to standalone composition types rather than extensions of a
feature reducer defined elsewhere. Tests for a distinct responsibility use their own suite in that
responsibility's test group. Reserve suite extensions for parts of the same suite grouped together
in its owner folder; do not retain an unrelated suite owner solely for an old test filter.

The application uses Model View Intent (MVI). `WorkspaceStateStore` owns one `WorkspaceModel`
per checkout/session, including the source session. `WorkspaceStoreInputs` captures operation
identity and proposes typed actions. Feature reducers synchronously update values and describe
effects. Reducers do not read storage, call the backend, schedule tasks, read clocks or generate
identifiers. Accepted domain events compose related feature changes before publication.
`WorkspaceEffectRunner` performs scoped backend, filesystem and persistence work and returns
typed results. Runtime jobs, subscriptions, handles and waiters stay outside model state.
Follow-up reads return through `WorkspaceStoreInputs` for fresh request identity and clock
capture. Perform filesystem-backed checkout validation before proposing a read, then let the
reducer revalidate the captured ownership against current workspace values.

`TaskWorkspaceCoordinator` keeps the store registry and runs checkout lifecycle effects;
`WorkspaceCoordinatorReducer` owns selection, creation, recovery, cleanup and aggregate quit
decisions. Capture owner/session, connection generation and request identity before work starts,
then validate the result against its pending operation. Execution ownership is separate from
the displayed conversation. Unknown command outcomes remain independent cleanup and quit
barriers; a terminal agent event does not clear them. Shared persistence retains existing
project/thread keys and ordering.

AppKit controllers dispatch captured `WorkspaceIntentTarget` callbacks and render narrow
read-only presentations. `WorkspaceEligibility` supplies the same capability rules to selectors
and reducers; reducers revalidate every proposal. Coalesce UI publication while processing every
accepted backend event in order. `ConversationViewController` delegates asynchronous text
preparation and superseded-render cancellation to `TranscriptPreparationCoordinator`, while
retaining focus, selection, scrolling, measurements and AppKit layout. `CodexService` remains
the application-facing interface; its concrete implementation belongs to `CodexClient/`.

Tests stay in the single `CodexGUITests` target and mirror source responsibilities: `App`, `Application`, `CodexClient`, `Persistence`, `Workspaces`, and `Features/<feature>`. Put full-window and cross-view ownership checks in `App`, backend protocol integration checks in `CodexClient`, and feature-specific view tests beside their feature group. SwiftPM discovers these subfolders automatically. Preserve suite names during file-only moves. When extracting an independent suite, update affected test filters and preserve test methods, assertions, actor isolation and serialization requirements.

Keep service-specific fixtures in that service group's `Support/` folder. Global test support
is reserved for fixtures used across responsibility groups. Usage view tests have their own
suite rather than sharing a navigation suite. Scripts, documentation and resources retain
their existing locations; root resources supply bundle metadata and branding, while source
resources are packaged by SwiftPM.

AppKit role references: [application lifecycle](https://developer.apple.com/documentation/appkit/nsapplication), [window controllers](https://developer.apple.com/documentation/appkit/nswindowcontroller), [view controllers](https://developer.apple.com/documentation/appkit/nsviewcontroller), [split view controllers](https://developer.apple.com/documentation/appkit/nssplitviewcontroller), and [macOS design guidance](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/).
