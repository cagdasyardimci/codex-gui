# Validation

Use [conventions](../CONVENTIONS.md#formatting-and-tooling) for formatting and [agent workflow](agent-workflow.md) for task routing.

## Automated checks

Run `make check` without `-j` for Swift formatting, the application build and tests. Do not change source or build settings during a run, or run competing builds in the same checkout. Use separate checkouts for independent builds. Apply the [test-completion requirements](#test-completion) before reporting results. See [native QA](native-qa.md#manual-preparation-and-isolation) for manual fixture isolation.

The default `make test` and the test step of `make check` run all 693 functions discovered by SwiftPM, in one process with parallel execution enabled (`PARALLEL=1`). The [completion wrapper](../Tests/run-swift-tests.py) requires a successful, nonempty Swift Testing completion summary. Tests require Swift and macOS Command Line Tools.

The SwiftPM target contains only these 693 test functions and their supporting fixtures. A direct `swift test` also discovers the same retained functions. Use unfiltered discovery when changing the inventory to check that new and renamed functions are included.

Use `make test PARALLEL=0` or `make check PARALLEL=0` to disable parallel execution. `PARALLEL` accepts only `0` or `1` and applies to named and custom selections too. Tests that intentionally change application-wide UI state use [AppKitTestIsolation](../Tests/CodexGUITests/Support/AppKitTestIsolation.swift) to coordinate native key-window and focus changes, sheets, popovers and transient panels across suites. Prefer scoped `AppKitTestIsolation.perform` inside the admitted MainActor test method, covering native construction, presentation, relevant asynchronous work, assertions and cleanup. Preserve `.serialized` on parameterized functions or their existing suites; each protected case must restore its owned native state before releasing the permit.

The `.appKitIsolation` trait remains available when exclusion must span an entire function, including all parameterized cases. Its function scope acquires before Swift Testing schedules the cases and admits the MainActor test body, so its protected interval includes that framework scheduling. Scoped acquisition avoids reserving AppKit during these admission and return hops. A trait's permit wait happens before the case's time limit; a scoped wait happens inside that limit. Keep existing case budgets rather than increasing them to hide contention.

`@MainActor` protects synchronous AppKit access; it does not require exclusive ownership of the application across suspension. Fixture-owned views, hidden windows, stores and services remain eligible for parallel execution. Inspect each fixture's own view hierarchy, retained popover content, or owned sheet or panel when locating controls. Avoid global appearance changes and application-wide window-list assertions when the contract concerns an owned fixture. Synthetic fixture windows call [prepareForTesting](../Tests/CodexGUITests/Support/WindowTestSupport.swift) before presentation: the fixture retains their lifetime and disables system opening and closing transitions. Application controls retain their own animation behavior. Native window transition acceptance belongs to launched-app verification.

Apply `@MainActor` to the methods and helpers that access actor-isolated objects. A suite-wide annotation is appropriate when its tests all require that access. Pure parsing, model construction and geometry calculations can run without it. Prepare independent files and Git repositories with [BackgroundTestWork](../Tests/CodexGUITests/Support/BackgroundTestWork.swift) before actor-bound fixture construction; it runs blocking work on a bounded utility queue without occupying the main thread or Swift's cooperative task workers. Pass only `Sendable` values across that boundary. Keep test assertions in the awaiting task, since utility operations do not inherit Swift Testing's task-local context. Use `GitTestCommandRunner.runAsync` for fixture commands called by actor-isolated tests, and retain native setup, callbacks and ordered teardown on their owning actor. An `await` does not move other synchronous work off that actor.

The scoped helper and permit queue run on `MainActor`, so an available permit can lead directly into native work without another actor hop. Waiting for a busy permit suspends the caller without blocking the main thread. Register cleanup before fallible work. Independent data preparation and backend connection can remain outside the native closure. Await only work that the assertions depend on; synchronous pane geometry does not require completion of unrelated text preparation or scroll-anchor restoration. For deferred native hover layout, await the owned synchronization task while preserving its automatic layout trigger.

Await an operation's completion, a captured task or the relevant fixture publication instead of assuming a fixed delay or number of yields is enough. When a native call has already delivered the owned callback on the same actor, assert that observed result directly; suspend for its event only while the callback is still pending. Control animation frames when asserting intermediate geometry; keep production scheduling defaults unchanged.

Event-driven fixture waits must retire their observations and callbacks when canceled. Use a local test time limit to bound scenarios that wait for mock checkpoints or publications. Inject scheduler timing when a test controls readiness through explicit gates and does not assert debounce behavior. Expensive independent expected-value calculations can run off the main thread from immutable snapshots; retain native queries and assertions on `MainActor`. Yielding between bounded native query batches provides fairness, not a readiness guarantee.

Match a readiness observation to the state that can satisfy its predicate: use owned store publications for snapshots and owned mock-service checkpoints for installed requests. Cancellation must remove and resume only the canceled gate or clock waiter. Register cleanup before fallible assertions. Finite operation handles retire immediately on cancellation; when asserting that a late response has been ignored, capture its execution tasks before retirement and await their actual return after releasing the mock response. A captured task snapshot includes only work already registered and is not a barrier for future operations.

Independent context-persistence fixtures should use private real `ProjectContextStore` directories. Stores intentionally sharing persistence within one fixture must share that directory and worker. The default application directory joins one ordered worker across stores, so using it in unrelated parallel fixtures can make readiness and whole-worker drains wait for other tests' operations. Preserve explicit shared-directory scenarios that assert this ordering.

Keep context files outside a checkout that the fixture indexes. Scoped asynchronous teardown must stop new work, release suspended mock requests, and settle accepted persistence before deleting owned directories or defaults domains. Await cleanup even if setup, an assertion, or cancellation ends the scenario.

Use a small owned checkout when constructing a native conversation fixture: project selection can eagerly start recursive file indexing. Using the host temporary directory as a checkout indexes unrelated fixtures. Keep paired stores on the same owned checkout when their assertions require overlapping checkout identity. Native wheel movement tests must present and lay out their window, locate wheel events in its viewport, and require scrollable content before awaiting movement.

For optional elapsed-time diagnostics, set `TEST_TIMING_OUTPUT` to a separate JSON file for each run:

```sh
TEST_TIMING_OUTPUT="$PWD/.build/test-timing-parallel.json" make test
TEST_TIMING_OUTPUT="$PWD/.build/test-timing-sequential.json" make test PARALLEL=0
```

[TestTiming](../Tests/CodexGUITests/Support/TestTiming.swift) records monotonic timestamps relative to one process origin, stable test IDs, span and parent-span IDs, and whether each marker executes on the main thread. Events stay in a lock-protected memory buffer; the standard test process writes the file atomically at normal exit. With the variable unset or empty, recording is disabled. A forcibly killed or crashed process may not produce a trace; a written trace does not establish a successful or complete run. Check the runner's completion summary independently.

The `.testTiming` trait records `test.function` and `test.case` scopes for selected diagnostic tests. Explicit `test.body` spans begin on entry to the actual test method; register their end defer before fixture defers so completion includes cleanup. Case-scope entry to body entry measures admission delay, including any actor scheduling on that path; it does not measure all later main-actor waits. Case spans have distinct IDs, including for parameterized functions. Body elapsed time includes asynchronous waits and is not CPU time.

For readiness waits, distinguish the producer satisfying its predicate from the waiting test resuming. [WorkspaceReadiness](../Tests/CodexGUITests/Support/WorkspaceReadiness.swift) records `workspace.readiness` spans with `satisfied` and `resumed` markers; coordinator callback adapters use equivalent markers. Fixture phase markers immediately after background preparation distinguish actor readmission from subsequent synchronous construction.

[AppKitTestIsolation](../Tests/CodexGUITests/Support/AppKitTestIsolation.swift) records `appkit.permit` spans without changing ownership: `begin` precedes entering the permit actor, `requested` precedes queueing there, `acquired` follows acquisition, and `released` follows protected execution and cleanup. `requested` to `acquired` includes queue waiting and resumption scheduling; `acquired` to `released` measures the protected interval. [GitTestCommandRunner](../Tests/CodexGUITests/Support/GitTestCommandRunner.swift) records `git.command` spans for fixture commands. Selected fixtures also mark setup and cleanup. Spans can overlap or contain other spans; do not add their durations as full-run time or label elapsed time as active CPU execution. Instrumentation adds some overhead, so compare repeated runs using the same instrumentation.

Use `native.body` spans inside scoped native closures to separate admission from protected execution. Their end defer must run after native fixture cleanup. Compare acquired-to-native-entry and native-exit-to-release intervals directly. Scoped parameterized tests record one permit per case; compare normalized function identities and case coverage as well as verifying that protected intervals remain disjoint, rather than requiring the previous number of function-scoped permits.

`BackgroundTestWork` records `fixture.io` spans around queue waiting and worker execution, with `execution.begin` and `execution.end` marking actual utility-thread work. It carries diagnostic test and parent-span context through each synchronous worker operation, so nested fixture Git spans retain their attribution. This does not restore Swift Testing's assertion context. `GitTestCommandRunner.runAsync` also marks worker execution within its `git.command` span; use those markers, rather than the caller's span entry, to verify where the blocking command ran.

### Test completion

Confirm a successful, nonempty Swift Testing completion summary and the intended test count in the output before reporting a pass. Use `swift test list` with the same toolchain flags from [Tests/Workflow.mk](../Tests/Workflow.mk) to inspect available tests when needed. The command-line runtime can exit early with status zero; the completion wrapper preserves the runner's exit status and rejects missing or zero-test completion summaries, including unmatched selections. Test counts describe test functions, including parameterized functions, rather than individual argument cases.

Run `git diff --check` for whitespace errors. Follow [README](../README.md#build-check-and-run) for bundling, then verify the signature with `codesign --verify --deep --strict --verbose=2 .build/CodexGUI.app`. These checks do not require a live model turn.

## Test-host maintenance

Use `make help` to list named selections. For example:

```sh
make test:summary
make test:navigation
make test:terminal-hover
make test:composer-appearance
make test
```

Run named selections with `make test:<group>`. Each command runs only its matching tests in one process and then stops. The default run uses no filter; named groups and `FILTER` select their configured subsets from the full inventory. `make help` lists commands and test selections. [Tests/Workflow.mk](../Tests/Workflow.mk) owns toolchain flags and explicit targets that call the shared `run-tests` function.

For a custom regular expression, use:

```sh
make test FILTER='ApprovalPolicyPopoverTests|ComposerAppearanceTests'
```

A custom selection runs through SwiftPM and the completion wrapper in one fresh process with the selected `PARALLEL` setting. Quote regular expressions to preserve shell characters and apply the [test-completion requirements](#test-completion). `FILTER` must be nonempty and is supported only by `make test`. Named group commands and `make check` reject it. `make check` validates the complete SwiftPM test inventory.

When adding or renaming tests, check unfiltered discovery and verify that configured selections still match and cover the intended cases. Focused runs add evidence but do not replace validation of the full test inventory. Do not relax assertions to make verification pass. Report failures and baseline comparisons separately.

For synthetic AppKit tests that verify a button's action routing or resulting layout, use [dispatchConfiguredAction](../Tests/CodexGUITests/Support/ControlActionTestSupport.swift) or the enabled control's `sendAction(_:to:)` with its configured action and target. Require that the action exists and dispatch succeeds, and preserve the resulting state and layout assertions. `performClick(_:)` can poll AppKit's native event queue; HIToolbox's wakeup can stop the standard SwiftPM async-main run loop before testing completes. Direct action dispatch does not establish native press animation, pointer tracking or keyboard behavior; keep those acceptance checks in [native QA](native-qa.md).

For documentation-only edits, check links and anchors, referenced paths, command syntax, whitespace and code fences. A build or app launch is normally unnecessary.

## Native and live acceptance

The optional launched-app case runs with `make test:ui` and the model-free [mock backend](mock-backend.md) by default. An overridden backend may behave differently or make model calls. This workflow occupies the interactive desktop and runs separately from `make check`. See [native QA](native-qa.md#xcode-launched-app-workflow) for preparation and evidence.

Controlled service tests and synthetic AppKit tests establish only their assertions. Live backend behavior, OS notification delivery, physical input, appearance parity and the minimum supported macOS require separate observation. Report which environment produced each result.

Verify minimum-macOS compatibility on the supported OS version. Review unexpected runtime exits separately from test outcomes.

See [CLI compatibility](cli-compatibility.md#verifying-a-cli-upgrade) for backend upgrade checks.
