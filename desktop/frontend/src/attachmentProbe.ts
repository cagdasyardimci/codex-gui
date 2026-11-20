import type { TranscriptRowRequest, WorkspaceSnapshot } from './generated/workspace';
import { loadTranscriptAttachment } from './projectIpc';
import { click, waitFor } from './fixtureControls';
import { rejectsStale } from './markdownProbe';

export async function verifyTranscriptAttachments(snapshot: WorkspaceSnapshot, scope: TranscriptRowRequest) {
  const item = snapshot.transcript.items.find((row) => row.itemId === 'first-saved-turn/first-attached');
  if (!item) throw new Error('The saved image-only prompt was missing');
  const captures = item.attachments;
  if (item.text || item.localImages.length || captures.length !== 2 ||
      captures.some((attachment, index) => attachment.id !== index || attachment.label !== 'panel.png' ||
        !attachment.image || Object.keys(attachment).length !== 3)) {
    throw new Error('Scoped attachment identities changed order or exposed a local path');
  }
  const row = { ...scope, itemId: item.itemId, revision: item.revision };
  await waitFor('Both checkout-owned attachment thumbnails did not decode', () => {
    const images = [...document.querySelectorAll<HTMLImageElement>(`[data-item-id="${item.itemId}"] .transcript-attachments img`)];
    return images.length === 2 && images.every((image) => image.src.startsWith('blob:') && image.naturalWidth === 1);
  });
  await rejectsStale(loadTranscriptAttachment({ row: scope, attachmentId: 0 }));
  await rejectsStale(loadTranscriptAttachment({ row, attachmentId: 2 }));
  await rejectsStale(loadTranscriptAttachment({ row: { ...row, revision: row.revision + 1 }, attachmentId: 0 }));
  const trigger = document.querySelector<HTMLButtonElement>(`[data-item-id="${item.itemId}"] button[aria-label="Expand panel.png"]`)!;
  trigger.click();
  const viewer = () => document.querySelector<HTMLDialogElement>('dialog.expanded-preview[open]');
  await waitFor('The saved attachment did not open in its expanded viewer', () => !!viewer());
  const dialog = viewer()!;
  await click('Download Original', dialog);
  await waitFor('The saved attachment download did not settle', () =>
    [...dialog.querySelectorAll('button:enabled')].some((control) => control.textContent === 'Download Original'));
  await click('Close', dialog);
  await waitFor('Closing the saved attachment did not restore its previous control', () => !viewer() && document.activeElement === trigger);
  return { row, attachmentId: 0 };
}
