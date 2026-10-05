# Feature ownership

Feature directories own AppKit views, controllers and the presentation helpers used by
those views. Shared workspace values, reducers and effects belong to `Application/`;
backend process and protocol code belong to `CodexClient/`.

| Directory | Responsibility |
| --- | --- |
| [Changes](Changes/) | Repository comparisons, reported changes and shared diff rendering. |
| [CommandPalette](CommandPalette/) | Native command palette presentation and input. |
| [Conversation](Conversation/) | Conversation controller, composer and transcript integration. |
| [Conversation/Composer](Conversation/Composer/) | Input controls, attachment inputs and command menus. |
| [Conversation/Transcript](Conversation/Transcript/) | Markdown preparation, rendering, collection items and turn navigation. |
| [Navigation](Navigation/) | Project and task navigation, sidebar controls and message search. |
| [PinnedSummary](PinnedSummary/) | Summary card and compact section presentations. |
| [ProjectContext](ProjectContext/) | Project context presentation and editing controls. |
| [Shared](Shared/) | Common presentation ownership, panel contracts and reusable view support. |
| [Sources](Sources/) | Source inventory, detail presentation, result cards and tab hover previews. |
| [Usage](Usage/) | Usage presentation and controls. |

Feature tests mirror these groups under
[Tests/CodexGUITests/Features](../../../Tests/CodexGUITests/Features/).
Full-window and cross-view integration tests belong in
[Tests/CodexGUITests/App](../../../Tests/CodexGUITests/App/).

See the [project overview](../../../README.md),
[conventions](../../../CONVENTIONS.md) and
[application architecture](../../../docs/architecture.md) for build instructions,
component rules and state/execution contracts.
