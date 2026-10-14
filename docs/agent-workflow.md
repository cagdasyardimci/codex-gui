# Working on Codex GUI

Start at [AGENTS.md](../AGENTS.md) for working rules and completion reporting. This guide owns the task procedure and documentation routes. Detailed contracts belong to the guides below; source and scripts establish their implementation.

## Documentation map

| Task or question | Owning document or resource |
| --- | --- |
| Product overview, requirements, dependencies, bundling and launch | [README](../README.md) |
| Swift formatting, naming, DRY, file placement and test organization | [Conventions](../CONVENTIONS.md) |
| Native controls, dialogs, accessibility, appearance and UI references | [AppKit conventions](../CONVENTIONS.md#appkit-behavior-and-accessibility) |
| Shared palette, reference styling and component geometry | [Interface styling](interface-styling.md) |
| Feature directories and view ownership | [Feature map](../Sources/CodexGUI/Features/README.md) |
| State transitions, effects, async ownership, execution and recovery | [Architecture](architecture.md) |
| Transcript residency and Git editing-turn identity | [Residency](architecture.md#conversation-content-residency), [latest Git turn](architecture.md#recorded-latest-git-turn) |
| CLI version assessment, capability claims, framing and protocol safeguards | [CLI compatibility](cli-compatibility.md) |
| Composer slash-command syntax and lifecycle | [Slash commands](slash-commands.md) |
| Transcript activity grouping and disclosure | [Activity presentation](activity-presentation-design.md) |
| Automated checks, host-filter maintenance and evidence requirements | [Validation](validation.md) |
| Controlled app-server protocol and mock scenarios | [Mock backend](mock-backend.md) |
| Synthetic app preparation and native acceptance scenarios | [Native QA](native-qa.md) |
| Exact build/test commands and dependency declarations | [Makefile](../Makefile), [Package.swift](../Package.swift) |

Read conventions before implementation, architecture before state/runtime changes, and validation before choosing checks or interpreting results. Then read the relevant feature or protocol guide. Links into source identify owners to inspect, not additional standing rules.

## Inspect the checkout

Begin with bounded reads:

```sh
git status --short
git diff --stat
git diff --cached --stat
rg --files Sources Tests docs scripts
```

Use these results and the documentation map to trace the affected owners, callers and tests. Follow the entry point's [working rules](../AGENTS.md#working-rules) for source inspection, checkout isolation and preserving unrelated work.

## Implement and verify

Read the owning feature or protocol contract before implementing the change. Apply [formatting and tooling](../CONVENTIONS.md#formatting-and-tooling) through the conventions.

Choose checks and evidence requirements through [validation](validation.md), including its routes to native acceptance.

## Deliver and maintain

Review the scoped diff, including new files that ordinary `git diff` does not show. When commits are requested, stage explicit paths or reviewed hunks, inspect the staged diff, and group commits by responsibility and dependency. History rewriting requires explicit task authorization. Deliver using the entry point's [completion report](../AGENTS.md#completion-report).

Update this map when topic ownership changes. Keep guides focused on current contracts, rationale and procedures. Do not add change-history narratives, past test results, test-case descriptions, coverage inventories, temporary artifacts or session-specific preferences. Tests document their own behavior; guides describe execution requirements and evidence interpretation.
