import { invoke } from '@tauri-apps/api/core';
import type { DeleteChatSource, WorkspaceSnapshot } from './generated/workspace';
import { click, clickByLabel, typeText, waitFor } from './fixtureControls';
import { rejectsStale } from './markdownProbe';
import { navigateWorkspace, prepareChatDeletion } from './projectIpc';

const FIRST = 'history-first';
const SECOND = 'history-second';
const MANAGED = 'managed-chat';
const UNCERTAIN = 'uncertain-delete';
const DRAFT = 'Keep this draft when cancelling.';
const RETAIN = 'Keep the draft after a lost deletion reply.';

function row(id: string) {
  return document.querySelector(`[data-sidebar-chat="${id}"]`);
}

function confirmation() {
  return document.querySelector<HTMLDialogElement>('dialog[aria-label="Delete Chat Permanently"][open]');
}

async function openSidebarDeletion(id: string, title: string) {
  const action = () => [...(row(id)?.querySelectorAll<HTMLButtonElement>('details button:enabled') ?? [])]
    .find((button) => button.textContent?.trim() === 'Delete Chat…');
  await waitFor('The captured sidebar row did not offer deletion', () => !!action());
  row(id)?.querySelector('summary')?.click();
  action()?.click();
  await waitFor('The confirmation did not identify the captured sidebar chat', () =>
    confirmation()?.querySelector('p')?.textContent === title);
}

async function commitDelete() {
  await click('Delete Chat Permanently');
  await waitFor('The deletion confirmation did not close', () => !confirmation());
}

export async function verifyChatDeletion(visible: () => WorkspaceSnapshot | null) {
  const sidebar = () => visible()?.navigation.sidebar;
  const draft = () => visible()?.navigation.draft?.text;
  const selected = () => visible()?.navigation.selectedChat;
  const saveDraft = async (text: string) => {
    typeText(text);
    await waitFor('The draft did not save before deletion', () => draft() === text);
  };
  const source = (id: string): DeleteChatSource => ({
    sidebar: { revision: sidebar()!.revision!, key: { projectId: sidebar()!.activeProject!, chatId: id } },
  });
  try {
    await waitFor('The regular checkout did not open', () => !!row(FIRST) && !!row(SECOND));
    const primary = sidebar()!.activeProject!;
    await click('First fixture chat');
    await waitFor('The first chat did not select', () => selected() === FIRST);
    await saveDraft(DRAFT);
    await openSidebarDeletion(FIRST, 'First fixture chat');
    if (document.activeElement?.textContent?.trim() !== 'Cancel') throw new Error('Cancel did not receive focus');
    await click('Cancel');
    await waitFor('Cancel removed the chat or its draft', () => !confirmation() && !!row(FIRST) && draft() === DRAFT);

    const obsolete = await prepareChatDeletion(source(FIRST));
    const revision = sidebar()!.revision!;
    await navigateWorkspace({ sidebar: { revision, change: {
      pinChat: { key: { projectId: primary, chatId: SECOND }, pinned: true },
    } } });
    await waitFor('Changing the sidebar did not retire the captured revision', () => sidebar()?.revision !== revision);
    await rejectsStale(navigateWorkspace({ confirmChatDeletion: obsolete.ticket }));
    await rejectsStale(navigateWorkspace({ confirmChatDeletion: obsolete.ticket }));

    await saveDraft('/delete');
    await click('Send');
    await waitFor('The slash command did not open the scoped confirmation', () =>
      confirmation()?.querySelector('p')?.textContent === 'First fixture chat');
    await click('Cancel');
    await waitFor('Cancelling the slash command consumed its draft', () => !confirmation() && draft() === '/delete');
    await click('Send');
    await waitFor('The slash confirmation did not reopen', () => !!confirmation());
    await commitDelete();
    await waitFor('The confirmed slash deletion removed a different row', () => !row(FIRST) && !!row(SECOND) && selected() === null);

    await click('Archived Chats');
    await clickByLabel('Delete Archived example');
    await waitFor('The archive did not capture the exact archived chat', () =>
      confirmation()?.querySelector('p')?.textContent === 'Archived example');
    await commitDelete();
    await waitFor('The confirmed deletion left the archived row behind', () =>
      !document.querySelector('[data-archived-chat="archived-chat"]'));
    await click('Close');

    await click('Uncertain fixture chat');
    await waitFor('The uncertain fixture chat did not select', () => selected() === UNCERTAIN);
    await saveDraft(RETAIN);
    await openSidebarDeletion(UNCERTAIN, 'Uncertain fixture chat');
    await commitDelete();
    await waitFor('A lost response removed the unconfirmed row or draft', () =>
      !!row(UNCERTAIN) && selected() === UNCERTAIN && draft() === RETAIN);
    await click('Reconnect');
    await waitFor('The reconnect did not restore the retained chat', () => !!row(UNCERTAIN)?.querySelector('button.chat-row:enabled'));
    const pending = await prepareChatDeletion(source(UNCERTAIN));
    await rejectsStale(navigateWorkspace({ confirmChatDeletion: pending.ticket }));

    await invoke('seed_deletion_fixture');
    await waitFor('The owned worktree did not become a separate selected project', () =>
      sidebar()?.activeProject !== primary && !!row(MANAGED));
    const managed = sidebar()!.activeProject!;
    await openSidebarDeletion(MANAGED, 'Managed fixture chat');
    await commitDelete();
    await waitFor('A failed cleanup did not preserve the managed project after the chat deletion', () =>
      !row(MANAGED) && sidebar()?.activeProject === managed && sidebar()?.projects.some((project) => project.id === managed) === true);
    await click('Refresh');
    await waitFor('Refresh resurrected a confirmed deleted chat', () =>
      !row(MANAGED) && [...document.querySelectorAll<HTMLButtonElement>('header button:enabled')]
        .some((button) => button.textContent?.trim() === 'Refresh'));
    await invoke('verify_attachments_result', { failure: null });
  } catch (error) {
    await invoke('verify_attachments_result', { failure: String(error) });
  }
}
