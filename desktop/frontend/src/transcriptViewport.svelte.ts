import { tick } from 'svelte';
import { SvelteMap } from 'svelte/reactivity';
import type { TranscriptItem, TranscriptViewportRequest, WorkspaceSnapshot } from './generated/workspace';
import { navigateWorkspace } from './projectIpc';
import { geometry, protectedTurns, readingAnchor, restoredOffset, windowEntries, type ReadingAnchor } from './transcriptWindow';

const MAX_MEASUREMENTS = 1024;
const MAX_CHAT_ANCHORS = 128;

export function createTranscriptViewport() {
  let rows = $state.raw<TranscriptItem[]>([]);
  let top = $state(0);
  let height = $state(0);
  let selection = $state<[string, string]>();
  let focused = $state<string>();
  const measured = new SvelteMap<string, number>();
  const layout = $derived(geometry(rows, measured));
  const entries = $derived(windowEntries(layout, top, height, selection, focused));
  let element: HTMLDivElement | undefined;
  let sizes: ResizeObserver | undefined;
  let publication: ReturnType<typeof setTimeout> | undefined;
  let lastRequest = '';
  let placement = 0;
  let pendingPosition = false;
  let anchoredRow: ReadingAnchor | undefined;
  let current: WorkspaceSnapshot | undefined;
  let restoring: ReadingAnchor | undefined;
  let requestedRestore: string | undefined;
  const anchors = new Map<string, ReadingAnchor>();

  function scopedChat(snapshot: WorkspaceSnapshot | undefined): string | undefined {
    const workspace = snapshot?.workspace;
    const chat = snapshot?.navigation.selectedChat;
    if (workspace && chat) return `${workspace.workspaceId}/${chat}`;
  }

  function rememberAnchor(chat: string, anchor: ReadingAnchor) {
    anchors.delete(chat);
    anchors.set(chat, anchor);
    if (anchors.size > MAX_CHAT_ANCHORS) {
      const oldest = anchors.keys().next().value;
      if (oldest !== undefined) anchors.delete(oldest);
    }
  }

  function mountedOffset(target: HTMLDivElement, anchor: ReadingAnchor | undefined) {
    if (!anchor) return;
    const row = target.querySelector(`[data-transcript-slot="${CSS.escape(anchor.itemId)}"]`);
    if (row) return target.scrollTop + row.getBoundingClientRect().top - target.getBoundingClientRect().top + anchor.offset;
  }

  function mountedAnchor(target: HTMLDivElement): ReadingAnchor | undefined {
    const edge = target.getBoundingClientRect().top;
    for (const slot of target.querySelectorAll<HTMLElement>('[data-transcript-slot]')) {
      const bounds = slot.getBoundingClientRect();
      if (bounds.top > edge + target.clientHeight) break;
      if (bounds.bottom <= edge + 1) continue;
      const itemId = slot.dataset.transcriptSlot;
      const at = itemId ? layout.positions.get(itemId) : undefined;
      const row = at === undefined ? undefined : rows[at];
      if (row) return { itemId: row.itemId, turnId: row.turnId, offset: edge - bounds.top };
    }
  }

  function place(next: number, anchor?: ReadingAnchor) {
    const target = element;
    if (!target) return;
    const position = Math.max(0, Math.min(next, layout.height - height));
    anchoredRow = anchor;
    if (Math.abs(position - top) < 0.5 && Math.abs(position - target.scrollTop) < 0.5 &&
        Math.abs((mountedOffset(target, anchor) ?? position) - target.scrollTop) < 0.5) return;
    const ticket = ++placement;
    pendingPosition = true;
    top = position;
    void tick().then(() => {
      if (ticket !== placement || element !== target) return;
      target.scrollTop = mountedOffset(target, anchor) ?? position;
      pendingPosition = false;
      top = target.scrollTop;
      anchoredRow ??= mountedAnchor(target);
      schedulePublication();
    });
  }

  function currentAnchor() {
    if (anchoredRow && layout.positions.has(anchoredRow.itemId)) return anchoredRow;
    const offset = pendingPosition ? top : (element?.scrollTop ?? top);
    return readingAnchor(layout, offset);
  }

  function restoreWhenAvailable() {
    const rail = current?.navigation.turnRail;
    const workspaceId = current?.workspace?.workspaceId;
    const chatId = current?.navigation.selectedChat;
    const candidate = restoring;
    if (!candidate || !workspaceId || !chatId || !rail || !rows.length) return;
    const position = restoredOffset(layout, candidate);
    if (position !== undefined) {
      if (requestedRestore === rail.id && rail.jump?.turnId === candidate.turnId) return;
      restoring = undefined;
      place(position, candidate);
      return;
    }
    if (requestedRestore !== rail.id && rail.turns.some((turn) => turn.id === candidate.turnId)) {
      requestedRestore = rail.id;
      void navigateWorkspace({ jumpToTurn: { workspaceId, chatId, railId: rail.id, turnId: candidate.turnId } })
        .catch(report);
    }
  }

  function receive(snapshot: WorkspaceSnapshot) {
    const previousChat = scopedChat(current);
    const nextChat = scopedChat(snapshot);
    const sameGeneration = current?.transcript.generation === snapshot.transcript.generation && previousChat === nextChat;
    const changedRows = rows !== snapshot.transcript.items;
    const anchor = !sameGeneration || changedRows ? currentAnchor() : undefined;
    if (!sameGeneration) {
      if (previousChat && anchor) rememberAnchor(previousChat, anchor);
      measured.clear();
      selection = undefined;
      focused = undefined;
      requestedRestore = undefined;
      restoring = nextChat ? anchors.get(nextChat) : undefined;
    }
    current = snapshot;
    if (changedRows) rows = snapshot.transcript.items;
    if (sameGeneration && anchor) {
      const position = restoredOffset(layout, anchor);
      if (position !== undefined) place(position, anchor);
    } else if (!sameGeneration) {
      const position = restoring ? restoredOffset(layout, restoring) : undefined;
      place(position ?? layout.height, position === undefined ? undefined : restoring);
    }
    restoreWhenAvailable();
    schedulePublication();
  }

  function jump(turnId: string) {
    const matching = restoring?.turnId === turnId ? restoring : undefined;
    restoring = undefined;
    const retained = matching ? restoredOffset(layout, matching) : undefined;
    const first = rows.findIndex((row) => row.turnId === turnId);
    if (first >= 0) {
      const anchor = retained === undefined ? { itemId: rows[first]!.itemId, turnId, offset: 0 } : matching;
      place(retained ?? layout.offsets[first]!, anchor);
    }
  }

  function noteInput() {
    restoring = undefined;
    placement += 1;
    pendingPosition = false;
    anchoredRow = undefined;
    if (element) top = element.scrollTop;
  }

  function schedulePublication() {
    if (publication !== undefined) return;
    publication = setTimeout(() => {
      publication = undefined;
      const workspaceId = current?.workspace?.workspaceId;
      const chatId = current?.navigation.selectedChat;
      const railId = current?.navigation.turnRail?.id;
      if (!element || !workspaceId || !chatId || !railId) return;
      const anchorTurn = currentAnchor()?.turnId || null;
      const request: TranscriptViewportRequest = {
        workspaceId, chatId, railId, anchorTurn, protectedTurns: protectedTurns(layout, top, height, selection, focused),
      };
      const token = JSON.stringify(request);
      if (lastRequest === token) return;
      lastRequest = token;
      void navigateWorkspace({ transcriptViewport: request }).catch(report);
    }, 75);
  }

  function scrolled() {
    if (!element) return;
    if (!pendingPosition) {
      const position = element.scrollTop;
      if (Math.abs(position - top) > 0.5) anchoredRow = mountedAnchor(element);
      top = position;
    }
    height = element.clientHeight;
    schedulePublication();
  }

  function rowFor(node: Node | null): string | undefined {
    const row = (node instanceof Element ? node : node?.parentElement)?.closest<HTMLElement>('[data-transcript-slot]');
    if (row && element?.contains(row)) return row.dataset.transcriptSlot;
  }

  function selectionChanged() {
    const value = window.getSelection();
    const start = rowFor(value?.anchorNode ?? null);
    const end = rowFor(value?.focusNode ?? null);
    if (value && !value.isCollapsed && start && end) selection = [start, end];
    else selection = undefined;
    schedulePublication();
  }

  function focusChanged() {
    focused = rowFor(document.activeElement);
    schedulePublication();
  }

  function attach(node: HTMLDivElement) {
    const signals = new AbortController();
    const resize = new ResizeObserver(scrolled);
    element = node;
    resize.observe(node);
    document.addEventListener('selectionchange', selectionChanged, { signal: signals.signal });
    document.addEventListener('focusin', focusChanged, { signal: signals.signal });
    scrolled();
    return { destroy() {
      resize.disconnect();
      sizes?.disconnect();
      sizes = undefined;
      signals.abort();
      clearTimeout(publication);
      publication = undefined;
      pendingPosition = false;
      anchoredRow = undefined;
      element = undefined;
    } };
  }

  function measure(node: HTMLElement) {
    sizes ??= new ResizeObserver((changes) => {
      const anchor = currentAnchor();
      for (const change of changes) {
        const row = change.target as HTMLElement;
        const id = row.dataset.transcriptSlot;
        if (!id || !layout.positions.has(id)) continue;
        const size = change.borderBoxSize?.[0]?.blockSize ?? row.getBoundingClientRect().height;
        if (size <= 0 || Math.abs(size - (measured.get(id) ?? 0)) < 0.5) continue;
        measured.set(id, size);
        if (measured.size > MAX_MEASUREMENTS) {
          const oldest = measured.keys().next().value;
          if (oldest !== undefined) measured.delete(oldest);
        }
      }
      const position = anchor ? restoredOffset(layout, anchor) : undefined;
      if (position !== undefined) place(position, anchor);
      schedulePublication();
    });
    sizes.observe(node);
    return { destroy: () => sizes?.unobserve(node) };
  }

  return { get entries() { return entries; }, receive, jump, noteInput, scrolled, attach, measure };
}

function report(error: unknown) {
  if (error !== 'staleSelection' && error !== 'retiredWorkspace') console.error(error);
}
