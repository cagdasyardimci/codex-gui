# Interface styling

When a selected chat has a cross-app lock, the conversation replaces its composer with a rounded, outlined notice containing a lock icon and the ownership message on the left, plus Retry and Fork chat at the right edge after a divider. The transcript remains visible. Its light and dark surface, primary text, secondary text, outer ring, subtler divider and hover fill follow the live ChatGPT component's resolved roles. Native geometry and typography follow that component's rendered bounds and font styles.

The overlapping desktop components use the measured reference typography, geometry and appearance colors. Native AppKit points are used for nominal CSS pixel dimensions; this does not establish identical glyph rasterization or window chrome.

## Token ownership and changes

The application target owns its token catalogues. Change a named input in its catalogue, then rebuild and relaunch so prepared text and width caches use the new configuration. The catalogues are immutable; there is no mutable global theme or runtime token editor.

| Catalogue | Owns |
| --- | --- |
| [LayoutTokens](../Sources/CodexGUI/App/Design/LayoutTokens.swift) | Dimensions, spacing, insets, icon sizes and layout-policy inputs; simple derived allowances and scalar/range validation, in AppKit points. |
| [ShapeTokens](../Sources/CodexGUI/App/Design/ShapeTokens.swift) | Radii, corner curves, stroke widths and related shape formulas, grouped by component role. |
| [TypographyTokens](../Sources/CodexGUI/App/Design/TypographyTokens.swift) | Value-only text roles, exact interface weights versus native font selections, line-height policy, tracking and text features. |
| [AppKitColorTokens](../Sources/CodexGUI/App/Design/AppKitColorTokens.swift) | Named native dynamic color roles and their light/dark values. |
| [ShadowTokens](../Sources/CodexGUI/App/Design/ShadowTokens.swift) | Immutable native shadow styles and named composite presets. |

| AppKit implementation | Owns |
| --- | --- |
| [AppKitColorResolution](../Sources/CodexGUI/App/Design/AppKitColorResolution.swift) | Dynamic sRGB/grayscale color construction and resolution under a view's effective appearance; it does not depend on named palette roles. |
| [AppKitFontResolver](../Sources/CodexGUI/App/Design/AppKitFontResolver.swift) | Native font construction and font-related attributed-string attributes. |
| [AppKitShapePath](../Sources/CodexGUI/App/Design/AppKitShapePath.swift) | Shared corner contours for native fills, borders and shadow paths; the corner curve is independent of its radius. |
| [AppKitShadowRenderer](../Sources/CodexGUI/App/Design/AppKitShadowRenderer.swift) | Applying exterior and inset shadow styles to layers, including paths, masks and blur conversion. |
| [AppKitControlStyling](../Sources/CodexGUI/App/Design/AppKitControlStyling.swift) | Shared native button, popup and section-label presentation defaults. |

| Layout owner | Owns |
| --- | --- |
| [ModelSelectorLayout](../Sources/CodexGUI/Features/Conversation/Composer/ModelSelectorLayout.swift) | Intrinsic width requests, drawing rectangles and artwork/control-height compatibility. |
| [PermissionControlLayout](../Sources/CodexGUI/Features/Conversation/Composer/PermissionControlLayout.swift) | Fractional title-width allowances and icon/title rectangles, using the actual cell's configuration. |
| [ComposerLayout](../Sources/CodexGUI/Features/Conversation/Composer/ComposerLayout.swift) | Footer reflow, measured row-fit requirements and viewport-based editor growth. |
| [NavigationSidebarLayout](../Sources/CodexGUI/Features/Navigation/NavigationSidebarLayout.swift) | Compensated section-row geometry, heading/icon fit and section-gap compatibility. |

The catalogues and layout helpers describe design inputs and geometry. Native owners retain measurement, constraints, drawing, interaction and appearance callbacks. Pure layout helpers consume measured inputs rather than measuring native views or fonts. Use the source owners below for current values and implementation details. This guide records shared presentation contracts and rationale rather than duplicating dimensions, color values, font weights or control declarations.

Choose token roles by purpose. Equal numeric values do not imply a shared design rule. Keep derived relationships computed rather than independently editable in consumers. Shape and layout remain separate responsibilities even when a shape depends on a component's configured size. Native metrics, artwork coordinates and operational update tolerances stay with their owners unless they represent shared design decisions. Keep parser quote/list offsets integer-valued until their representation is explicitly changed.

Validate configuration relationships and component fit separately from available-space behavior. A valid configuration must still work with the component's truncation, reflow, scrolling or collapse policy. Measure changes in the owning component's coordinate space: a clipped viewport, intrinsic size request and final frame can differ.

## Appearance ownership

Use the shared color catalogue for semantic color roles. Follow [AppKit conventions](../CONVENTIONS.md#appkit-behavior-and-accessibility) for effective appearance, retained colors, detached panels and appearance-change verification.

## Component ownership

| Styling concern | Source owner |
| --- | --- |
| Composer placement and shared reading-column alignment | [ConversationViewController](../Sources/CodexGUI/Features/Conversation/ConversationViewController/ConversationViewController.swift) |
| Locked-chat notice and artwork | [ConversationLockView](../Sources/CodexGUI/Features/Conversation/ConversationLockView.swift) |
| Composer editor/footer constraints and control reflow | [ComposerSurfaceLayout](../Sources/CodexGUI/Features/Conversation/Composer/ComposerSurfaceLayout.swift), [ComposerToolbarView](../Sources/CodexGUI/Features/Conversation/Composer/ComposerToolbarView.swift) |
| Permission and model menus | [ApprovalPolicyPopoverView](../Sources/CodexGUI/Features/Conversation/Composer/ApprovalPolicyPopoverView.swift), [ModelEffortPopoverView](../Sources/CodexGUI/Features/Conversation/Composer/ModelEffortPopoverView.swift), [ComposerPopoverPanel](../Sources/CodexGUI/Features/Conversation/Composer/ComposerPopoverPanel.swift) |
| Task hover cards | [TaskHoverCard](../Sources/CodexGUI/Features/Navigation/TaskHoverCard.swift), [TaskSidebarCellView](../Sources/CodexGUI/Features/Navigation/TaskSidebarCellView.swift) |
| Sidebar views and artwork | [NavigationViewController](../Sources/CodexGUI/Features/Navigation/NavigationViewController/NavigationViewController.swift), [DesktopBrandWordmark](../Sources/CodexGUI/App/DesktopBrandWordmark.swift) |
| Shared Markdown text and decorations | [MarkdownAttributedStringRenderer](../Sources/CodexGUI/Features/Shared/Markdown/MarkdownAttributedStringRenderer.swift), [MarkdownLayoutManager](../Sources/CodexGUI/Features/Shared/Markdown/MarkdownLayoutManager.swift) |
| Link icons and external lookup | [WebLinkFaviconAttachment](../Sources/CodexGUI/Features/Shared/Markdown/WebLinkFaviconAttachment.swift), [WebLinkFaviconLoader](../Sources/CodexGUI/Features/Shared/WebLinkFaviconLoader.swift) |
| Transcript message containers and user messages | [ConversationCollectionItem](../Sources/CodexGUI/Features/Shared/Transcript/ConversationCollectionItem.swift) |
| Transcript scrolling and turn navigation | [TranscriptViewController](../Sources/CodexGUI/Features/Shared/Transcript/TranscriptViewController/TranscriptViewController.swift) |
| Window chrome and native toolbar placement | [WindowChromeViewController](../Sources/CodexGUI/App/WindowLayout/WindowChromeViewController.swift), [NativeWindowButtonAlignment](../Sources/CodexGUI/App/NativeWindowButtonAlignment.swift), [toolbar coordinator](../Sources/CodexGUI/App/MainWindowController/MainWindowController+ToolbarAndPanels.swift) |
| Tools tabs, toolbar and artwork | [ToolsTabViewController](../Sources/CodexGUI/App/ToolsTabViewController.swift), [ToolsToolbarCoordinator](../Sources/CodexGUI/App/ToolsToolbarCoordinator.swift), [ToolsPaneIcons](../Sources/CodexGUI/App/ToolsPaneIcons.swift) |
| Shared file artwork and search | [WorkspaceFileIcon](../Sources/CodexGUI/Features/Shared/WorkspaceFileIcon.swift), [ViewerSearchField](../Sources/CodexGUI/Features/Shared/ViewerSearchField.swift), [ViewerFileSearchResultView](../Sources/CodexGUI/Features/Shared/ViewerFileSearchResultView.swift) |
| Shared file tree interactions and rows | [ViewerFileTreeView](../Sources/CodexGUI/Features/Shared/ViewerFileTreeView.swift), [ViewerFileTreeRow](../Sources/CodexGUI/Features/Shared/ViewerFileTreeRow.swift) |
| Shared file actions and status | [ViewerFileActions](../Sources/CodexGUI/Features/Shared/ViewerFileActions.swift), [ViewerStatusView](../Sources/CodexGUI/Features/Shared/ViewerStatusView.swift) |
| Shared navigator panes | [ViewerNavigatorSplitView](../Sources/CodexGUI/Features/Shared/ViewerNavigatorSplitView.swift), [ViewerFileNavigatorView](../Sources/CodexGUI/Features/Shared/ViewerFileNavigatorView.swift), [ViewerNavigatorTransition](../Sources/CodexGUI/Features/Shared/ViewerNavigatorTransition.swift) |
| Shared toolbar controls | [ViewerToolbarButton](../Sources/CodexGUI/Features/Shared/ViewerToolbarButton.swift), [ViewerToolbarGroup](../Sources/CodexGUI/Features/Shared/ViewerToolbarGroup.swift) |
| Shared source text and viewport | [SourceTextView](../Sources/CodexGUI/Features/Shared/SourceTextView.swift), [SourceTextViewport](../Sources/CodexGUI/Features/Shared/SourceTextViewport.swift) |
| Workspace file documents and navigation | [FilesViewController](../Sources/CodexGUI/Features/Files/FilesViewController.swift), [FileDocumentViewController](../Sources/CodexGUI/Features/Files/Document/FileDocumentViewController.swift), [FileNavigatorViewController](../Sources/CodexGUI/Features/Files/FileNavigatorViewController.swift) |
| Inspector and pinned summary | [InspectorViewController](../Sources/CodexGUI/App/InspectorViewController.swift), [PinnedSummaryViewController](../Sources/CodexGUI/Features/PinnedSummary/PinnedSummaryViewController.swift) |

Use the [feature map](../Sources/CodexGUI/Features/README.md) for other presentation owners. Shared text painting is owned by [DesktopTextRendering](../Sources/CodexGUI/App/DesktopTextRendering.swift); composer reference artwork is owned by [ComposerFooterIcons](../Sources/CodexGUI/Features/Conversation/Composer/ComposerFooterIcons.swift).

Composer and project preference controls share effort labels through [ModelPreferencePresentation](../Sources/CodexGUI/Features/Shared/ModelPreferencePresentation.swift). Their native controls and selection lifecycles remain with their features.

## Conversation and navigation presentation

Project rows reveal their ellipsis and New Chat buttons only while hovered, including the current
project. Project row backgrounds use the shared sidebar row highlight only while hovered,
including when the project is current or its row is selected.
Project, chat and section-heading hover backgrounds share the sidebar superellipse contour;
high-contrast row outlines follow the same contour.

The Projects / Recents heading highlights its background and reveals its ellipsis and add buttons
while hovered. The controls keep their layout space while hidden.
The sidebar heading's ellipsis opens an arrowless custom AppKit menu with **Organize sidebar**
(**By project**, **In one list**) and **Sort chats by** (**Last updated**, **Manual order**).
Its main surface is 220 points wide and submenus are 180 points wide, with 4-point gutters,
13-point interface text, 28.5703125-point rows and right-aligned checkmarks. Checkmarks use
75% opacity at rest and full opacity while their row is hovered or keyboard-highlighted.
The surfaces use
shared popover blur, border and shadow styling. Hover or click opens a submenu; arrows navigate,
Return, keypad Enter or Space chooses, Left closes a submenu, and Escape dismisses. Outside clicks,
window deactivation, closure and anchor removal dismiss without taking focus. The panel follows
its anchor's appearance and restores the prior responder after explicit dismissal.

The adjacent plus adds a project in grouped mode and starts a chat in flat mode. The heading's
context menu retains access to project and conversation management. By project retains
current-project expansion and Show more. In one list displays unarchived chats across projects
under **Recents**, sourced from the backend's global conversation listing; the existing archived
filter requests the corresponding global archived list. Pins remain separate. Loading and failure
states stay visible, and selecting a cross-project chat adopts its validated checkout before opening
its history. Last updated sorts newest first, preserving source order for equal or missing dates.
Manual order starts from that order and supports dragging ordinary chat rows while search is empty.
Reordering preserves selection and saved positions for other projects; newly listed chats follow
saved chats. Pins and project membership are independent of this presentation order.

Hiding the pinned summary releases the inspector pane when it has no detail or tool content. The transcript and composer center within the resulting conversation pane at their existing reading width. Content visibility does not overwrite saved inspector visibility or detail width; an expanded conversation keeps its containing pane and releases only its summary aside.

Chat search and changed-file jump use the shared arrowless `DesktopSearchPanel`. Its explicit
viewport is bounded by the parent window and visible screen, independently of the content's
fitting size. Chat search centers over a dimmed window; changed-file jump opens beneath its
toolbar anchor and can extend over the editor. Both retain a fixed query header and scroll
results within the remaining height. Chat search keeps title/preview matching and shows
available chats with project context and a New chat action. File jump lists the captured
comparison's files with inline directory context. Arrow keys select, Return accepts, and
Escape dismisses; chat results also expose Control-1 through Control-9 shortcuts. Dismissal
restores prior focus for explicit acceptance/cancellation, while window deactivation, closure
and anchor removal retire the panel without taking focus. Shared query geometry comes from
`ViewerSearchField`; these panels omit its navigator surface border.

Task hover cards use a preferred width clamped to the available screen. Titles and project names wrap within bounded lines, and card height follows the content. Computer and time metadata remain beside the first title line. The passive child panel does not take focus and dismisses when the row or window loses its hover context. The hover card owners above retain sizing, positioning and dismissal details.

Conversation transcript Markdown and turn navigation previews highlight HTTP(S) links and show an inline site icon. Bare URLs in prose are links; inline and fenced code remain literal. Loading a site icon sends the site's host to Google's favicon service, allowing restricted redirects to its image host. If the response is unavailable or unusable, the system LinkPresentation API requests metadata for the site's origin. These lookups use the host or origin rather than the link's full path. A globe appears when no icon is available, and dark monochrome icons are tinted white in dark appearance. Local and file links retain their file presentation. The link icon owners above retain request validation, resource limits and caching.

## File viewers

The file viewer places its breadcrumb and capsule actions in a row spanning both panes. The navigator's folder header and filename filter sit beneath that row; directory rows use disclosure chevrons without duplicate folder icons. File icons occupy the disclosure column, keeping file and folder names aligned at each tree depth. The filename filter shares centered text and icon geometry between drawing and native editing. With no selected file, the breadcrumb shows `/` centered in a circular surface with square bounds matching the toolbar control height. Open is hidden, and a canvas empty-state surface centers the folder artwork, title and instruction within the document pane. Files actions share one outlined, softly shadowed capsule. Icon-only controls have square bounds, with pale blue circular backgrounds for selected actions; grouped controls do not add individual borders or shadows. Preview file tabs use italic titles and source files use code artwork; retained titles are upright. Preview replacement and Keep Open behavior is unchanged. The fixed-height tools tab strip scrolls by wheel input and reveals the selected tab without a horizontal scrollbar, so legacy scrollbar preferences cannot reduce the tab viewport height. Source/Preview keeps its own toolbar control, using an icon in compact panes. Content search is the document/search button's primary action; its context menu also exposes opening a file by name. The Open control lists available applications, opening the file's folder or GitHub location, and Save as. Copy Markdown sits at the document's top-right edge rather than in the Open menu and copies the current source buffer. Its accessory area shares the document background, without a separate shaded strip. Source text uses a compact, separator-free line-number gutter and spacious visual line spacing, including wrapped continuations. Changes and Files share the native `SourceTextView` for source typography, paragraph spacing, syntax colors and text behavior. `SourceTextViewport` owns text/ruler installation and wrapping geometry shared by document and diff columns. Their containers retain file editing and diff-specific row numbering, split alignment and change highlights. Both tools open with wrapping enabled; the Changes toolbar can turn it off. The Open control displays the preferred editor's icon, or the system file handler's icon. Conflict and save-failure recovery remain available when needed without adding routine controls to the healthy Open menu. Files and Changes use the shared `ViewerToolbarButton` for native toolbar buttons. Its capsule presentation owns standalone borders and shadows; its grouped presentation leaves the enclosing surface to `ViewerToolbarGroup` while retaining selection and pressed feedback. Comparison controls opt into the outlined capsule group surface; other group surfaces retain their existing flat styling. The Changes scope selector keeps totals beside its capsule, and a thin rule separates the toolbar from the content. Feature controllers retain actions, enabled and selected state, menu contents and compact-layout policies. Breadcrumb and revision-field content remain feature-owned. Markdown body rendering continues to use the shared renderer. `FileViewerIcons` maps non-file roles to the OpenAIStyle catalogue and uses SF Symbols for roles absent from that catalogue. `WorkspaceFileIcon` owns file artwork and the shared document-search toolbar icon for both viewers, including intrinsic Swift color in file listings. Both navigators use `ViewerSearchField` for filter drawing and native editing geometry. Quick-open and changed-file jump share command translation and bounded keyboard selection, while their matching, data identities, row presentation and sheet/panel lifecycles remain local. Filename quick open and content search share a borderless query field, fixed header and status footer with capsule keyboard keycaps and a compact Escape control. Content search follows the ChatGPT desktop reference's dense, single-line rows: monospaced source text, pale highlighted literal matches, trailing filename and line number, and a full-width capsule selection. Its file-mask field sits beside the query. Filename quick open retains the shared two-line filename/directory rows and remains available through Command-P and the search context menu. Escape closes either sheet and restores prior focus. Reference geometry and light colors are measured from the supplied screenshot; point conversion and font identity are inferred. Dark appearance uses the native application's adaptive palette rather than an unobserved reference. `ViewerNavigatorSplitView` owns both viewers' pane layout, divider hit area and resize cursor, dragging, clamping, width restoration and visibility. Desired navigator widths stay within the shared navigator's supported bounds while reserving space for the document. The actual width shrinks further when space requires it; growing the pane restores the desired width. Hiding releases the navigator and divider width completely. `ViewerNavigatorTransition` owns animation, cancellation and reduced-motion behavior within that container. `ViewerFileNavigatorView` supplies the common filter/scroll layout and autohiding scroll bars; Files adds its root chooser and filter status through its header slots. `ViewerFileTreeView` is the native outline control used by both viewers. It owns row construction, disclosure, single/double activation, parent/child keyboard traversal and context-menu targeting. Adapters supply stable rows and children, including Files' lazy loading and Git's captured hierarchy. `ViewerFileTreeRow` owns both navigators' row geometry, depth indentation, shared disclosure/icon column, indentation guides, trailing name truncation and full-path tooltips. `ViewerFileTreeSelectionRow` draws the same outlined selection while retaining normal label colors. File rows expose captured file actions through their context menus. Git counts are optional accessories; the snapshot projection and workspace lazy outline remain separate adapters. Folder expansion does not open a file or change the selected tool tab. `ViewerFileActions` captures each menu's path and content provider, owns clipboard/export and external-opening actions, common menu sections, error presentation and installed-application destinations. The Copy Markdown button uses the same clipboard writer. Files supplies its captured source buffer and recovery commands; Changes supplies comparison-blob bytes. Changes labels workspace-opening commands explicitly and offers them only for existing workspace files. Exporting a compared version never substitutes patch text or workspace bytes. `ViewerStatusView` supplies readable, selectable loading and failure messages and the optional empty-state icon/title. Each feature owns its message, retry and recovery decisions. The Files landing tab uses package artwork; document tabs use code artwork for source files and the shared type-specific artwork for other files. Native outline and text-finder controls retain their system icons; the Open action retains the selected application's system-provided icon.

Changes code panes own horizontal wheel input through [GitCodeScrollView](../Sources/CodexGUI/Features/Changes/Diff/GitCodeScrollView.swift); vertical gestures and their ending events go to the enclosing viewer. Horizontal input updates the clip position directly, preserving its vertical origin and size. Precise deltas use points; discrete deltas use `horizontalLineScroll`. Shift uses the horizontal delta when already normalized, otherwise the vertical delta. Horizontal gestures remain consumed at document boundaries. Incoming momentum deltas are applied without adding inertia or rubber-band overscroll; this policy does not reproduce AppKit's animated horizontal scrolling or its native live-scroll notification lifecycle. Physical trackpad feel and accessibility acceptance require observation in the launched app.

## Native adaptation rationale

Files Markdown uses [FileMarkdownStyling](../Sources/CodexGUI/Features/Shared/Markdown/FileMarkdownStyling.swift)
for Desktop reading typography: medium headings, source-aware heading gaps, preserved soft line
breaks and bare monospace inline code. Files uses compact, neutral code blocks with faint surfaces
and right-aligned language labels; transcript code cards and highlighting remain independent.
Files links omit site icons, recognize bare email addresses outside code, and exclude paragraph
separators from link decoration. Semantic list markers, nested quotes, resolved references,
source-preserving copy and declared table alignment retain their shared native behavior. Quote
rails use the Files thickness and stop at paragraph gaps; quoted headings retain heading ink.
Distinct parsed blocks retain their source identity so adjacent matching headings or paragraphs keep their blank-line gaps. Files preserves the first paragraph gap through its top inset because TextKit omits initial paragraph spacing. Raw HTML stays literal, with source-line spacing rather than repeated block gaps. Typography and layout inputs live in the `FileMarkdown` token roles.

Recognized front matter appears in a native Metadata grid above the Files scrolling body. Scalar
values wrap and scalar sequences use wrapping chips. [MarkdownFileMetadata](../Sources/CodexGUI/Features/Shared/Markdown/MarkdownFileMetadata.swift)
owns the bounded YAML subset; malformed or unsupported structures remain literal Markdown.
Switching files or modes retires the visible metadata with its document. Shared Git previews can
place the same panel inline with their content.

Each main window has its own toolbar identifier because its tools-pane composition can differ from other windows. AppKit synchronizes items between toolbars with the same identifier, including when configuration autosaving is disabled. Toolbar composition belongs to the window's controller; configuration autosaving stays disabled because the application supplies that composition.

The composer footer shows one submission control at a time. While viewing a stoppable active task, an empty draft shows Stop; text, attached context or a pending image import replaces it with the send arrow. Running turns retain the existing steering action. Its arrow uses the same icon, circular fill and enabled or disabled colors as the normal send control. Pending image imports keep submission disabled.

The model and effort button keeps its opening width while its picker is shown, so changing effort does not move the centered popover. It sizes to the selected model and effort again when the picker closes.

The composer editor paints the same surface color as its enclosing view so AppKit can repaint the previous insertion point. Its setup belongs to [composer configuration](../Sources/CodexGUI/Features/Conversation/ConversationViewController/ConversationViewController+Composer.swift).

Project/location strips and voice controls are outside the existing composer components. Matching the reference does not require reserving footer space for omitted controls. The Tools landing page places Changes and Files side by side when two columns fit, and stacks full-width tiles in narrow panes. Use the source owners above for sizing calculations.

Popover surface shadows need transparent panel padding to avoid clipping; adding a second native window shadow would darken the result. AppKit controls backdrop blur, which requires paired visual acceptance against the reference. See [popover surface](../Sources/CodexGUI/Features/Shared/DesktopPopoverSurface.swift) and the panel owner above for implementation.

Effort hover motion approximates the observed trajectory and respects Reduce Motion. Hover and particle implementation belongs to [EffortSlider](../Sources/CodexGUI/Features/Conversation/Composer/EffortSlider.swift).

## Reference and acceptance

Reference measurements apply to the measured revision and appearance preferences; they do not establish the current implementation's visual parity. Codex GUI uses compiled styling and effective macOS appearance.

Native adaptation does not establish pixel equivalence. CSS and Core Animation shadow kernels differ, native panels retain OS-controlled effects, and system text rendering can differ despite matching font instances and glyph advances. These differences require visual acceptance rather than equality of source constants.

Use [validation](validation.md) for checks and evidence limits, and [native QA](native-qa.md) for acceptance procedures.

Styling comparisons require paired captures with matching content, control state and appearance preferences. Cover both appearances at wide and narrow widths, including selection, hover, focus, disabled controls, multiline drafts, long code, tables and retained tool tabs. Unmeasured reference descendants, syntax colors and native window chrome must not be inferred from a container's inherited style.
