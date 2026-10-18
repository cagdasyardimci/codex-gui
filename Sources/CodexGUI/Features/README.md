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
| [Usage](Usage/) | Native usage controls and details; shared usage projection belongs to Application/Presentation. |

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

Changes and Files share [SourceTextView](Shared/SourceTextView.swift) for native source
text presentation. `SourceTextViewport` owns common scroll/text/ruler installation and wrapping geometry; feature
containers own editing, diff row mapping and document height.

Files and Changes use shared `ViewerToolbarButton` presentations and `ViewerToolbarGroup`
surfaces. Responsive composition and domain-specific actions remain feature-owned.

Workspace file icons, viewer search fields, filename result rows and navigator width
transitions live in Shared. `ViewerNavigatorSplitView` owns the shared resizable pane and
visibility policy; `ViewerFileNavigatorView` owns filter/scroll layout. Both navigator adapters
use the same `ViewerFileTreeView` native outline for input, disclosure, traversal and row
construction, with `ViewerFileTreeRow` and `ViewerFileTreeSelectionRow` for layout and painting.
`ViewerFileActions` owns common menu sections, captured operations, clipboard writes, error presentation
and installed app destinations;
`ViewerStatusView` owns loading, failure and empty-state presentation. Git snapshot loading and Files directory/search/save services
retain their feature-specific lifecycles and captured identities.
