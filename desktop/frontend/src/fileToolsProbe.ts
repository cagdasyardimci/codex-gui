import { invoke } from '@tauri-apps/api/core';
import { cancelFileSearch, changeFileTools, openFileSearchHit, readFileSearch, readFileTab, startFileSearch } from './fileTools';
import { click, clickByLabel, editor, typeText, waitFor } from './fixtureControls';
import type { DraftAttachmentScope, WorkspaceSnapshot } from './generated/workspace';
import { rejectsStale } from './markdownProbe';
import { navigateWorkspace } from './projectIpc';

const FIRST = 'history-first';
const SECOND = 'history-second';
const BETA_EDIT = 'The first chat owns this file.\n';
const ADOPT_EDIT = 'Keep the new chat file.\n';
const CONFLICT_EDIT = 'Keep this buffer after the conflicting save.\n';
const GUIDE = 'Guide café #.md';
const GUIDE_ORIGINAL = '# Local guide\n\nAlpha first.\nALPHA second.\n';
const GUIDE_EDIT = '# Saved guide\n\nPreserve café from the first chat.\n';

const panel = () => document.querySelector<HTMLElement>('aside[aria-label="Project Files"]');
const browser = () => panel()?.querySelector<HTMLElement>('nav[aria-label="Project File Browser"]');
const field = () => panel()?.querySelector<HTMLTextAreaElement>('textarea');
const closeDialog = () => document.querySelector<HTMLDialogElement>('dialog[aria-label="Close File"][open]');
const quitDialog = () => document.querySelector<HTMLDialogElement>('dialog.quit-dialog[open]');
const quickOpenField = () => document.querySelector<HTMLInputElement>('dialog[aria-label="Quick Open"][open] input');
const fileSearchDialog = () => document.querySelector<HTMLDialogElement>('dialog[aria-label="Search Files"][open]');

function enterSearchText(control: HTMLInputElement, value: string) {
  control.value = value;
  control.dispatchEvent(new InputEvent('input', { bubbles: true }));
}

function key(target: HTMLElement, key: string, modifiers: KeyboardEventInit = {}) {
  target.dispatchEvent(new KeyboardEvent('keydown', { key, bubbles: true, cancelable: true, ...modifiers }));
}

function searchFiles(query: string) {
  enterSearchText(quickOpenField()!, query);
}

function quickOpenResults() {
  return [...(quickOpenField()?.closest('dialog')?.querySelectorAll('[role="option"]') ?? [])]
    .map((result) => result.firstElementChild?.textContent).join(',');
}

async function openQuickOpen() {
  await waitFor('The workspace did not finish navigation before Quick Open', () =>
    !!document.querySelector('button[aria-keyshortcuts="Meta+P Control+P"]:enabled'));
  editor().focus();
  key(editor(), 'p', { ctrlKey: true });
  await waitFor('The keyboard shortcut did not focus Quick Open', () => !!quickOpenField() && document.activeElement === quickOpenField());
}

async function verifyQuickOpen(visible: () => WorkspaceSnapshot | null, scope: DraftAttachmentScope) {
  const draft = 'Keep this text and its selection when choosing a file.';
  typeText(draft);
  await waitFor('The first draft did not settle before Quick Open', () => visible()?.navigation.draft?.text === draft);
  const composer = editor();
  composer.setSelectionRange(5, 14);
  await openQuickOpen();
  searchFiles('pix');
  await waitFor('Incremental search did not find both image files', () => quickOpenResults() === 'pixel.png,pixel2.png');
  searchFiles('pixel2');
  await waitFor('Narrowing the query did not retire the previous results', () => quickOpenResults() === 'pixel2.png');
  key(quickOpenField()!, 'Escape');
  await waitFor('Escape changed the closed pane, focused control or selection', () =>
    !quickOpenField() && !panel() && document.activeElement === composer && composer.value === draft &&
    composer.selectionStart === 5 && composer.selectionEnd === 14);

  await openQuickOpen();
  searchFiles('alpha');
  await waitFor('The nested file did not become selectable', () => quickOpenResults() === 'alpha.txt');
  await navigateWorkspace({ openChat: { workspaceId: scope.workspaceId, chatId: SECOND } });
  await waitFor('Changing chat left the preceding file chooser or pane open', () =>
    visible()?.navigation.selectedChat === SECOND && !quickOpenField() && !panel());
  await click('First fixture chat');
  await waitFor('The first chat did not restore before selecting a file', () => visible()?.navigation.selectedChat === FIRST);

  await openQuickOpen();
  searchFiles('pixel');
  await waitFor('The owning chat did not find both images', () => quickOpenResults() === 'pixel.png,pixel2.png');
  key(quickOpenField()!, 'ArrowDown');
  key(quickOpenField()!, 'Enter');
  await waitFor('Keyboard selection did not open the second result with the pane initially closed', () =>
    !quickOpenField() && !!panel()?.querySelector('img[alt="pixel2.png"]') && document.activeElement === editor());
  const opened = await changeFileTools({ scope, change: 'inspect' });
  if (opened.tabs.length !== 1 || opened.tabs[0]?.preview || opened.tabs[0]?.id !== opened.selected) {
    throw new Error('Quick Open did not retain the selected file under the initiating chat');
  }
  await clickByLabel('Close pixel2.png');
  await click('Hide Files');
  await waitFor('The file pane did not close after Quick Open', () => !panel());

  await click('Command Palette');
  const commands = () => document.querySelector<HTMLDialogElement>('dialog[aria-label="Command Palette"][open]');
  await waitFor('The command palette did not open', () => !!commands());
  await click('Quick Open', commands()!);
  await waitFor('The command palette did not transfer focus to the file chooser', () =>
    !!quickOpenField() && document.activeElement === quickOpenField());
  key(quickOpenField()!, 'Escape');
  await waitFor('Cancelling from the command palette opened the file pane', () => !quickOpenField() && !panel());
}

async function verifyFileSearch(visible: () => WorkspaceSnapshot | null, scope: DraftAttachmentScope) {
  const before = await startFileSearch({ scope, query: 'Unique replacement target', mask: '*.txt' });
  const first = await readFileSearch({ session: before, cursor: null });
  const match = first.matches.find((entry) => entry.path === 'replace.txt');
  if (!match) throw new Error('Search did not record the file identity for replacement');
  const target = { session: before, id: match.id };
  await invoke('overwrite_file_tools_fixture', { replacement: true });
  await rejectsStale(openFileSearchHit(target));
  const after = await startFileSearch({ scope, query: 'Heading', mask: '*.txt' });
  await rejectsStale(openFileSearchHit(target));
  await cancelFileSearch(after);
  await rejectsStale(readFileSearch({ session: after, cursor: null }));

  const retired = await startFileSearch({ scope, query: 'Café marker', mask: '*.txt' });
  await navigateWorkspace({ openChat: { workspaceId: scope.workspaceId, chatId: SECOND } });
  await waitFor('The new owner did not select before validating the retired file query', () =>
    visible()?.navigation.selectedChat === SECOND);
  await rejectsStale(readFileSearch({ session: retired, cursor: null }));
  await click('First fixture chat');
  await waitFor('The file search owner did not restore before typing', () => visible()?.navigation.selectedChat === FIRST);

  await click('Search Files');
  const query = () => fileSearchDialog()?.querySelector<HTMLInputElement>('input[role="combobox"]');
  await waitFor('The file search did not focus its query', () => !!query() && document.activeElement === query());
  const mask = fileSearchDialog()!.querySelector<HTMLInputElement>('input:not([role])')!;
  enterSearchText(mask, '*.{txt,md}');
  enterSearchText(query()!, 'CAFÉ MARKER');
  const matches = () => [...(fileSearchDialog()?.querySelectorAll('[role="option"] strong') ?? [])];
  await waitFor('The first page did not contain the scoped file matches', () =>
    matches().length === 24 && matches()[0]?.textContent === 'search.txt:2' &&
    matches().every((match) => match.textContent?.startsWith('search.txt:')));
  await click('More Matches', fileSearchDialog()!);
  await waitFor('Paging did not reach the last line of the same file', () =>
    matches().length === 29 && matches().at(-1)?.textContent === 'search.txt:30' && document.activeElement === query());
  key(query()!, 'ArrowUp');
  key(query()!, 'Enter');
  await waitFor('Keyboard selection did not reveal the exact matching source line', () => {
    const input = field();
    return !fileSearchDialog() && !!input && input.value.slice(input.selectionStart, input.selectionEnd) === 'Café marker 29';
  });
  const input = field()!;
  input.focus();
  key(input, 'F', { ctrlKey: true, shiftKey: true });
  await waitFor('The shortcut in Files did not open file search', () => !!query() && document.activeElement === query());
  key(query()!, 'Escape');
  await waitFor('Escape did not restore the chosen file line', () => !fileSearchDialog() && document.activeElement === input &&
    input.value.slice(input.selectionStart, input.selectionEnd) === 'Café marker 29');
  await clickByLabel('Close search.txt');
  await click('Hide Files');
  await waitFor('The file pane did not close after search', () => !panel());
}

async function verifyFileActions(visible: () => WorkspaceSnapshot | null, scope: DraftAttachmentScope) {
  await showFiles();
  await browse(GUIDE);
  await waitFor('The Markdown source did not load', () => field()?.value === GUIDE_ORIGINAL);
  await click('Preview', panel()!);
  await waitFor('Markdown preview did not render the owning file heading', () =>
    panel()?.querySelector('[aria-label="Markdown Preview"] h1')?.textContent === 'Local guide');
  await click('View Source', panel()!);
  await waitFor('Returning to source did not preserve the document', () => field()?.value === GUIDE_ORIGINAL);
  const source = field()!;
  source.focus();
  key(source, 'f', { ctrlKey: true });
  const find = () => panel()?.querySelector<HTMLInputElement>('input[aria-label="Find Text"]');
  await waitFor('In-file Find did not focus its query', () => !!find() && document.activeElement === find());
  enterSearchText(find()!, 'alpha');
  const selection = () => source.value.slice(source.selectionStart, source.selectionEnd);
  await waitFor('Find did not select the first exact source match', () => selection() === 'Alpha');
  await click('Next Match', panel()!);
  await waitFor('Find did not preserve the second match’s source casing', () => selection() === 'ALPHA');
  key(find()!, 'Escape');
  await waitFor('Closing Find did not restore source focus', () => !find() && document.activeElement === source);

  await editFile(GUIDE_ORIGINAL, GUIDE_EDIT);
  const target = (await changeFileTools({ scope, change: 'inspect' })).selected!;
  await invoke('file_save_fixture_gate', { hold: true });
  try {
    await click('Save', panel()!);
    await waitFor('The save did not reserve the original native tab', () => visible()?.navigation.savingFiles === true);
    await click('Second fixture chat');
    await waitFor('The pending save blocked switching chats', () => visible()?.navigation.selectedChat === SECOND && !panel());
    await invoke('file_save_fixture_gate', { hold: false });
    await waitFor('The hidden save changed which chat or pane was displayed', () =>
      visible()?.navigation.selectedChat === SECOND && visible()?.navigation.savingFiles === false && !panel());
  } finally {
    await invoke('file_save_fixture_gate', { hold: false }).catch(() => {});
  }
  await click('First fixture chat');
  await waitFor('Returning to the saved owner did not recover the edited source', () =>
    visible()?.navigation.selectedChat === FIRST && field()?.value === GUIDE_EDIT);
  const restored = await changeFileTools({ scope, change: 'inspect' });
  if (restored.selected !== target || restored.tabs.some((tab) => tab.dirty || tab.saving)) {
    throw new Error('The save completed for a different file or retained a submitted edit as dirty');
  }
  for (const action of ['Copy Source', 'Save As…', 'Show in Folder', 'Open in Default App', 'Open in VS Code', 'Open in GitHub']) {
    await click('File Actions', panel()!);
    const menu = () => panel()?.querySelector<HTMLElement>('[role="group"][aria-label="File Actions"]');
    await waitFor('The file action choices did not open', () => !!menu());
    await click(action, menu()!);
    await waitFor('The captured file action did not settle', () => !menu() &&
      [...panel()!.querySelectorAll<HTMLButtonElement>('button:enabled')].some((button) => button.textContent?.trim() === 'File Actions'));
  }
  await clickByLabel(`Close ${GUIDE}`);
  await click('Hide Files', panel()!);
  await waitFor('The pane did not close after completing file actions', () => !panel());
}

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
    await verifyQuickOpen(visible, first);
    await verifyFileSearch(visible, first);
    await verifyFileActions(visible, first);
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
    await click('Save', panel()!);
    await waitFor('The conflicting save discarded the buffer or kept its controls locked', () =>
      field()?.value === CONFLICT_EDIT && !visible()?.navigation.savingFiles &&
      [...panel()!.querySelectorAll<HTMLButtonElement>('button:enabled')].some((button) => button.textContent?.trim() === 'Save'));
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
