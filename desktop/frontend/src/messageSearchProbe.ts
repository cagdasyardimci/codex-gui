import { invoke } from '@tauri-apps/api/core';
import { tick } from 'svelte';
import type { WorkspaceSnapshot } from './generated/workspace';
import { click, editor, typeText, waitFor } from './fixtureControls';
import { rejectsStale } from './markdownProbe';
import type { MessageSearchIndex } from './messageSearchIndex';
import { navigateWorkspace, openMessageSearch, readMessageSearchPage } from './projectIpc';

const FIRST = 'history-first';
const SECOND = 'history-second';
const FIRST_NEEDLE = 'Café waterline';
const SECOND_NEEDLE = 'Cross chat amber phrase';
const OLDER_NEEDLE = 'Hidden target café quadrant';

function field() {
  return document.querySelector<HTMLInputElement>('dialog[aria-label="Search Messages"][open] input');
}

function key(target: EventTarget, name: string, options: KeyboardEventInit = {}) {
  target.dispatchEvent(new KeyboardEvent('keydown', { key: name, bubbles: true, cancelable: true, ...options }));
}

function query(text: string) {
  const input = field();
  if (!input) throw new Error('The search field is not mounted');
  input.value = text;
  input.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText' }));
}

function matches() {
  return [...document.querySelectorAll('#message-search-results mark')].map((mark) => mark.textContent);
}

async function open() {
  await waitFor('The workspace did not finish its preceding action', () =>
    !!document.querySelector('button[aria-keyshortcuts="Meta+Shift+F Control+Shift+F"]:enabled'));
  editor().focus();
  key(editor(), 'F', { ctrlKey: true, shiftKey: true });
  await waitFor('Keyboard search did not open with focus', () => !!field() && document.activeElement === field());
}

export async function verifyMessageSearch(visible: () => WorkspaceSnapshot | null, index: MessageSearchIndex) {
  const chat = () => visible()?.navigation.selectedChat;
  const draft = () => visible()?.navigation.draft?.text;
  const text = () => visible()?.transcript.items.find((row) => row.text.includes('Unrelated first fragment'))?.text;
  const saving = async (value: string) => {
    typeText(value);
    await waitFor('The chat did not save its draft', () => draft() === value);
  };
  try {
    await click('First fixture chat');
    await waitFor('The current chat search index did not cover its resident history', () =>
      chat() === FIRST && index.targets().some((target) => target.chatId === FIRST && target.covered && target.earlier));
    const workspaceId = visible()!.workspace!.workspaceId;
    await saving('Trigger an unrelated stream');
    await click('Send');
    await waitFor('The unrelated stream did not start', () => text()?.includes('Unrelated first fragment') === true);
    await open();
    query('CAFE WATERLINE');
    await waitFor('Unicode search did not produce the original snippet', () => matches().join() === FIRST_NEEDLE);
    const revision = index.revision;
    await waitFor('The unrelated stream did not deliver another fragment', () => text()?.includes('then another fragment') === true);
    if (index.revision !== revision || matches().join() !== FIRST_NEEDLE) throw new Error('An unrelated delta changed the search index');
    query('ordinary filler');
    await tick();
    query('cafe waterline');
    await waitFor('An obsolete query published its results', () => matches().join() === FIRST_NEEDLE);
    const snippet = document.querySelector('#message-search-results mark')?.parentElement?.textContent ?? '';
    if (!snippet.startsWith('…') || !snippet.endsWith('…')) throw new Error('The original match did not have bounded context');
    key(field()!, 'Escape');
    await waitFor('Closing search did not restore the composer focus', () => !field() && document.activeElement === editor());

    await waitFor('The coding fixture did not finish its turn', () => visible()?.navigation.actions.send === true);
    for (let page = 0; page < 3; page++) {
      const earlier = visible()!.navigation.olderHistory!;
      await navigateWorkspace({ loadOlderHistory: { workspaceId, chatId: FIRST, ticket: earlier.ticket } });
      await waitFor('The earlier history page did not settle', () => visible()?.navigation.olderHistory?.ticket !== earlier.ticket);
    }
    await waitFor('Resident history eviction did not change search coverage', () =>
      index.targets().some((target) => target.chatId === FIRST && target.partial));
    await saving('Keep the draft before jumping to another chat.');

    await open();
    query('cross chat amber');
    if (matches().length) throw new Error('A chat was indexed before its history was loaded');
    await click('Search More Messages');
    await waitFor('Paging did not include the unloaded chat without selecting it', () =>
      matches().join() === 'Cross chat amber' && chat() === FIRST);
    if (!document.querySelector('#message-search-results')?.textContent?.includes(SECOND_NEEDLE)) {
      throw new Error('The cross-chat result lost its original context');
    }
    key(field()!, 'Enter');
    await waitFor('Cross-chat search did not jump to the exact original item', () =>
      !field() && chat() === SECOND &&
      visible()?.navigation.turnRail?.jump?.itemId === 'second-search-turn/needle' &&
      !!document.querySelector('[data-transcript-slot="second-search-turn/needle"]'));

    const canceled = await openMessageSearch(workspaceId);
    const pending = rejectsStale(readMessageSearchPage({ session: canceled, chatId: SECOND, restart: true }));
    await navigateWorkspace({ closeMessageSearch: canceled });
    await pending;
    await rejectsStale(readMessageSearchPage({ session: canceled, chatId: FIRST, restart: true }));
    await rejectsStale(navigateWorkspace({ openMessageSearchHit: {
      session: canceled, workspaceId, chatId: FIRST, turnId: 'search-turn-04', itemId: 'search-turn-04/needle',
    } }));

    await open();
    query('hidden target cafe quadrant');
    if (matches().length) throw new Error('The nonresident older hit was present before loading its page');
    for (let page = 0; page < 5 && !matches().length; page++) {
      await click('Search More Messages');
      await waitFor('Loading an older history page did not settle', () => !!field() &&
        (matches().length > 0 || [...document.querySelectorAll<HTMLButtonElement>('dialog button:enabled')]
          .some((button) => button.textContent?.trim() === 'Search More Messages')));
    }
    await waitFor('The paged search did not find the nonresident older message', () => matches().join() === OLDER_NEEDLE);
    key(field()!, 'Enter');
    await waitFor('The older hit did not restore its exact chat, item and draft', () =>
      !field() && chat() === FIRST && draft() === 'Keep the draft before jumping to another chat.' &&
      visible()?.navigation.turnRail?.jump?.itemId === 'search-turn-04/needle' &&
      !!document.querySelector('[data-transcript-slot="search-turn-04/needle"]'));
    await invoke('verify_attachments_result', { failure: null });
  } catch (error) {
    await invoke('verify_attachments_result', { failure: String(error) });
  }
}
