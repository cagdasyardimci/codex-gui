# Feature ownership

This map owns feature-directory routing. Follow
[conventions](../../../CONVENTIONS.md#file-organization-and-ownership) for placement and
naming rules, and [architecture](../../../docs/architecture.md) for behavioral contracts.

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
| [Shared](Shared/) | Common presentations, panel contracts and reusable view support. |
| [Sources](Sources/) | Source inventory, detail presentation, result cards and tab hover previews. |
| [Subagents](Subagents/) | Delegated-work lifecycle, list, and tab-contained read-only child conversations. |
| [Usage](Usage/) | Usage presentation and controls. |

For test placement, see [test organization](../../../CONVENTIONS.md#test-organization).
For task routing, return to [agent workflow](../../../docs/agent-workflow.md#documentation-map).
