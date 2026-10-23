# Offline Mermaid runtime

`mermaid.min.js` is the unmodified browser bundle from the official `mermaid@11.12.1`
npm distribution: https://registry.npmjs.org/mermaid/-/mermaid-11.12.1.tgz

SHA-256: `198b19442f86f0b46a17e56d3abf744c3a28a3427e66fa8dada3b589a77babcc`

The Mermaid MIT license is in `LICENSE`; bundled dependency notices are retained at
the end of the JavaScript bundle. This pinned bundle contains all diagram loaders,
including Gantt and mindmap, with no dynamic imports. Runtime rendering reads only
these local resources. The page denies network requests through its content security
policy; diagrams render in strict mode and become bounded, inert SVG attachments with a WebKit-prepared vector PDF representation for AppKit display.

`render.js` and `index.html` are application integration code. SVG text uses
`geometricPrecision` before Mermaid measures labels and retains that mode in exports.
This avoids WebKit changing SVG font metrics with screen or transform scaling.
The [WebKit SVG text implementation](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/rendering/svg/RenderSVGInlineText.cpp)
owns that scaling behavior.

Flowchart node weights, rectangular-node padding and minimum heights, and edge-label
pill bounds are applied before ELK measures or routes them. Cylinders, decision diamonds
and other semantic shapes retain their own sizing rules. Padded edge labels are centered using their complete bounding-box origin and size.
The exported SVG and its native PDF display share the same geometry.

`elk.min.js` bundles `@mermaid-js/layout-elk@0.2.0` with `elkjs@0.9.3` for offline
orthogonal layout, using the existing Mermaid 11 runtime. The integration registers
its loaders before preparing diagrams; no layout chunks or workers are fetched.
The build adapts the pinned layout module's root `spacing.baseValue` from 35 to 40
to match connector spacing in the reference renderer. Cluster spacing remains 30.
The esbuild loader requires exactly one matching module and source value, and
checks both before writing the rebuilt resource so upstream changes fail visibly.

SHA-256: `552724dd6606ff61355f0554cb167af88c5ecba9b95fd1e65ae2035c175a3930`

Rebuild the adapter with the locked development-only dependencies:

```sh
npm ci --ignore-scripts --prefix scripts/mermaid-layout
node scripts/mermaid-layout/build.mjs
```

The build retains inline notices and produces `ELK-LICENSES.txt` for all bundled
packages. The app also includes these notices in `ThirdPartyLicenses/mermaid`.
The MIT adapter source is published in the
[Mermaid repository](https://github.com/mermaid-js/mermaid/tree/%40mermaid-js/layout-elk%400.2.0/packages/mermaid-layout-elk).
ELK.js is distributed under EPL-2.0; its corresponding source is available in
[elkjs v0.9.3](https://github.com/kieler/elkjs/tree/v0.9.3).
