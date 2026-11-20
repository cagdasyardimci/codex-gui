# Working on Codex GUI

Start at [AGENTS.md](../AGENTS.md) for working rules and completion reporting. This guide owns the task procedure and documentation routes. Detailed contracts belong to the guides below; source and scripts establish their implementation.

## Documentation map

| Task or question | Owning document or resource |
| --- | --- |
| Product overview, requirements, dependencies, bundling and launch | [README](../README.md) |
| Tauri beta artifacts, installation, platform support and signing | [Desktop packaging](desktop-packaging.md) |
| Swift workflow parity and Mac data disposition | [Tauri parity and Mac import baseline](tauri-parity.md) |
| Swift formatting, naming, DRY, file placement and test organization | [Conventions](../CONVENTIONS.md) |
| Native controls, dialogs, accessibility and appearance | [AppKit conventions](../CONVENTIONS.md#appkit-behavior-and-accessibility) |
| Shared presentation boundaries, adaptation rationale and UI references | [Interface styling](interface-styling.md) |
| State transitions, effects, async ownership, execution and recovery | [Architecture](architecture.md) |
| Transcript residency and Git editing-turn identity | [Residency](architecture.md#conversation-content-residency), [latest Git turn](architecture.md#recorded-latest-git-turn) |
| CLI version assessment, capability claims, framing and protocol safeguards | [CLI compatibility](cli-compatibility.md) |
| Configuration semantics and Settings capability boundaries | [Settings](settings.md) |
| Remote host enablement, pairing, device management and lifetime | [Remote access](remote-access.md) |
| Composer commands, context mentions and lifecycle | [Slash commands](slash-commands.md) |
| Transcript activity grouping and disclosure | [Activity presentation](activity-presentation-design.md) |
| Automated checks, host-filter maintenance and evidence requirements | [Validation](validation.md) |
| Controlled app-server protocol and mock scenarios | [Mock backend](mock-backend.md) |
| Synthetic app preparation and native acceptance scenarios | [Native QA](native-qa.md) |
| Exact build/test commands and dependency declarations | [Makefile](../Makefile), [Package.swift](../Package.swift) |
| Markdown rendering sample corpus | [Benchmark](markdown-benchmark.md) |
| Offline math and diagram dependencies, generation and updates | [Markdown resources](markdown-resources.md) |

Read conventions before implementation, architecture before state/runtime changes, and validation before choosing checks or interpreting results. Then read the relevant feature or protocol guide. Links into source identify owners to inspect, not additional standing rules.

## AppKit maintenance through cutover

The repository maintainer (`cagdasyardimci`) owns the Swift reference, its [build entry point](../Makefile), the AppKit checks, and the Swift documentation through Mac cutover. The initial reference is [`c082455`](https://github.com/cagdasyardimci/codex-gui/commit/c0824558b060d90a6486c3aef743877677f0d4f1).

Qualify correctness and security fixes in each edition that implements the affected behavior. For a Swift fix to a workflow still being ported, record the corrected behavior in the owning fixture or Tauri acceptance check before accepting that workflow. When advancing the Swift reference, record the previous and new revisions, the affected workflows, and which fixture or visual evidence must be refreshed. Follow [validation](validation.md) for the checks that support the new reference.

At one-way cutover, tag the final Swift source and retain its build instructions, dependency pins, and historical QA evidence. Route current support, build, and migration guidance to Tauri. Preserve the original import source and recover migrated and newer work in Tauri.

## Deliver and maintain

Review the scoped diff, including new files that ordinary `git diff` does not show. When commits are requested, stage explicit paths or reviewed hunks, inspect the staged diff, and group commits by responsibility and dependency. History rewriting requires explicit task authorization. Deliver using the entry point's [completion report](../AGENTS.md#completion-report).

Update this map when topic ownership changes. Keep guides focused on contracts, rationale and procedures that cannot be clearly recovered from source. Link to the owning code for declarations, constants, control inventories, field mappings and algorithm walkthroughs; do not mirror them in prose. Cross-reference another guide instead of restating its policy. Do not add change-history narratives, past test results, test-case descriptions, coverage inventories, temporary artifacts or session-specific preferences. Tests document their own behavior; guides describe execution requirements and evidence interpretation.
