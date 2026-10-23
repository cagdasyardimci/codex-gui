/* Offline Mermaid SVG preparation. Called only through structured WebKit arguments. */
// Adapt default rectangular flowchart nodes before ELK measures or routes them.
// Other semantic shapes retain their own sizing rules.
mermaid.registerLayoutLoaders(markdownElkLayouts.default.map(entry => ({
    ...entry,
    loader: async () => {
        const layout = await entry.loader();
        return {
            ...layout,
            render: (data, svg, helpers, options) => layout.render(data, svg, {
                ...helpers,
                insertNode: (parent, node, settings) => {
                    if (data.type === "flowchart-v2" && node.shape === "squareRect") {
                        node.labelPaddingX ??= 36;
                        node.height = Math.max(node.height || 0, 60);
                    }
                    return helpers.insertNode(parent, node, settings);
                },
                insertEdgeLabel: async (parent, edge) => {
                    const label = await helpers.insertEdgeLabel(parent, edge);
                    if (data.type === "flowchart-v2" && edge.label) {
                        sizeMarkdownFlowchartEdgeLabel(label, edge);
                    }
                    return label;
                }
            }, options)
        };
    }
})));

// Give ELK the complete pill bounds before it places connectors or groups.
function sizeMarkdownFlowchartEdgeLabel(label, edge) {
    const text = label.querySelector("text");
    const background = label.querySelector("rect.background");
    if (!text || !background) return;
    for (const span of [text, ...text.querySelectorAll("tspan")]) {
        if (!/font-size\s*:/i.test(edge.labelStyle || "")) span.style.fontSize = "13px";
    }
    if (!/font-weight\s*:/i.test(edge.labelStyle || "")) text.style.fontWeight = "600";
    const ink = text.getBBox();
    const height = Math.max(26, ink.height + 10);
    background.setAttribute("x", String(ink.x - 13));
    background.setAttribute("y", String(ink.y - (height - ink.height) / 2));
    background.setAttribute("width", String(ink.width + 26));
    background.setAttribute("height", String(height));
    const box = label.getBBox();
    edge.width = box.width;
    edge.height = box.height;
    label.parentNode.setAttribute("transform",
        `translate(${-box.x - box.width / 2}, ${-box.y - box.height / 2})`);
}

// Keep WebKit SVG font metrics independent of screen and transform scaling, including
// Mermaid's temporary measurement SVGs. Retain the same mode in the exported SVG.
const markdownDiagramTextRendering = "geometricPrecision";
document.documentElement.style.textRendering = markdownDiagramTextRendering;

globalThis.renderMarkdownDiagram = async function (source, dark, maximumPixels) {
    const fontFamily = "-apple-system, system-ui, Segoe UI, sans-serif";
    const textColor = dark ? "#e4e9f2" : "#1a1c1f";
    const fillColor = dark ? "#1f3554" : "#e0edfe";
    const borderColor = dark ? "#5c81b2" : "#5796ff";
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
            lineColor: dark ? "#9aafcc" : "rgba(26, 28, 31, 0.494)",
            textColor,
            mainBkg: fillColor,
            nodeBorder: borderColor,
            clusterBkg: dark ? "#1d2939" : "#f5f8fe",
            clusterBorder: borderColor,
            titleColor: textColor,
            edgeLabelBackground: dark ? "#161719" : "#ffffff",
            actorBkg: fillColor,
            actorBorder: borderColor,
            actorLineColor: dark ? "#9aafcc" : "rgba(26, 28, 31, 0.494)",
            actorTextColor: textColor,
            signalColor: dark ? "#9aafcc" : "rgba(26, 28, 31, 0.494)",
            signalTextColor: textColor,
            labelBoxBkgColor: dark ? "#161719" : "#ffffff",
            labelBoxBorderColor: dark ? "#41464e" : "#e5e5e5",
            labelTextColor: textColor,
            loopTextColor: textColor,
            activationBkgColor: dark ? "#161719" : "#ffffff",
            activationBorderColor: dark ? "#41464e" : "#e5e5e5",
            noteBkgColor: dark ? "#161719" : "#ffffff",
            noteBorderColor: dark ? "#5bb96c" : "#56c568",
            noteTextColor: textColor,
            doneTaskBkgColor: dark ? "#161719" : "#ffffff",
            doneTaskBorderColor: dark ? "#41464e" : "#e5e5e5",
            taskBkgColor: fillColor,
            taskBorderColor: borderColor,
            activeTaskBkgColor: fillColor,
            activeTaskBorderColor: borderColor,
            pie1: "#539bff",
            pie2: "#62c780",
            pie3: "#f48b52",
            pieStrokeColor: dark ? "#161719" : "#ffffff",
            pieOuterStrokeWidth: "0px",
            cScale0: dark ? "#2866ad" : "#539bff",
            cScale1: dark ? "#27673e" : "#62c780",
            cScale2: dark ? "#894521" : "#f48b52",
            cScale3: dark ? "#735d18" : "#f9d65d"
        },
        fontFamily,
        // Measure the same weight that will be displayed, so node widths include bold ink.
        themeCSS: /^\s*(?:flowchart|graph)\b/m.test(source)
            ? ".node text, .node tspan { font-weight: 600; }"
            : "",
        layout: "elk",
        htmlLabels: false,
        maxTextSize: 8192,
        maxEdges: 128,
        suppressErrorRendering: true,
        deterministicIds: true,
        deterministicIDSeed: "markdown-preview",
        secure: ["secure", "securityLevel", "startOnLoad", "maxTextSize", "maxEdges",
            "suppressErrorRendering", "theme", "themeVariables", "themeCSS", "fontFamily",
            "htmlLabels"],
        flowchart: { htmlLabels: false, useMaxWidth: false, curve: "linear", rankSpacing: 60 },
        sequence: { useMaxWidth: false },
        state: { rankSpacing: /^\s*stateDiagram/m.test(source) ? 75 : 50 },
        gantt: { useMaxWidth: false, useWidth: 1512, fontSize: 14, sectionFontSize: 14,
            barHeight: 20, barGap: 4, leftPadding: 75, rightPadding: 50 },
        mindmap: { useMaxWidth: false }
    });
    const host = document.getElementById("diagram");
    host.replaceChildren();
    try {
        const result = await mermaid.render("markdown-diagram", source);
        host.innerHTML = result.svg;
        const svg = host.querySelector("svg");
        if (!svg) return null;
        styleMarkdownDiagram(svg, dark, textColor);
        const box = svg.viewBox.baseVal;
        if (!(box.width > 0 && box.height > 0)
            || !Number.isFinite(box.width * box.height)) return null;
        const displayScale = Math.min(1, 1800 / box.width, 1800 / box.height);
        const naturalWidth = box.width * displayScale;
        const naturalHeight = box.height * displayScale;
        svg.setAttribute("width", String(naturalWidth));
        svg.setAttribute("height", String(naturalHeight));
        svg.style.maxWidth = "none";
        svg.style.textRendering = markdownDiagramTextRendering;
        // Only self-contained, inert vector content may reach native SVG decoding.
        if (svg.querySelector("image,foreignObject,script")) return null;
        svg.querySelectorAll("a").forEach(node => {
            node.replaceWith(...node.childNodes);
        });
        if (svg.querySelectorAll("*").length > 16384) return null;
        for (const element of [svg, ...svg.querySelectorAll("*")]) {
            for (const attribute of [...element.attributes]) {
                if (/^on/i.test(attribute.name)) return null;
                if (/(^|:)href$/i.test(attribute.name) && !attribute.value.trim().startsWith("#"))
                    return null;
                if (hasExternalMarkdownSVGResource(attribute.value)) return null;
            }
        }
        // Mermaid's generated CSS may refer to local markers, but never external resources.
        const styles = [...svg.querySelectorAll("style")].map(node => node.textContent).join("\n");
        if (hasExternalMarkdownSVGResource(styles)) return null;
        const markup = new XMLSerializer().serializeToString(svg);
        if (new TextEncoder().encode(markup).length > Math.min(1048576, maximumPixels * 4))
            return null;
        return { naturalWidth, naturalHeight, svg: markup };
    } catch (error) {
        host.replaceChildren();
        throw error;
    }
};

// Inspect CSS in both style elements and presentation/inline-style attributes. Resolve CSS
// escapes before checking so escaped function names and imports cannot bypass the resource rule.
function hasExternalMarkdownSVGResource(value) {
    const normalized = value
        .replace(/\/\*[\s\S]*?\*\//g, "")
        .replace(/\\(?:\r\n|[\r\n\f])/g, "")
        .replace(/\\(?:([0-9a-f]{1,6})[ \t\r\n\f]?|([^\r\n\f0-9a-f]))/gi,
            (_, hex, literal) => {
                if (!hex) return literal;
                const codePoint = parseInt(hex, 16);
                return String.fromCodePoint(codePoint > 0 && codePoint <= 0x10ffff
                    && !(codePoint >= 0xd800 && codePoint <= 0xdfff) ? codePoint : 0xfffd);
            });
    if (/@import\b/i.test(normalized)) return true;
    let external = false;
    const remainder = normalized.replace(
        /\burl\s*\(\s*(?:"([^"]*)"|'([^']*)'|([^)]*))\s*\)/gi,
        (_, doubleQuoted, singleQuoted, unquoted) => {
            const target = (doubleQuoted ?? singleQuoted ?? unquoted).trim();
            if (!target.startsWith("#")) external = true;
            return "";
        });
    // Reject malformed URL functions as well; only complete local references are admitted.
    return external || /\burl\s*\(/i.test(remainder);
}

// Keep semantic shapes and source class definitions; only the default presentation changes.
function styleMarkdownDiagram(svg, dark, textColor) {
    const selector = "#" + svg.id;
    const rules = document.createElementNS("http://www.w3.org/2000/svg", "style");
    const canvas = dark ? "#161719" : "#ffffff";
    const outline = dark ? "#414b58" : "#dce1e5";
    const ink = dark ? "#8bbdff" : "#075aaf";
    rules.textContent = `
        ${selector} .edgeLabel .label text { fill: ${textColor}; }
        ${selector} .edgeLabel .label rect { fill: ${canvas}; }
        ${selector} .mindmap-node text { fill: ${textColor}; }
        ${selector} .slice { fill: #1a1c1f; }
        ${selector} .section-root circle { fill: ${dark ? "#2866ad" : "#539bff"}; }
        ${selector} .mindmap-node line { stroke: none; }
        ${selector} .section, ${selector} .section0, ${selector} .section1 { fill: ${canvas}; }
        ${selector} .pieCircle { opacity: 0.7; }
    `;
    const role = svg.getAttribute("aria-roledescription");
    if (svg.classList.contains("classDiagram") || role === "stateDiagram") {
        const labelFill = dark ? "#1f3554" : "#e0edfe";
        const opacity = role === "stateDiagram" ? 0.5 : 1;
        rules.textContent += `
            ${selector} .edgeLabel .label rect { fill: ${labelFill}; opacity: ${opacity}; }
        `;
    }
    if (role === "sequence") {
        // Separate translucent fill and stroke reproduce the reference's overlapping outline.
        const markerColor = dark ? "#9aafcc" : "rgba(26, 28, 31, 0.494)";
        rules.textContent += `
            ${selector} #arrowhead path { fill: ${markerColor}; stroke: ${markerColor}; }
        `;
    }
    if (svg.classList.contains("flowchart")) {
        rules.textContent += `
            ${selector} .node rect { stroke: ${outline}; }
            ${selector} .node polygon, ${selector} .node path { stroke: ${outline}; }
            ${selector} .node text, ${selector} .node tspan { fill: ${ink}; font-weight: 600; }
            ${selector} .cluster rect { fill: ${canvas}; stroke: ${outline}; }
            ${selector} .edgeLabel rect { rx: 14; ry: 14; stroke: ${outline}; }
            ${selector} .edgeLabel text, ${selector} .edgeLabel tspan { fill: ${ink}; }
        `;
    }
    svg.append(rules);
    // Mermaid centers the label's width/height but can omit its padded bbox origin.
    // Center the complete label so ink and backing align with their connector.
    svg.querySelectorAll(".edgeLabel > .label").forEach(label => {
        const box = label.getBBox();
        if (!(box.width > 0 && box.height > 0)
            || !Number.isFinite(box.x + box.y + box.width + box.height)) return;
        label.setAttribute("transform",
            `translate(${-box.x - box.width / 2}, ${-box.y - box.height / 2})`);
    });
    if (svg.classList.contains("flowchart")) {
        svg.querySelectorAll(".node rect, .edgeLabel rect").forEach(rect => {
            if (Number(rect.getAttribute("rx")) > 0) return;
            rect.setAttribute("rx", "16");
            rect.setAttribute("ry", "16");
        });
    }
    if (svg.classList.contains("mindmapDiagram")) {
        svg.querySelectorAll(".mindmap-node > .label").forEach(label => {
            const text = label.querySelector("text");
            if (!text) return;
            const box = text.getBBox();
            label.setAttribute("transform", `translate(${-box.x - box.width / 2},${-box.y - box.height / 2})`);
        });
    }
}
