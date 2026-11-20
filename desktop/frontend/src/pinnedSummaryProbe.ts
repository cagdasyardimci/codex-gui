import { invoke } from '@tauri-apps/api/core';
import type { WorkspaceSnapshot } from './generated/workspace';
import { countChatChanges } from './diffIpc';
import { click, waitFor } from './fixtureControls';
import { rejectsStale } from './markdownProbe';

function summary() {
  return document.querySelector('aside[aria-label="Pinned Chat Summary"]');
}

function summaryShows(source: string, additions: string, deletions: string) {
  const view = summary();
  return !!view?.querySelector(`img[alt="${CSS.escape(source)}"]`) &&
    view.textContent?.includes('1 changed file') === true &&
    [...view.querySelectorAll('dd span')].map((item) => item.textContent).join() === [additions, deletions].join();
}

export async function verifyPinnedSummary(visible: () => WorkspaceSnapshot | null) {
  const selected = () => visible()?.navigation.selectedChat;
  try {
    await click('First fixture chat');
    await waitFor('The first summary did not show its own source and edit totals', () =>
      selected() === 'history-first' && summaryShows('first-source.png', '+1', '−1'));
    const first = { workspaceId: visible()!.workspace!.workspaceId, chatId: 'history-first' };
    await click('Open Changes');
    await waitFor('The summary did not reveal the actual Changes pane', () =>
      !!document.querySelector('aside[aria-label="Checkout Changes"] button[data-file-id]'));
    if (await countChatChanges(first) !== 1) throw new Error('The summary did not read the verified checkout');
    await click('tracked.txt');
    await waitFor('Refreshing the summary invalidated an open Changes file handle', () =>
      document.querySelector('pre[aria-label="Patch"]')?.textContent?.includes('+after') === true);
    await click('Changes');

    await click('Pinned Summary');
    await waitFor('The first chat summary did not hide', () => !summary());
    await click('Second fixture chat');
    await waitFor('The second chat retained the previous summary visibility or values', () =>
      selected() === 'history-second' && summaryShows('second-source.png', '+2', '−0') &&
      !summary()?.querySelector('img[alt="first-source.png"]'));
    await rejectsStale(countChatChanges(first));
    await click('Refresh');
    await waitFor('Refresh applied the summary from a retired chat', () =>
      summaryShows('second-source.png', '+2', '−0') && selected() === 'history-second');

    await click('First fixture chat');
    await waitFor('Switching back did not restore this chat’s hidden summary', () => selected() === 'history-first' && !summary());
    await click('Pinned Summary');
    await waitFor('Reopening the summary used a different chat’s contents', () =>
      summaryShows('first-source.png', '+1', '−1') && !summary()?.querySelector('img[alt="second-source.png"]'));
    await invoke('verify_attachments_result', { failure: null });
  } catch (error) {
    await invoke('verify_attachments_result', { failure: String(error) });
  }
}
