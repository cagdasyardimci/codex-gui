# Offline Mermaid runtime

`mermaid.min.js` is the unmodified browser bundle from the official [mermaid@11.12.1 npm distribution](https://registry.npmjs.org/mermaid/-/mermaid-11.12.1.tgz).

SHA-256: `198b19442f86f0b46a17e56d3abf744c3a28a3427e66fa8dada3b589a77babcc`

The Mermaid MIT license is in `LICENSE`; bundled dependency notices remain at the end of the JavaScript bundle. Runtime integration lives in [render.js](render.js) and [index.html](index.html). Native display rationale belongs to [interface styling](../../../../docs/interface-styling.md#native-adaptation-rationale).

`elk.min.js` is rebuilt from the pinned dependencies in the [layout adapter lockfile](../../../../scripts/mermaid-layout/package-lock.json). The [build adapter](../../../../scripts/mermaid-layout/build.mjs) contains the reference-spacing customization and guards its upstream match. Review that customization when updating dependencies.

SHA-256: `552724dd6606ff61355f0554cb167af88c5ecba9b95fd1e65ae2035c175a3930`

Rebuild the adapter with the locked development-only dependencies:

```sh
npm ci --ignore-scripts --prefix scripts/mermaid-layout
node scripts/mermaid-layout/build.mjs
```

The build retains inline notices and produces `ELK-LICENSES.txt` for all bundled packages. The app also includes these notices in `ThirdPartyLicenses/mermaid`. The MIT adapter source is published in the [Mermaid repository](https://github.com/mermaid-js/mermaid/tree/%40mermaid-js/layout-elk%400.2.0/packages/mermaid-layout-elk). ELK.js is distributed under EPL-2.0; its corresponding source is available in [elkjs v0.9.3](https://github.com/kieler/elkjs/tree/v0.9.3).
