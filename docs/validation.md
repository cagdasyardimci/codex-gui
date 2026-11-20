# Validation

This guide owns check selection, test-fixture discipline and evidence interpretation. Use [conventions](../CONVENTIONS.md#formatting-and-tooling) for formatting and [native QA](native-qa.md) for launched-app procedures.

## Automated checks

### Rust desktop core

Install [rustup](https://rustup.rs/) and run `cargo check-core` from [the desktop workspace](../desktop/Cargo.toml). The workspace pins the Rust toolchain and checks the core against its committed lockfile.

The [desktop workflow](../.github/workflows/desktop-core.yml) checks the core and validates the [portable fixture launch](mock-backend.md#portable-desktop-fixture) on macOS, Windows, and Ubuntu.

### Tauri diagnostic shell

Install the [Tauri system prerequisites](https://v2.tauri.app/start/prerequisites/) for the host OS and use the pinned Node and pnpm versions. From the repository root, run `pnpm --dir desktop/frontend install --frozen-lockfile` and `pnpm --dir desktop/frontend tauri dev`. The beta initializes its data and worktree root under its own application identity so it can launch alongside AppKit.

The desktop build job type-checks the frontend and compiles the host with the embedded production frontend. Reproduce it with `pnpm --dir desktop/frontend check` and `pnpm --dir desktop/frontend tauri build --debug --no-bundle -- --locked`. Build and install artifacts using the [Tauri package guide](desktop-packaging.md). After the build, pass the executable to [the WebView fixture check](../desktop/fixtures/verify_webview_fixture.py). The check requires the mounted frontend to reconstruct and render exact Unicode text for two interleaved items across a reload. Run it under `xvfb-run -a` on Ubuntu when a desktop display is unavailable. Pass `--media` to verify the secure WebView context and audio APIs. The probe requires repeatable Opus and data channel negotiation when the engine exposes peer connections. It records the capability separately on Ubuntu so media integration can account for the packaged WebKitGTK build. Qualify microphone grants and audible provider audio in [native and live acceptance](#native-and-live-acceptance).

After changing the [workspace IPC contract](../desktop/core/src/ipc.rs), regenerate the frontend types with `cargo run --manifest-path desktop/Cargo.toml --locked -p codex-gui-core --example export_workspace_ipc > desktop/frontend/src/generated/workspace.ts`. Core tests compare the checked-in output against Rust. The launched WebView fixture checks typed grant rejection and workspace snapshot recovery after a revision gap and renderer reload.

Run the [installed history fixture](../desktop/fixtures/verify_history_fixture.py) with the packaged executable. It exercises chat switching, draft writes, composer focus and synthetic composition, a competing writer, cold resume streaming, manual reconnect, and native process restart. It verifies grouped command output, selection preservation when revealing a saved response action, checkout-scoped image dependencies, and ordered previews in a saved image-only prompt. It checks offline Markdown rendering, deferred math and diagram rendering during streaming, and preview release when a chat is retired. It checks the bounded preview and committed jump for separate unloaded turns, the reading anchor when older history arrives, and path index reuse across chats. A larger history checks the mount and retention bounds, selection outside the visible window, and targeted restoration of an evicted anchor. The fixture verifies both drafts survive clearing the checkout and checks the backend trace for thread or turn creation. Physical IME acceptance belongs to the [native and live checks](#native-and-live-acceptance).

The [installed account fixture](../desktop/fixtures/verify_account_fixture.py) exercises cancellation, an obsolete completion, the successful account and model refresh, and retained draft text. It replaces the browser handoff with a local fixture and leaves the disposable Codex profile empty. Use the release-candidate checks for real ChatGPT sign-in.

The [installed composer attachment fixture](../desktop/fixtures/verify_composer_attachment_fixture.py) supplies fixture results to the picker and drop intake and dispatches an image paste through the WebView. It changes chats while a picker result is pending, verifies identical stored bytes on an image-only Send, and checks image and file reuse with the original draft text intact. Physical picker, clipboard and drag interactions belong to [native and live acceptance](#native-and-live-acceptance).

Run the same fixture with `--annotations` to verify Cancel, point placement at two zoom levels, restoration after a chat switch, and rejection when a save carries another image digest. The outgoing turn must retain the three original image bytes in order and number the comments with the unannotated image included in the count.

Run it with `--context` to verify the plus selection, @ token replacement following a Unicode grapheme, rejection of retired choices, and the exact outgoing file mention, code excerpt, project context and skill.

Run it with `--settings` to verify model-specific effort and speed, cancellation and retirement of Full Access confirmation, and the exact settings in three captured Send requests across a pending change and a return to configured permissions.

The [installed turn checkpoint](../desktop/fixtures/verify_turn_fixture.py) uses two fresh profiles. One recovers an ambiguous submission, answers a captured approval and questions, verifies the totals from the backend's attributed edit report, and opens the Git patch for the resulting checkout edit. The other switches chats and reloads the WebView during an active turn, then checks that stopping it targets the original owner and preserves that chat's draft. The package workflow also runs the installed account and history fixtures for first-launch sign-in and draft restoration. Use release-candidate acceptance for the real-account workflow.

The [installed diff fixture](../desktop/fixtures/verify_diff_fixture.py) creates its own Git checkout. It verifies a tracked edit and an untracked patch with Unicode names, checks that selecting a file triggers the patch request, and compares the Git index and source bytes before and after the read.

The [installed quit fixture](../desktop/fixtures/verify_quit_fixture.py) injects a draft write failure and cancels native Close during a turn. It runs Stop All and application Quit across two checkouts, exercising a turn that completes during confirmation and a command that exits after its turn. It checks captured interrupts, durable drafts, and unresolved execution evidence after exit.

### Swift AppKit

Run `make check` without `-j`. Keep source and build settings stable during a run; competing builds need separate checkouts because commands share the build directory. [Makefile](../Makefile) and [Tests/Workflow.mk](../Tests/Workflow.mk) define commands, toolchain flags and selections. Use `make help` to discover them rather than maintaining a separate command inventory.

Use `make test:<group>` for a named selection, or `make test FILTER='SuiteOne|SuiteTwo'` for a custom regular expression. Quote filters. `FILTER` is supported only by `make test`; omit it for a full check. Use `PARALLEL=0` when a sequential run is needed. Focused results do not replace full-inventory validation.

When adding or renaming tests, inspect unfiltered discovery with the toolchain flags in `Tests/Workflow.mk`, then verify that configured selections still cover the intended cases. Do not hard-code current test counts in guides. Do not relax assertions to make verification pass; report failures and baseline comparisons separately.

#### Test completion

Confirm a successful, nonempty Swift Testing completion summary and the intended selection before reporting a pass. A command-line runtime can exit early with status zero, so exit status alone is insufficient. The [completion wrapper](../Tests/run-swift-tests.py) rejects missing or zero-test summaries. Counts describe test functions, including parameterized functions, rather than individual argument cases.

Run `git diff --check` for whitespace. For bundled-app changes, follow [bundling](../README.md#build-check-and-run) and verify the result with `codesign --verify --deep --strict --verbose=2 .build/CodexGUI.app`.

For documentation-only changes, check local links and anchors, referenced paths, command syntax, whitespace and code fences. Builds and app launches are normally unnecessary. The [Markdown benchmark](markdown-benchmark.md) is a rendering corpus: intentional line breaks, unsupported syntax and example links are sample content rather than guide formatting or working references.

## Test-host maintenance

`@MainActor` serializes synchronous AppKit access but does not grant exclusive application ownership across suspension. Use [AppKitTestIsolation](../Tests/CodexGUITests/Support/AppKitTestIsolation.swift) for application-wide focus, key-window, sheet and transient-panel changes. Prefer a scoped permit covering native construction through cleanup; use the function trait only when exclusion must span the entire function. Follow [test organization](../CONVENTIONS.md#test-organization) when changing suite or parameterized-case boundaries.

Inspect fixture-owned hierarchies instead of global window lists, and avoid global appearance changes for local contracts. Prepare synthetic windows with [WindowTestSupport](../Tests/CodexGUITests/Support/WindowTestSupport.swift). Keep fixture animations distinct from production window-transition acceptance.

Move independent blocking file and Git preparation off the main actor through [BackgroundTestWork](../Tests/CodexGUITests/Support/BackgroundTestWork.swift) and [GitTestCommandRunner](../Tests/CodexGUITests/Support/GitTestCommandRunner.swift). Transfer only Sendable values and keep assertions in the awaiting test task: utility work does not inherit Swift Testing's assertion context. Awaiting a helper does not itself move synchronous work off the calling actor.

Await owned publications, checkpoints or captured task completion rather than fixed sleeps or yield counts. Match the observation to the predicate: store publication for state, service checkpoints for installed requests. Cancellation must retire only the canceled observation or waiter. Capture tasks before operation retirement when checking rejection of late responses; a task snapshot is not a barrier for work registered later. Await only work relevant to the assertion, and control scheduling when testing intermediate animation geometry.

Register cleanup when acquiring resources, before fallible work. Teardown must stop producers, release suspended mock requests, settle accepted writes and then remove directories or defaults domains. Await it after failure or cancellation too. Give independent persistence fixtures private directories; intentionally shared stores must share their directory and worker. Keep context files outside the indexed checkout and use a small owned repository rather than a shared temporary-directory root.

For synthetic button routing, require a configured action and successful [direct dispatch](../Tests/CodexGUITests/Support/ControlActionTestSupport.swift). `performClick(_:)` can poll AppKit's event queue and stop the SwiftPM async-main run loop before tests complete. Direct dispatch establishes routing; native tracking, animation and keyboard acceptance require [launched-app observation](native-qa.md). Wheel tests must present and lay out their owned window, target its viewport and establish scrollable content before awaiting movement.

### Timing diagnostics

Set `TEST_TIMING_OUTPUT` to a distinct JSON file for each diagnostic run. [TestTiming](../Tests/CodexGUITests/Support/TestTiming.swift) and the instrumented helpers define available spans and markers. A crash or forced termination may leave no trace; a trace does not prove successful completion.

Compare repeated runs with the same instrumentation and case coverage. Elapsed spans include waiting and may overlap; do not sum them as run time or call them CPU time. Distinguish producer readiness from waiter resumption, actor admission from native execution, and worker queue time from blocking execution. Preserve cleanup inside measured fixture intervals and verify that protected AppKit intervals remain disjoint when changing isolation scope.

## Native and live acceptance

For the Tauri migration, run automated checks and installed fixtures during implementation. Consolidate the remaining real account, provider, and physical-device checks on the release candidates before cutover.

`make test:ui` runs separately from `make check` and occupies the interactive desktop. Use [native QA](native-qa.md#xcode-launched-app-workflow) for setup, isolation and artifact review. An overridden backend can make model calls; see the [mock backend](mock-backend.md) for the default.

Controlled-service and synthetic AppKit results establish only their asserted behavior. Live backend operation, OS notification delivery, audible sound, physical input, visual parity and minimum-supported-macOS behavior require separate observation in those environments. State which environment produced each result, preserve failures and review unexpected runtime exits separately.

For CLI upgrades, follow the [compatibility procedure](cli-compatibility.md#verifying-a-cli-upgrade).
