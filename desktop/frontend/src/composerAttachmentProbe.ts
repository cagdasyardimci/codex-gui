import { invoke } from '@tauri-apps/api/core';
import type { DraftAttachmentScope, WorkspaceSnapshot } from './generated/workspace';
import { loadComposerImage, pickComposerAttachments } from './projectIpc';
import { click, clickByLabel, editor, typeText, waitFor } from './fixtureControls';
import { rejectsStale } from './markdownProbe';

const FIRST = 'history-first';
const SECOND = 'history-second';
const PICK = 'picked.png';
const FILE = 'notes.txt';
const PASTE = 'Pasted image';
const FIRST_DRAFT = 'Keep the first project draft.';
const REUSED_DRAFT = 'Keep this text when reusing attachments.';
const PIXEL = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGMQSTnxHwAEEAJAKtk0QwAAAABJRU5ErkJggg==';

export async function verifyComposerAttachments(visible: () => WorkspaceSnapshot | null) {
  try {
    const draft = () => visible()?.navigation.draft;
    const labels = () => draft()?.attachments.map((attachment) => attachment.label).join('\n');
    const active = (thread: string) => visible()?.navigation.selectedChat === thread;
    await click('First fixture chat');
    await waitFor('First fixture chat did not select its draft', () => active(FIRST) && !!draft());
    typeText(FIRST_DRAFT);
    await waitFor('The original draft text did not persist', () => draft()?.text === FIRST_DRAFT);
    const workspaceId = visible()?.workspace?.workspaceId;
    const draftId = draft()?.id;
    if (!workspaceId || !draftId) throw new Error('The attachment fixture had no draft owner');
    const scope: DraftAttachmentScope = { workspaceId, chatId: FIRST, draftId };
    const picked = pickComposerAttachments(scope);
    await new Promise<void>((resolve) => setTimeout(resolve, 75));
    await click('Second fixture chat');
    await waitFor('The picker fixture did not switch draft owners', () => active(SECOND));
    await picked;
    if (labels() || editor().value) throw new Error('The native picker redirected a captured attachment');
    await click('First fixture chat');
    await waitFor('The picker did not restore its original attachment owner', () => labels() === PICK && editor().value === FIRST_DRAFT);
    await invoke('drop_composer_attachment_fixture', { scope });
    const clipboard = new DataTransfer();
    clipboard.items.add(new File([Uint8Array.from(atob(PIXEL), (byte) => byte.charCodeAt(0))], 'paste.png', { type: 'image/png' }));
    editor().dispatchEvent(new ClipboardEvent('paste', { clipboardData: clipboard, cancelable: true }));
    await waitFor('The native drop and paste did not preserve attachment order', () => labels() === [PICK, FILE, PASTE].join('\n'));
    await waitFor('The picker and paste previews did not decode', () =>
      [...document.querySelectorAll<HTMLImageElement>('.composer-attachments img')].filter((image) => image.naturalWidth === 1).length === 2);
    await clickByLabel(`Remove ${PICK}`);
    await clickByLabel(`Remove ${FILE}`);
    typeText('');
    await waitFor('The image-only draft did not retain its pasted bytes', () => labels() === PASTE && draft()?.text === '');
    await click('Send');
    await waitFor('The image-only turn did not publish its stored preview', () =>
      labels() === '' && !!document.querySelector<HTMLImageElement>('.transcript-attachments img[alt="Image"]')?.naturalWidth &&
      visible()?.navigation.actions.stop === null);
    typeText(REUSED_DRAFT);
    await waitFor('The draft for reuse did not persist', () => draft()?.text === REUSED_DRAFT);
    await clickByLabel('Attach Image to draft');
    await waitFor('The sent image did not reattach to the draft', () => labels() === 'Image');
    await clickByLabel(`Attach ${FILE} to draft`);
    await waitFor('Reusing history attachments changed the pending text or order', () =>
      labels() === ['Image', FILE].join('\n') && editor().value === REUSED_DRAFT && draft()?.text === REUSED_DRAFT);
    const reused = draft()?.attachments[0];
    if (!reused) throw new Error('The reused image was not captured');
    await click('Second fixture chat');
    await waitFor('Switching chats leaked the reused attachment or text', () => active(SECOND) && !labels() && editor().value === '');
    await rejectsStale(loadComposerImage({ scope, attachmentId: reused.id }));
    await click('First fixture chat');
    await waitFor('The original draft did not restore reused attachments', () =>
      active(FIRST) && editor().value === REUSED_DRAFT && labels() === ['Image', FILE].join('\n'));
    await invoke('verify_attachments_result', { failure: null });
  } catch (error) {
    await invoke('verify_attachments_result', { failure: String(error) });
  }
}
