import { invoke } from '@tauri-apps/api/core';
import { tick } from 'svelte';
import type { WorkspaceSnapshot } from './generated/workspace';
import { click, editor, typeText, waitFor } from './fixtureControls';
import { rejectsStale } from './markdownProbe';
import { navigateWorkspace } from './projectIpc';

const FIRST_DRAFT = 'Keep this café draft.';
const OTHER_DRAFT = 'Keep the other checkout draft.';

function searchField() {
  return document.querySelector<HTMLInputElement>('dialog[open] input[role="combobox"]');
}

function key(target: EventTarget, value: string, options: KeyboardEventInit = {}) {
  target.dispatchEvent(new KeyboardEvent('keydown', {
    key: value, bubbles: true, cancelable: true, ...options,
  }));
}

async function open(value: string, label: string, altKey = false) {
  await waitFor('The preceding navigation did not settle', () =>
    !!document.querySelector('header button[aria-keyshortcuts="Meta+Shift+P Control+Shift+P"]:enabled'));
  key(editor(), value, { ctrlKey: true, shiftKey: true, altKey, code: `Key${value}` });
  await waitFor(`Keyboard did not open ${label} with focus`, () => {
    const search = searchField();
    return search?.getAttribute('aria-label') === label && document.activeElement === search;
  });
  return searchField()!;
}

function query(search: HTMLInputElement, value: string) {
  search.value = value;
  search.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText' }));
}

function selectedResult(search: HTMLInputElement) {
  return document.getElementById(search.getAttribute('aria-activedescendant') ?? '')?.textContent;
}

export async function verifyCommandPalette(visible: () => WorkspaceSnapshot | null) {
  const sidebar = () => visible()?.navigation.sidebar;
  const project = () => sidebar()?.activeProject;
  const selected = () => visible()?.navigation.selectedChat;
  const draft = () => visible()?.navigation.draft?.text;
  const saveDraft = async (text: string) => {
    typeText(text);
    await waitFor('The captured chat did not save its draft', () => draft() === text);
  };
  try {
    await waitFor('The primary checkout did not load its chats', () => !!project() && sidebar()?.chats.length === 2);
    const primary = project()!;
    await click('First fixture chat');
    await waitFor('The primary chat did not open', () => selected() === 'history-first');
    await saveDraft(FIRST_DRAFT);
    editor().focus();
    editor().setSelectionRange(5, 11);

    let search = await open('P', 'Search Commands');
    query(search, 'CHANGES');
    await waitFor('The palette did not find the Changes action', () => selectedResult(search)?.trim() === 'Changes');
    key(search, 'Enter', { isComposing: true });
    if (!searchField() || document.querySelector('[aria-label="Checkout Changes"]')) {
      throw new Error('An IME confirmation selected a command');
    }
    key(search, 'Escape');
    await waitFor('Cancelling the palette did not restore the selection', () =>
      !searchField() && document.activeElement === editor() &&
      editor().selectionStart === 5 && editor().selectionEnd === 11 && draft() === FIRST_DRAFT);

    search = await open('P', 'Search Commands');
    query(search, 'changes');
    await waitFor('The Changes action did not become selectable', () => selectedResult(search)?.trim() === 'Changes');
    key(search, 'Enter');
    await waitFor('Enter did not open the actual Changes pane', () =>
      !searchField() && !!document.querySelector('aside[aria-label="Checkout Changes"]'));

    await invoke('select_fixture_checkout', { secondary: true });
    await waitFor('The other project did not load', () => project() !== primary &&
      sidebar()?.chats.some((chat) => chat.key.chatId === 'other-history-first') === true);
    const secondary = project()!;
    await click('Other First fixture chat');
    await waitFor('The other project did not select its chat', () => selected() === 'other-history-first');
    await saveDraft(OTHER_DRAFT);

    search = await open('O', 'Search Projects', true);
    query(search, 'PRIMARY CAFE');
    await waitFor('The project chooser did not match an accent-folded recent', () =>
      selectedResult(search)?.includes('Primary café') === true &&
      search.closest('dialog')?.querySelectorAll('[role="option"]').length === 1);
    key(search, 'Enter');
    await waitFor('The project chooser opened the wrong checkout', () => !searchField() && project() === primary);

    search = await open('K', 'Search Chats');
    query(search, 'other fixture chat');
    await waitFor('The chat chooser did not find both scoped titles', () =>
      search.closest('dialog')?.querySelectorAll('[role="option"]').length === 2);
    const firstChoice = search.getAttribute('aria-activedescendant');
    key(search, 'ArrowDown');
    await waitFor('Down did not move the active chat entry', () => search.getAttribute('aria-activedescendant') !== firstChoice);
    key(search, 'ArrowUp');
    await waitFor('Up did not return to the first chat entry', () => search.getAttribute('aria-activedescendant') === firstChoice);
    query(search, 'first other checkout');
    await waitFor('Project detail did not disambiguate the chat', () => selectedResult(search)?.includes('Other First') === true);
    key(search, 'Enter');
    await waitFor('The captured chat did not restore the other project and draft together', () =>
      !searchField() && project() === secondary && selected() === 'other-history-first' && draft() === OTHER_DRAFT &&
      document.activeElement === editor());

    search = await open('K', 'Search Chats');
    query(search, 'first primary cafe');
    await waitFor('The first chat was absent under its original owner', () =>
      selectedResult(search)?.includes('Primary café') === true);
    const revision = sidebar()!.revision!;
    const captured = { projectId: primary, chatId: 'history-first' };
    await navigateWorkspace({ sidebar: { revision, change: { pinChat: { key: captured, pinned: true } } } });
    await waitFor('Pinning the result did not invalidate the captured sidebar revision', () => sidebar()?.revision !== revision);
    await rejectsStale(navigateWorkspace({ sidebar: { revision, change: { openChat: captured } } }));
    key(search, 'Enter');
    await tick();
    await waitFor('The stale choice did not stay open for explicit selection', () => !!searchField() &&
      project() === secondary && selected() === 'other-history-first' &&
      !!search.closest('dialog')?.querySelector('[role="option"]:enabled'));
    key(search, 'Enter');
    await waitFor('The refreshed choice did not restore the original draft', () =>
      !searchField() && project() === primary && selected() === 'history-first' && draft() === FIRST_DRAFT);

    await open('P', 'Search Commands');
    await invoke('select_fixture_checkout', { secondary: true });
    await waitFor('A retired checkout left its captured chooser open', () => !searchField() && project() === secondary);
    await invoke('verify_attachments_result', { failure: null });
  } catch (error) {
    await invoke('verify_attachments_result', { failure: String(error) });
  }
}
