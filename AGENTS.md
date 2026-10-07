# Agent entry point

This file applies throughout the repository. Follow the current task instructions and use [the agent workflow](docs/agent-workflow.md) to select the documents for your task. Each topic has one owning guide in its documentation map. The guides describe the current implementation, its contracts and the procedures for working on it.

## Working rules

- Inspect Git status and the affected code before editing. Preserve unrelated tracked, untracked, ignored, staged and IDE files. Do not reset, stash, clean, broadly stage or rewrite history to simplify a dirty checkout.
- Keep changes within the requested scope. Work in the current checkout unless the task requires isolation; coordinate shared source, build directory, index and HEAD changes.
- Group independent, bounded, non-conflicting `functions.exec`-eligible calls in one execution. Use `Promise.allSettled` for independent diagnostics or reads when partial results are useful, and inspect every result. Use `Promise.all` only when any failure invalidates the stage; it does not cancel calls already running. Keep dependencies, adaptive investigations, waits, resumptions, approvals, large outputs and conflicting mutations sequential. Tool availability and concurrency do not expand the task scope.
- Use `rg` and `rg --files` to find owners. Read the component and its tests before editing.
- Follow the [DRY principle](CONVENTIONS.md#dry-principle) when considering shared code.
- Update the topic's owning guide when its contract changes. Add routes from other documents rather than copying the same rule into several places.

## Completion report

State what changed, why, which checks ran and their outcomes, and any required acceptance that remains unverified. Link changed files. Do not describe inspected tests as executed, or synthetic fixtures as live GUI or real-model evidence. Interpret results according to [validation](docs/validation.md).
