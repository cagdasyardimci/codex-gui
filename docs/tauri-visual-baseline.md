# AppKit visual and asset baseline

The [Swift reference](tauri-parity.md) produced these comparison captures on Apple Silicon macOS 27.0.1 build 26A434 using Xcode 27.2 build 27B52. The signed debug bundle identifier is `local.codexgui.appkit`. Its executable SHA-256 is `f6ea3096ba32cabdfd730c65b8156d63b4d739e3ed8a29a40ab33d3d7a516d65`. The pinned cached dependencies matched the reference lockfile.

Each capture shows the selected `qa-reading` conversation from the component QA fixture. The project, transcript, approval policy, model, and empty draft match across captures. The window captures use 2 pixels per point. The AppKit evidence recorder supplied resolved fonts, colors, and view bounds. Companion state confirmed the connected fixture and selected chat. The standalone runs exercised the signed AppKit build with an isolated mock backend and preference suite. The Xcode interaction suite timed out before its automation session started.

## Matched captures

| Appearance | 1200 × 760 pt | 900 × 760 pt | Composer text view, wide and narrow | Resolved composer color |
| --- | --- | --- | --- | --- |
| Light | [Wide](tauri-visual-baseline/light-wide.png) | [Narrow](tauri-visual-baseline/light-narrow.png) | 531 × 44 pt and 312 × 44 pt | sRGB `#0d0d0d` |
| Dark | [Wide](tauri-visual-baseline/dark-wide.png) | [Narrow](tauri-visual-baseline/dark-narrow.png) | 531 × 44 pt and 312 × 44 pt | sRGB `#fcfcfc` |

The composer resolved to `.SF NS` at 14 pt with optical-size axis 17 and weight axis 430. Its rendered empty field retains the same height at both widths. The narrow state wraps the composer action strip. The attachment, approval policy and Send targets remain 30 pt high in the narrow Dark accessibility geometry. The Send target is 30 pt wide and disabled with the empty draft. The transcript code block retains its code styling, and the terminal row truncates within the narrower viewport.

Match the Mac workspace’s sidebar organization, transcript rhythm, composer and action strip, pinned summary and tools layout, and the visual relationships and focus behavior of shared menus and Settings. Use the reference captures alongside the [Swift regression routes](tauri-regression-evidence.md) to qualify matching surfaces as their owners land. Native title bars, window controls, file pickers, system permissions, clipboard, fullscreen, IME, and accessibility follow platform conventions. Match the user workflow across platforms while recording the differences introduced by native controls.

## Asset disposition

| Asset | Release treatment |
| --- | --- |
| App icon and project-owned appearance illustrations | Use the project originals and preserve the owning artwork and license. Use original SVG sources for the Tauri appearance tiles. [AppKit artwork sources](../Sources/CodexGUI/Resources/AppearanceModes/README.md) · [Project license](../LICENSE.md) |
| Subagent avatars | Reuse the existing light and dark artwork with its CC0 attribution. [Avatar notice](../Sources/CodexGUI/Resources/SubagentAvatars/NOTICE.txt) |
| AppKit system symbols and native decorations | Use platform-provided controls and approved original or redistributable artwork for shared UI. Preserve applicable dependency notices for any SDK artwork that ships. [Third-party notices](../README.md#third-party-notices) |
| Markdown, math, diagram and code resources | Preserve offline behavior and ship the notices for the chosen JS runtime, syntax assets and KaTeX fonts. Use the owning resource guide for provenance and rebuild steps. [Markdown resources](markdown-resources.md) |
| Settings title | Use Inter Semibold v4.1 as the redistributable Tauri face and keep its SIL OFL 1.1 notice with the bundle. Exclude the locally licensed OpenAI Sans font bytes from the Tauri resources. [Inter release](https://github.com/rsms/inter/releases/tag/v4.1) · [Inter license](https://github.com/rsms/inter/blob/v4.1/LICENSE.txt) · [AppKit typography](interface-styling.md) |

CoreText measured the two Settings faces at 18 pt. The advance for “Settings” was 70.47 pt in OpenAI Sans and 71.81 pt in Inter. Inter’s widest change among “Settings,” “Appearance,” and “Notifications” was 4.87 pt. Its 21.78 pt typographic line fits the reference’s 24 pt line box. Confirm installed title fit with the final shared Settings controls at C110.
