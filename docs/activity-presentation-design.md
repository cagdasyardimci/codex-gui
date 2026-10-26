# Conversation activity presentation

This guide records why activity is grouped and what its projection must preserve. Current labels, icons, geometry and disclosure mechanics live in [UI/Transcript](../Sources/CodexGUI/UI/Transcript/).

## Grouping and disclosure

Group consecutive command activities within a turn to reduce visual noise while retaining each observation. User messages, assistant commentary, image views and turn boundaries interrupt grouping. Repeated reads remain separate observations rather than being deduplicated.

Disclosure must preserve exceptional outcomes even while details are closed. Completion alone does not imply a zero exit code. Read-file navigation and command disclosure remain distinct actions. Hiding a disclosure glyph on hover exit must not remove its hit region, keyboard access or accessible name, change expansion or move text.

Preserve the reader's scroll anchor, output selection and inner scroll position across output updates and disclosure changes. Reset these only when their transcript owner changes. Layout measurement and rendering must share geometry.

## Data and ownership

Use structured backend action metadata rather than guessing behavior from shell program names. Unknown actions retain the original command. Display grouping projects canonical records without changing execution ownership or command cleanup barriers from [architecture](architecture.md#ownership-and-recovery).

Stable display identities must map back to source items for navigation, failures and bookmarks. Navigating to a hidden item reveals its group. Disclosure callbacks remain scoped to the transcript owner.

Elapsed-time presentation requires authoritative timestamps and live execution evidence; saved in-progress history cannot establish a ticking turn. File-edit summaries wait for the owning turn's confirmed terminal outcome, rather than an individual file-change item's completion. Missing timing or status must remain unknown.

Use [validation](validation.md) for checks and evidence requirements.
