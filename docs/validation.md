# Validation

This guide owns check selection, test-fixture discipline and evidence interpretation. Use [conventions](../CONVENTIONS.md#formatting-and-tooling) for formatting and [native QA](native-qa.md) for launched-app procedures.

## Automated checks

Run `make check` without `-j`. Keep source and build settings stable during a run; competing builds need separate checkouts because commands share the build directory. [Makefile](../Makefile) and [Tests/Workflow.mk](../Tests/Workflow.mk) define commands, toolchain flags and selections. Use `make help` to discover them rather than maintaining a separate command inventory.

Use `make test:<group>` for a named selection, or `make test FILTER='SuiteOne|SuiteTwo'` for a custom regular expression. Quote filters. `FILTER` is supported only by `make test`; omit it for a full check. Use `PARALLEL=0` when a sequential run is needed. Focused results do not replace full-inventory validation.

When adding or renaming tests, inspect unfiltered discovery with the toolchain flags in `Tests/Workflow.mk`, then verify that configured selections still cover the intended cases. Do not hard-code current test counts in guides. Do not relax assertions to make verification pass; report failures and baseline comparisons separately.

### Test completion

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

`make test:ui` runs separately from `make check` and occupies the interactive desktop. Use [native QA](native-qa.md#xcode-launched-app-workflow) for setup, isolation and artifact review. The default [mock backend](mock-backend.md) is model-free; an overridden backend can make model calls.

Controlled-service and synthetic AppKit results establish only their asserted behavior. Live backend operation, OS notification delivery, audible sound, physical input, visual parity and minimum-supported-macOS behavior require separate observation in those environments. State which environment produced each result, preserve failures and review unexpected runtime exits separately.

For CLI upgrades, follow the [compatibility procedure](cli-compatibility.md#verifying-a-cli-upgrade).
