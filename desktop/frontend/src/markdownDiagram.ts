import mermaid from 'mermaid';
import elkLayouts from '@mermaid-js/layout-elk';

const MAX_SOURCE_LENGTH = 8192;
const MAX_SVG_LENGTH = 2 * 1024 * 1024;
const MAX_PREVIEW_EDGE = 1800;
let serial = Promise.resolve();
let nextId = 0;

mermaid.registerLayoutLoaders(elkLayouts);

export function diagram(source: string, signal: AbortSignal): Promise<Blob | undefined> {
  if (source.length > MAX_SOURCE_LENGTH || signal.aborted) return Promise.resolve(undefined);
  const result = serial.then(async () => {
    if (signal.aborted) return;
    const dark = matchMedia('(prefers-color-scheme: dark)').matches;
    mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', htmlLabels: false,
      theme: dark ? 'dark' : 'default', layout: 'dagre', maxTextSize: MAX_SOURCE_LENGTH, maxEdges: 128,
      flowchart: { htmlLabels: false },
      suppressErrorRendering: true, secure: ['secure', 'securityLevel', 'startOnLoad', 'maxTextSize',
        'maxEdges', 'htmlLabels', 'flowchart', 'suppressErrorRendering', 'themeCSS', 'themeVariables'] });
    const stage = document.createElement('div');
    stage.className = 'markdown-diagram-stage';
    stage.setAttribute('aria-hidden', 'true');
    document.body.append(stage);
    try {
      const result = await mermaid.render(`markdown-diagram-${++nextId}`, source, stage);
      if (!signal.aborted) return previewSvg(result.svg);
    } finally {
      stage.remove();
    }
  });
  serial = result.then(() => {}, () => {});
  return result;
}

function previewSvg(source: string): Blob | undefined {
  if (source.length > MAX_SVG_LENGTH) return;
  const template = document.createElement('template');
  template.innerHTML = source;
  const svg = template.content.querySelector('svg');
  const unsupported = svg?.querySelector('script, image, foreignObject, iframe, object');
  if (!svg || unsupported) throw new Error(`SVG element ${unsupported?.localName ?? 'root'} was outside the preview contract`);
  const box = svg.getAttribute('viewBox')?.trim().split(/[ ,]+/).map(Number);
  if (!box || box.length !== 4 || !box.every(Number.isFinite) || box[2]! <= 0 || box[3]! <= 0) throw new Error('SVG dimensions were invalid');
  const scale = Math.min(1, MAX_PREVIEW_EDGE / box[2]!, MAX_PREVIEW_EDGE / box[3]!);
  svg.setAttribute('width', String(box[2]! * scale));
  svg.setAttribute('height', String(box[3]! * scale));
  svg.style.removeProperty('max-width');
  const nodes = svg.querySelectorAll('*');
  if (nodes.length > 16_384) return;
  for (const node of [svg, ...nodes]) {
    for (const attribute of node.attributes) {
      if (/^on/i.test(attribute.name) || /(^|:)href$/i.test(attribute.name) && !attribute.value.startsWith('#') ||
          hasExternalResource(attribute.value)) throw new Error(`SVG attribute ${attribute.name} was outside the preview contract`);
    }
  }
  if ([...svg.querySelectorAll('style')].some((style) => hasExternalResource(style.textContent ?? ''))) throw new Error('SVG styles included an external resource');
  const markup = new XMLSerializer().serializeToString(svg);
  return new Blob([markup], { type: 'image/svg+xml' });
}

function hasExternalResource(value: string): boolean {
  const css = value.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\\(?:\r\n|[\r\n\f])/g, '')
    .replace(/\\(?:([0-9a-f]{1,6})[ \t\r\n\f]?|([^\r\n\f0-9a-f]))/gi, (_, hex, literal) => {
      if (!hex) return literal;
      const point = Number.parseInt(hex, 16);
      return String.fromCodePoint(point > 0 && point <= 0x10ffff ? point : 0xfffd);
    });
  if (/@import\b/i.test(css)) return true;
  const local = /\burl\(\s*(?:(['"])#[^'"\s]+\1|#[^'"\s)]+)\s*\)/gi;
  return /\burl\s*\(/i.test(css.replace(local, ''));
}
