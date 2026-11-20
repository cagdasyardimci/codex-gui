import { invoke } from '@tauri-apps/api/core';
import { click, editor, typeText, waitFor } from './fixtureControls';
import type { WorkspaceSnapshot } from './generated/workspace';
import { navigateWorkspace } from './projectIpc';

const REJECTED = 'Rejected fixture draft write';
const RECOVERED = 'Recovered text before quit';
const LAST_DRAFT = 'Accepted draft retained while quitting 日本語';
const FIRST = 'history-second';
const OTHER = 'other-history-second';

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

    async function start(thread: string, text = 'Hold this fixture turn') {
      await click('Second fixture chat');
      await waitFor('The captured chat was not writable', () =>
        visible()?.navigation.selectedChat === thread && !!visible()?.navigation.actions.send);
      typeText(text);
      await click('Send');
      await waitFor('The fixture turn was not active', () => active(thread));
    }

    function active(thread: string) {
      const target = visible()?.navigation.actions.stop;
      return !!target && 'turn' in target && target.turn.threadId === thread;
    }

    async function select(secondary: boolean) {
      await invoke('select_fixture_checkout', { secondary });
      await waitFor('Checkout switch did not load the captured project', () =>
        !!visible()?.workspace?.projectPath.includes(secondary ? 'Other checkout' : 'Checkout café') &&
        visible()?.navigation.chats.length === 2);
    }

    await start(FIRST);
    await invoke('request_quit_fixture', { application: false });
    await waitFor('The close event did not request confirmation', () => !!visible()?.navigation.quit?.confirm);
    await click('Cancel');
    await waitFor('Cancelling close retired the active turn or the window', () =>
      visible()?.navigation.quit === null && !!visible()?.navigation.actions.stop &&
      visible()?.navigation.selectedChat === FIRST);

    await select(true);
    await waitFor('The parked checkout was missing from Stop All', () =>
      !!visible()?.navigation.actions.stopAll && !visible()?.navigation.actions.stop);
    await start(OTHER);
    await click('Stop All…');
    await waitFor('Stop All did not request confirmation', () => !!visible()?.navigation.quit?.stopOnly);
    await click('Cancel');
    await waitFor('Cancelling Stop All interrupted a turn', () => !visible()?.navigation.quit && active(OTHER));
    await click('Stop All…');
    await click('Stop All');
    await waitFor('Stop All did not drain both captured turns', () =>
      !visible()?.navigation.quit && !visible()?.navigation.actions.stopAll);

    await select(false);
    await start(FIRST);

    typeText(LAST_DRAFT);
    await waitFor('The accepted draft was not saved before switching', () =>
      visible()?.navigation.draft?.text === LAST_DRAFT);
    await select(true);
    await start(OTHER, 'Complete during Quit confirmation');
    await invoke('request_quit_fixture', { application: true });
    await waitFor('Application Quit did not share close confirmation', () =>
      !!visible()?.navigation.quit?.confirm && active(OTHER));
    await waitFor('The visible turn did not complete while Quit was confirming', () =>
      !!visible()?.navigation.quit?.confirm && !active(OTHER) && !!visible()?.navigation.actions.stopAll);
    await click('Stop and Quit');
  } catch (error) {
    await invoke('report_quit_failure', { failure: String(error) });
  }
}
