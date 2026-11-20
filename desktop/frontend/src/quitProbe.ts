import { invoke } from '@tauri-apps/api/core';
import { click, editor, typeText, waitFor } from './fixtureControls';
import type { WorkspaceSnapshot } from './generated/workspace';
import { navigateWorkspace } from './projectIpc';

const REJECTED = 'Rejected fixture draft write';
const RECOVERED = 'Recovered text before quit';
const LAST_DRAFT = 'Accepted draft retained while quitting 日本語';

export async function verifyQuit(visible: () => WorkspaceSnapshot | null) {
  try {
    await waitFor('The saved chat draft did not restore on launch', () =>
      visible()?.navigation.selectedChat === 'history-first' && !!visible()?.navigation.draft &&
      visible()?.navigation.chats.length === 2);
    const draftId = visible()?.navigation.draft?.id;
    if (!draftId) throw new Error('The saved draft did not have an identity');
    const lastSaved = visible()?.navigation.draft?.text;
    typeText(REJECTED);
    try {
      await navigateWorkspace({ editDraft: { draftId, text: REJECTED } });
      throw new Error('The fixture write did not fail');
    } catch (error) {
      if (error !== 'projectUnavailable') throw error;
    }
    const before = visible()?.revision ?? 0;
    await invoke('request_quit_fixture', { application: false });
    await waitFor('Close failed to retain the app and the unsaved draft after a write error', () =>
      (visible()?.revision ?? 0) >= before + 2 && visible()?.navigation.quit === null &&
      visible()?.navigation.draft?.text === lastSaved && editor().value === REJECTED && !editor().readOnly);
    typeText(RECOVERED);
    await waitFor('The composer did not recover its ability to save after close', () =>
      visible()?.navigation.draft?.text === RECOVERED);

    await click('Second fixture chat');
    await waitFor('The second chat was not writable', () =>
      visible()?.navigation.selectedChat === 'history-second' && !!visible()?.navigation.actions.send);
    typeText('Hold this fixture turn');
    await click('Send');
    await waitFor('The fixture turn was not active', () => {
      const target = visible()?.navigation.actions.stop;
      return !!target && 'turn' in target && target.turn.threadId === 'history-second';
    });
    await invoke('request_quit_fixture', { application: false });
    await waitFor('The close event did not request confirmation', () => !!visible()?.navigation.quit?.confirm);
    await click('Cancel');
    await waitFor('Cancelling close retired the active turn or the window', () =>
      visible()?.navigation.quit === null && !!visible()?.navigation.actions.stop &&
      visible()?.navigation.selectedChat === 'history-second');

    typeText(LAST_DRAFT);
    await invoke('request_quit_fixture', { application: true });
    await waitFor('Application Quit did not share close confirmation', () =>
      !!visible()?.navigation.quit?.confirm && editor().value === LAST_DRAFT);
    await click('Stop and Quit');
  } catch (error) {
    await invoke('report_quit_failure', { failure: String(error) });
  }
}
