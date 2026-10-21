/* Offline Mermaid raster preparation. Called only through structured WebKit arguments. */
globalThis.renderMarkdownDiagram = async function (source, dark, maximumPixels) {
    const fontFamily = "-apple-system, system-ui, Segoe UI, sans-serif";
    const textColor = dark ? "#e4e9f2" : "#1f2328";
    const fillColor = dark ? "#1f3554" : "#e8f0fe";
    const borderColor = dark ? "#5c81b2" : "#9cb7e7";
    mermaid.initialize({
        startOnLoad: false,
        securityLevel: "strict",
        theme: "base",
        themeVariables: {
            darkMode: dark,
            fontFamily,
            fontSize: "14px",
            background: dark ? "#161719" : "#ffffff",
            primaryColor: fillColor,
            primaryTextColor: textColor,
            primaryBorderColor: borderColor,
            secondaryColor: dark ? "#293b52" : "#eef4ff",
            secondaryTextColor: textColor,
            secondaryBorderColor: borderColor,
            tertiaryColor: dark ? "#243044" : "#f6f9ff",
            tertiaryTextColor: textColor,
            tertiaryBorderColor: borderColor,
            lineColor: dark ? "#9aafcc" : "#7a8aa6",
            textColor,
            mainBkg: fillColor,
            nodeBorder: borderColor,
            clusterBkg: dark ? "#1d2939" : "#f5f8fe",
            clusterBorder: borderColor,
            titleColor: textColor,
            edgeLabelBackground: dark ? "#161719" : "#ffffff",
            actorBkg: fillColor,
            actorBorder: borderColor,
            actorTextColor: textColor,
            signalColor: dark ? "#9aafcc" : "#7a8aa6",
            signalTextColor: textColor
        },
        fontFamily,
        htmlLabels: false,
        maxTextSize: 8192,
        maxEdges: 128,
        suppressErrorRendering: true,
        deterministicIds: true,
        deterministicIDSeed: "markdown-preview",
        secure: ["secure", "securityLevel", "startOnLoad", "maxTextSize", "maxEdges",
            "suppressErrorRendering", "theme", "themeVariables", "themeCSS", "fontFamily",
            "htmlLabels"],
        flowchart: { htmlLabels: false, useMaxWidth: false },
        sequence: { useMaxWidth: false },
        gantt: { useMaxWidth: false, useWidth: 900, fontSize: 14, sectionFontSize: 14,
            barHeight: 24, barGap: 8, leftPadding: 100, rightPadding: 50 },
        mindmap: { useMaxWidth: false }
    });
    const host = document.getElementById("diagram");
    host.replaceChildren();
    try {
        const result = await mermaid.render("markdown-diagram", source);
        host.innerHTML = result.svg;
        const svg = host.querySelector("svg");
        if (!svg) return null;
        const box = svg.viewBox.baseVal;
        if (!(box.width > 0 && box.height > 0)
            || !Number.isFinite(box.width * box.height)) return null;
        const displayScale = Math.min(1, 900 / box.width, 1800 / box.height);
        const naturalWidth = box.width * displayScale;
        const naturalHeight = box.height * displayScale;
        // Preserve the full diagram while bounding both PNG dimensions and retained pixels.
        const scale = Math.min(2, 4096 / box.width, 4096 / box.height,
            Math.sqrt((maximumPixels - 8192) / (box.width * box.height)));
        const width = Math.max(1, Math.floor(box.width * scale));
        const height = Math.max(1, Math.floor(box.height * scale));
        if (width * height > maximumPixels) return null;
        svg.setAttribute("width", String(width));
        svg.setAttribute("height", String(height));
        svg.style.maxWidth = "none";
        // Keep source fallback when the SVG cannot be rasterized without losing content.
        if (svg.querySelector("image,foreignObject,script")) return null;
        svg.querySelectorAll("a").forEach(node => {
            node.replaceWith(...node.childNodes);
        });
        const markup = new XMLSerializer().serializeToString(svg);
        const image = new Image();
        await new Promise((resolve, reject) => {
            image.onload = resolve;
            image.onerror = reject;
            image.src = "data:image/svg+xml;charset=utf-8," + encodeURIComponent(markup);
        });
        const canvas = document.createElement("canvas");
        canvas.width = width;
        canvas.height = height;
        const context = canvas.getContext("2d");
        context.drawImage(image, 0, 0, width, height);
        return { width, height, naturalWidth, naturalHeight, png: canvas.toDataURL("image/png") };
    } finally {
        host.replaceChildren();
    }
};
