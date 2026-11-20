import { invoke } from '@tauri-apps/api/core';
import type { WorkspaceSnapshot } from './generated/workspace';
import { click, typeText, waitFor } from './fixtureControls';

const GENERATED = 'Réparer le flux';
const MANUAL = 'Manual chat title';
const FIRST_INPUT = 'Refactor the message stream\n' + 'é'.repeat(4_100);
const SECOND_INPUT = 'Keep the manual chat title';

export async function verifyAutomaticTitles(visible: () => WorkspaceSnapshot | null) {
  const chat = () => visible()?.navigation.selectedChat;
  const title = (id: string) => visible()?.navigation.sidebar.chats.find((row) => row.key.chatId === id)?.title;
  async function start(text: string) {
    await click('New Chat');
    await waitFor('The new conversation draft was not selected', () => chat() === null);
    typeText(text);
    await waitFor('The first prompt was not saved', () => visible()?.navigation.draft?.text === text);
    await click('Send');
    await waitFor('The first prompt did not bind its new chat', () => chat()?.startsWith('thread-') === true);
    return chat()!;
  }
  try {
    const first = await start(FIRST_INPUT);
    if (title(first) !== FIRST_INPUT.replace('\n', ' ').slice(0, 120)) {
      throw new Error('The new chat lost its bounded provisional title');
    }
    await click('First fixture chat');
    await waitFor('The existing chat did not select', () => chat() === 'history-first');
    await waitFor('The completed title did not apply to the initiating chat', () =>
      chat() === 'history-first' && title(first) === GENERATED && title('history-first') === 'First fixture chat');
    if (visible()?.navigation.sidebar.chats.some((row) => row.key.chatId.startsWith('title-helper-')) ||
        visible()?.transcript.items.some((row) => row.text.includes('Réparer'))) {
      throw new Error('The ephemeral helper became visible in another chat');
    }

    const second = await start(SECOND_INPUT);
    await waitFor('The ordinary turn did not finish while generating a title', () =>
      visible()?.transcript.items.some((row) => row.completed && row.text === 'The ordinary fixture turn completed.') === true &&
      visible()?.navigation.actions.send === true);
    const row = () => document.querySelector(`[data-sidebar-chat="${CSS.escape(second)}"]`);
    const rename = () => [...(row()?.querySelectorAll<HTMLButtonElement>('details button:enabled') ?? [])]
      .find((button) => button.textContent?.trim() === 'Rename Chat');
    await waitFor('The source chat was not eligible for manual rename', () => !!rename());
    row()?.querySelector('summary')?.click();
    rename()?.click();
    const field = () => document.querySelector<HTMLInputElement>('dialog[aria-label="Rename Chat"][open] input');
    await waitFor('The rename editor did not open', () => !!field());
    field()!.value = MANUAL;
    field()!.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText' }));
    await click('Save Name');
    await waitFor('The manual title did not retire its helper', () => !field() && title(second) === MANUAL);
    await click('Refresh');
    await waitFor('Refreshing changed the captured titles', () =>
      title(first) === GENERATED && title(second) === MANUAL && !field());
    await invoke('verify_attachments_result', { failure: null });
  } catch (error) {
    await invoke('verify_attachments_result', { failure: String(error) });
  }
}
