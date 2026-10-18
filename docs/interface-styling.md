# Interface styling

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

The catalogues and layout helpers describe design inputs and geometry. Native owners retain measurement, constraints, drawing, interaction and appearance callbacks. Pure layout helpers consume measured inputs rather than measuring native views or fonts. Use the source owners below for current values and implementation details; do not maintain a second inventory of dimensions, colors, font weights or control behavior in this guide.

Choose token roles by purpose. Equal numeric values do not imply a shared design rule. Keep derived relationships computed rather than independently editable in consumers. Shape and layout remain separate responsibilities even when a shape depends on a component's configured size. Native metrics, artwork coordinates and operational update tolerances stay with their owners unless they represent shared design decisions. Keep parser quote/list offsets integer-valued until their representation is explicitly changed.

Validate configuration relationships and component fit separately from available-space behavior. A valid configuration must still work with the component's truncation, reflow, scrolling or collapse policy. Measure changes in the owning component's coordinate space: a clipped viewport, intrinsic size request and final frame can differ.

## Appearance ownership

Use the shared color catalogue for semantic color roles. Follow [AppKit conventions](../CONVENTIONS.md#appkit-behavior-and-accessibility) for effective appearance, retained colors, detached panels and appearance-change verification.

## Component ownership

| Styling concern | Source owner |
| --- | --- |
| Composer placement and shared reading-column alignment | [ConversationViewController](../Sources/CodexGUI/Features/Conversation/ConversationViewController/ConversationViewController.swift) |
| Composer editor/footer constraints and control reflow | [ComposerSurfaceLayout](../Sources/CodexGUI/Features/Conversation/Composer/ComposerSurfaceLayout.swift), [ComposerToolbarView](../Sources/CodexGUI/Features/Conversation/Composer/ComposerToolbarView.swift) |
| Permission and model menus | [ApprovalPolicyPopoverView](../Sources/CodexGUI/Features/Conversation/Composer/ApprovalPolicyPopoverView.swift), [ModelEffortPopoverView](../Sources/CodexGUI/Features/Conversation/Composer/ModelEffortPopoverView.swift), [ComposerPopoverPanel](../Sources/CodexGUI/Features/Conversation/Composer/ComposerPopoverPanel.swift) |
| Sidebar views and artwork | [NavigationViewController](../Sources/CodexGUI/Features/Navigation/NavigationViewController/NavigationViewController.swift), [DesktopBrandWordmark](../Sources/CodexGUI/App/DesktopBrandWordmark.swift) |
| Shared Markdown text and decorations | [MarkdownAttributedStringRenderer](../Sources/CodexGUI/Features/Shared/Markdown/MarkdownAttributedStringRenderer.swift), [MarkdownLayoutManager](../Sources/CodexGUI/Features/Shared/Markdown/MarkdownLayoutManager.swift) |
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

Composer and project preference controls share effort labels through
[ModelPreferencePresentation](../Sources/CodexGUI/Features/Shared/ModelPreferencePresentation.swift).
Their native controls and selection lifecycles remain with their features.

The file viewer places its breadcrumb and capsule actions in a row spanning both panes.
The navigator's folder header and filename filter sit beneath that row; directory rows
use disclosure chevrons without duplicate folder icons. File icons occupy the disclosure
column, keeping file and folder names aligned at each tree depth. The filename filter
shares centered text and icon geometry between drawing and native editing.
With no selected file, the breadcrumb shows `/` centered in a circular surface with
square bounds matching the toolbar control height. Open is hidden, and a canvas empty-state
surface centers the folder artwork, title and instruction within the document pane.
Icon-only toolbar controls have square bounds and circular backgrounds. Preview tabs use upright titles;
their replacement and Keep Open behavior is unchanged. The fixed-height tools tab strip
scrolls by wheel input and reveals the selected tab without a horizontal scrollbar, so
legacy scrollbar preferences cannot reduce the tab viewport height. Source/Preview keeps
its own toolbar control, using an icon in compact panes. Content search is the document/search
button's primary action; its context menu also exposes opening a file by name. The Open capsule
lists available applications, opening the file's folder or GitHub location, and Save as.
Copy Markdown sits at the document's top-right edge rather than in the Open menu and
copies the current source buffer. Its accessory area shares the document background,
without a separate shaded strip. Source text uses a compact, separator-free line-number
gutter and spacious visual line spacing, including wrapped continuations. Changes and Files share the native `SourceTextView` for source typography, paragraph
spacing, syntax colors and text behavior. `SourceTextViewport` owns text/ruler installation
and wrapping geometry shared by document and diff columns. Their containers retain file editing and
diff-specific row numbering, split alignment and change highlights. Both tools open
with wrapping enabled; the Changes toolbar can turn it off.
The Open capsule displays the preferred editor's icon,
or the system file handler's icon. Conflict and save-failure recovery remain available
when needed without adding routine controls to the healthy Open menu.
Files and Changes use the shared `ViewerToolbarButton` for native toolbar buttons.
Its capsule presentation owns standalone borders, shadows and selected backgrounds;
its grouped presentation leaves the enclosing surface to `ViewerToolbarGroup`.
Feature controllers retain actions, enabled and selected state, menu contents and
compact-layout policies. Breadcrumb and revision-field content remain feature-owned.
Markdown body rendering continues to use the shared renderer. `FileViewerIcons` maps non-file roles to the
OpenAIStyle catalogue and uses SF Symbols for roles absent from that catalogue.
`WorkspaceFileIcon` owns file artwork for both viewers, including intrinsic Swift color.
Both navigators use `ViewerSearchField` for filter drawing and native editing geometry.
Quick-open and changed-file jump results share filename/directory rows, command translation and
bounded keyboard selection, while their matching, data identities and sheet/popover lifecycles remain local.
Filename quick open and content search share a borderless query field, fixed header and status
footer with capsule keyboard keycaps and a compact Escape control. Content search follows the
ChatGPT desktop reference's dense, single-line rows: monospaced source text, pale highlighted
literal matches, trailing filename and line number, and a full-width capsule selection.
Its file-mask field sits beside the query. Filename quick open retains the shared two-line
filename/directory rows and remains available through Command-P and the search context menu.
Escape closes either sheet and restores prior focus. Reference geometry and light colors are
measured from the supplied screenshot; point conversion and font identity are inferred. Dark
appearance uses the native application's adaptive palette rather than an unobserved reference.
`ViewerNavigatorSplitView` owns both viewers' pane layout, divider hit area and resize cursor,
dragging, clamping, width restoration and visibility. Both start at 241 points, allow desired
navigator widths of 120–360 points and reserve 160 points for the document. The actual width
shrinks further when space requires it; growing the pane restores the desired width. Hiding
releases the navigator and divider width completely. `ViewerNavigatorTransition` owns animation,
cancellation and reduced-motion behavior within that container.
`ViewerFileNavigatorView` supplies the common filter/scroll layout and autohiding scroll bars;
Files adds its root chooser and filter status through its header slots.
`ViewerFileTreeView` is the native outline control used by both viewers. It owns row construction,
disclosure, single/double activation, parent/child keyboard traversal and context-menu targeting.
Adapters supply stable rows and children, including Files' lazy loading and Git's captured hierarchy.
`ViewerFileTreeRow` owns both navigators' 28-point rows, 16-point depth increments,
shared disclosure/icon column, indentation guides, trailing name truncation and full-path
tooltips. `ViewerFileTreeSelectionRow` draws the same outlined selection while retaining
normal label colors. File rows expose captured file actions through their context menus.
Git counts are optional accessories; the snapshot projection and
workspace lazy outline remain separate adapters. Folder expansion does not open a file
or change the selected tool tab.
`ViewerFileActions` captures each menu's path and content provider, owns clipboard/export
and external-opening actions, common menu sections, error presentation and installed-application
destinations. The Copy Markdown button uses the same clipboard writer. Files supplies
its captured source buffer and recovery commands; Changes supplies comparison-blob bytes.
Changes labels workspace-opening commands explicitly and offers them only for existing
workspace files. Exporting a compared version never substitutes patch text or workspace bytes.
`ViewerStatusView` supplies readable, selectable loading and failure messages and the optional
empty-state icon/title. Each feature owns its message, retry and recovery decisions.
File tabs and the Files landing tab use the same package artwork. Native outline
and text-finder controls retain their system icons; the Open action retains the
selected application's system-provided icon.

## Native adaptation rationale

Each main window has its own toolbar identifier because its tools-pane composition
can differ from other windows. AppKit synchronizes items between toolbars with the
same identifier, including when configuration autosaving is disabled. Toolbar
composition belongs to the window's controller; configuration autosaving stays
disabled because the application supplies that composition.

The composer editor paints the same surface color as its enclosing view so AppKit can repaint the previous insertion point. Its setup belongs to [composer configuration](../Sources/CodexGUI/Features/Conversation/ConversationViewController/ConversationViewController+Composer.swift).

Project/location strips and voice controls are outside the existing composer components.
Matching the reference does not require reserving footer space for omitted controls.
The Tools landing page places Changes and Files side by side when two columns fit,
and stacks full-width tiles in narrow panes. Use the source owners above for sizing calculations.

Popover surface shadows need transparent panel padding to avoid clipping; adding a second native window shadow would darken the result. AppKit controls backdrop blur, which requires paired visual acceptance against the reference. See [popover styling](../Sources/CodexGUI/Features/Conversation/Composer/EffortPopoverStyle.swift) and the panel owner above for implementation.

Effort hover motion approximates the observed trajectory and respects Reduce Motion. Hover and particle implementation belongs to [EffortSlider](../Sources/CodexGUI/Features/Conversation/Composer/EffortSlider.swift).

## Reference and acceptance

Reference measurements apply to the measured revision and appearance preferences; they do not establish the current implementation's visual parity. Codex GUI uses compiled styling and effective macOS appearance.

Native adaptation does not establish pixel equivalence. CSS and Core Animation shadow kernels differ, native panels retain OS-controlled effects, and system text rendering can differ despite matching font instances and glyph advances. These differences require visual acceptance rather than equality of source constants.

Use [validation](validation.md) for checks and evidence limits, and [native QA](native-qa.md) for acceptance procedures.

Styling comparisons require paired captures with matching content, control state and appearance preferences. Cover both appearances at wide and narrow widths, including selection, hover, focus, disabled controls, multiline drafts, long code, tables and retained tool tabs. Unmeasured reference descendants, syntax colors and native window chrome must not be inferred from a container's inherited style.
