# Interface styling

This guide owns shared component boundaries, native adaptation rationale and reference-comparison procedure. Use [AppKit conventions](../CONVENTIONS.md#appkit-behavior-and-accessibility) for accessibility, appearance and deferred dialogs. Current dimensions, colors, typography and component variants belong in source.

## Token ownership and changes

Use the [design catalogues](../Sources/CodexGUI/App/Design/) for named design inputs and [UI components](../Sources/CodexGUI/UI/Components/) for reusable composition. Change a named input at its owner, then rebuild and relaunch so prepared text and measurement caches use the new configuration.

Choose token roles by purpose: equal values do not establish a shared design rule. Compute derived relationships rather than maintaining independent copies. Keep shape and layout responsibilities separate, and leave artwork coordinates, native metrics and operational tolerances with their owners unless they represent shared design decisions. Pure layout helpers consume measured inputs rather than measuring native views or fonts.

Validate configuration fit separately from available-space behavior. A valid configuration still needs truncation, reflow, scrolling or collapse when space shrinks. Measure in the component's coordinate space; a clipped viewport, intrinsic request and final frame can differ.

## Component ownership

A reusable component owns its complete appearance, composition and interaction states. Feature adapters supply semantic content, selection, operation state and callbacks. They must not independently restyle the same variant. Infrastructure helpers support complete components; assembling the same helpers repeatedly in features is not shared component ownership.

Action tooltips share [the tooltip presentation](../Sources/CodexGUI/UI/Components/Controls/DesktopTooltip.swift) through [native control adaptation](../Sources/CodexGUI/UI/Components/Controls/DesktopControlTooltip.swift). Preserve native action routing and keep transient panels passive; focus, pointer exit, dismissal and owner retirement belong to the shared lifecycle. Show shortcut badges only for actions wired in the local app. Give each hover target one tooltip owner: toolbar items with custom views leave presentation to those views, row-wide native tooltips must not cover custom actions, and content embedded in a tooltip-owning control must not register a second native tooltip.

[Turn previews](../Sources/CodexGUI/UI/Transcript/TurnNavigationRail.swift) retire when their anchor or an ancestor is hidden. Full-view pane transitions can hide a conversation without delivering a pointer-exit event, so hidden anchors must also reject new preview presentation.

Domain eligibility, persistence and asynchronous request identity remain feature responsibilities. Native composition reuse must not merge independent decision lifetimes. Apply [DRY](../CONVENTIONS.md#dry-principle) when deciding whether callers share a contract.

Find existing controls and compositions in [UI/Components](../Sources/CodexGUI/UI/Components/) before adding one. Follow [placement conventions](../CONVENTIONS.md#responsibility-boundaries) to select the owning source.

## Native adaptation rationale

Each main window needs its own toolbar identifier: AppKit synchronizes items between toolbars sharing an identifier even when configuration autosaving is disabled. The application supplies toolbar composition, so autosaving remains disabled.

Composer editors paint their enclosing surface color so AppKit can erase the previous insertion point. Popover shadows need transparent panel padding to avoid clipping; adding a second native window shadow darkens the result. System-controlled blur and shadow kernels require rendered comparison.

Rich Mermaid rendering uses a WebKit-prepared vector PDF for AppKit display because AppKit's direct SVG decoder loses Mermaid CSS, text positioning and markers. Exports retain SVG. Offline resource provenance and rebuild instructions belong to the [Mermaid resource guide](../Sources/CodexGUI/Resources/Mermaid/README.md).

Transcript site icons make external requests to Google's favicon service, with LinkPresentation origin metadata as fallback. Requests use the host or origin rather than a link's full path. Keep this network behavior explicit when changing [favicon loading](../Sources/CodexGUI/UI/Markdown/WebLinkFaviconLoader.swift); it is separate from offline diagram rendering.

## Reference and acceptance

For reference-driven work, record the reference revision, content, control state and appearance preferences. Distinguish measured text and geometry from inferred font identity, point conversion and behavior. Use native AppKit points for nominal CSS pixel dimensions, while recognizing that glyph rasterization, shadows and native chrome require visual acceptance.

Use paired captures with matching content and state. Cover both appearances at wide and narrow widths, including hover, focus, selection, disabled controls, multiline drafts, long code, tables and retained tool tabs. Do not infer descendant styles, syntax colors or window chrome from container styles. Unobserved reference appearances remain unverified.

Reference accounts and screenshots do not establish backend capabilities or authorize unrelated controls. Populate identity and usage from the connected account. Keep unavailable actions out of the working capability claims. Follow [validation](validation.md#native-and-live-acceptance) for evidence interpretation and [native QA](native-qa.md) for launched-app procedures.
