# Validation

Use [conventions](../CONVENTIONS.md#formatting-and-tooling) for formatting and
[agent workflow](agent-workflow.md) for task routing.

## Automated checks

Run `make check` to validate style-driver and runner regressions, Swift formatting,
the application build and Swift Testing. Run it without `-j`: the current Makefile lists
lint, build and test as prerequisites, so parallel Make can overlap these stages.
`make test` runs the predefined shared and isolated SwiftPM test hosts serially.
Shown native windows and popovers run in separate test-host lifecycles. Each host must
exit successfully and end with a Swift Testing completion summary reporting passed tests
and suites; a zero exit code alone is insufficient.
Do not change source files or build flags during a verification run.
Each checkout uses its own `.build` directory. The current Makefile has no build-directory
override; setting `BUILD_DIRECTORY` does not change its commands. Use separate checkouts
for independent builds, and coordinate builds that share a checkout. See
[native QA](native-qa.md#preparation-and-isolation-limits) for the synthetic fixture's
runtime isolation limits.

Tests cover protocol framing and
request ownership, reducer transitions, stale
results, ordered persistence, workspace recovery, late command outcomes, cleanup and
quit barriers, transcript preparation, review and native layout.

Run `python3 scripts/check-qa-backend.py` for the isolated backend fixture checker and
`git diff --check` for whitespace errors. Follow [README](../README.md#build-check-and-run)
for bundling, then verify the signature with
`codesign --verify --deep --strict --verbose=2 .build/CodexGUI.app`.
These checks do not require a live model turn.

Ordinary-chat concurrency regressions cover shared-connection starts, interleaved output
and approvals, independent navigation and drafts, steering and Stop, background completion,
stale callbacks, relaunch recovery and aggregate quit barriers. Existing managed-checkout
tests remain part of the same gate.

Run `python3 scripts/check-concurrent-app-server.py --help` for the installed-backend
concurrency probe. It starts an isolated app-server and a localhost synthetic Responses
provider, holds two turns in one temporary checkout, interrupts one, and releases the other
to completion. It excludes account credentials and does not use remote model inference.
Its evidence establishes the exercised backend protocol behavior with that synthetic
provider; it does not establish live GUI behavior or real-model acceptance.

## Test-host maintenance

When changing suite or method identifiers, splitting tests or changing isolation needs,
inspect shared-host exclusions and isolated-host filters in
[the host runner](../scripts/run-test-hosts.py) and update
[its regression fixtures](../scripts/test-run-test-hosts.py).
Check that the exclusions and isolated filters cover the intended tests without gaps or
duplicate selection; the runner does not automatically validate this coverage.
Focused runs add evidence but do not replace the complete host sequence. Do not relax
assertions to make verification pass. Report failures and baseline comparisons separately.

For documentation-only edits, check links and anchors, referenced paths, command syntax,
whitespace and code fences. A build or app launch is normally unnecessary.

## Native and live acceptance

Use [native QA](native-qa.md) for preparation, runtime isolation and native acceptance scenarios.

Controlled service tests and synthetic AppKit tests establish their asserted behavior;
they do not establish live execution, OS notification delivery or physical input.
Live model turns, rename/archive requests, approvals, Stop, steering, complete interrupted-command recovery,
native image drag/drop, exact copied code bytes, live account usage, light/dark parity
and execution on the minimum supported macOS 14 require separate observation.
No additional native or live acceptance result is claimed by the automated checks.

The application and installed Swift Testing framework require macOS 14 or later.
Execution on the minimum supported macOS 14 remains unverified. Existing toolchain
and synthetic AppKit constraint warnings may remain even when
the tests pass. Review unexpected runtime exits separately from test outcomes.

See [CLI compatibility](cli-compatibility.md) for the tested protocol baseline and
[native QA](native-qa.md) for interaction and live acceptance requirements.

## Command and checkout safeguards

Regression coverage exercises an interrupted agent with a still-pending command,
late results from the exact command owner, stale history reads, recovered unknown
outcomes and cleanup/quit refusal. Temporary Git repositories cover clean checkout
creation, dirty and ignored-file refusal, ownership mismatches, retained branches,
failed-removal recovery and independent task identities. Native observation of these
workflows remains a separate acceptance step.

## Release checklist

Follow the [CLI upgrade procedure](cli-compatibility.md#verifying-a-cli-upgrade) for backend changes
and the native/live acceptance requirements above for notification, model and platform evidence.
