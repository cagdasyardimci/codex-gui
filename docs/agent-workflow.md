# Working on Codex GUI

Start at [AGENTS.md](../AGENTS.md) for working rules and completion reporting.
This guide owns the task procedure and documentation routes. Detailed contracts belong to
the guides below; source and scripts establish their implementation.

## Documentation map

| Task or question | Owning document or resource |
| --- | --- |
| Product overview, requirements, dependencies, bundling and launch | [README](../README.md) |
| Swift formatting, naming, DRY, file placement and test organization | [Conventions](../CONVENTIONS.md) |
| Native controls, dialogs, accessibility, appearance and UI references | [AppKit conventions](../CONVENTIONS.md#appkit-behavior-and-accessibility) |
| Feature directories and view ownership | [Feature map](../Sources/CodexGUI/Features/README.md) |
| State transitions, effects, async ownership, execution and recovery | [Architecture](architecture.md) |
| Transcript residency and Git editing-turn identity | [Residency](architecture.md#conversation-content-residency), [latest Git turn](architecture.md#recorded-latest-git-turn) |
| CLI version assessment, capability claims, framing and protocol safeguards | [CLI compatibility](cli-compatibility.md) |
| Composer slash-command syntax and lifecycle | [Slash commands](slash-commands.md) |
| Transcript activity grouping and disclosure | [Activity presentation](activity-presentation-design.md) |
| Automated checks, host-filter maintenance and evidence requirements | [Validation](validation.md) |
| Synthetic app preparation and native acceptance scenarios | [Native QA](native-qa.md) |
| Exact build/test commands and dependency declarations | [Makefile](../Makefile), [Package.swift](../Package.swift) |

Read conventions before implementation, architecture before state/runtime changes, and
validation before choosing checks or interpreting results. Then read the relevant feature
or protocol guide. Links into source identify owners to inspect, not additional standing rules.

## Inspect the checkout

Begin with bounded reads:

```sh
git status --short
git diff --stat
git diff --cached --stat
rg --files Sources Tests docs scripts
```

Read affected working-tree files and both staged and unstaged diffs. Use `rg` to locate
current owners and trace their callers, state transitions and tests.
Resolve a stable source version or isolated checkout if concurrent work prevents consistent
verification. Preserve unrelated changes according to the entry point's working rules.

## Implement and verify

Locate the owning source and corresponding tests using the conventions and feature map.
Trace the changed action through the relevant architecture or protocol contract before
editing. Apply formatting through the conventions' tooling procedure, including its
scoped command when the checkout contains unrelated edits.

Choose checks through validation. For native work, use its acceptance routes into the QA
guide. Keep the source version stable and record the evidence required by those guides.

## Deliver and maintain

Review the scoped diff. Check new files explicitly because ordinary `git diff` omits
untracked additions. If committing is part of the task, stage explicit paths or reviewed
hunks and inspect the staged diff. Group commits by responsibility and dependency while
preserving unrelated index entries. History rewriting requires explicit task authorization.
Use the entry point's [completion report](../AGENTS.md#completion-report).

Change the owning guide when a rule changes and update this map if ownership changes.
Document the current implementation and working rules. Do not add change-history narratives,
past test results, temporary artifacts or session-specific preferences.
