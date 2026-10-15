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
| Transcript message containers and user messages | [ConversationCollectionItem](../Sources/CodexGUI/Features/Conversation/Transcript/ConversationCollectionItem.swift) |
| Window chrome and native toolbar placement | [WindowChromeViewController](../Sources/CodexGUI/App/WindowLayout/WindowChromeViewController.swift), [NativeWindowButtonAlignment](../Sources/CodexGUI/App/NativeWindowButtonAlignment.swift), [toolbar coordinator](../Sources/CodexGUI/App/MainWindowController/MainWindowController+ToolbarAndPanels.swift) |
| Tools tabs, toolbar and artwork | [ToolsTabViewController](../Sources/CodexGUI/App/ToolsTabViewController.swift), [ToolsToolbarCoordinator](../Sources/CodexGUI/App/ToolsToolbarCoordinator.swift), [ToolsPaneIcons](../Sources/CodexGUI/App/ToolsPaneIcons.swift) |
| Inspector and pinned summary | [InspectorViewController](../Sources/CodexGUI/App/InspectorViewController.swift), [PinnedSummaryViewController](../Sources/CodexGUI/Features/PinnedSummary/PinnedSummaryViewController.swift) |

Use the [feature map](../Sources/CodexGUI/Features/README.md) for other presentation owners. Shared text painting is owned by [DesktopTextRendering](../Sources/CodexGUI/App/DesktopTextRendering.swift); composer reference artwork is owned by [ComposerFooterIcons](../Sources/CodexGUI/Features/Conversation/Composer/ComposerFooterIcons.swift).

## Native adaptation rationale

Each main window has its own toolbar identifier because its tools-pane composition
can differ from other windows. AppKit synchronizes items between toolbars with the
same identifier, including when configuration autosaving is disabled. Toolbar
composition belongs to the window's controller; configuration autosaving stays
disabled because the application supplies that composition.

The composer editor paints the same surface color as its enclosing view so AppKit can repaint the previous insertion point. Its setup belongs to [composer configuration](../Sources/CodexGUI/Features/Conversation/ConversationViewController/ConversationViewController+Composer.swift).

Project/location strips and voice controls are outside the existing composer components. Matching the reference does not require reserving footer space for omitted controls. The Tools layout reserves column space for actions not yet implemented, so its existing tile need not fill the available row. Use the source owners above for sizing calculations.

Popover surface shadows need transparent panel padding to avoid clipping; adding a second native window shadow would darken the result. AppKit controls backdrop blur, which requires paired visual acceptance against the reference. See [popover styling](../Sources/CodexGUI/Features/Conversation/Composer/EffortPopoverStyle.swift) and the panel owner above for implementation.

Effort hover motion approximates the observed trajectory and respects Reduce Motion. Hover and particle implementation belongs to [EffortSlider](../Sources/CodexGUI/Features/Conversation/Composer/EffortSlider.swift).

## Reference and acceptance

Reference measurements apply to the measured revision and appearance preferences; they do not establish the current implementation's visual parity. Codex GUI uses compiled styling and effective macOS appearance.

Native adaptation does not establish pixel equivalence. CSS and Core Animation shadow kernels differ, native panels retain OS-controlled effects, and system text rendering can differ despite matching font instances and glyph advances. These differences require visual acceptance rather than equality of source constants.

Use [validation](validation.md) for checks and evidence limits, and [native QA](native-qa.md) for acceptance procedures.

Styling comparisons require paired captures with matching content, control state and appearance preferences. Cover both appearances at wide and narrow widths, including selection, hover, focus, disabled controls, multiline drafts, long code, tables and retained tool tabs. Unmeasured reference descendants, syntax colors and native window chrome must not be inferred from a container's inherited style.
