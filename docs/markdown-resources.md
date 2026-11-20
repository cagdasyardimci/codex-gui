# Offline Markdown rendering dependencies

The Swift reference pins KaTeX, Mermaid and ELK in the root [package manifest](../package.json) and [lockfile](../pnpm-lock.yaml). Both builds generate upstream JavaScript, stylesheets, fonts and notices from pinned dependencies. The installed apps render offline. Node.js and pnpm are build-time dependencies.

Tauri pins its packages in the [frontend manifest](../desktop/frontend/package.json). The frontend production build packages lazy KaTeX and Mermaid modules, local fonts, and the license notices for the bundled dependencies. The [rich Markdown view](../desktop/frontend/src/MarkdownRichBlock.svelte) starts rendering when a completed block enters the viewport and releases its preview when the block is retired.

## Prepare and build

Install Node.js 22 or later with the pnpm version pinned in `package.json`, then run `make resources` from the repository root. Before using SwiftPM or Xcode directly in a fresh checkout, run `make resources` first. Resource preparation uses the lockfile and disables dependency lifecycle scripts; the [Makefile](../Makefile) defines which commands prepare resources automatically.

Do not edit the generated files produced by the [resource builder](../scripts/build-markdown-resources.mjs). Local integrations remain in [KaTeX](../Sources/CodexGUI/Resources/KaTeX) and [Mermaid](../Sources/CodexGUI/Resources/Mermaid). Rendering and semantic presentation contracts belong to [interface styling](interface-styling.md#native-adaptation-rationale).

## Update dependencies

Update exact dependency versions in the root manifest, run `pnpm install --lockfile-only --ignore-scripts`, review the lockfile, then run `make resources`. pnpm verifies the archive integrity recorded in the lockfile. Keep lifecycle scripts disabled; the resource builder invokes the pinned esbuild binary directly through its API.

The builder retains the ELK adapter's reference-spacing customization and rejects an upstream source that no longer matches. Review that customization when upgrading Mermaid or its layout dependencies. Before accepting an update, verify offline operation, diagram geometry, SVG export, inline math baselines, display math, source fallback, typography and theme refresh using the [validation workflow](validation.md).

## Licenses

The builder copies KaTeX and Mermaid licenses, retains inline JavaScript notices and generates notices for all packages included in the ELK bundle. The [bundle script](../scripts/bundle.sh) installs them in the app's third-party notices. ELK.js uses EPL-2.0; its corresponding source is available in [elkjs v0.9.3](https://github.com/kieler/elkjs/tree/v0.9.3). Review that source link when updating ELK.js.
