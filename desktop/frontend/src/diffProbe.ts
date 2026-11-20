import { invoke } from '@tauri-apps/api/core';
import { performDiffAction, readPatch } from './diffIpc';
import { click, clickByLabel, waitFor } from './fixtureControls';
import type { DiffComparison, WorkspaceSnapshot } from './generated/workspace';
import { rejectsStale } from './markdownProbe';

const TRACKED = 'notes café [draft].txt';
const UNTRACKED = 'untracked café.txt';
const MARKDOWN = 'compared.md';
const BITMAP = 'pixel.png';

function changedFile(name: string) {
  return Array.from(document.querySelectorAll<HTMLButtonElement>('.changes-files button'))
    .find((button) => button.textContent?.trim() === name);
}

function patchText() {
  return document.querySelector('[aria-label="Patch"]')?.textContent;
}

function field<T extends HTMLInputElement | HTMLSelectElement>(name: string) {
  return document.querySelector<T>(`[aria-label="${name}"]`)!;
}

function changeComparison(comparison: DiffComparison) {
  const control = field<HTMLSelectElement>('Comparison');
  control.value = JSON.stringify(comparison);
  control.dispatchEvent(new Event('change', { bubbles: true }));
}

function setFilter(query: string) {
  const filter = field<HTMLInputElement>('Filter Changed Files');
  filter.value = query;
  filter.dispatchEvent(new Event('input', { bubbles: true }));
}

function marker(name: string) {
  return document.querySelector<HTMLButtonElement>(`button[aria-label="${name}"]`);
}

async function clickAction(label: string) {
  await click(label);
  await waitFor(`The ${label} action did not settle`, () =>
    [...document.querySelectorAll('button:enabled')].some((button) => button.textContent?.trim() === label));
}

export async function verifyDiff(visible: () => WorkspaceSnapshot | null) {
  try {
    await waitFor('The selected checkout did not load', () => !!visible()?.workspace && !!visible()?.navigation.draft);
    const snapshot = visible()!;
    const scope = { workspaceId: snapshot.workspace!.workspaceId, chatId: snapshot.navigation.selectedChat,
      draftId: snapshot.navigation.draft!.id };
    await click('Changes');
    await waitFor('The bounded checkout list did not identify both files', () =>
      !!changedFile(TRACKED) && !!changedFile(UNTRACKED));
    if (patchText() !== undefined) throw new Error('A patch loaded before selecting a file');
    const original = changedFile(TRACKED)?.dataset.fileId;
    if (!original) throw new Error('The tracked file did not have an identity');

    setFilter('CAFÉ [DRAFT]');
    await waitFor('Filtering did not preserve the intended Unicode path', () => !!changedFile(TRACKED) && !changedFile(UNTRACKED));
    const jump = field<HTMLSelectElement>('Jump to File');
    jump.value = original;
    jump.dispatchEvent(new Event('change', { bubbles: true }));
    await waitFor('Jump did not focus and show the selected Git patch', () =>
      !!patchText()?.includes('-Before café') && !!patchText()?.includes('+After 日本語') &&
      document.activeElement === changedFile(TRACKED));
    if (patchText()?.includes('Context 09')) throw new Error('Unchanged context was already expanded');
    const more = [...document.querySelectorAll<HTMLButtonElement>('.context-button')].find((button) => button.textContent?.includes('More Lines'));
    if (!more) throw new Error('There was no control to expand unchanged context');
    more.click();
    await waitFor('Expansion did not reveal the original context', () => !!patchText()?.includes('Context 09'));
    await click('Split');
    await waitFor('Split layout did not place the changed text on opposite sides', () =>
      [...document.querySelectorAll('.split-row')].some((row) => row.children[0]?.textContent?.includes('-Before café') &&
        row.children[1]?.textContent?.includes('+After 日本語')));
    const row = [...document.querySelectorAll('.split-row .add span')].find((node) => node.textContent === '+After 日本語');
    if (!row) throw new Error('The added text was missing from the split layout');
    const selection = getSelection()!;
    const range = document.createRange();
    range.selectNodeContents(row);
    selection.addRange(range);
    if (selection.toString() !== '+After 日本語') throw new Error('Line text was not selectable in the split layout');
    selection.removeAllRanges();
    await click('Unified');

    await clickByLabel('Mark File Reviewed');
    await waitFor('The file review marker did not settle', () => marker('Mark File Reviewed')?.getAttribute('aria-pressed') === 'true');
    await clickByLabel('Mark Hunk 1 Reviewed');
    await waitFor('The hunk review marker did not settle', () => marker('Mark Hunk 1 Reviewed')?.getAttribute('aria-pressed') === 'true');
    await click('Refresh Changes');
    await waitFor('Refreshing the summary did not retire previous file identities', () =>
      !!changedFile(TRACKED)?.dataset.fileId && changedFile(TRACKED)?.dataset.fileId !== original);
    await rejectsStale(readPatch({ scope, fileId: original }));
    await click(TRACKED);
    await waitFor('Markers did not bind to the same unchanged patch and hunk', () =>
      ['Mark File Reviewed', 'Mark Hunk 1 Reviewed'].every((name) => marker(name)?.getAttribute('aria-pressed') === 'true'));

    await invoke('change_compared_file_fixture', { restore: false });
    await clickAction('Copy Patch');
    await clickAction('Export Patch');
    await clickAction('Export After');
    await clickAction('Open After in VS Code');
    await invoke('change_compared_file_fixture', { restore: true });
    const shown = changedFile(TRACKED)!.dataset.fileId!;
    await rejectsStale(performDiffAction({ target: { scope: { ...scope, draftId: 'retired' }, fileId: shown }, action: 'copyPatch' }));

    setFilter('');
    await click('Refresh Changes');
    await waitFor('Refreshing after an external change did not issue a new comparison', () =>
      !!changedFile(TRACKED)?.dataset.fileId && changedFile(TRACKED)?.dataset.fileId !== shown);
    await click(TRACKED);
    await waitFor('Old markers leaked into different file content', () =>
      !!patchText()?.includes('+External revision') &&
      ['Mark File Reviewed', 'Mark Hunk 1 Reviewed'].every((name) => marker(name)?.getAttribute('aria-pressed') === 'false'));
    await click(UNTRACKED);
    await waitFor('The untracked patch did not include the new file', () =>
      !!patchText()?.includes('+Untracked café') && !patchText()?.includes('+External revision'));
    await click(MARKDOWN);
    await click('Preview After');
    await waitFor('The compared Markdown did not render from the captured bytes', () =>
      document.querySelector('.diff-rich-preview h1')?.textContent === 'Compared Markdown');
    await click(BITMAP);
    await click('Preview After');
    await waitFor('The compared image did not render from its captured bytes', () =>
      document.querySelector<HTMLImageElement>('.diff-rich-preview img')?.naturalWidth === 1);

    changeComparison('staged');
    await waitFor('The staged comparison did not exclude working-only files', () =>
      !!changedFile(TRACKED) && !changedFile(UNTRACKED) && !changedFile(BITMAP));
    await click(TRACKED);
    await waitFor('The staged view did not compare the index', () =>
      !!patchText()?.includes('-Before café') && !!patchText()?.includes('+Staged café'));
    changeComparison('unstaged');
    await waitFor('The unstaged comparison did not include working-only files', () => !!changedFile(UNTRACKED));
    await click(TRACKED);
    await waitFor('The unstaged view used the wrong baseline', () =>
      !!patchText()?.includes('-Staged café') && !!patchText()?.includes('+External revision'));
    const branch = { branch: 'refs/heads/comparison-base' };
    await waitFor('The comparison branch was not offered', () =>
      [...field<HTMLSelectElement>('Comparison').options].some((option) => option.value === JSON.stringify(branch)));
    changeComparison(branch);
    await waitFor('The branch comparison did not load', () => !!changedFile(TRACKED) && !patchText());
    await click(TRACKED);
    await waitFor('The branch comparison did not pin its baseline', () =>
      !!patchText()?.includes('-Before café') && !!patchText()?.includes('+External revision'));
    const commit = field<HTMLSelectElement>('Comparison').querySelector('optgroup[label="Recent Commits"] option')?.getAttribute('value');
    if (!commit) throw new Error('The recorded commit was missing');
    changeComparison(JSON.parse(commit));
    await waitFor('The commit comparison did not retire the previous working-tree scope', () =>
      !!changedFile(TRACKED) && !changedFile(UNTRACKED));
    await click(TRACKED);
    await waitFor('The pinned commit did not show its version', () =>
      !!patchText()?.includes('+Before café') && !patchText()?.includes('External revision'));
    const pinnedId = changedFile(TRACKED)!.dataset.fileId!;
    const revisions = [...document.querySelectorAll<HTMLElement>('.workspace-changes summary')]
      .find((summary) => summary.textContent === 'Compare Revisions');
    if (!revisions) throw new Error('The explicit revision controls were missing');
    revisions.click();
    for (const label of ['Base Revision', 'Target Revision']) {
      const input = field<HTMLInputElement>(label);
      input.value = 'HEAD';
      input.dispatchEvent(new Event('input', { bubbles: true }));
    }
    await click('Compare');
    await waitFor('Comparing identical refs did not retire the previous patch', () => !patchText() && !changedFile(TRACKED));
    await rejectsStale(readPatch({ scope, fileId: pinnedId }));
    await invoke('verify_diff_result', { failure: null });
  } catch (error) {
    await invoke('verify_diff_result', { failure: String(error) });
  }
}
