import { invoke } from '@tauri-apps/api/core';
import type { WorkspaceSnapshot } from './generated/workspace';
import { click, typeText, waitFor } from './fixtureControls';
import { rejectsStale } from './markdownProbe';
import { openSentPrompt } from './projectIpc';

const FIRST = 'history-first';
const TURN = 'revision-source-turn';
const PROMPT = `${TURN}/editable-prompt`;
const FOLLOW_UP = `${TURN}/later-prompt`;
const SOURCE_DRAFT = 'Source draft remains in its own chat.';

export async function verifyPromptRevision(visible: () => WorkspaceSnapshot | null) {
  const nav = () => visible()?.navigation;
  const selected = () => nav()?.selectedChat;
  const draft = () => nav()?.draft;
  const edit = () => document.querySelector<HTMLButtonElement>(
    `[data-item-id="${CSS.escape(PROMPT)}"] button[aria-label="Edit sent prompt"]`);
  const modal = () => document.querySelector<HTMLDialogElement>('dialog[aria-label="Edit Sent Prompt"][open]');
  async function revise(value: string) {
    await waitFor('The original finished prompt had no Edit action', () => !!edit());
    edit()!.click();
    await waitFor('The original prompt and attachments were not captured', () => {
      const text = modal()?.querySelector('textarea')?.value;
      const labels = [...(modal()?.querySelectorAll('li') ?? [])].map((entry) => entry.textContent?.trim());
      return text === 'Original prompt café' && labels.join('/') === 'Selected notes/picked.png/Image';
    });
    const field = modal()!.querySelector('textarea')!;
    field.value = value;
    field.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText' }));
    await click('Fork and Send');
    await waitFor('The captured fork request did not close its editor', () => !modal());
  }
  try {
    await click('First fixture chat');
    await waitFor('The original chat did not load its finished prompts', () => selected() === FIRST && !!edit());
    const original = visible()!;
    const followUp = original.transcript.items.find((row) => row.itemId === FOLLOW_UP);
    if (!followUp || document.querySelector(`[data-item-id="${CSS.escape(FOLLOW_UP)}"] button[aria-label="Edit sent prompt"]`)) {
      throw new Error('A later user message had an Edit action');
    }
    await rejectsStale(openSentPrompt({ workspaceId: original.workspace!.workspaceId, chatId: FIRST,
      itemId: followUp.itemId, generation: original.transcript.generation, revision: followUp.revision }));
    typeText(SOURCE_DRAFT);
    await waitFor('The independent source draft was not stored', () => draft()?.text === SOURCE_DRAFT);

    await revise('/plan Literal revised prompt café');
    await waitFor('The captured fork was not selected and sent', () =>
      selected() === 'revision-fork-1' && !!nav()?.actions.stop);
    await waitFor('The first fork did not settle', () =>
      nav()?.actions.stop === null && draft()?.text === '' && nav()?.literalForkRevision === false);
    if (visible()?.transcript.items.some((row) => row.turnId === TURN)) {
      throw new Error('The new chat retained the addressed turn after the before-turn fork');
    }

    await click('First fixture chat');
    await waitFor('The original chat or its draft changed', () => selected() === FIRST && draft()?.text === SOURCE_DRAFT);
    await revise('Keep the fork draft after writer lock.');
    await waitFor('Failed writer selection did not preserve the prepared fork draft', () =>
      selected() === 'revision-fork-2' && nav()?.retryable === true &&
      draft()?.text === 'Keep the fork draft after writer lock.' && draft()?.attachments.length === 3 &&
      !nav()?.actions.stop);

    await click('First fixture chat');
    await waitFor('The original chat did not reopen', () => selected() === FIRST && draft()?.text === SOURCE_DRAFT);
    await revise('//status Keep both slashes.');
    await click('Second fixture chat');
    await waitFor('The delayed fork retargeted the visible conversation', () =>
      selected() === 'history-second' && nav()?.chats.some((chat) => chat.id === 'revision-fork-3') === true);
    await click('Revision Fork 3');
    await waitFor('The superseded selection did not retain the revised draft', () =>
      selected() === 'revision-fork-3' && draft()?.text === '//status Keep both slashes.' &&
      draft()?.attachments.length === 3 && nav()?.literalForkRevision === true && !nav()?.actions.stop);
    await click('Send');
    await waitFor('Sending the retained literal draft did not start its own turn', () => !!nav()?.actions.stop);
    await waitFor('The retained fork draft did not settle', () => nav()?.actions.stop === null && draft()?.text === '');
    await click('First fixture chat');
    await waitFor('The final source history or draft changed', () =>
      selected() === FIRST && draft()?.text === SOURCE_DRAFT && visible()?.transcript.items.some((row) => row.itemId === PROMPT) === true);
    await invoke('verify_attachments_result', { failure: null });
  } catch (error) {
    await invoke('verify_attachments_result', { failure: String(error) });
  }
}
