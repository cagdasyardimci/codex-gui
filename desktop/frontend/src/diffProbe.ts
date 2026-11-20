import { invoke } from '@tauri-apps/api/core';
import { readPatch } from './diffIpc';
import { click, waitFor } from './fixtureControls';
import type { WorkspaceSnapshot } from './generated/workspace';

const TRACKED = 'notes café [draft].txt';
const UNTRACKED = 'untracked café.txt';

function changedFile(name: string) {
  return Array.from(document.querySelectorAll<HTMLButtonElement>('.changes-files button'))
    .find((button) => button.textContent === name);
}

function patchText() {
  return document.querySelector('[aria-label="Patch"]')?.textContent;
}

export async function verifyDiff(visible: () => WorkspaceSnapshot | null) {
  try {
    await waitFor('The selected checkout did not load', () => !!visible()?.workspace);
    const workspaceId = visible()?.workspace?.workspaceId;
    if (!workspaceId) throw new Error('The checkout authority was missing');
    await click('Changes');
    await waitFor('The bounded checkout list did not identify both files', () =>
      !!changedFile(TRACKED) && !!changedFile(UNTRACKED));
    if (patchText() !== undefined) throw new Error('A patch loaded before selecting a file');
    const original = changedFile(TRACKED)?.dataset.fileId;
    if (!original) throw new Error('The tracked file did not have an identity');
    await click(TRACKED);
    await waitFor('The tracked patch did not include the exact edit', () =>
      !!patchText()?.includes('-Before café') && !!patchText()?.includes('+After 日本語'));
    await click(UNTRACKED);
    await waitFor('The untracked patch did not include the new file', () =>
      !!patchText()?.includes('+Untracked café') && !patchText()?.includes('+After 日本語'));
    await click('Refresh Changes');
    await waitFor('Refreshing the summary did not retire previous file identities', () =>
      !!changedFile(TRACKED)?.dataset.fileId && changedFile(TRACKED)?.dataset.fileId !== original);
    try {
      await readPatch({ workspaceId, fileId: original });
      throw new Error('A retired selection could still request a Git patch');
    } catch (error) {
      if (error !== 'staleSelection') throw error;
    }
    await invoke('verify_diff_result', { failure: null });
  } catch (error) {
    await invoke('verify_diff_result', { failure: String(error) });
  }
}
