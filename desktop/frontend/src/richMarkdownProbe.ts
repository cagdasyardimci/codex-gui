import { waitFor } from './fixtureControls';
import type { WorkspaceSnapshot } from './generated/workspace';

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
  row()?.querySelector('.markdown-document > p')?.scrollIntoView({ block: 'start' });
  await waitFor('The installed inline math assets did not render the formula', () =>
    !!row()?.querySelector('p math'));
  row()?.querySelector('.markdown-display-math')?.scrollIntoView({ block: 'center' });
  await waitFor('The installed display math assets did not render the fraction', () =>
    !!row()?.querySelector('.markdown-display-math math'));
  row()?.querySelector('.markdown-diagram')?.scrollIntoView({ block: 'center' });
  function image() {
    return row()?.querySelector<HTMLImageElement>('.markdown-diagram img');
  }
  await waitFor('The installed diagram assets did not publish a decoded preview', () =>
    !!image()?.naturalWidth && image()?.src.startsWith('blob:') === true &&
    !document.querySelector('.markdown-diagram-stage'));
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
