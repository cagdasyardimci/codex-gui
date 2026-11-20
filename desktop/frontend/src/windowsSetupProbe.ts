import { invoke } from '@tauri-apps/api/core';
import { click, editor, typeText, waitFor } from './fixtureControls';
import type { WorkspaceSnapshot } from './generated/workspace';
import { navigateWorkspace } from './projectIpc';

export async function verifyWindowsSetup(visible: () => WorkspaceSnapshot | null) {
  const firstChat = 'history-first';
  const draft = 'Draft retained during Windows sandbox setup 日本語';
  try {
    await waitFor('The sandbox action was missing for the selected checkout', () =>
      !!visible()?.navigation.chats.length &&
      ['setupSandbox', 'updateSandbox'].includes(visible()?.navigation.writeAccess ?? ''));
    const workspaceId = visible()?.workspace?.workspaceId;
    if (!workspaceId) throw new Error('Could not capture the checkout');
    const updating = visible()?.navigation.writeAccess === 'updateSandbox';
    await click('First fixture chat');
    await waitFor('Sandbox setup prevented reading history', () =>
      visible()?.navigation.selectedChat === firstChat &&
      !!visible()?.transcript.items.some((item) => item.text === 'History in the first chat.'));
    typeText(draft);
    await waitFor('The draft did not persist before Windows setup', () => visible()?.navigation.draft?.text === draft);
    try {
      await navigateWorkspace({ retry: { workspaceId, chatId: firstChat } });
      throw new Error('An unconfigured sandbox allowed acquiring writer ownership');
    } catch (error) {
      if (error !== 'staleSelection') throw error;
    }
    await click(updating ? 'Update Sandbox' : 'Set Up Sandbox');
    await waitFor('The setup request did not remain gated while pending', () =>
      visible()?.navigation.writeAccess === (updating ? 'updatingSandbox' : 'settingUpSandbox'));
    await waitFor('Setup did not reread readiness and restore the selected chat', () =>
      visible()?.navigation.writeAccess === 'ready' && visible()?.navigation.selectedChat === firstChat &&
      !!visible()?.navigation.retryable && visible()?.navigation.draft?.text === draft &&
      editor().value === draft);
    await invoke('verify_windows_setup_result', { failure: null });
  } catch (error) {
    await invoke('verify_windows_setup_result', { failure: String(error) });
  }
}
