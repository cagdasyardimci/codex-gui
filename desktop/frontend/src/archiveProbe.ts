import { invoke } from '@tauri-apps/api/core';
import type { WorkspaceSnapshot } from './generated/workspace';
import { click, clickByLabel, typeText, waitFor } from './fixtureControls';
import { rejectsStale } from './markdownProbe';
import { navigateWorkspace, readArchive } from './projectIpc';

const FIRST = 'history-first';
const SECOND = 'history-second';
const FIRST_DRAFT = 'Keep the first archive draft.';
const SECOND_DRAFT = 'Keep the rejected archive draft.';

function activeRow(id: string) {
  return document.querySelector(`[data-sidebar-chat="${id}"]`);
}

function archiveRow(id: string) {
  return document.querySelector(`[data-archived-chat="${id}"]`);
}

async function rowAction(row: () => Element | null, label: string) {
  const action = () => [...(row()?.querySelectorAll<HTMLButtonElement>('details button:enabled') ?? [])]
    .find((button) => button.textContent?.trim() === label);
  await waitFor(`The row did not offer ${label}`, () => !!action());
  row()?.querySelector('summary')?.click();
  action()?.click();
}

function search(query: string) {
  const input = document.querySelector<HTMLInputElement>('dialog[aria-label="Archived Chats"] input');
  if (!input) throw new Error('Archive search did not mount');
  input.value = query;
  input.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText' }));
}

export async function verifyArchive(visible: () => WorkspaceSnapshot | null) {
  const sidebar = () => visible()?.navigation.sidebar;
  const selection = () => visible()?.navigation.selectedChat;
  const draft = () => visible()?.navigation.draft?.text;
  const saveDraft = async (text: string) => {
    typeText(text);
    await waitFor('The draft did not settle before the archive action', () => draft() === text);
  };
  const projectRow = () => document.querySelector('[data-sidebar-project]');
  try {
    await waitFor('The fixture chats did not load', () => !!activeRow(FIRST) && !!activeRow(SECOND));
    const workspaceId = visible()!.workspace!.workspaceId;
    const projectId = sidebar()!.activeProject!;
    await click('First fixture chat');
    await waitFor('The first chat did not select', () => selection() === FIRST);
    await saveDraft(FIRST_DRAFT);
    await click('Second fixture chat');
    await waitFor('The second chat did not select', () => selection() === SECOND);
    await saveDraft(SECOND_DRAFT);

    await rowAction(projectRow, 'Archive Project Chats…');
    await click('Cancel');
    await waitFor('Cancel removed an active sidebar row', () =>
      !document.querySelector('dialog[aria-label="Archive Project Chats"]') && !!activeRow(FIRST) && !!activeRow(SECOND));

    await rowAction(projectRow, 'Archive Project Chats…');
    await click('Archive Chats');
    await waitFor('Project archive did not preserve the earlier success and the newly active chat', () =>
      !activeRow(FIRST) && !!activeRow(SECOND) && selection() === SECOND && draft() === SECOND_DRAFT);

    await rowAction(() => activeRow(SECOND), 'Archive Chat');
    await waitFor('A rejected archive removed its chat or draft', () =>
      !!activeRow(SECOND)?.querySelector('button.chat-row:enabled') && selection() === SECOND && draft() === SECOND_DRAFT);
    await rejectsStale(navigateWorkspace({ sidebar: { revision: sidebar()!.revision!, change: {
      archiveChat: { projectId, chatId: 'unrelated-chat' },
    } } }));

    await click('Archived Chats');
    await waitFor('The Archive dialog did not open with search focus', () =>
      document.activeElement?.getAttribute('aria-label') === 'Search Archived Chats');
    await waitFor('The archive did not load enough metadata to page its rows', () =>
      document.querySelectorAll('[data-archived-chat]').length === 30);
    if (archiveRow('zz-archive-deep')) throw new Error('The beyond-page archive row was already mounted');
    search('paperclip semaphore');
    await waitFor('Search did not find preview text beyond the rendered and backend pages', () =>
      !!archiveRow('zz-archive-deep') && document.querySelectorAll('[data-archived-chat]').length === 1);
    search('first fixture chat');
    await waitFor('The partially archived chat was not available to restore', () => !!archiveRow(FIRST));
    await clickByLabel('Restore First fixture chat');
    await waitFor('The confirmed restore did not clear stale list results', () =>
      !archiveRow(FIRST) && !!activeRow(FIRST) &&
      [...document.querySelectorAll<HTMLButtonElement>('dialog button:enabled')]
        .some((button) => button.textContent?.trim() === 'Refresh Archive'));
    await click('Close');
    await click('First fixture chat');
    await waitFor('Restoring lost the archived draft', () => selection() === FIRST && draft() === FIRST_DRAFT);

    const old = await readArchive({ workspaceId });
    await saveDraft('/archive');
    await click('Send');
    await waitFor('The slash command did not archive its captured chat', () =>
      !activeRow(FIRST) && selection() === null);
    await rejectsStale(navigateWorkspace({ restoreArchive: { revision: old.revision, target: { chat: 'older-primary' } } }));
    await click('Archived Chats');
    search('older local conversation');
    await waitFor('The archive did not include the other primary chat', () => !!archiveRow('older-primary'));
    await clickByLabel('Restore chats in Archive primary');
    await waitFor('Restoring the project did not include chats hidden by the query', () =>
      !archiveRow('older-primary') && !!activeRow(FIRST) && !!activeRow('older-primary') && !!activeRow(SECOND));
    await click('Close');
    await click('Second fixture chat');
    await waitFor('Project restore retargeted the rejected chat draft', () => selection() === SECOND && draft() === SECOND_DRAFT);
    await invoke('verify_attachments_result', { failure: null });
  } catch (error) {
    await invoke('verify_attachments_result', { failure: String(error) });
  }
}
