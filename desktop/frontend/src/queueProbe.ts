import { invoke } from '@tauri-apps/api/core';
import { click, editor, typeText, waitFor } from './fixtureControls';
import type { WorkspaceSnapshot } from './generated/workspace';
import { navigateWorkspace } from './projectIpc';

type Snapshot = () => WorkspaceSnapshot | null;

const HELD = 'Hold this fixture turn';
const FIRST = 'First queued follow-up';
const EDITED = 'Edited queued follow-up 日本語';
const DELETE = 'Delete this follow-up';
const STRAIGHT = 'Steer directly into this turn';
const LAST = 'Resume from the empty composer';
const OTHER = 'history-second';
const RELOADED = 'installed-queue-fixture-reloaded';

function ready(visible: Snapshot) {
  const queue = visible()?.navigation.queue;
  return queue && !queue.busy;
}

async function entries(visible: Snapshot, ...expected: string[]) {
  await waitFor(`The queue did not contain ${expected.join(', ')}`, () => {
    const queue = visible()?.navigation.queue;
    return !!queue && !queue.busy && JSON.stringify(queue.entries.map((entry) => entry.text)) === JSON.stringify(expected);
  });
}

function rowButton(input: string, label: string) {
  const row = [...document.querySelectorAll('.queue-entry')]
    .find((row) => row.querySelector('.queue-input')?.textContent === input);
  return [...(row?.querySelectorAll('button') ?? [])].find((button) => button.textContent?.trim() === label);
}

async function clickRow(input: string, label: string) {
  await waitFor(`Could not use ${label} on ${input}`, () => rowButton(input, label)?.disabled === false);
  rowButton(input, label)?.click();
}

async function enterText(visible: Snapshot, text: string) {
  typeText(text);
  await waitFor('The queue fixture draft was not persisted', () => visible()?.navigation.draft?.text === text);
}

async function submit(visible: Snapshot, text: string, label: string) {
  await enterText(visible, text);
  await click(label);
  await waitFor(`The ${label} action did not retire the submitted draft`, () =>
    visible()?.navigation.draft?.text === '' && editor().value === '');
}

async function stop(visible: Snapshot) {
  await click('Stop');
  await waitFor('The captured queue turn was not stopped', () =>
    visible()?.navigation.actions.stop === null && !!visible()?.navigation.queue?.resume && !!ready(visible));
}

async function driveQueue(visible: Snapshot) {
  await submit(visible, HELD, 'Send');
  await waitFor('The queue had no accepted active turn', () =>
    !!visible()?.navigation.queue?.activeTurn && !!ready(visible));
  const owner = visible()?.navigation.selectedChat;
  const title = visible()?.navigation.chats.find((row) => row.id === owner)?.title;
  if (!owner || !title) throw new Error('Could not identify the active fixture chat');

  await submit(visible, FIRST, 'Queue');
  await entries(visible, FIRST);
  await submit(visible, DELETE, 'Queue');
  await entries(visible, FIRST, DELETE);
  await enterText(visible, 'A separate unsent draft');
  await waitFor('An occupied draft did not protect Edit', () => rowButton(FIRST, 'Edit')?.disabled === true);
  await enterText(visible, '');

  await clickRow(FIRST, 'Edit');
  await waitFor('Queue edit did not populate the original draft', () =>
    !!visible()?.navigation.queue?.editing && !!ready(visible) && editor().value === FIRST);
  await enterText(visible, 'Discard this edit');
  await click('Cancel Edit');
  await entries(visible, FIRST, DELETE);
  await waitFor('Cancel did not clear the edited draft', () => !visible()?.navigation.queue?.editing && editor().value === '');
  await clickRow(FIRST, 'Edit');
  await waitFor('The queue editor did not reopen', () =>
    !!visible()?.navigation.queue?.editing && !!ready(visible) && editor().value === FIRST);
  await enterText(visible, EDITED);
  await click('Save Queue Edit');
  await entries(visible, EDITED, DELETE);
  await clickRow(DELETE, 'Move Up');
  await entries(visible, DELETE, EDITED);

  const captured = visible();
  const revision = captured?.navigation.queue?.revision;
  const entry = captured?.navigation.queue?.entries[0];
  const workspaceId = captured?.workspace?.workspaceId;
  if (!revision || !entry || !workspaceId) throw new Error('The queue action did not capture its scope');
  await click('Second fixture chat');
  await waitFor('Switching chats showed another chat’s entries', () =>
    visible()?.navigation.selectedChat === OTHER && !!ready(visible) &&
    visible()?.navigation.queue?.entries.length === 0);
  let staleActionRejected = false;
  try {
    await navigateWorkspace({ queue: { workspaceId, chatId: owner, revision, command: { delete: entry.id } } });
  } catch (error) {
    if (error !== 'staleSelection') throw error;
    staleActionRejected = true;
  }
  if (!staleActionRejected) throw new Error('The previous chat’s queue action was accepted after switching');
  await click(title);
  await waitFor('The original queue did not keep its active turn', () =>
    visible()?.navigation.selectedChat === owner && !!visible()?.navigation.queue?.activeTurn);
  await entries(visible, DELETE, EDITED);
  await clickRow(EDITED, 'Steer');
  await entries(visible, DELETE);
  await clickRow(DELETE, 'Delete');
  await entries(visible);

  await click('Queue Follow-ups');
  await waitFor('The queue toggle did not turn off', () => visible()?.navigation.queue?.enabled === false);
  await submit(visible, STRAIGHT, 'Steer');
  await entries(visible);
  await click('Queue Follow-ups');
  await waitFor('The queue toggle did not turn on', () => visible()?.navigation.queue?.enabled === true);
  await submit(visible, HELD, 'Queue');
  await entries(visible, HELD);
  await submit(visible, LAST, 'Queue');
  await entries(visible, HELD, LAST);

  await stop(visible);
  await click('Resume Queue');
  await waitFor('The queue panel did not resume the first captured entry', () =>
    !!visible()?.navigation.queue?.activeTurn && !!ready(visible) && visible()?.navigation.queue?.entries[0]?.text === LAST);
  await stop(visible);
  await click('Resume');
  await entries(visible);
  await waitFor('The composer’s resumed turn did not complete', () =>
    visible()?.navigation.actions.stop === null &&
    !!document.querySelector('.workspace-transcript')?.textContent?.includes(LAST));

  await click('Queue Follow-ups');
  await waitFor('The saved queue preference was missing', () => visible()?.navigation.queue?.enabled === false);
  await click('Second fixture chat');
  await waitFor('The queue toggle leaked to another chat', () =>
    visible()?.navigation.selectedChat === OTHER && visible()?.navigation.queue?.enabled === true);
  await click(title);
  await waitFor('Returning to the original chat lost its queue preference', () =>
    visible()?.navigation.selectedChat === owner && visible()?.navigation.queue?.enabled === false);
  sessionStorage.setItem(RELOADED, owner);
  window.location.reload();
}

export async function verifyQueue(visible: Snapshot) {
  try {
    await waitFor('The queue fixture project did not load', () =>
      !!visible()?.workspace && (visible()?.navigation.chats.length ?? 0) >= 2 &&
      visible()?.navigation.writeAccess === 'ready');
    const owner = sessionStorage.getItem(RELOADED);
    if (!owner) {
      await driveQueue(visible);
      return;
    }
    await waitFor('WebView reload lost the captured queue preference', () =>
      visible()?.navigation.selectedChat === owner && visible()?.navigation.queue?.enabled === false &&
      !!ready(visible));
    await invoke('verify_turn_result', { failure: null });
  } catch (error) {
    await invoke('verify_turn_result', {
      failure: `${String(error)}. Observed queue ${JSON.stringify(visible()?.navigation.queue)}`,
    });
  }
}
