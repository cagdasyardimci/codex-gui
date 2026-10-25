# Feature ownership

This map owns feature-directory routing. Follow [conventions](../../../CONVENTIONS.md#file-organization-and-ownership) for placement and naming rules, and [architecture](../../../docs/architecture.md) for behavioral contracts.

| Directory | Responsibility |
| --- | --- |
| [Changes](Changes/) | Repository comparisons, reported changes and shared diff rendering. |
| [Files](Files/) | Workspace file browsing, document tabs, source editing, rich previews and file search. |
| [CommandPalette](CommandPalette/) | Native command palette presentation and input. |
| [Conversation](Conversation/) | Conversation controller, composer and transcript integration. |
| [Conversation/Composer](Conversation/Composer/) | Input controls, attachment inputs and command menus. |
| [MessageSearch](MessageSearch/) | Message-search sheet, results and history-loading controls. |
| [Navigation](Navigation/) | Project and task navigation and sidebar controls. |
| [PinnedSummary](PinnedSummary/) | Summary card and compact section presentations. |
| [ProjectContext](ProjectContext/) | Project context presentation and editing controls. |
| [Shared](Shared/) | Common presentations, panel contracts and reusable view support. |
| [Shared/Markdown](Shared/Markdown/) | Markdown parsing, native text rendering, rich attachments, plain-text presentation and the runtime preview adapter. |
| [Shared/Transcript](Shared/Transcript/) | Reusable transcript controller, preparation, message rows, selection, scrolling and turn navigation. |
| [Sources](Sources/) | Source inventory, detail presentation, result cards and tab hover previews. |
| [Subagents](Subagents/) | Delegated-work lifecycle, list, and tab-contained read-only child conversations. |
| [RemoteAccess](RemoteAccess/) | Native host status, pairing and device management window. |
| [Usage](Usage/) | Native usage controls and details; shared usage projection belongs to Application/Presentation. |

For shared component ownership and presentation contracts, see [interface styling](../../../docs/interface-styling.md#component-ownership), including [conversation and navigation](../../../docs/interface-styling.md#conversation-and-navigation-presentation) and [file viewers](../../../docs/interface-styling.md#file-viewers). Transcript activity grouping and disclosure follow [activity presentation](../../../docs/activity-presentation-design.md).

For test placement, see [test organization](../../../CONVENTIONS.md#test-organization). For task routing, return to [agent workflow](../../../docs/agent-workflow.md#documentation-map).
