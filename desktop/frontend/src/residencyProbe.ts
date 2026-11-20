import type { WorkspaceSnapshot } from './generated/workspace';
import { click, waitFor } from './fixtureControls';

export async function verifyResidentHistory(visible: () => WorkspaceSnapshot | null) {
  await click('First fixture chat');
  await waitFor('The large transcript and its reference index did not load', () =>
    visible()?.navigation.selectedChat === 'history-first' &&
    visible()?.navigation.turnRail?.turns.length === 96 && !!visible()?.navigation.olderHistory);
  const viewport = document.querySelector<HTMLDivElement>('.workspace-transcript');
  if (!viewport) throw new Error('The large transcript viewport did not mount');
  const moveToStart = async () => {
    viewport.scrollTop = 0;
    await frame();
    await waitFor('The transcript did not reach its first resident row', () => {
      if (viewport.scrollTop > 1) {
        viewport.scrollTop = 0;
        return false;
      }
      const first = viewport.firstElementChild as HTMLElement | null;
      return first?.dataset.transcriptSlot === visible()?.transcript.items[0]?.itemId;
    });
  };
  for (let page = 0; page < 4; page++) {
    const ticket = visible()?.navigation.olderHistory?.ticket;
    if (!ticket) throw new Error('The history cursor was exhausted before the fixture was read');
    await moveToStart();
    viewport.dispatchEvent(new WheelEvent('wheel', { deltaY: -100 }));
    await waitFor(`The large transcript did not advance its older cursor on page ${page + 1}`, () =>
      visible()?.navigation.olderHistory?.ticket !== ticket);
    await frame();
  }
  const state = visible();
  const loaded = new Set(state?.transcript.items.map((row) => row.turnId));
  const references = state?.navigation.turnRail?.turns;
  if (!state || references?.length !== 96 || loaded.size > 75 || loaded.size < 50 ||
      viewport.querySelectorAll('[data-transcript-slot]').length > 56) {
    throw new Error('The transcript exceeded its residency or mount bounds');
  }
  const evicted = references.slice(0, -20).find((turn) => !loaded.has(turn.id));
  if (!evicted) throw new Error('The fixture did not evict a turn outside the recent page');
  await moveToStart();
  const first = viewport.querySelector('[data-transcript-slot] p');
  const selection = window.getSelection();
  if (!first || !selection) throw new Error('A readable row did not mount for selection');
  const range = document.createRange();
  range.selectNodeContents(first);
  selection.removeAllRanges();
  selection.addRange(range);
  const selected = selection.toString();
  await frame();
  await frame();
  viewport.scrollTop = viewport.scrollHeight;
  await waitFor('Scrolling the large transcript did not mount its most recent row', () =>
    !!viewport.querySelector('[data-turn-id="first-saved-turn"]'));
  if (!selected || !first.isConnected || selection.toString() !== selected ||
      viewport.querySelectorAll('[data-transcript-slot]').length > 56) {
    throw new Error('Virtualizing offscreen history changed the native selection');
  }
  selection.removeAllRanges();
  const marker = document.querySelector<HTMLButtonElement>(`[data-turn-reference="${evicted.id}"]`);
  if (!marker) throw new Error('The evicted turn lost its rail action');
  marker.click();
  const anchored = () => {
    const card = viewport.querySelector<HTMLElement>(`[data-turn-id="${evicted.id}"]`);
    if (!card || visible()?.navigation.turnRail?.jump?.turnId !== evicted.id) return false;
    const viewportTop = viewport.getBoundingClientRect().top;
    return Math.abs(card.getBoundingClientRect().top - viewportTop) <= 12;
  };
  const verifyAnchor = async (description: string) => {
    await waitFor(description, anchored).catch((error) => {
      const snapshot = visible();
      const card = viewport.querySelector(`[data-turn-id="${evicted.id}"]`);
      throw new Error(`${error.message} ${JSON.stringify({ target: evicted.id, entered: snapshot?.navigation.selectedChat,
        jump: snapshot?.navigation.turnRail?.jump?.turnId, scrollTop: viewport.scrollTop,
        maximumScroll: viewport.scrollHeight - viewport.clientHeight,
        rowTop: card ? card.getBoundingClientRect().top - viewport.getBoundingClientRect().top : undefined,
        present: snapshot?.transcript.items.some((row) => row.turnId === evicted.id) })}`);
    });
  };
  await verifyAnchor('An evicted turn did not reload at its own reading anchor');
  await click('Second fixture chat');
  await waitFor('The neighboring chat did not replace the viewport', () =>
    visible()?.navigation.selectedChat === 'history-second');
  await click('First fixture chat');
  await verifyAnchor('Returning to the chat did not reload its evicted reading anchor');
}

function frame(): Promise<void> {
  return new Promise((resolve) => requestAnimationFrame(() => resolve()));
}
