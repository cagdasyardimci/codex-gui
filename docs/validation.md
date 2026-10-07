# Validation

Use [conventions](../CONVENTIONS.md#formatting-and-tooling) for formatting and [agent workflow](agent-workflow.md) for task routing.

## Automated checks

Run `make check` without `-j` for Swift formatting, the application build and tests. Do not change source or build settings during a run, or run competing builds in the same checkout. Use separate checkouts for independent builds. Inspect the output to confirm the intended tests executed and completed; a command exit alone can miss an empty selection or incomplete host. See [native QA](native-qa.md#manual-preparation-and-isolation) for manual fixture isolation.

Run `git diff --check` for whitespace errors. Follow [README](../README.md#build-check-and-run) for bundling, then verify the signature with `codesign --verify --deep --strict --verbose=2 .build/CodexGUI.app`. These checks do not require a live model turn.

## Test-host maintenance

Use `make test-groups` to list named selections. For example:

```sh
make test TEST_SUITE=summary
make test TEST_SUITE=navigation
make test TEST_SUITE=terminal-hover
make test
make test-suites
```

Refer to the Makefile for current selections and isolation.

When renaming tests, check that the configured selections still match and cover the intended cases. Inspect executed counts; an empty filter can exit successfully. Focused runs add evidence but do not replace full verification. Do not relax assertions to make verification pass. Report failures and baseline comparisons separately.

For documentation-only edits, check links and anchors, referenced paths, command syntax, whitespace and code fences. A build or app launch is normally unnecessary.

## Native and live acceptance

The optional launched-app case runs with `make ui-test` and the model-free [mock backend](mock-backend.md) by default. An overridden backend may behave differently or make model calls. This workflow occupies the interactive desktop and runs separately from `make check`. See [native QA](native-qa.md#xcode-launched-app-workflow) for preparation and evidence.

Controlled service tests and synthetic AppKit tests establish only their assertions. Live backend behavior, OS notification delivery, physical input, appearance parity and the minimum supported macOS require separate observation. Report which environment produced each result.

Verify minimum-macOS compatibility on the supported OS version. Review unexpected runtime exits separately from test outcomes.

See [CLI compatibility](cli-compatibility.md#verifying-a-cli-upgrade) for backend upgrade checks.
