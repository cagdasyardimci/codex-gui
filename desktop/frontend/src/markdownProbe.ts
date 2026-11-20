import type { TranscriptRowRequest, WorkspaceSnapshot } from './generated/workspace';
import { loadTranscriptImage, openTranscriptLink, renderTranscriptMarkdown } from './projectIpc';
import { waitFor } from './fixtureControls';

const TARGET = 'https://example.invalid/path';

export async function verifyRenderedMarkdown(snapshot: WorkspaceSnapshot, scope: TranscriptRowRequest) {
  const main = snapshot.transcript.items.find((item) => item.itemId === 'first-saved-turn/first-markdown');
  const fallback = snapshot.transcript.items.find((item) => item.itemId === 'first-saved-turn/first-markdown-depth');
  if (!main || !fallback) throw new Error('The Markdown fixture rows were missing');
  const row = { ...scope, itemId: main.itemId, revision: main.revision };
  const viewport = document.querySelector<HTMLDivElement>('.workspace-transcript');
  if (viewport) viewport.scrollTop = viewport.scrollHeight;
  const surface = () => document.querySelector(`[data-item-id="${main.itemId}"] .markdown-document`);
  await waitFor('The Markdown row did not mount', () => !!surface());
  surface()?.scrollIntoView({ block: 'center' });
  await waitFor('The offline Markdown renderer did not decode the contained image', () => {
    const image = surface()?.querySelector<HTMLImageElement>('img[alt="Contained panel"]');
    return !!image?.naturalWidth && image.src.startsWith('blob:');
  }).catch((error) => {
    const image = surface()?.querySelector<HTMLImageElement>('img[alt="Contained panel"]');
    throw new Error(`${error.message} ${JSON.stringify({ mounted: !!surface(), parsed: !!surface()?.querySelector('h2'),
      hasImage: !!image, loaded: image?.complete, width: image?.naturalWidth })}`);
  });
  const rendered = surface()!;
  const fallbackRequest = { ...scope, itemId: fallback.itemId, revision: fallback.revision };
  const fallbackSource = document.querySelector(`[data-item-id="${fallback.itemId}"] .markdown-source`);
  if (rendered.querySelector('h2')?.textContent !== 'Markdown fixture' ||
      rendered.querySelector('pre code[data-language="rust"]')?.textContent !== 'let label = "café 日本語";\n' ||
      rendered.querySelector('tbody td strong')?.textContent !== 'café' ||
      rendered.querySelectorAll('img').length !== 1 || rendered.querySelectorAll('button.markdown-link').length !== 2 ||
      rendered.querySelector('figure') || !rendered.textContent?.includes('<figure data-fixture-raw>') ||
      !['Blocked destination', 'Offline remote', 'Escaping path'].every((text) => rendered.textContent?.includes(text)) ||
      fallbackSource?.textContent !== fallback.text || await renderTranscriptMarkdown(fallbackRequest) !== null) {
    throw new Error('The Markdown structure, containment, or source fallback did not match its offline fixture');
  }
  await openTranscriptLink({ row, target: TARGET });
  await rejectsStale(openTranscriptLink({ row, target: 'https://example.invalid/unrelated' }));
  await rejectsStale(loadTranscriptImage({ row, target: '../panel.png' }));
  const heading = () => [...(surface()?.querySelectorAll<HTMLButtonElement>('button.markdown-link') ?? [])]
    .find((control) => control.textContent?.trim() === 'Heading');
  if (!viewport) throw new Error('The Markdown viewport was absent');
  await waitFor('The heading link was absent', () => !!heading());
  viewport.scrollTop = viewport.scrollHeight;
  const before = viewport.scrollTop;
  heading()?.click();
  await waitFor('The offline heading link did not move the viewport', () => viewport.scrollTop < before - 10);
  viewport.scrollTop = viewport.scrollHeight;
  return row;
}

export async function rejectsStale(operation: Promise<unknown>) {
  try {
    await operation;
  } catch (error) {
    if (error === 'staleSelection') return;
    throw error;
  }
  throw new Error('A scoped Markdown operation accepted unrelated or retired content');
}
