# Design token centralization proposal

Implementation plan. Current token ownership and change rules are documented in the
[interface styling guide](interface-styling.md#token-ownership-and-changes).

This proposal centralizes the repository's design decisions so that changing a named
token updates every place that intentionally uses it. It includes colors, typography,
spacing, control dimensions, radii, shadows and layout policy. Component owners continue
to perform measurement, install constraints, draw and handle interaction.

The scope is the existing application target. Separate packages, token generators,
Figma integration and a runtime theme editor are outside this proposal. The current
[interface styling guide](interface-styling.md) remains the guide to existing styling;
this document describes the proposed organization and its dependency rules.

The central guarantee is conditional: a valid token change reaches its declared
consumers, dependent values are recalculated, and unrelated roles retain their meaning.
Centralization cannot make every arbitrary combination of measurements a valid layout.
Unsupported combinations need an explicit validation rule or a defined layout response.

## 1. Keep a small set of central owners

Group central catalogues and their native implementations in `Sources/CodexGUI/App/Design`,
inside the existing application target. Group component roles inside each catalogue.

| Owner | Responsibility |
| --- | --- |
| `LayoutTokens.swift` | Dimensions, spacing, insets, icon sizes and layout-policy inputs; simple derived allowances and scalar/range validation. |
| `ShapeTokens.swift` | Radii, strokes and related shape formulas, grouped by component role. |
| `TypographyTokens.swift` | Immutable text-role descriptions: font selection, size, weight representation, line-height policy, tracking and relevant text features. |
| `AppKitColorTokens.swift` | Named native dynamic colors and their light/dark values. |
| `ShadowTokens.swift` | Immutable native shadow styles and named composite presets. |
| `AppKitColorResolution.swift` | Dynamic native color construction and resolution under the owning view's appearance, without depending on named palette roles. |
| `AppKitFontResolver.swift` | Native font construction and font-related attributed-string attributes. |
| `AppKitShadowRenderer.swift` | Applying shadow styles to layers, including paths, masks and blur conversion. |
| `AppKitControlStyling.swift` | Shared native button, popup and label presentation defaults. |
| Component and layout owners | Resolve the central descriptions against actual content, bounds and state; apply the result. |

`DesktopSurface.swift` and `DesktopSegmentedControl.swift` remain separate view files in
`App`. The views own retained layers, constraints, events and layout/appearance callbacks.
Feature-local helpers remain beside their features. The pure layout, shape and typography
catalogues use Foundation; native color and shadow catalogues use AppKit on the main actor.

When a shape depends on a layout dimension, pass that dimension explicitly. For example,
the composer radius function receives the owning configuration's control height instead
of reading a global layout default. Sidebar outline geometry derives from its shape
inputs. Keep tab role selection independent of control size.

Pure metric and typography descriptions should be usable without UI access or mutable
global state. Native view mutations and UI factories retain their appropriate main-actor
isolation. Use AppKit points for geometry, normally represented as `CGFloat`; preserve
existing integer geometry representations until a separate change requires fractions.

Keep design inputs, simple derived measurements and immutable configuration checks in the
catalogues. Feature-local pure layout helpers own calculations involving actual bounds,
measured content and state, together with their component-specific fit requirements.
Measurement and drawing consume the same helper and configuration. Native owners measure
fonts and views, install constraints, draw and perform updates. The current helper owners
are listed in the [interface styling guide](interface-styling.md#token-ownership-and-changes).

Suggested metric groups are sidebar, composer, reading column, transcript, tabs,
popovers, summary, window modes and chrome. Within a group, distinguish meaningful
subroles: sidebar project actions and task actions, for example, have different contracts.

Existing helpers can temporarily forward to the catalogues during migration. They must
not retain copied literals that can drift independently. Defaults in
[AppKitLayout](../Sources/CodexGUI/App/WindowLayout/AppKitLayout.swift), such as stack
spacing and pinning insets, also count as design decisions when components inherit them.
An explicit component value intentionally overrides that default.

Share a token because its consumers share a design rule. Two unrelated measurements
that happen to equal 8 should not automatically become the same token. Operational
tolerances, cache capacities and persistence version numbers stay with their owners.

## 2. Give roles names before moving values

A role identifies what a measurement controls. Its current numeric value is not its
identity.

For example, [ToolsTabViewController](../Sources/CodexGUI/App/ToolsTabViewController.swift)
currently selects a button radius using this comparison:

```swift
button.cornerRadius = size == Layout.closeControlSize ? 10 : 12.5
```

The close control is currently 20 points and other controls are 28 points. If the close
size becomes 28, the other 28-point controls also satisfy the comparison and acquire a
10-point radius. Moving the numbers into a central file alone would preserve this bug.

The proposed consumer chooses metrics by role, such as close, add, expand or hide. Each
role supplies its intended size and radius. Changing the close size then changes only
the close size and relationships that explicitly depend on it.

The same rule applies to colors and fonts. Equal present values do not imply that two
roles must change together.

## 3. Make dependencies explicit and one-directional

There are three different relationships to represent.

| Relationship | Meaning | Example |
| --- | --- | --- |
| Derived value | An output is calculated from authoritative inputs. | Permission title inset equals leading padding plus icon width plus icon-to-title gap. |
| Compatibility requirement | Independently meaningful inputs must satisfy a condition. | A preference group must fit the action row under the current composer constraints. |
| Available-space policy | The component responds to actual space and content. | Reflow the composer footer, truncate a title, scroll tabs or collapse a pane. |

Derived values should be computed properties or pure functions, not separately editable
constants. Keep their dependency direction visible:

```text
authoritative component inputs
    -> derived geometry
    -> component measurement, drawing and constraints
```

Avoid circular definitions such as deriving a control height from a footer height while
also deriving that footer height from the control. Choose the independent input first.
There is no need for a generic token registry, expression language or dependency resolver;
ordinary Swift references and focused functions are sufficient for this repository.

A compatibility requirement is not automatically a formula. If two control heights
have separate meanings, retain both and validate their relationship. Derive them from
one shared height only when the design deliberately requires them to remain equal.

## 4. Resolve layout in two phases

The first phase is pure calculation. It resolves relationships between inputs, including
title insets, action-group widths, section-header heights and minimum tab widths.

The second phase uses runtime facts: actual bounds, measured text, font metrics,
attachments, selected content and window mode. The component selects a layout mode and
applies constraints or drawing geometry using those facts and the first phase's outputs.

Native layout can repeat the second phase after widths, content or state change. Token
dependency resolution being one-directional does not mean AppKit lays out the view in
one pass. Layout callbacks must update width-dependent decisions, and mutually exclusive
constraint sets must be switched together. Initial layout can use a conservative mode
before a usable width exists.

Keep these measurements distinct:

| Measurement | Meaning |
| --- | --- |
| Natural content size | Space the content needs without the component's caps. |
| Requested intrinsic size | Size the component asks its parent to provide. |
| Allocated frame | Space the parent actually provides. |
| Desired constraint value | Target expressed by a layout constraint. |
| Settled frame | Geometry after priorities, other constraints and layout passes resolve. |

A consistent token update does not necessarily enlarge a view. A fixed allocation may
instead leave less room for its title, which then truncates according to existing policy.

## 5. Sidebar: derive alignment and compensated gaps

[NavigationSidebarLayout](../Sources/CodexGUI/Features/Navigation/NavigationSidebarLayout.swift)
already centralizes several sidebar relationships. Preserve that structure when moving
its authoritative values into the proposed catalogue.

Current inputs include row height 30, row spacing 1, cell inset 8, icon size 16,
icon-to-text gap 8, section spacing 16 and section-content spacing 4.

```text
projectTitleInset = cellInset + iconSize + iconTextSpacing
                  = 8 + 16 + 8 = 32

sectionTopInset = firstSection ? 0 : sectionSpacing - rowSpacing
sectionRowHeight = sectionTopInset + rowHeight
                   + sectionContentSpacing - rowSpacing
```

The 32-point title inset is inside the cell. Adding the pane's outer 8-point inset gives
the 40-point pane-relative alignment. Consumers must not add either inset twice.

The current section-row heights are 33 points for the first header and 48 for later
headers. If row spacing becomes 2, those heights become 32 and 46. That compensation
preserves the intended section gaps despite the row container's spacing.

Validate the supported domain of this formula, including heading fit and unsupported
negative adjustments. Do not hide invalid combinations with arbitrary clamping.

Project actions currently use two 20-point controls with an 8-point gap, giving a
48-point group. Task actions use a separate geometry contract. A change to one action
group should not change the other merely because both contain small buttons.

Selection geometry should also use a single relationship where appropriate: a
12.5-point outer radius, a 1-point outline and its 0.5-point inset produce a 12-point
inner radius. Drawing and size calculations should consume the same resolved geometry.

## 6. Composer: distinguish insets, footer rows and editor growth

The main owner is
[ConversationViewController+Composer](../Sources/CodexGUI/Features/Conversation/ConversationViewController/ConversationViewController+Composer.swift).

Current inputs include editor minimum height 44, editor horizontal inset 12, editor top
inset 14, footer horizontal and bottom insets 8, editor-to-footer gap 4, control height
28, leading-control gap 5, action gap 8 and compact-row gap 4. The surface radius is 22;
it is an independent shape decision.

### Horizontal measurements and the breakpoint

Let `S` be the composer surface width:

```text
footerWidth = S - 2 * footerHorizontalInset
editorWidth = S - 2 * editorHorizontalInset
```

At a surface width of 736, the current footer width is 720 and editor width is 712.
Those are distinct inset roles. Existing nested layout must express their difference
or use separate anchors. Changing the footer inset from 8 to 10 should preserve the
editor's 12-point surface inset.

The current 440-point breakpoint applies to footer inner width. Its corresponding
surface width is `440 + 2 * footerHorizontalInset`, currently 456.

| Surface width | Footer inset | Footer inner width | Threshold result |
| --- | --- | --- | --- |
| 456 | 8 | 440 | Wide |
| 456 | 12 | 432 | Compact |
| 464 | 12 | 440 | Wide |

These are source arithmetic examples, not native rendering observations. Resolving the
breakpoint against the wrong width would create inconsistent mode changes.

### Preserve the current footer constraint contract

The action group controls footer height under the current constraints. In wide mode,
its top and bottom define the footer; leading and preference groups must fit within that
height. In compact mode, the leading group occupies the first row and the action group
defines the second row; the preference group must fit within that second row.

With `L` as leading-group height and `A` as action-group height:

```text
wideFooterHeight = A
compactFooterHeight = L + compactRowGap + A
```

These formulas assume the other groups satisfy their row-fit requirements. A
32-point preference group and 28-point action group are incompatible with the current
required relationships. Writing `max(preferenceHeight, actionHeight)` in the token
catalogue would not change those relationships. Supporting that combination would
require an explicit change to the component's constraints.

For an empty composer without attachments and with all three groups at 28 points, the
current body height is 98 in wide mode and 130 in compact mode:

```text
wide = 14 + 44 + 4 + 28 + 8 = 98
compact = 14 + 44 + 4 + (28 + 4 + 28) + 8 = 130
```

If the designated controls all become 32 while retaining those assumptions, the totals
become 102 and 138. Independent control heights require their own compatibility check.

### Editor growth is a target, not an unconditional frame size

The editor grows according to measured text and an independent window-content viewport:

```text
upper = max(editorMinimumHeight, viewportHeight * maximumViewportFraction)
desired = min(upper, max(editorMinimumHeight, measuredContentHeight))
```

The current fraction is 0.25. Use the existing independent viewport source so that the
editor's own changing height does not become its growth limit.

The desired-height equality currently has `.defaultHigh` priority. The controller also
uses an update tolerance and post-layout measurement. Its final frame can therefore
differ temporarily, or because other constraints prevail. The current 2-point update
tolerance is an operational value, not a shared spacing token.

## 7. Control measurement and drawing must share their geometry

### Permission control

[PermissionControlLayout](../Sources/CodexGUI/Features/Conversation/Composer/PermissionControlLayout.swift)
uses leading padding 7, icon width 16, icon-to-title gap 4 and trailing padding 7:

```text
titleInset = 7 + 16 + 4 = 27
widthAllowance = titleInset + 7 = 34
intrinsicWidth = measuredTitleWidth + widthAllowance
```

Preserve its fractional text measurement rather than adding a generic rounding rule.
The icon rectangle and title rectangle should resolve from these same inputs for
measurement and drawing. The parent's required control height should use the intended
shared control-height role.

### Model selector

[ModelEffortSelectionButton](../Sources/CodexGUI/Features/Conversation/Composer/ModelEffortSelectionButton.swift)
has its own rounding and width policy. Its natural width includes `ceil(titleWidth)`,
16 points of horizontal padding, a trailing gap of 4 plus chevron width 16, and an
optional 14-point bolt plus 4-point gap.

Its current maximum intrinsic request is 300. Picker presentation uses a 164-point
minimum intrinsic request; other presentation uses a 1-point safety floor. These are
intrinsic request bounds, not required bounds on the allocated frame. The parent gives
the selector low horizontal compression resistance, and the title can truncate in the
middle. There is no separately defined normal readable-title minimum to extract.

The chevron's drawing rectangle and reserved width must come from the same resolved
geometry. Otherwise changing its width can update sizing while leaving its drawing
hardcoded.

For an illustrative measured title width of 240, a visible bolt and an allocated frame
width of 280:

| Chevron width | Natural width | Intrinsic request | Allocated width | Remaining title width |
| --- | --- | --- | --- | --- |
| 16 | 294 | 294 | 280 | 226 |
| 24 | 302 | 300 | 280 | 218 |

The larger chevron consistently consumes another 8 points even though the view's outer
width remains 280. Truncation is the existing response to that shortage.

A future footer policy could combine its breakpoint with the minimum required group
widths. That would be a behavior refinement beyond extracting the current threshold.
Compact mode also needs an explicit fallback or a supported minimum-width restriction;
changing rows does not guarantee that every possible control combination fits.

## 8. Tabs: calculate minimum width for each role

Current tab inputs include configured minimum width 88, maximum width 238, height 32,
gap 2, leading inset 10, trailing inset 7 and minimum selection width 24. Ordinary tabs
have a 20-point close control; conversation tabs have a 28-point More control.

```text
effectiveMinimum(role) = max(configuredMinimum,
                            leadingInset + minimumSelectionWidth
                            + trailingControlSize(role) + trailingInset)
```

At current values the internal requirements are 61 and 69, so both use the configured
88-point minimum. Changing the leading inset to 40 gives an ordinary minimum of 91
and a conversation minimum of 99. A calculation that only considers the close control
would be wrong for conversation tabs.

Use each variant's minimum consistently in header allocation and tab constraints. If
uniform widths are the intended policy, the common floor must satisfy the largest
requirement among visible variants. Validate that the effective floor does not exceed
the configured maximum.

For `n` tabs, the equal-share candidate is:

```text
idealWidth = (availableTabArea - (n - 1) * tabGap) / n
```

Apply the existing minimum/maximum and horizontal-scroll policy to that candidate.
Increasing a valid minimum can make scrolling start sooner; it need not widen the window.

[ToolsTabSurface](../Sources/CodexGUI/App/ToolsTabSurface.swift) also has a geometry
relationship: outer radius 6.5 and edge width 0.5 give a path inset 0.25 and path radius
6.25. Keep that relationship shared between shape construction and edge drawing.
The separator's visibility threshold at pane width 362 remains a distinct visual policy.

## 9. Window policy: validate every mode and coordinate space

[WindowLayoutStore](../Sources/CodexGUI/Persistence/WindowLayoutStore.swift) currently
defines navigation width 255 with bounds 200–280, regular review width 326 with bounds
220–360, a 360-point conversation minimum and a 560-point comfortable width.

[WindowPaneController](../Sources/CodexGUI/App/WindowLayout/WindowPaneController.swift)
selects different contracts for different modes. Tools use a 320-point minimum and no
fixed maximum. Files use the review minimum, a 1000-point maximum and an initial
760-point preference. Summary content is 300 points with an 8-point trailing allowance,
giving an initial pane preference of 308.

Validate the selected mode's preferred width against its active limits. Checking only
the regular default is insufficient. For example, minimum 340, regular default 350 and
maximum 360 form a valid regular configuration, but the summary preference of 308 is
below that minimum. Current pure policy can return a preference without enforcing all
limits. The proposal must either restrict configurations accordingly or explicitly
define how policy handles a preferred width outside its active bounds.

A repeated literal 220 in the files drag clamp should reference the same active-minimum
rule as the mode configuration. Preserve the distinction between policies: saved widths
are accepted when finite and in bounds, otherwise rejected in favor of a default; dragging
can clamp. Do not silently change persistence behavior during token extraction.

### Comfortable width and minimum width serve different purposes

Automatic collapse uses comfortable conversation space. Explicit expansion uses a
minimum-space reservation. With split width 1000, navigation 255, total divider width 2
and review preference 326, the conversation remainder is 417, below comfortable 560.
Automatic mode therefore collapses, while explicit expansion can fit a review pane
because its available review space after reserving 360 is 383, above minimum 220.

At split width 800, the same conversation remainder is 217 and available review space
is 183. Expansion cannot satisfy the review minimum. If only comfortable width becomes
200, the automatic comparison alone passes because 217 is at least 200, despite the
minimum-space problem. Validate the assumptions between comfort, reservation and active
pane limits, or deliberately add a required-fit decision to the policy.

### Viewport width is not always laid-out content width

The tools policy reserves a 320-point conversation viewport, while
[ClippedPaneViewController](../Sources/CodexGUI/App/WindowLayout/ClippedPaneViewController.swift)
can lay out conversation content at a 360-point minimum and clip it within that viewport.
The composer is therefore not necessarily measured at 320 points when the visible
viewport is 320 points wide. Each consumer must use the coordinate space named by its
rule: viewport, content view, surface or inner content rectangle.

The transcript's 736-point reading-column maximum, 40-point horizontal inset and
algorithmic width floor are separate from pane minimums. A reading-column maximum does
not define a minimum window width.

## 10. Typography, transcript geometry and appearance follow the same rules

Typography roles must preserve the existing distinction between measured interface-font
weights such as 430 and native font selections. A numeric weight should not silently
become an approximate named native weight. Keep the existing font construction in
[AppKitFontResolver](../Sources/CodexGUI/App/Design/AppKitFontResolver.swift), separate from the role
descriptions.

Text measurement and drawing must use the same resolved font and paragraph policy.
Current examples include 14-point prose with a 22.75-point line height, 12-point code
with a 20-point line height, and separate inline-code, heading and table roles. Font
size, line height and baseline offset are separate decisions; do not automatically
scale one merely because another changes.

Transcript geometry also crosses measurement and drawing boundaries. In
[ConversationMarkdownLayoutManager](../Sources/CodexGUI/Features/Conversation/Transcript/ConversationMarkdownLayoutManager.swift),
the 48-point code header is used both to reserve paragraph space and to position drawn
content. Its inset, header, bottom padding and inter-block gap must be resolved together.
In [ConversationCollectionItem](../Sources/CodexGUI/Features/Conversation/Transcript/ConversationCollectionItem.swift),
message padding changes wrapping and therefore measured height; measurement and display
must consume the same padding role. Internal reply-action gap and the outer gap between
content and reply actions remain separate roles.

[ParsedConversationContent](../Sources/CodexGUI/Features/Conversation/Transcript/ParsedConversationContent.swift)
uses integer quote-rail geometry. Supporting fractional quote or list offsets would
require a representation change rather than an implicit cast of a new token.

For colors, preserve dynamic `NSColor` values until resolution under the owning view's
`effectiveAppearance`. Retained layer `CGColor` values and attributed colors still need
the documented appearance refresh lifecycle. Centralization does not remove that
responsibility. Only derive an alpha-adjusted role from another color when that
relationship is intentional.

[ShadowTokens](../Sources/CodexGUI/App/Design/ShadowTokens.swift) owns named presets;
[AppKitShadowRenderer](../Sources/CodexGUI/App/Design/AppKitShadowRenderer.swift) owns their
common rendering behavior. Conversion from CSS-style blur to a Gaussian radius remains
an approximation; bounds, spread and corner geometry remain part of shadow resolution.
Renderer implementation margins do not automatically become design tokens.

Native chrome alignment retains its native baseline and callbacks. Extracting its
measurements must preserve the existing control sizes, coordinate conversion and
update behavior. A later visual change to window-button offsets is separate from
centralization.

## 11. Configuration lifetime includes prepared content

[PreparedConversationContent](../Sources/CodexGUI/Features/Conversation/Transcript/ConversationContent.swift)
contains prepared text and layout caches. Existing cache identity assumes a stable
presentation configuration within the prepared object.

For this proposal, a source-level token change is adopted through a rebuild and relaunch,
with freshly prepared content. Variant checks must likewise construct fresh prepared
objects for each configuration. Reusing an object prepared with old fonts or geometry
can make a correct token change appear ineffective.

A runtime theme editor would require a separate invalidation or configuration-identity
design. That additional cache machinery is unnecessary for the proposed scope.

## 12. Handle each kind of conflict explicitly

| Conflict | Response |
| --- | --- |
| One design rule copied into several literals | Replace copies with one authoritative input and explicit consumers. |
| Different roles inferred from equal numbers | Select by role; retain independent inputs where meanings differ. |
| Circular derived definitions | Choose an independent input and one-directional calculations. |
| Incompatible required dimensions | Reject the unsupported configuration or deliberately revise the layout contract. |
| Normal shortage of available space | Apply the defined truncation, reflow, scrolling or collapse policy. |
| Incorrect coordinate-space assumption | Resolve against the actual viewport, content view or inner rectangle specified by the rule. |
| Old prepared text or cached layout | Use fresh preparation for the new configuration, or explicitly invalidate it if runtime changes are later supported. |
| Wide and compact constraints active together | Switch mutually exclusive sets completely and update them during layout. |

Do not reduce constraint priorities merely to conceal an invalid token combination.
Priority is part of the component's behavior and should change only for a defined reason.

## 13. Migrate and verify without changing the initial design

The proposed implementation sequence is:

1. Inventory the existing inputs, consumers, formulas and state-dependent policies.
   Record each measurement's coordinate space and whether it is a requirement, preference,
   cap, threshold or renderer detail.
2. Define named roles and central catalogues using current values. Replace numeric
   role inference with explicit roles. Preserve native interactions and initial visuals.
3. Move one component family at a time. Route measurement, intrinsic sizing, constraints
   and drawing through the same inputs and computed relationships.
4. Validate the supported combinations and preserve existing shortage policies. Treat
   changes to reflow, pane policy, constraint priority or persistence as explicit behavior
   changes rather than consequences of moving constants.
5. Verify baseline values, isolated token changes, interacting changes and retained-view
   transitions, then perform native acceptance.

Verification must distinguish arithmetic from settled native layout. Pure checks establish
derived values and policy decisions; component checks establish installed constraints,
intrinsic requests and drawing geometry; native observation establishes final frames,
clipping, focus, accessibility and appearance behavior.

Important checks include changing close size from 20 to 28 without changing other control
radii; raising a tab inset and checking both trailing-control variants; detecting a
32-point preference control in a 28-point action row; validating summary and files
preferences against their active limits; and repeating width changes on the same attached
component so that layout callbacks and constraint switching are exercised.

Retain independent baseline expectations. A check that derives every expected value from
the same tokens as the implementation cannot establish that the intended baseline was
preserved. Typography checks also need to confirm that measurement and drawing resolve
the same configuration, with freshly prepared content where required.

The measurements and examples in this proposal describe source contracts and arithmetic.
Use the automated checks and native acceptance above when implementing or changing these
rules; source arithmetic alone does not establish observed native rendering.
