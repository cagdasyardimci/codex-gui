import { invoke } from '@tauri-apps/api/core';
import type { TranscriptRowRequest, WorkspaceId, WorkspaceSnapshot } from './generated/workspace';
import { checkTranscriptImages, navigateWorkspace, searchProjectPaths } from './projectIpc';
import { click, editor, typeText, waitFor } from './fixtureControls';

const FIRST = 'history-first';
const SECOND = 'history-second';
const DRAFT = 'Composed café 日本語';
const UNSENT = 'Unsent checkout draft';
const REPLY = 'A streamed reply with café 日本語 👩🏽‍💻.';

function shortcut(key: string, composing = false) {
  window.dispatchEvent(new KeyboardEvent('keydown', { key, ctrlKey: true, isComposing: composing }));
}

function containsText(text: string) {
  return document.querySelector('.workspace-transcript')?.textContent?.includes(text) ?? false;
}

function frame(): Promise<void> {
  return new Promise((resolve) => requestAnimationFrame(() => resolve()));
}

async function verifyOlderHistory(visible: () => WorkspaceSnapshot | null) {
  const initial = visible();
  const older = initial?.navigation.olderHistory;
  if (!older) return;
  const viewport = document.querySelector<HTMLDivElement>('.workspace-transcript');
  const boundary = initial.transcript.items[0];
  const anchor = viewport?.firstElementChild;
  if (!viewport || !anchor || boundary?.itemId !== 'older-fixture-05/response' ||
      viewport.scrollHeight <= viewport.clientHeight) {
    throw new Error('The newest history page did not fill the scrollable transcript');
  }
  viewport.scrollTop = 100;
  await frame();
  viewport.scrollTop = 0;
  await frame();
  await frame();
  if (visible()?.navigation.olderHistory?.ticket !== older.ticket ||
      visible()?.navigation.olderHistory?.pending || viewport.firstElementChild !== anchor) {
    throw new Error('Programmatic scrolling requested an older history page');
  }
  const top = anchor.getBoundingClientRect().top - viewport.getBoundingClientRect().top;
  for (let count = 0; count < 2; count++) {
    viewport.dispatchEvent(new WheelEvent('wheel', { deltaY: -100 }));
  }
  await waitFor('The upward scroll did not prepend earlier turns', () =>
    visible()?.transcript.items[0]?.itemId === 'older-fixture-01/response' &&
    visible()?.navigation.olderHistory === null);
  await frame();
  const restoredTop = anchor.getBoundingClientRect().top - viewport.getBoundingClientRect().top;
  const retained = visible()?.transcript.items.find((row) => row.itemId === boundary.itemId);
  const ordered = [...new Set(visible()?.transcript.items.filter((row) => row.turnId.startsWith('older-fixture-'))
    .map((row) => row.turnId))];
  if (!anchor.isConnected || Math.abs(restoredTop - top) > 1 || retained?.revision !== boundary.revision ||
      ordered.length !== 32 || ordered.some((id, index) => id !== `older-fixture-${String(index + 1).padStart(2, '0')}`)) {
    throw new Error('Prepending history changed the visible row, its position, or its revision');
  }
}

async function verifyTurnRail(visible: () => WorkspaceSnapshot | null) {
  if (!visible()?.navigation.olderHistory) return;
  await waitFor('The rail did not expose unloaded turn references', () =>
    !!visible()?.navigation.turnRail?.turns.some((turn) => turn.id === 'older-fixture-03'));
  const viewport = document.querySelector<HTMLDivElement>('.workspace-transcript');
  const hover = document.querySelector<HTMLButtonElement>('button[data-turn-reference="older-fixture-03"]');
  const delayed = document.querySelector<HTMLButtonElement>('button[data-turn-reference="older-fixture-04"]');
  const jump = document.querySelector<HTMLButtonElement>('button[data-turn-reference="older-fixture-05"]');
  if (!viewport || !hover || !delayed || !jump || visible()?.transcript.items.some((row) => row.turnId === 'older-fixture-03')) {
    throw new Error('The first rail target must be outside the loaded transcript');
  }
  const before = viewport.scrollTop;
  const rows = visible()!.transcript.items.map((row) => row.itemId).join('\n');
  hover.dispatchEvent(new MouseEvent('mouseenter'));
  await waitFor('The separate turn preview did not show the first and last text', () => {
    const preview = document.querySelector('.turn-rail-preview')?.textContent;
    return !!preview?.includes('A saved long turn') && preview.includes('Saved history page fixture 03');
  });
  if (viewport.scrollTop !== before || visible()?.transcript.items.map((row) => row.itemId).join('\n') !== rows) {
    throw new Error('The hover preview changed the transcript position or resident rows');
  }
  delayed.dispatchEvent(new MouseEvent('mouseenter'));
  jump.click();
  await waitFor('The committed jump did not replace the preview and open the unloaded turn', () =>
    !document.querySelector('.turn-rail-preview') &&
    visible()?.transcript.items[0]?.itemId === 'older-fixture-05/response' &&
    visible()?.navigation.turnRail?.jump?.turnId === 'older-fixture-05');
  await frame();
  const opened = viewport.firstElementChild?.getBoundingClientRect();
  if (!opened || Math.abs(opened.top - viewport.getBoundingClientRect().top) > 1) {
    throw new Error('The committed jump did not position the target turn in the viewport');
  }
}

async function verifySavedRows(workspaceId: WorkspaceId, snapshot: WorkspaceSnapshot) {
  const saved = snapshot.transcript.items.find((item) => item.itemId === 'first-saved-turn/first-history');
  const group = snapshot.transcript.items.find((item) => item.role === 'commands');
  if (!saved || group?.commands.length !== 2 || group.commands[1]?.output !== 'Café.md\n') {
    throw new Error('The saved turn did not group its command output');
  }
  const commands = document.querySelector<HTMLDetailsElement>(`[data-item-id="${group.itemId}"] details`);
  commands?.querySelector('summary')?.click();
  if (!commands?.open || !commands.querySelector('ul')?.textContent?.includes('Café.md\n')) {
    throw new Error('The command group did not reveal its saved output');
  }
  commands.open = false;
  const row = document.querySelector(`[data-item-id="${saved.itemId}"]`);
  const paragraph = row?.querySelector('p');
  const copy = row?.querySelector<HTMLButtonElement>('button');
  const selection = window.getSelection();
  if (!row || !paragraph || !copy || !selection) throw new Error('The saved response action did not render');
  const range = document.createRange();
  range.selectNodeContents(paragraph);
  selection.removeAllRanges();
  selection.addRange(range);
  const selected = selection.toString();
  const height = row.getBoundingClientRect().height;
  window.dispatchEvent(new KeyboardEvent('keydown', { key: 'Tab' }));
  copy.focus({ preventScroll: true });
  await frame();
  const revealed = getComputedStyle(copy).opacity === '1';
  const selectionRetained = !!selected && selection.toString() === selected && selection.containsNode(paragraph, true);
  const geometryRetained = row.getBoundingClientRect().height === height;
  if (!revealed || !selectionRetained || !geometryRetained) {
    throw new Error(`Revealing a saved action failed ${JSON.stringify({ revealed, selectionRetained, geometryRetained })}`);
  }
  selection.removeAllRanges();
  const request: TranscriptRowRequest = { workspaceId, chatId: FIRST, generation: snapshot.transcript.generation,
    itemId: saved.itemId, revision: saved.revision };
  const source = snapshot.transcript.items.find((item) => item.itemId === 'first-saved-turn/first-image');
  if (!source) throw new Error('The fixture image response did not render');
  const imageRequest = { ...request, itemId: source.itemId, revision: source.revision };
  const [image] = await checkTranscriptImages(imageRequest);
  if (image?.path !== 'notes/panel.png' || !image.revision?.byteCount) {
    throw new Error('The installed transcript did not project its scoped image dependency');
  }
  return { row, request, imageRequest };
}

export async function verifyHistory(
  phase: 'initial' | 'restore',
  visible: () => WorkspaceSnapshot | null,
) {
  try {
    await waitFor('Selected project or chat list was missing', () =>
      !!visible()?.workspace?.projectPath.includes('Checkout café') &&
      visible()?.navigation.chats.length === 2);
    const workspaceId = visible()?.workspace?.workspaceId;
    if (!workspaceId) throw new Error('Could not capture the project owner');
    if (phase === 'restore') {
      await waitFor('Restart did not restore the selected chat and draft', () =>
        visible()?.navigation.selectedChat === FIRST && editor().value === DRAFT && containsText(REPLY));
      shortcut('n');
      await waitFor('New Chat shortcut did not select the unsent draft', () =>
        visible()?.navigation.selectedChat === null);
      await waitFor('New Chat shortcut did not retain the unsent draft', () =>
        editor().value === UNSENT);
      await waitFor('New Chat shortcut did not focus the composer', () =>
        document.activeElement === editor());
      await click('Clear Project');
      await waitFor('Clearing the project lost the unsent draft', () =>
        visible()?.workspace === null && visible()?.navigation.draft?.text === UNSENT &&
        visible()?.navigation.account.identity === 'fixture@example.invalid' &&
        editor().value === UNSENT && !document.querySelector('nav[aria-label="Chats"]') &&
        Array.from(document.querySelectorAll('.composer-actions button'))
          .some((button) => button instanceof HTMLButtonElement && button.textContent?.trim() === 'Send' && button.disabled));
      try {
        await navigateWorkspace({ refresh: { workspaceId } });
        throw new Error('Retired workspace could still access chat history');
      } catch (error) {
        if (error !== 'retiredWorkspace') throw error;
      }
      try {
        await searchProjectPaths({ workspaceId, query: 'café.md' });
        throw new Error('Retired workspace could still search project files');
      } catch (error) {
        if (error !== 'retiredWorkspace') throw error;
      }
    } else {
      typeText(UNSENT);
      await waitFor('Unsent draft did not persist', () => visible()?.navigation.draft?.text === UNSENT);
      await click('First fixture chat');
      await waitFor('Writer lock did not leave readable history', () =>
        visible()?.navigation.selectedChat === FIRST && !!visible()?.navigation.retryable &&
        containsText('History in the first chat.'));
      await verifyTurnRail(visible);
      await verifyOlderHistory(visible);
      const saved = await verifySavedRows(workspaceId, visible()!);
      const [path, ...others] = await searchProjectPaths({ workspaceId, query: ' CAFÉ.MD ' });
      if (path?.displayPath !== 'notes/Café.md' || others.length) {
        throw new Error('Project search did not return the visible checkout file');
      }
      const control = editor();
      control.focus();
      control.dispatchEvent(new CompositionEvent('compositionstart', { bubbles: true }));
      typeText(DRAFT, true);
      shortcut('n', true);
      if (visible()?.navigation.selectedChat !== FIRST || document.activeElement !== control) {
        throw new Error('IME input changed the selected chat or focus');
      }
      control.dispatchEvent(new CompositionEvent('compositionend', { bubbles: true, data: DRAFT }));
      await waitFor('Committed IME text was not saved', () => visible()?.navigation.draft?.text === DRAFT);
      await click('Retry');
      await waitFor('Cold resume did not stream into the selected chat', () =>
        !visible()?.navigation.retryable && containsText('A streamed reply') && !containsText(REPLY));
      if (!saved.row.isConnected || !saved.row.querySelector('[aria-label="Copy response"]') ||
          visible()?.transcript.items.find((item) => item.itemId === saved.request.itemId)?.revision !== saved.request.revision) {
        throw new Error('An unrelated delta replaced the saved response or retired its copy action');
      }
      if (!visible()?.transcript.items.some((row) => row.role === 'commands' &&
          row.commands.length === 2 && row.commands[1]?.output === 'Café 日本語\n' && row.completed)) {
        throw new Error('The resumed command group lost its streamed output');
      }
      await waitFor('The complete stream was not rendered exactly', () =>
        containsText(REPLY) && !!visible()?.transcript.items.some((item) => item.completed && item.text === REPLY));
      await click('Second fixture chat');
      await waitFor('Chat switching showed stale transcript or draft', () =>
        visible()?.navigation.selectedChat === SECOND && !containsText(REPLY) &&
        containsText('History in the second chat.') && editor().value === '');
      try {
        await checkTranscriptImages(saved.imageRequest);
        throw new Error('A retired transcript could still inspect local images');
      } catch (error) {
        if (error !== 'staleSelection') throw error;
      }
      const [secondPath] = await searchProjectPaths({ workspaceId, query: 'café.md' });
      if (secondPath?.id.revision !== path.id.revision || secondPath?.id.entry !== path.id.entry) {
        throw new Error('Switching chats replaced the checkout-owned path index');
      }
      await click('First fixture chat');
      await waitFor('Returning to the first chat did not restore its draft', () =>
        visible()?.navigation.selectedChat === FIRST && containsText(REPLY) && editor().value === DRAFT);
      await click('Refresh');
      await click('Reconnect');
      await waitFor('Refresh or reconnect lost the selected history', () =>
        visible()?.navigation.selectedChat === FIRST && containsText(REPLY) && editor().value === DRAFT &&
        !!Array.from(document.querySelectorAll('button')).find((button) => button.textContent?.trim() === 'Reconnect' && !button.disabled));
    }
    await invoke('verify_history_result', { failure: null });
  } catch (error) {
    const navigation = visible()?.navigation;
    const control = document.querySelector<HTMLTextAreaElement>('textarea[aria-label="Message"]');
    const evidence = {
      phase, unsentSelected: navigation?.selectedChat === null,
      unsentDraftPublished: navigation?.draft?.text === UNSENT,
      unsentDraftRendered: control?.value === UNSENT, editorFocused: document.activeElement === control,
      documentFocused: document.hasFocus(), activeElement: document.activeElement?.localName,
    };
    await invoke('verify_history_result', { failure: `${String(error)} ${JSON.stringify(evidence)}` });
  }
}
