import { waitFor } from './fixtureControls';
import type { WorkspaceSnapshot } from './generated/workspace';
import { richBlockPhase } from './MarkdownRichBlock.svelte';

const FORMULA = '$x^2$';
export const RICH_SUFFIX = '\n\nInline $x^2$.\n\n$$\\frac{a}{b}$$\n\n```mermaid\nflowchart LR\n  A[Local] --> B[Offline]\n```';

function richRow(visible: () => WorkspaceSnapshot | null) {
  return visible()?.transcript.items.find((item) => item.text.includes(FORMULA));
}

function surface(itemId: string | undefined) {
  return itemId ? document.querySelector(`[data-item-id="${CSS.escape(itemId)}"]`) : null;
}

export async function verifyStreamingFormula(visible: () => WorkspaceSnapshot | null) {
  await waitFor('Formula syntax did not remain readable during streaming', () => {
    const item = richRow(visible);
    const row = surface(item?.itemId);
    return !!item && !item.completed && !!row?.querySelector('.markdown-source')?.textContent?.includes(FORMULA) &&
      !row.querySelector('math, .markdown-diagram');
  });
}

export async function verifySettledRichMarkdown(visible: () => WorkspaceSnapshot | null) {
  const viewport = document.querySelector<HTMLDivElement>('.workspace-transcript');
  if (viewport) viewport.scrollTop = viewport.scrollHeight;
  const row = () => surface(richRow(visible)?.itemId);
  await waitFor('The completed Markdown row did not mount its rich blocks', () =>
    !!row()?.querySelector('.markdown-diagram') && !!row()?.querySelector('.markdown-display-math'));
  // Keep the same row mounted while measuring asynchronously decoded content.
  row()?.querySelector<HTMLButtonElement>('.transcript-copy')?.focus({ preventScroll: true });
  const inline = row()?.querySelector('.markdown-inline-math');
  inline?.scrollIntoView({ block: 'center', inline: 'nearest' });
  await waitFor('The installed inline math assets did not render the formula', () =>
    !!row()?.querySelector('.markdown-inline-math math')).catch((error) => {
    const formula = row()?.querySelector('.markdown-inline-math');
    const resources = performance.getEntriesByType('resource').map((entry) => entry.name.split('/').pop())
      .filter((name) => name && /markdownFormula|[Kk]a[Tt]e[Xx]/.test(name));
    throw new Error(`${error.message} ${JSON.stringify({ mounted: !!formula, formula: formula?.getBoundingClientRect().toJSON(),
      viewport: viewport?.getBoundingClientRect().toJSON(), resources })}`);
  });
  row()?.querySelector('.markdown-display-math')?.scrollIntoView({ block: 'center' });
  await waitFor('The installed display math assets did not render the fraction', () =>
    !!row()?.querySelector('.markdown-display-math math'));
  row()?.querySelector('.markdown-diagram')?.scrollIntoView({ block: 'center' });
  function image() {
    return row()?.querySelector<HTMLImageElement>('.markdown-diagram img');
  }
  await waitFor('The installed diagram assets did not publish a decoded preview', () =>
    !!image()?.naturalWidth && image()?.hidden === false && image()?.src.startsWith('blob:') === true &&
    !document.querySelector('.markdown-diagram-stage')).catch((error) => {
    const preview = image();
    const container = row()?.querySelector<HTMLElement>('.markdown-diagram');
    const resources = performance.getEntriesByType('resource').map((entry) => entry.name.split('/').pop())
      .filter((name) => name && /markdownDiagram|flowDiagram|render-/.test(name));
    throw new Error(`${error.message} ${JSON.stringify({ pendingRender: !!document.querySelector('.markdown-diagram-stage'),
      hasImage: !!preview, hidden: preview?.hidden, loaded: preview?.complete, width: preview?.naturalWidth, resources,
      renderPhase: container ? richBlockPhase.get(container) : undefined })}`);
  });
  const preview = image()!;
  const source = preview.src;
  const revoke = URL.revokeObjectURL;
  let released = false;
  URL.revokeObjectURL = (url: string) => {
    released ||= source === url;
    revoke(url);
  };
  return async () => {
    try {
      await waitFor('Switching chats did not release the mounted diagram preview', () =>
        released && !preview.isConnected && !document.querySelector('.markdown-diagram-stage'));
    } finally {
      URL.revokeObjectURL = revoke;
    }
  };
}
