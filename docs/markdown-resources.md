# Offline Markdown rendering dependencies

KaTeX, Mermaid and ELK are managed by the root [package manifest](../package.json) and [lockfile](../pnpm-lock.yaml). Upstream JavaScript, stylesheets, fonts and generated notices are build outputs rather than vendored source. The installed app renders offline; Node.js and pnpm are build-time dependencies only.

## Prepare and build

Install Node.js 22 or later with the pnpm version pinned in `package.json`, then run `make resources` from the repository root. This performs a locked `pnpm install --frozen-lockfile` installation with dependency lifecycle scripts disabled and generates the runtime resources. The normal `make build`, `make test`, named test groups and bundle commands prepare resources automatically. Before using SwiftPM or Xcode directly in a fresh checkout, run `make resources` first.

The [resource builder](../scripts/build-markdown-resources.mjs) copies upstream distributions and the app-owned HTML and JavaScript integration into an ignored resource directory consumed by [SwiftPM](../Package.swift). Do not edit generated files. Local integrations remain in [KaTeX](../Sources/CodexGUI/Resources/KaTeX) and [Mermaid](../Sources/CodexGUI/Resources/Mermaid). Rendering and semantic presentation contracts belong to [interface styling](interface-styling.md#native-adaptation-rationale).

## Update dependencies

Update exact dependency versions in the root manifest, run `pnpm install --lockfile-only --ignore-scripts`, review the lockfile, then run `make resources`. pnpm verifies the archive integrity recorded in the lockfile. Keep lifecycle scripts disabled; the resource builder invokes the pinned esbuild binary directly through its API.

The builder retains the ELK adapter's reference-spacing customization and rejects an upstream source that no longer matches. Review that customization when upgrading Mermaid or its layout dependencies. Before accepting an update, verify offline operation, diagram geometry, SVG export, inline math baselines, display math, source fallback, typography and theme refresh using the [validation workflow](validation.md).

## Licenses

The builder copies KaTeX and Mermaid licenses, retains inline JavaScript notices and generates notices for all packages included in the ELK bundle. The [bundle script](../scripts/bundle.sh) installs them in the app's third-party notices. ELK.js uses EPL-2.0; its corresponding source is available in [elkjs v0.9.3](https://github.com/kieler/elkjs/tree/v0.9.3). Review that source link when updating ELK.js.
