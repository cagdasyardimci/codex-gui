import { invoke } from '@tauri-apps/api/core';
import type { WorkspaceSnapshot } from './generated/workspace';
import { click, typeText, waitFor } from './fixtureControls';

export async function verifyManagedWorktree(visible: () => WorkspaceSnapshot | null) {
  const source = () => visible()?.workspace?.projectPath;
  const navigation = () => visible()?.navigation;
  try {
    await waitFor('The worktree source did not open', () => !!source() && navigation()?.writeAccess === 'ready');
    const initial = source();
    if (initial?.endsWith('Source project')) {
      typeText('Keep the original draft in the source checkout.');
      await waitFor('The source draft did not persist', () =>
        navigation()?.draft?.text === 'Keep the original draft in the source checkout.');
      await click('New Chat in Worktree');
      await waitFor('The managed worktree did not become the selected project', () => !!source() && source() !== initial &&
        navigation()?.selectedChat === null && navigation()?.draft?.text === '' && navigation()?.writeAccess === 'ready');
    }
    typeText('Run in the managed checkout.');
    await click('Send');
    await waitFor('The managed worktree did not receive its conversation', () =>
      !!navigation()?.selectedChat && visible()?.transcript.items.some(({ text }) => text.includes('日本語')) === true);
    await invoke('verify_attachments_result', { failure: null });
  } catch (error) {
    await invoke('verify_attachments_result', { failure: String(error) });
  }
}
