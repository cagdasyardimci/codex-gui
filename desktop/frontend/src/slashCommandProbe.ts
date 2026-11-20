import { invoke } from '@tauri-apps/api/core';
import type { WorkspaceSnapshot } from './generated/workspace';
import { click, clickByLabel, typeText, waitFor } from './fixtureControls';

export async function verifySlashCommands(visible: () => WorkspaceSnapshot | null) {
  const navigation = () => visible()?.navigation;
  const draft = () => navigation()?.draft;
  const slash = () => navigation()?.slashCommands;
  const dialog = (label: string) => document.querySelector(`dialog[aria-label="${CSS.escape(label)}"][open]`);
  const enter = async (text: string) => {
    typeText(text);
    await waitFor(`The fixture did not store ${text}`, () => draft()?.text === text);
    await click('Send');
  };
  const consumed = () => waitFor('The accepted command remained in the draft', () => draft()?.text === '');
  const completeTurn = async () => {
    await waitFor('The captured command did not admit its prompt', () => !!navigation()?.actions.stop);
    await waitFor('The fixture turn did not settle', () => navigation()?.actions.stop === null && draft()?.text === '');
  };
  try {
    await click('First fixture chat');
    await waitFor('The saved chat and capabilities did not load', () =>
      navigation()?.selectedChat === 'history-first' && !!slash()?.available.includes('compact') &&
      slash()?.context?.tokens === 2560);
    typeText('/');
    await click('/status');
    await waitFor('Choosing a command did not complete its token', () => draft()?.text === '/status ');
    await click('Send');
    await waitFor('The context panel did not show active usage', () =>
      dialog('Conversation Details')?.textContent?.includes('25%') === true);
    await click('Close');
    await consumed();

    await enter('/review base');
    await waitFor('An invalid command cleared the draft or started a turn', () =>
      draft()?.text === '/review base' && navigation()?.actions.stop === null);
    await enter('/model alternative-model');
    await consumed();
    await enter('/reasoning high');
    await consumed();
    await enter('/fast on');
    await consumed();
    await enter('/permissions full');
    await waitFor('Full Access did not ask about the captured project', () => !!dialog('Full Access'));
    await click('Close');
    if (draft()?.text !== '/permissions full' || navigation()?.composerSettings?.selection.permissions !== 'configured') {
      throw new Error('Closing Full Access changed the draft or permissions');
    }
    await enter('/permissions auto');
    await consumed();

    await enter('/skills');
    await clickByLabel('Add Review fixture');
    await waitFor('The skill command did not stage its selection without Send', () =>
      draft()?.text === '' && draft()?.attachments[0]?.label === 'Review fixture' && !navigation()?.actions.stop);
    await enter('/plan');
    await waitFor('The selected chat did not enable plan mode', () => slash()?.plan === true && draft()?.text === '');
    await enter('  //status literal café');
    await completeTurn();
    await enter('/plan');
    await waitFor('The selected chat did not restore default mode', () => slash()?.plan === false && draft()?.text === '');
    await enter('/plan\n  Preserve this plan prompt.');
    await completeTurn();

    await enter('/compact');
    await waitFor('The compaction reply consumed a draft before completion', () =>
      !navigation()?.actions.send && draft()?.text === '/compact');
    await waitFor('Compaction did not reconcile its context', () =>
      navigation()?.actions.send === true && draft()?.text === '' && slash()?.context?.tokens === 1024);

    await enter('/plan');
    await waitFor('An uncertain plan change cleared the draft or left Send active', () =>
      navigation()?.writeAccess === 'unavailable' && draft()?.text === '/plan' && !navigation()?.actions.send);
    await click('Reconnect');
    await waitFor('Reconnect dropped the uncertain plan change', () =>
      slash()?.recoverPlan === true && draft()?.text === '/plan' && !navigation()?.actions.send);
    await click('Send');
    await waitFor('The explicit plan recovery choices did not open', () => !!dialog('Conversation Mode'));
    await click('Use Default');
    await waitFor('The explicit reapply did not resolve the original checkout and draft', () =>
      navigation()?.actions.send === true && draft()?.text === '' && !slash()?.plan && !slash()?.recoverPlan);

    await invoke('verify_attachments_result', { failure: null });
  } catch (error) {
    await invoke('verify_attachments_result', { failure: String(error) });
  }
}
