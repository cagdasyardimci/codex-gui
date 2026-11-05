# Appearance mode illustrations

These reference mode illustrations depict Light and Dark independently of custom theme colors. Their fixed neutral fills are narrowly scoped artwork; accent marks and the owning control's selection border use semantic theme colors. Original SVG sources are retained here. Runtime drawing uses WebKit-prepared vector PDF plates to retain the illustration filters and shadows, with separate template masks for semantic accent marks.

After editing the source SVGs, regenerate both representations on macOS:

```sh
swiftc -parse-as-library scripts/render-appearance-modes.swift -o .build/render-appearance-modes
.build/render-appearance-modes Sources/CodexGUI/Resources/AppearanceModes
```

Verify the generated plates in both appearances and check semantic accent changes using the owning renderer's tests. The preparation tool is an asset-build step; the application loads bundled native vector representations without starting WebKit for these controls.
