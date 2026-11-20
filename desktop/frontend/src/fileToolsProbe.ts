import { invoke } from '@tauri-apps/api/core';
import { changeFileTools, readFileTab } from './fileTools';
import { click, clickByLabel, typeText, waitFor } from './fixtureControls';
import type { DraftAttachmentScope, WorkspaceSnapshot } from './generated/workspace';
import { rejectsStale } from './markdownProbe';
import { navigateWorkspace } from './projectIpc';

const FIRST = 'history-first';
const SECOND = 'history-second';
const BETA_EDIT = 'The first chat owns this file.\n';
const ADOPT_EDIT = 'Keep the new chat file.\n';
const CONFLICT_EDIT = 'Keep this buffer after the conflicting save.\n';

const panel = () => document.querySelector<HTMLElement>('aside[aria-label="Project Files"]');
const browser = () => panel()?.querySelector<HTMLElement>('nav[aria-label="Project File Browser"]');
const field = () => panel()?.querySelector<HTMLTextAreaElement>('textarea');
const closeDialog = () => document.querySelector<HTMLDialogElement>('dialog[aria-label="Close File"][open]');
const quitDialog = () => document.querySelector<HTMLDialogElement>('dialog.quit-dialog[open]');

async function browse(name: string) {
  await waitFor('The file browser did not open', () => !!browser());
  await click(name, browser()!);
}

async function showFiles() {
  if (!panel()) await click('Files');
  await waitFor('The file pane did not open', () => !!panel());
}

async function editFile(original: string, replacement: string) {
  await waitFor('The file did not open with its original bytes', () => field()?.value === original);
  const input = field()!;
  input.value = replacement;
  input.dispatchEvent(new InputEvent('input', { bubbles: true }));
}

export async function verifyFileTools(visible: () => WorkspaceSnapshot | null) {
  const selected = () => visible()?.navigation.selectedChat;
  const scope = (): DraftAttachmentScope => ({
    workspaceId: visible()!.workspace!.workspaceId,
    chatId: selected()!,
    draftId: visible()!.navigation.draft!.id,
  });
  const inspect = () => changeFileTools({ scope: scope(), change: 'inspect' });
  try {
    await click('First fixture chat');
    await waitFor('The first file tools owner did not select', () => selected() === FIRST);
    const first = scope();
    await showFiles();
    await browse('folder');
    await browse('alpha.txt');
    await waitFor('The first preview did not render nested text', () => field()?.value === 'Alpha\n');
    const alpha = (await inspect()).selected!;
    await browse('Parent Folder');
    await browse('beta.txt');
    await waitFor('The next file did not replace the clean preview', () => field()?.value === 'Original beta\n');
    const beta = (await inspect()).selected!;
    if ((await inspect()).tabs.map((tab) => tab.id).join() !== beta) throw new Error('The preview slot kept its previous file');
    await rejectsStale(readFileTab({ scope: first, tabId: alpha }));
    await click('Keep Tab');
    await browse('pixel.png');
    await waitFor('The first raster tab did not render', () => !!panel()?.querySelector('img[alt="pixel.png"]'));
    const firstImage = (await inspect()).selected!;
    await browse('pixel2.png');
    await waitFor('The second raster tab did not render', () => !!panel()?.querySelector('img[alt="pixel2.png"]'));
    const secondImage = (await inspect()).selected!;
    await click('Move Tab Left');
    await waitFor('Moving an image tab did not change the presented order', () =>
      panel()?.querySelectorAll('[data-file-tab]')[1]?.getAttribute('data-file-tab') === secondImage);
    const ordered = (await inspect()).tabs;
    if (ordered.map((tab) => tab.id).join() !== [beta, secondImage, firstImage].join() ||
        ordered.some((tab) => tab.preview)) throw new Error('The retained text and two image tabs did not stay independent');

    const tabs = panel()!.querySelector<HTMLElement>('nav[aria-label="Open Files"]')!;
    await click('beta.txt', tabs);
    await editFile('Original beta\n', BETA_EDIT);
    const input = field()!;
    input.focus();
    input.setSelectionRange(4, 9);
    input.dispatchEvent(new Event('select'));
    await click('Expand File Pane');
    await waitFor('The file pane did not expand', () => !!panel()?.classList.contains('wide'));
    await click('Second fixture chat');
    await waitFor('The second chat inherited the first chat file pane', () => selected() === SECOND && !panel());
    await rejectsStale(readFileTab({ scope: first, tabId: beta }));
    await showFiles();
    if ((await inspect()).tabs.length !== 0 || panel()!.classList.contains('wide')) {
      throw new Error('The second chat inherited the first chat tab list or layout');
    }
    await browse('conflict.txt');
    await editFile('Original conflict\n', CONFLICT_EDIT);
    await invoke('overwrite_file_tools_fixture');
    await clickByLabel('Close conflict.txt');
    await waitFor('A conflicting close did not identify its captured file', () =>
      closeDialog()?.querySelector('h2')?.textContent === 'conflict.txt');
    const second = scope();
    const conflict = (await inspect()).selected!;
    const rejectedClose = await changeFileTools({ scope: second, change: { close: conflict } });
    if (!rejectedClose.discard) throw new Error('The conflicting close did not return a discard target');
    await click('Cancel', closeDialog()!);
    await waitFor('Cancel did not retain the unsaved file edit', () => !closeDialog() && field()?.value === CONFLICT_EDIT);

    await click('First fixture chat');
    await waitFor('Reopening the first chat did not restore its editor and pane layout', () =>
      selected() === FIRST && !!panel()?.classList.contains('wide') && field()?.value === BETA_EDIT &&
      field()?.selectionStart === 4 && field()?.selectionEnd === 9);
    const restored = await inspect();
    if (restored.tabs.map((tab) => tab.id).join() !== ordered.map((tab) => tab.id).join() ||
        restored.selected !== beta || !restored.tabs[0]?.dirty) throw new Error('The first file session was not restored');
    await rejectsStale(changeFileTools({ scope: second, change: { discard: rejectedClose.discard } }));
    await clickByLabel('Close beta.txt');
    await waitFor('Closing the first chat file did not settle its edit', () =>
      !panel()?.querySelector(`[data-file-tab="${beta}"]`));

    await click('New Chat');
    await waitFor('A fresh draft did not retire the first file presentation', () =>
      selected() === null && !!visible()?.navigation.draft && !panel());
    const draft = scope();
    await showFiles();
    await browse('adopt.txt');
    await editFile('Original adoption\n', ADOPT_EDIT);
    const source = await inspect();
    const adoptedFile = source.selected!;
    typeText('Start a chat with its existing file tab.');
    await click('Send');
    await waitFor('The backend did not create the first thread', () =>
      !!selected() && selected() !== FIRST && selected() !== SECOND);
    await waitFor('The first thread did not adopt its file tool buffer', () => field()?.value === ADOPT_EDIT);
    const adopted = await inspect();
    if (scope().draftId !== draft.draftId || adopted.sessionId !== source.sessionId || adopted.selected !== adoptedFile) {
      throw new Error('The first thread received a different file tools session');
    }
    await click('First fixture chat');
    await waitFor('The original chat did not restore before quit', () => selected() === FIRST && !!panel());
    await invoke('request_quit_fixture', { application: true });
    await waitFor('Quit did not account for hidden file edits', () =>
      !!quitDialog()?.textContent?.includes('Save and Quit'));
    const saveTicket = visible()!.navigation.quit!.ticket;
    await click('Save and Quit', quitDialog()!);
    await waitFor('A hidden conflicting tab did not block quit after saving other files', () =>
      !!quitDialog()?.textContent?.includes('Discard Changes and Quit'));
    await rejectsStale(navigateWorkspace({ confirmQuit: { ticket: saveTicket } }));
    await click('Cancel', quitDialog()!);
    await click('Second fixture chat');
    await waitFor('Cancelling quit lost the hidden edit or changed its owner', () =>
      selected() === SECOND && field()?.value === CONFLICT_EDIT);
    await click('First fixture chat');
    await waitFor('The first chat could not own the quit view', () => selected() === FIRST);
    await invoke('request_quit_fixture', { application: false });
    await waitFor('The remaining file did not require settlement', () =>
      !!quitDialog()?.textContent?.includes('Save and Quit'));
    await click('Save and Quit', quitDialog()!);
    await click('Discard Changes and Quit', quitDialog()!);
  } catch (error) {
    await invoke('report_quit_failure', { failure: String(error) });
  }
}
