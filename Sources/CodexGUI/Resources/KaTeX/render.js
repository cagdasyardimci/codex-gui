"use strict";

async function renderMarkdownMath(source, dark, maximumPixels, typography, colors, inline) {
  const host = document.getElementById("diagram");
  host.replaceChildren();
  host.style.transform = "none";
  host.style.color = colors.text;
  const formula = document.createElement("span");
  host.appendChild(formula);
  katex.render(source, formula, {
    displayMode: !inline,
    output: "html",
    throwOnError: true,
    errorColor: colors.text,
    trust: false,
    strict: "error",
    maxExpand: 1000,
    maxSize: 32
  });
  const math = formula.querySelector(".katex");
  // KaTeX families carry TeX glyph metrics; substituting UI fonts would invalidate layout.
  // The central typography configuration supplies the size, and semantic ink is inherited.
  math.style.fontSize = `${typography.fontSize}px`;
  math.getBoundingClientRect();
  await document.fonts.ready;
  const marker = document.createElement("span");
  marker.style.cssText = "display:inline-block;width:0;height:0;vertical-align:baseline";
  host.appendChild(marker);
  const bounds = math.getBoundingClientRect();
  const baselineDescent = inline ? bounds.bottom - marker.getBoundingClientRect().top : 0;
  if (![bounds.width, bounds.height, baselineDescent].every(Number.isFinite) ||
      bounds.width <= 0 || bounds.height <= 0 ||
      bounds.width > 1800 || bounds.height > 1800 ||
      bounds.width * bounds.height * 4 > maximumPixels) {
    throw new Error("Math exceeds the prepared-content budget");
  }
  host.style.transform = `translate(${-bounds.left}px, ${-bounds.top}px)`;
  return {
    svg: "",
    naturalWidth: bounds.width,
    naturalHeight: bounds.height,
    baselineDescent
  };
}
