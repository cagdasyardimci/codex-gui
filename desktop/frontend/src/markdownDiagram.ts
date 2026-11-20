import mermaid from 'mermaid';
import elkLayouts from '@mermaid-js/layout-elk';

const MAX_SOURCE_LENGTH = 8192;
const MAX_SVG_LENGTH = 2 * 1024 * 1024;
let serial = Promise.resolve();
let nextId = 0;

mermaid.registerLayoutLoaders(elkLayouts);

export function diagram(source: string, signal: AbortSignal): Promise<Blob | undefined> {
  if (source.length > MAX_SOURCE_LENGTH || signal.aborted) return Promise.resolve(undefined);
  const result = serial.then(async () => {
    if (signal.aborted) return;
    const dark = matchMedia('(prefers-color-scheme: dark)').matches;
    mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', htmlLabels: false,
      theme: dark ? 'dark' : 'default', layout: 'elk', maxTextSize: MAX_SOURCE_LENGTH, maxEdges: 128,
      suppressErrorRendering: true, secure: ['secure', 'securityLevel', 'startOnLoad', 'maxTextSize',
        'maxEdges', 'htmlLabels', 'suppressErrorRendering', 'themeCSS', 'themeVariables'] });
    const stage = document.createElement('div');
    stage.className = 'markdown-diagram-stage';
    stage.setAttribute('aria-hidden', 'true');
    document.body.append(stage);
    try {
      const result = await mermaid.render(`markdown-diagram-${++nextId}`, source, stage);
      if (!signal.aborted && result.svg.length <= MAX_SVG_LENGTH) {
        return new Blob([result.svg], { type: 'image/svg+xml' });
      }
    } finally {
      stage.remove();
    }
  });
  serial = result.then(() => {}, () => {});
  return result;
}
