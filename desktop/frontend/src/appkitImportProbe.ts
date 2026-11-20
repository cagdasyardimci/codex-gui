import { invoke } from '@tauri-apps/api/core';
import { click, clickByLabel, waitFor } from './fixtureControls';
import type { AppearanceView, WorkspaceSnapshot } from './generated/workspace';

export async function verifyAppKitImport(
  visible: () => WorkspaceSnapshot | null, appearance: () => AppearanceView | undefined,
) {
  try {
    const navigation = () => visible()?.navigation;
    await waitFor('The imported project, selected chat and draft did not restore', () =>
      navigation()?.selectedChat === 'history-first' && navigation()?.draft?.text === 'Imported thread draft');
    await waitFor('The imported desktop presentation did not apply', () =>
      !document.querySelector('.workspace-sidebar') && appearance()?.mode === 'dark' &&
      getComputedStyle(document.documentElement).backgroundColor === 'rgb(35, 49, 66)' &&
      getComputedStyle(document.documentElement).getPropertyValue('--workspace-content-size').trim() === '18px');
    await waitFor('The imported review pane did not reopen', () => !!document.querySelector('.workspace-changes'));
    const comparison = () => document.querySelector<HTMLSelectElement>('select[aria-label="Comparison"]');
    await waitFor('The recorded last-turn patch was not available', () =>
      !![...(comparison()?.options ?? [])].find(({ text }) => text === 'Last Turn'));
    comparison()!.value = JSON.stringify('lastTurn');
    comparison()!.dispatchEvent(new Event('change', { bubbles: true }));
    await click('notes.txt').catch(() => {
      throw new Error(`The applied comparison did not list notes.txt: ${comparison()?.value}, ${JSON.stringify(navigation()?.lastTurn)}`);
    });
    const marked = (label: string) =>
      document.querySelector(`button[aria-label="${label}"]`)?.getAttribute('aria-pressed') === 'true';
    await waitFor('Review markers did not match the original reported file and hunk', () =>
      marked('Mark File Reviewed') && marked('Mark Hunk 1 Reviewed'));
    await clickByLabel('Mark Hunk 1 Reviewed');
    await waitFor('The imported hunk could not be unmarked', () => !marked('Mark Hunk 1 Reviewed'));
    await invoke('appearance_fixture_action', { action: 'navigationPane' });
    await waitFor('The native sidebar action did not restore the preferred width', () => {
      const sidebar = document.querySelector('.workspace-sidebar');
      return !!sidebar && Math.abs(sidebar.getBoundingClientRect().width - 232) <= 2;
    });
    await waitFor('The imported manual chat order did not reach the sidebar', () => {
      const chats = [...document.querySelectorAll('.workspace-sidebar .chat-title')].map((row) => row.textContent?.trim());
      return chats.indexOf('Third fixture chat') >= 0 && chats.indexOf('Third fixture chat') < chats.indexOf('Second fixture chat');
    });
    const evidence = await invoke('appearance_fixture_state');
    await invoke('verify_appearance_result', { failure: null, evidence });
  } catch (error) {
    await invoke('verify_appearance_result', { failure: String(error), evidence: {} });
  }
}
