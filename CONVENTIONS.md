# Swift and AppKit conventions

These conventions apply to the Swift source and tests.

## Formatting and tooling

Run `make format` to apply the style. Follow [validation](docs/validation.md#automated-checks) for build and test commands. Install SwiftFormat with `brew install swiftformat`; its minimum version is declared in [.swiftformat](.swiftformat). Python 3 runs the checked-in driver. The configuration enables only layout rules, avoiding automatic changes to declarations, expressions, or literals. Use the Makefile commands so the supplemental rules also run.

[.swiftformat](.swiftformat) owns mechanical layout settings; [the driver](scripts/swift-style.py) owns supplemental checks. Do not duplicate their rule inventory here or run Apple's `swift-format`, whose brace policy conflicts with this project. The driver preserves non-whitespace tokens, so manually split overlong literals without changing their text, escapes or interpolation. Preserve meaningful phase boundaries rather than treating every blank line as interchangeable.

In a checkout with unrelated edits, apply formatting only to your Swift paths using `python3 scripts/swift-style.py <file-or-directory>` and review the resulting diff.

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

### Responsibility boundaries

Use the [source tree](Sources/CodexGUI/) to locate existing owners rather than maintaining a parallel directory inventory. App-shell coordination stays in App; feature views and view-facing helpers stay in Features; reusable controls and presentation subsystems stay in UI; canonical state, transitions and shared eligibility stay in Application; wire decoding stays in CodexClient; durable local storage stays in Persistence; checkout lifecycle stays in Workspaces. These are review boundaries within one module, not separate compilation targets.

Within Application, keep feature transitions with their reducers, cross-feature transitions in Composition and operational handles in Runtime. Services define backend/filesystem interfaces; presentation selectors project canonical values without taking native view ownership. Canonical values shared by persistence, reducers and protocol requests belong in State. Do not move feature-local presentation into application state merely because several views use it.

Place reusable presentation in [UI](Sources/CodexGUI/UI/) only when callers share its contract. Cross-feature use alone does not make domain-specific code generic: keep feature projections and navigation with their owning feature or app-shell coordinator, and shared application value formatting in Application/Presentation. Keep independent feature lifetimes local. Design catalogues belong in App/Design and reusable native controls in [UI/Components](Sources/CodexGUI/UI/Components/). Follow [architecture](docs/architecture.md) for behavioral boundaries and [interface styling](docs/interface-styling.md#component-ownership) for complete component reuse.

### Component files and extensions

Name extension-only source and test files `OwnerType+Concern.swift`, using the exact extended type as the owner. Put extensions of different owners in separate files. A file defining a primary type keeps that type's filename and may include related supporting extensions. An extension split organizes one component; it does not establish a separate controller or responsibility boundary. Keep independent types in files named for those types. Separate effect descriptions from runtime schedulers and operation handles so each is discoverable by its name.

Use an owner-named subfolder when a component's main file and several extensions clutter a directory shared with other components. Keep the main file and its extensions together, retaining their explicit filenames. Keep shared support types outside owner folders. Do not add another owner folder where an existing feature directory already groups the component clearly, or for a single small extension.

### Resources and supporting files

Scripts, documentation and resources retain their existing locations; root resources supply bundle metadata and branding, while source resources are packaged by SwiftPM.

## MVI and reducer architecture

Follow [state transitions](docs/architecture.md#state-transitions), [ownership and recovery](docs/architecture.md#ownership-and-recovery), and [presentation](docs/architecture.md#presentation) in the architecture guide.

## AppKit behavior and accessibility

- Keep AppKit mutations on the main actor. Parse process output and prepare long message content away from the main actor. Use Auto Layout and standard macOS controls. Give interactive controls accessible labels and keyboard access; use system colors and appearance so light and dark modes both work.

For requested redesigns, change the specified presentation while preserving unaffected interaction and ownership contracts. For behavior-preserving refactors, apply the naming, geometry and DRY preservation rules above.

For deferred dialogs, capture the target identity and callback when presenting, then revalidate scope and eligibility before accepting confirmation. Selection or callback replacement must not redirect the operation. Use one guarded completion path; see [modal workflows](Sources/CodexGUI/Features/Navigation/NavigationViewController/NavigationViewController+ModalWorkflows.swift) and [dialog completion](Sources/CodexGUI/Features/Navigation/TaskDeletion/TaskDeletionConfirmationPanel.swift). Verify accessible control names, focus traversal, default actions, Escape, Return and keypad Enter through AppKit event routing. A key-equivalent string alone does not establish keyboard behavior; choose default actions according to the feature's contract.

For reference-based UI work, follow [reference acceptance](docs/interface-styling.md#reference-and-acceptance). Use alignment rectangles for alignment assertions and bounds for clipping checks.

Retain semantic colors until drawing or resolve them under the owning view's `effectiveAppearance`. Alpha-adjusted colors, attributed-string colors and layer `CGColor` values can retain an earlier appearance; refresh them and invalidate drawing as needed. Use the owning view's appearance during its callback; children may still have their previous appearance. Reuse [AppKitColorTokens](Sources/CodexGUI/App/Design/AppKitColorTokens.swift), [AppKitColorResolution](Sources/CodexGUI/App/Design/AppKitColorResolution.swift) and existing refresh paths. Reuse [DesktopAttributedTitleButton](Sources/CodexGUI/UI/Components/Controls/DesktopAttributedTitleButton.swift) for retained attributed button titles. Anchor-following panels use [DesktopPanelAppearanceBinding](Sources/CodexGUI/UI/Components/Panels/DesktopPanelAppearanceBinding.swift); invalidate the binding on dismissal and replace it when rebinding. Appearance regressions switch an existing attached view repeatedly in both directions through its window or ancestor, preserving relevant focus, selection, hover, text and geometry. Do not recreate the view or manually invoke its appearance callback to simulate the change. Keep automated assertions separate from live macOS appearance observations.

## Test organization

Keep test code, fixtures and test tools under `Tests/`. Keep build, bundling and formatting utilities in `scripts/`. Generated evidence belongs in ignored build or temporary directories. Do not add regression suites for test runners, evidence validators or formatting utilities.

Keep SwiftPM tests in the single `CodexGUITests` target and mirror source responsibilities. Put cross-view checks with their application owner and feature-specific tests with their feature. Preserve suite names during file-only moves. When extracting an independent suite, preserve test methods, assertions, actor isolation and serialization requirements.

Tests for a distinct responsibility use their own suite in that responsibility's test group. Reserve suite extensions for parts of the same suite grouped together in its owner folder.

Keep service-specific fixtures in that service group's `Support/` folder. Global test support is reserved for fixtures used across responsibility groups.

When a test group becomes crowded, use shallow subfolders named for its tested responsibilities. Keep one suite's main file and extensions together.

Split tests by independent contracts rather than size alone. When extracting fixtures, preserve construction inputs and teardown order, register cleanup when resources are acquired, and explicitly mark AppKit fixture types, including nested types, `@MainActor`. Scenario splits must retain parameterized inputs and required event ordering; separate `.serialized` suites do not establish mutual serialization. For test execution, see [validation](docs/validation.md#test-host-maintenance).

## References

AppKit role references: [application lifecycle](https://developer.apple.com/documentation/appkit/nsapplication), [window controllers](https://developer.apple.com/documentation/appkit/nswindowcontroller), [view controllers](https://developer.apple.com/documentation/appkit/nsviewcontroller), [split view controllers](https://developer.apple.com/documentation/appkit/nssplitviewcontroller), and [macOS design guidance](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/).
