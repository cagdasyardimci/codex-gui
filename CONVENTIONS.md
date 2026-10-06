# Swift and AppKit conventions

These conventions apply to the Swift source and tests.

## Formatting and tooling

Run `make format` to apply the style. Follow [validation](docs/validation.md#automated-checks) for build and test commands. Install SwiftFormat 0.63.0 or later (`brew install swiftformat`); Python 3 runs the checked-in driver. `.swiftformat` enables only layout rules, avoiding automatic changes to declarations, expressions, or literals. Use the Makefile commands so the supplemental rules also run.

Use tabs for indentation, displayed at four columns, and keep code within 100 columns. Put every opening brace on its own line, including closure braces; place closure parameters or capture lists after that line. Keep fitting single-argument calls compact. Put every argument of a multi-argument call on a separate line, with the closing parenthesis on its own line. Wrap long single-argument calls as needed. Separate creation, styling, configuration, insertion, and other meaningful phases with blank lines; keep related statements together.

`scripts/swift-style.py` supplements SwiftFormat using its Swift tokens because ordinary Allman formatting leaves inline closures unchanged and argument wrapping otherwise depends on line length. It verifies that supplemental changes preserve non-whitespace tokens. String literals, their interpolation, and comment contents are preserved. Do not run Apple's `swift-format` over these files: its brace formatting conflicts with this style.

The driver rejects any remaining line over 100 display columns. Wrap long text manually with concatenated fragments that preserve exact spaces, escapes, and interpolation; reflow comments and embedded fixtures without changing their behavior.

- Use [SwiftFormat](https://github.com/nicklockwood/SwiftFormat) through the checked-in driver for consistent layout. Its [rule reference](https://github.com/nicklockwood/SwiftFormat/blob/main/Rules.md) describes the configured layout rules. Choose descriptive names even when a shorter name would fit the formatter.

In a checkout with unrelated edits, apply formatting only to your Swift paths using
`python3 scripts/swift-style.py <file-or-directory>` and review the resulting diff.

## Naming and readability

- Follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/): prefer clarity at the call site, name types with `UpperCamelCase`, name functions and values with `lowerCamelCase`, use informative argument labels, and document behavior that is not apparent from a declaration.

Review these rules manually: meaningful function responsibilities and phase boundaries; descriptive names; compound decisions named by their meaning when practical; explicit constructor types where `.init` obscures the created value; short intent comments; and shared geometry/constants between measurement and drawing. Keep obvious arithmetic inline, split calculations only when distinct decisions need explanation, and preserve existing numeric relationships. Extract repeated geometry or a small layout structure when it helps understanding. Verify unexplained coordinate adjustments before documenting their intent.

## DRY principle

DRY means "Don't Repeat Yourself": give each shared rule or behavior one authoritative implementation so a correction reaches all callers that depend on that contract. Look for duplicated decisions, validation, state transitions, parsing, layout calculations and fixtures, not just repeated lines. Reuse an existing implementation before introducing another one.

Extract shared code when callers represent the same responsibility and must change together. Compare their inputs, outputs, ownership, failure behavior, ordering and lifecycle first. Similar syntax alone does not establish a shared contract. Keep independent behavior separate when its rules can evolve independently; do not force it into a helper with caller-specific flags or unrelated branches merely to reduce repetition.

Place the shared implementation with the responsibility that owns it. Keep feature-local helpers local and promote them only when other owners need the same contract. Shared abstractions must retain the [architecture boundaries](docs/architecture.md).

For example, measurement and drawing of the same component should use one layout calculation, and selectors and reducers should use the same eligibility rule while reducers still revalidate intents. Two dialogs with different confirmation semantics may share styling without sharing their decision logic. During extraction, preserve observable behavior, actor isolation, cancellation, request identity and resource cleanup. Verify affected callers with meaningful regressions; fewer lines alone do not demonstrate a better abstraction.

## File organization and ownership

- Keep source folders shallow and named by responsibility. Prefer small methods with explicit state transitions. Protocol error handling follows [CLI lifecycle safeguards](docs/cli-compatibility.md#protocol-lifecycle-safeguards).

### Source groups

Source ownership follows the same groups. `App/` owns application lifecycle and shared window controls; `Features/<feature>/` owns feature views and their presentation helpers; `Application/` owns workspace models, actions, reducers, effects and presentation selectors; `CodexClient/` owns `AppServer`, wire models, framing, and diagnostics; `Persistence/` owns local stores, including review markers; `Workspaces/` owns checkout lifecycle and task coordination. These folders compile into one module, so responsibility boundaries remain a code-review concern rather than separate targets.

### Application groups

Within `Application/`, use `State/` for shared models, actions, intents, identity and eligibility; `Runtime/` for stores, inputs, hydration, effect execution, persistence scheduling and operation handles; `Reducers/<feature>/` for feature transitions and their supporting values; `Composition/` for cross-feature transitions; `Presentation/` for selectors and snapshot helpers; and `Services/` for backend and filesystem service interfaces and implementations. Keep these groups shallow. `Services/Git/` owns Git comparison and baseline implementations, including captured-tree storage models that are not workspace state. `Runtime/Review/` owns Git review and summary execution. Feature-specific command models stay in `Reducers/Composer/`; review models and analysis stay in `Reducers/Review/`. Shared baseline identities and references remain in `State/`. Canonical compact turn previews belong to `State/`; their preparation contract is defined in [architecture](docs/architecture.md#state-transitions). Pure reported-patch composition belongs to `Reducers/Review/`; transcript preparation may cache its results beside the transcript views. Feature-specific presentation types stay beside their views, with shared presentation ownership in `Features/Shared/`. `Persistence/` also owns durable task workspace records; `Workspaces/` retains checkout locations, Git lifecycle and coordination.

### Feature groups

Use the [feature directory map](Sources/CodexGUI/Features/README.md) for feature views
and presentation helpers. Shared subagent avatars and attachment preparation belong to
`Features/Shared/`. `CodexClient/InlineImageData.swift` identifies inline image payloads;
`Application/Services/LocalAttachmentURL.swift` resolves local attachment paths and file URLs.
Keep these shared values independent of feature views. `App/WindowLayout/` groups pane
controls, layout policies and transitions.

### Component files and extensions

Name extension-only source and test files `OwnerType+Concern.swift`, using the exact extended type as the owner. Put extensions of different owners in separate files. A file defining a primary type keeps that type's filename and may include related supporting extensions. An extension split organizes one component; it does not establish a separate controller or responsibility boundary. Keep independent types in files named for those types. Separate effect descriptions from runtime schedulers and operation handles so each is discoverable by its name.

Use an owner-named subfolder when a component's main file and several extensions clutter a directory shared with other components. Keep the main file and its extensions together, retaining their explicit filenames. Apply this to `MainWindowController`, `NavigationViewController`, `ConversationViewController`, `WorkspaceEffectRunner`, `AppServer`, `WorkspaceCoordinatorReducer`, `TaskWorkspaceCoordinator`, `GitWorktreeManager`, and the `ApplicationStateTests` suite. Keep shared support types outside owner folders. Do not add another owner folder where an existing feature directory already groups the component clearly, or for a single small extension.

### Resources and supporting files

Scripts, documentation and resources retain their existing locations; root resources supply bundle metadata and branding, while source resources are packaged by SwiftPM.

## MVI and reducer architecture

Follow [state transitions](docs/architecture.md#state-transitions),
[ownership and recovery](docs/architecture.md#ownership-and-recovery), and
[presentation](docs/architecture.md#presentation) in the architecture guide.
File placement is defined above; runtime behavior is defined there.

## AppKit behavior and accessibility

- Keep AppKit mutations on the main actor. Parse process output and prepare long message content away from the main actor. Use Auto Layout and standard macOS controls. Give interactive controls accessible labels and keyboard access; use system colors and appearance so light and dark modes both work.

For requested redesigns, change the specified presentation while preserving unaffected
interaction and ownership contracts. For behavior-preserving refactors, apply the naming,
geometry and DRY preservation rules above.

For deferred dialogs, capture the target identity and callback when presenting, then
revalidate scope and eligibility before accepting confirmation. Selection or callback
replacement must not redirect the operation. Use one guarded completion path; see
[modal workflows](Sources/CodexGUI/Features/Navigation/NavigationViewController/NavigationViewController+ModalWorkflows.swift) and
[dialog completion](Sources/CodexGUI/Features/Navigation/TaskDeletion/TaskDeletionConfirmationPanel.swift).
Verify accessible control names, focus traversal, default actions, Escape, Return and
keypad Enter through AppKit event routing. A key-equivalent string alone does not establish
keyboard behavior; choose default actions according to the feature's contract.

For reference-based UI work, distinguish observed text/geometry from inferred behavior.
Screenshot content does not establish backend semantics or authorize unrelated changes.
Verify interaction, accessibility and appearance separately from visual similarity.
Use alignment rectangles for alignment assertions and bounds for clipping checks.

Retain semantic colors until drawing or resolve them under the owning view's
`effectiveAppearance`. Alpha-adjusted colors, attributed-string colors and layer `CGColor`
values can retain an earlier appearance; refresh them and invalidate drawing as needed.
Use the owning view's appearance during its callback; children may still have their previous
appearance. Reuse [DesktopTheme](Sources/CodexGUI/App/DesktopTheme.swift) and existing refresh paths. Anchor-following
panels use [DesktopPanelAppearanceBinding](Sources/CodexGUI/Features/Shared/DesktopPanelAppearanceBinding.swift); invalidate the binding
on dismissal and replace it when rebinding.
Appearance regressions switch an existing attached view repeatedly in both directions
through its window or ancestor, preserving relevant focus, selection, hover, text and geometry.
Do not recreate the view or manually invoke its appearance callback to simulate the change.
Keep automated assertions separate from live macOS appearance observations.

## Test organization

SwiftPM tests stay in the single `CodexGUITests` target and mirror source responsibilities: `App`, `Application`, `CodexClient`, `Persistence`, `Workspaces`, and `Features/<feature>`. Put full-window and cross-view ownership checks in `App`, backend protocol integration checks in `CodexClient`, and feature-specific view tests beside their feature group. SwiftPM discovers these subfolders automatically. Preserve suite names during file-only moves. When extracting an independent suite, update affected test filters and preserve test methods, assertions, actor isolation and serialization requirements.

Tests for a distinct responsibility use their own suite in that responsibility's test group. Reserve suite extensions for parts of the same suite grouped together in its owner folder; do not retain an unrelated suite owner solely for an old test filter.

Keep service-specific fixtures in that service group's `Support/` folder. Global test support is reserved for fixtures used across responsibility groups. Usage view tests have their own suite rather than sharing a navigation suite.

When a test group becomes crowded, use shallow subfolders named for its tested responsibilities. `App/` groups full-window checks in `Windows/`, Git review checks in `GitReview/`, and inspector integration in `Tools/`. `CodexClient/` groups AppServer integration and protocol models in `AppServer/` and `Protocol/`. Runtime tests use `Workspace/`, `Conversation/`, `ProjectContext/` and `ProjectFiles/`, alongside existing owner and support folders. Transcript tests use `Markdown/`, `TurnNavigation/`, `Preparation/`, `Layout/` and `Rows/`. Keep one suite's main file and extensions together; these folder moves preserve suite names, traits and test-host filters.

Split tests by independent contracts rather than size alone. When extracting fixtures,
preserve construction inputs and teardown order, register cleanup when resources are
acquired, and explicitly mark AppKit fixture types, including nested types, `@MainActor`.
Scenario splits must retain parameterized inputs and required event ordering; separate
`.serialized` suites do not establish mutual serialization.
For host-filter maintenance and execution, see [validation](docs/validation.md#test-host-maintenance).

## References

AppKit role references: [application lifecycle](https://developer.apple.com/documentation/appkit/nsapplication), [window controllers](https://developer.apple.com/documentation/appkit/nswindowcontroller), [view controllers](https://developer.apple.com/documentation/appkit/nsviewcontroller), [split view controllers](https://developer.apple.com/documentation/appkit/nssplitviewcontroller), and [macOS design guidance](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/).
