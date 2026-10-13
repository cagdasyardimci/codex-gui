# Interface styling

This guide maps shared design inputs to their owners in the application target.
Token extraction preserves the current native presentation and interaction policies.
Use AppKit points for geometry and verify changes in the owning component.

## Token ownership and changes

The application target owns its token catalogues. Change a named input in its catalogue,
then rebuild and relaunch so prepared text and width caches use the new configuration.
The catalogues are immutable; there is no mutable global theme or runtime token editor.

| Catalogue | Owns |
| --- | --- |
| [LayoutTokens](../Sources/CodexGUI/App/Design/LayoutTokens.swift) | Dimensions, spacing, insets, icon sizes and layout-policy inputs; simple derived allowances and scalar/range validation, in AppKit points. |
| [ShapeTokens](../Sources/CodexGUI/App/Design/ShapeTokens.swift) | Radii, corner curves, stroke widths and related shape formulas, grouped by component role. |
| [TypographyTokens](../Sources/CodexGUI/App/Design/TypographyTokens.swift) | Value-only text roles, exact interface weights versus native font selections, line-height policy, tracking and text features. |
| [AppKitColorTokens](../Sources/CodexGUI/App/Design/AppKitColorTokens.swift) | Named native dynamic color roles and their light/dark values. |
| [ShadowTokens](../Sources/CodexGUI/App/Design/ShadowTokens.swift) | Immutable native shadow styles and named composite presets. |

The catalogues live in `App/Design` within the existing application target. Layout,
shape and typography descriptions depend on Foundation. Native color and shadow
catalogues use AppKit on the main actor.

| AppKit implementation | Owns |
| --- | --- |
| [AppKitColorResolution](../Sources/CodexGUI/App/Design/AppKitColorResolution.swift) | Dynamic sRGB/grayscale color construction and resolution under a view's effective appearance; it does not depend on named palette roles. |
| [AppKitFontResolver](../Sources/CodexGUI/App/Design/AppKitFontResolver.swift) | Native font construction and font-related attributed-string attributes. |
| [AppKitShapePath](../Sources/CodexGUI/App/Design/AppKitShapePath.swift) | Shared corner contours for native fills, borders and shadow paths; the corner curve is independent of its radius. |
| [AppKitShadowRenderer](../Sources/CodexGUI/App/Design/AppKitShadowRenderer.swift) | Applying exterior and inset shadow styles to layers, including paths, masks and blur conversion. |
| [AppKitControlStyling](../Sources/CodexGUI/App/Design/AppKitControlStyling.swift) | Shared native button, popup and section-label presentation defaults. |

Dependencies flow from native owners through the implementations to their catalogues.
Generic color resolution does not look up named color roles. Views retain their layers,
constraints, event handling and layout/appearance callbacks.

Component owners resolve inputs against actual bounds, content and state. Native views retain
their constraints, interaction and appearance callbacks. Existing native presentation and
layout policies remain unchanged when a consumer adopts the central descriptions.

Keep derived relationships computed and select roles by meaning. Validate immutable
configuration ranges; preserve each component's truncation, scrolling and reflow policy.
Resolve layer colors under the owning view's effective appearance and refresh them when
that appearance changes. Rebuild and relaunch after source-level token changes so prepared
content uses the new configuration. Follow [validation](validation.md) for checks.

The composer text view fills its editor bounds with the same `AppKitColorTokens.composer`
color as its enclosing surface so AppKit can repaint the previous insertion point.

## Pane sizing

The tools pane opens at 320 points and resizes down to 320 points. Its upper drag limit follows the available
split width after the navigation pane, dividers and a 320-point conversation viewport.

Ordinary conversation mode retains a 360-point minimum. `WindowPaneLayoutPolicy`
selects the reservation for the active mode; `WindowPaneController` applies the same
minimum to the native split item. `WindowPaneLayout` validates the immutable window
configuration before forwarding it. Navigation, review, summary and files preferences
must fit their configured bounds, and comfortable conversation width must cover both
minimum reservations. Invalid persisted widths retain their existing fallback policy.

The composer footer reserves its microphone width through `LayoutTokens.ModelSelector`;
the current native footer omits the voice control. Its model trigger keeps the same
width while the effort picker is open.

The effort popover owns its visual-effect backdrop and surface shadow. Its transparent
panel padding accommodates that shadow without adding a second native window shadow.

Model selection replaces the effort content in the same panel. Long model lists scroll;
Escape dismisses the panel and returns focus to the composer.

The effort thumb enlarges visually on hover without changing logical slider geometry.
Its immutable animation configuration controls entry, exit and reduced-motion behavior.

## Tools tab pane

Source owners: [ToolsTabViewController](../Sources/CodexGUI/App/ToolsTabViewController.swift), [ToolsToolbarCoordinator](../Sources/CodexGUI/App/ToolsToolbarCoordinator.swift), [ToolsPaneIcons](../Sources/CodexGUI/App/ToolsPaneIcons.swift).
