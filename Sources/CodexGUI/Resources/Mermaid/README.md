# Offline Mermaid runtime

`mermaid.min.js` is the unmodified browser bundle from the official `mermaid@11.12.1`
npm distribution: https://registry.npmjs.org/mermaid/-/mermaid-11.12.1.tgz

SHA-256: `198b19442f86f0b46a17e56d3abf744c3a28a3427e66fa8dada3b589a77babcc`

The Mermaid MIT license is in `LICENSE`; bundled dependency notices are retained at
the end of the JavaScript bundle. This pinned bundle contains all diagram loaders,
including Gantt and mindmap, with no dynamic imports. Runtime rendering reads only
these local resources. The page denies network requests through its content security
policy; diagrams render in strict mode and become bounded, inert PNG attachments.

`render.js` and `index.html` are application integration code.
