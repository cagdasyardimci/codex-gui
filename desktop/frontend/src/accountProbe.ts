import { invoke } from '@tauri-apps/api/core';
import { click, editor, typeText, waitFor } from './fixtureControls';
import type { WorkspaceSnapshot } from './generated/workspace';
import { navigateWorkspace } from './projectIpc';

export async function verifyAccount(visible: () => WorkspaceSnapshot | null) {
  const draft = 'Draft retained through ChatGPT sign-in 日本語';
  const account = () => visible()?.navigation.account;
  try {
    await waitFor('The initial unsent draft was missing', () => !!visible()?.navigation.draft);
    typeText(draft);
    await waitFor('The initial draft was not persisted', () => visible()?.navigation.draft?.text === draft);
    await click('Sign In');
    await waitFor('The browser sign-in attempt was not published', () => !!account()?.loginTicket);
    const first = account()?.loginTicket;
    if (!first) throw new Error('The sign-in ticket was lost');
    await click('Cancel Sign-in');
    await waitFor('Cancellation left a pending attempt or changed the account', () =>
      account()?.loginTicket === null && account()?.identity === null);
    await click('Sign In');
    await waitFor('The replacement sign-in was not published', () =>
      !!account()?.loginTicket && account()?.loginTicket !== first && account()?.identity === null);
    try {
      await navigateWorkspace({ cancelSignIn: { ticket: first } });
      throw new Error('An obsolete sign-in ticket could cancel the replacement');
    } catch (error) {
      if (error !== 'staleSelection') throw error;
    }
    await waitFor('Completion did not refresh the initiating account and its models', () =>
      account()?.identity === 'subscriber@example.invalid' &&
      account()?.loginTicket === null && account()?.models.length === 1 &&
      account()?.models[0]?.id === 'fixture-default' && !!account()?.models[0]?.isDefault);
    if (visible()?.navigation.draft?.text !== draft || editor().value !== draft) {
      throw new Error('Sign-in overwrote the local draft');
    }
    await invoke('verify_account_result', { failure: null });
  } catch (error) {
    await invoke('verify_account_result', { failure: String(error) });
  }
}
