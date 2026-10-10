# Feature ownership

This map owns feature-directory routing. Follow [conventions](../../../CONVENTIONS.md#file-organization-and-ownership) for placement and naming rules, and [architecture](../../../docs/architecture.md) for behavioral contracts.

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

Hiding the pinned summary releases the inspector pane when it has no detail or tool content.
The transcript and composer center within the resulting conversation pane at their existing
reading width. Content visibility does not overwrite saved inspector visibility or detail width;
an expanded conversation keeps its containing pane and releases only its summary aside.

For test placement, see [test organization](../../../CONVENTIONS.md#test-organization). For task routing, return to [agent workflow](../../../docs/agent-workflow.md#documentation-map).

Navigation task hover cards use a fixed 320-point width. Titles and project names wrap, and card
height follows the content. Computer and time metadata remain beside the first title line.
The passive child panel does not take focus and dismisses when the row or window loses its
hover context.

Conversation transcript Markdown and turn navigation previews highlight HTTP(S) links and show an
inline site icon. Bare URLs in prose are links; inline and fenced code remain literal. A visible
link first requests an icon with `sz=256` from Google's favicon service for the site's host, accepting
the service's redirect to its gstatic image host. If the response is unavailable or unusable, the
system LinkPresentation metadata API is asked for the site's icon. Icons are limited to 128 KB.
Results and failures are cached per origin for up to 128 sites during the app session; a globe is
shown when no icon is available. Dark monochrome icons are tinted white
in dark appearance. Local and file links keep their existing file presentation.
