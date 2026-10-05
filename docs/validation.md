# Validation

## Automated checks

Run `make check` to validate style-driver regressions, Swift formatting, the application
build and Swift Testing. Native popover layout tests run in a separate test-host lifecycle.
The runner reports the executed test and suite counts. Tests cover protocol framing and
request ownership, reducer transitions, stale
results, ordered persistence, workspace recovery, late command outcomes, cleanup and
quit barriers, transcript preparation, review and native layout.

Run `python3 scripts/check-qa-backend.py` for the isolated backend fixture checker and
`git diff --check` for whitespace errors. `scripts/bundle.sh` creates and ad hoc signs
the development app bundle. These checks do not require a live model turn.

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

## Native and live acceptance

Use [native QA](native-qa.md) for a fresh isolated synthetic app-server and disposable
Git fixture. Verify exact window frames, composer focus and context restoration,
reading position during streaming, approval ownership, independent Stop and steering,
late command cleanup protection, normal quit/relaunch and retained worktree branches.

Controlled service tests and synthetic AppKit tests establish their asserted behavior;
they do not establish live execution, OS notification delivery or physical input.
Live model turns, rename/archive requests, approvals, Stop, steering, complete interrupted-command recovery,
native image drag/drop, exact copied code bytes, live account usage, light/dark parity
and macOS 13 execution require separate observation. No additional native or live
acceptance result is claimed by the automated checks.

The application targets macOS 13; the installed Swift Testing framework targets macOS
14. Existing toolchain and synthetic AppKit constraint warnings may remain even when
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

Before using a new CLI version, regenerate and inspect its app-server schemas, run the
fixture and automated checks, then exercise recovery in a disposable repository. Keep
notification, live-model and platform acceptance evidence separate from source tests.
