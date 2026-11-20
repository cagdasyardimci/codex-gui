import { invoke } from '@tauri-apps/api/core';
import type { WorkspaceSnapshot } from './generated/workspace';
import { navigateWorkspace } from './projectIpc';
import { click, editor, typeText, waitFor } from './fixtureControls';

const FIRST = 'history-first';
const SECOND = 'history-second';
const DRAFT = 'Composed café 日本語';
const UNSENT = 'Unsent checkout draft';
const REPLY = 'A streamed reply with café 日本語 👩🏽‍💻.';

function shortcut(key: string, composing = false) {
  window.dispatchEvent(new KeyboardEvent('keydown', { key, ctrlKey: true, isComposing: composing }));
}

function containsText(text: string) {
  return document.querySelector('.workspace-transcript')?.textContent?.includes(text) ?? false;
}

export async function verifyHistory(
  phase: 'initial' | 'restore',
  visible: () => WorkspaceSnapshot | null,
) {
  try {
    await waitFor('Selected project or chat list was missing', () =>
      !!visible()?.workspace?.projectPath.includes('Checkout café') &&
      visible()?.navigation.chats.length === 2);
    const workspaceId = visible()?.workspace?.workspaceId;
    if (!workspaceId) throw new Error('Could not capture the project owner');
    if (phase === 'restore') {
      await waitFor('Restart did not restore the selected chat and draft', () =>
        visible()?.navigation.selectedChat === FIRST && editor().value === DRAFT && containsText(REPLY));
      shortcut('n');
      await waitFor('New Chat shortcut did not select the unsent draft', () =>
        visible()?.navigation.selectedChat === null);
      await waitFor('New Chat shortcut did not retain the unsent draft', () =>
        editor().value === UNSENT);
      await waitFor('New Chat shortcut did not focus the composer', () =>
        document.activeElement === editor());
      await click('Clear Project');
      await waitFor('Clearing the project lost the unsent draft', () =>
        visible()?.workspace === null && visible()?.navigation.draft?.text === UNSENT &&
        visible()?.navigation.account.identity === 'fixture@example.invalid' &&
        editor().value === UNSENT && !document.querySelector('nav[aria-label="Chats"]') &&
        Array.from(document.querySelectorAll('.composer-actions button'))
          .some((button) => button instanceof HTMLButtonElement && button.textContent?.trim() === 'Send' && button.disabled));
      try {
        await navigateWorkspace({ refresh: { workspaceId } });
        throw new Error('Retired workspace could still access chat history');
      } catch (error) {
        if (error !== 'retiredWorkspace') throw error;
      }
    } else {
      typeText(UNSENT);
      await waitFor('Unsent draft did not persist', () => visible()?.navigation.draft?.text === UNSENT);
      await click('First fixture chat');
      await waitFor('Writer lock did not leave readable history', () =>
        visible()?.navigation.selectedChat === FIRST && !!visible()?.navigation.retryable &&
        containsText('History in the first chat.'));
      const control = editor();
      control.focus();
      control.dispatchEvent(new CompositionEvent('compositionstart', { bubbles: true }));
      typeText(DRAFT, true);
      shortcut('n', true);
      if (visible()?.navigation.selectedChat !== FIRST || document.activeElement !== control) {
        throw new Error('IME input changed the selected chat or focus');
      }
      control.dispatchEvent(new CompositionEvent('compositionend', { bubbles: true, data: DRAFT }));
      await waitFor('Committed IME text was not saved', () => visible()?.navigation.draft?.text === DRAFT);
      await click('Retry');
      await waitFor('Cold resume did not stream into the selected chat', () =>
        !visible()?.navigation.retryable && containsText('A streamed reply') && !containsText(REPLY));
      await waitFor('The complete stream was not rendered exactly', () =>
        containsText(REPLY) && !!visible()?.transcript.items.some((item) => item.completed && item.text === REPLY));
      await click('Second fixture chat');
      await waitFor('Chat switching showed stale transcript or draft', () =>
        visible()?.navigation.selectedChat === SECOND && !containsText(REPLY) &&
        containsText('History in the second chat.') && editor().value === '');
      await click('First fixture chat');
      await waitFor('Returning to the first chat did not restore its draft', () =>
        visible()?.navigation.selectedChat === FIRST && containsText(REPLY) && editor().value === DRAFT);
      await click('Refresh');
      await click('Reconnect');
      await waitFor('Refresh or reconnect lost the selected history', () =>
        visible()?.navigation.selectedChat === FIRST && containsText(REPLY) && editor().value === DRAFT &&
        !!Array.from(document.querySelectorAll('button')).find((button) => button.textContent?.trim() === 'Reconnect' && !button.disabled));
    }
    await invoke('verify_history_result', { failure: null });
  } catch (error) {
    const navigation = visible()?.navigation;
    const control = document.querySelector<HTMLTextAreaElement>('textarea[aria-label="Message"]');
    const evidence = {
      phase, selectedChat: navigation?.selectedChat, viewText: navigation?.draft?.text,
      editorText: control?.value, editorFocused: document.activeElement === control,
      documentFocused: document.hasFocus(), activeElement: document.activeElement?.localName,
    };
    await invoke('verify_history_result', { failure: `${String(error)} ${JSON.stringify(evidence)}` });
  }
}
