import { invoke } from '@tauri-apps/api/core';
import type { WorkspaceSnapshot } from './generated/workspace';
import { click, clickByLabel, typeText, waitFor } from './fixtureControls';

const FIRST = 'history-first';
const SECOND = 'history-second';
const RESPONSE = 'first-saved-turn/first-history';
const ANSWER = 'History in the first chat.';
const SOURCE_DRAFT = 'Keep the first source draft.';
const FORK_DRAFT = 'A different draft in the response branch.';
const LOCKED_DRAFT = 'Keep the writer-locked source draft.';

export async function verifyConversationFork(visible: () => WorkspaceSnapshot | null) {
  const nav = () => visible()?.navigation;
  const selected = () => nav()?.selectedChat;
  const draft = () => nav()?.draft;
  const response = () => document.querySelector(`[data-item-id="${CSS.escape(RESPONSE)}"]`);
  const action = (name: string) => response()?.querySelector<HTMLButtonElement>(
    `button[aria-label="${CSS.escape(name)}"]:enabled`);
  const invokeAction = async (name: string) => {
    await waitFor(`The completed response did not offer ${name}`, () => !!action(name));
    action(name)?.click();
  };
  const record = async (text: string) => {
    typeText(text);
    await waitFor('The selected draft did not persist', () => draft()?.text === text);
  };
  try {
    await click('First fixture chat');
    await waitFor('The finished source response was not available', () =>
      selected() === FIRST && !!action('Branch in new chat'));
    await record(SOURCE_DRAFT);
    await invokeAction('Bookmark response');
    await waitFor('The response bookmark was not projected into the chat', () =>
      nav()?.bookmarkedResponses.includes(RESPONSE) === true && !!action('Remove response bookmark'));

    await invokeAction('Branch in new chat');
    await waitFor('The branch was not selected with the intended boundary', () =>
      selected() === 'conversation-fork-1' && !!response() && nav()?.turnRail?.turns.length === 1);
    if (draft()?.text || nav()?.actions.stop) throw new Error('Branching copied or sent the source draft');
    await record(FORK_DRAFT);
    await click('Project Context');
    await click(ANSWER);
    await waitFor('The bookmark did not reopen the original nonresident response', () =>
      selected() === FIRST && nav()?.turnRail?.jump?.itemId === RESPONSE && !!response());
    if (draft()?.text !== SOURCE_DRAFT) throw new Error('Branching changed the original draft');
    await click('Project Context');
    await clickByLabel(`Remove bookmark ${ANSWER}`);
    await waitFor('The bookmark removal did not update the original response', () =>
      !nav()?.bookmarkedResponses.includes(RESPONSE) && !!action('Bookmark response'));
    await invokeAction('Bookmark response');
    await invokeAction('Remove response bookmark');
    await waitFor('The saved bookmark remained in Project Context', () =>
      !nav()?.bookmarkedResponses.includes(RESPONSE) &&
      !document.querySelector('#project-bookmarks'));
    const panel = document.querySelector('aside[aria-label="Project Context"]');
    if (panel) await click('Close');

    await click('Second fixture chat');
    await waitFor('Fork Chat was unavailable under the external writer lock', () =>
      selected() === SECOND && nav()?.retryable === true && nav()?.canFork === true);
    await record(LOCKED_DRAFT);
    await click('Fork Chat');
    await waitFor('The writer-locked chat did not fork through the original saved history', () =>
      selected() === 'conversation-fork-2' && visible()?.transcript.items.some((row) => row.itemId === 'second-saved-turn/second-history') === true);
    if (draft()?.text || nav()?.actions.stop) throw new Error('The writer-locked fork moved or submitted the source draft');
    await click('Second fixture chat');
    await waitFor('The locked source draft changed after forking', () =>
      selected() === SECOND && draft()?.text === LOCKED_DRAFT);

    await click('First fixture chat');
    await waitFor('The source chat did not reopen for the scoped slash command', () =>
      selected() === FIRST && nav()?.canFork === true);
    await record('/fork');
    await click('Send');
    await waitFor('The unacknowledged fork did not preserve the captured source draft', () =>
      nav()?.writeAccess === 'unavailable' && draft()?.text === '/fork');
    await click('Reconnect');
    await waitFor('The fork receipt did not survive reconnect', () =>
      selected() === FIRST && nav()?.recoverFork === true && nav()?.chats.some((row) => row.id === 'conversation-fork-3') === true);
    await click('Resolve Fork');
    const recovered = () => [...document.querySelectorAll<HTMLButtonElement>('dialog[aria-label="Resolve Fork"][open] button')]
      .find((button) => button.textContent?.trim() === 'Conversation Fork 3');
    await waitFor('The saved fork was missing from the recovery chooser', () => !!recovered());
    recovered()?.click();
    await waitFor('Recovery selected a different thread or started a turn', () =>
      selected() === 'conversation-fork-3' && nav()?.recoverFork === false && !nav()?.actions.stop);
    await invoke('verify_attachments_result', { failure: null });
  } catch (error) {
    await invoke('verify_attachments_result', { failure: String(error) });
  }
}
