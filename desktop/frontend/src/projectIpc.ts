import { invoke } from '@tauri-apps/api/core';
import type {
  DraftAttachmentRequest, DraftAttachmentScope, MarkdownNode, MarkdownTargetRequest, NavigationIntent, ProjectPathMatch, ProjectPathRequest, ReuseAttachmentRequest, StreamChange, TranscriptImageDependency, TranscriptItem, TranscriptMediaRequest, TranscriptRowRequest, TranscriptView, WorkspaceId, WorkspaceRequest, WorkspaceSnapshot, WorkspaceSubscription,
  WorkspaceUpdate, WorkspaceUpdateRequest, WorkspaceView,
} from './generated/workspace';

export function pickWorkspace(): Promise<WorkspaceId | null> {
  return invoke('pick_workspace');
}

export function readWorkspace(request: WorkspaceRequest): Promise<WorkspaceView> {
  return invoke('workspace_snapshot', { request });
}

export function searchProjectPaths(request: ProjectPathRequest): Promise<ProjectPathMatch[]> {
  return invoke('search_project_paths', { request });
}

export function copyTranscriptRow(request: TranscriptRowRequest): Promise<void> {
  return invoke('copy_transcript_row', { request });
}

export function checkTranscriptImages(request: TranscriptRowRequest): Promise<TranscriptImageDependency[]> {
  return invoke('check_transcript_images', { request });
}

export function renderTranscriptMarkdown(request: TranscriptRowRequest): Promise<MarkdownNode[] | null> {
  return invoke('render_transcript_markdown', { request });
}

export function loadTranscriptImage(request: MarkdownTargetRequest): Promise<ArrayBuffer> {
  return invoke('load_transcript_image', { request });
}

export function loadTranscriptAttachment(request: TranscriptMediaRequest): Promise<ArrayBuffer> {
  return invoke('load_transcript_attachment', { request });
}

export function pickComposerAttachments(scope: DraftAttachmentScope): Promise<void> {
  return invoke('pick_composer_attachments', { scope });
}

export function pasteComposerImage(scope: DraftAttachmentScope, bytes: ArrayBuffer): Promise<void> {
  return invoke('paste_composer_image', bytes, {
    headers: { 'x-codex-attachment-scope': encodeURIComponent(JSON.stringify(scope)) },
  });
}

export function removeComposerAttachment(request: DraftAttachmentRequest): Promise<void> {
  return invoke('remove_composer_attachment', { request });
}

export function loadComposerImage(request: DraftAttachmentRequest): Promise<ArrayBuffer> {
  return invoke('load_composer_image', { request });
}

export function reuseComposerAttachment(request: ReuseAttachmentRequest): Promise<void> {
  return invoke('reuse_composer_attachment', { request });
}

export function openTranscriptLink(request: MarkdownTargetRequest): Promise<void> {
  return invoke('open_transcript_link', { request });
}

export function subscribeWorkspace(): Promise<WorkspaceSubscription> {
  return invoke('subscribe_workspace');
}

export function nextWorkspaceUpdate(request: WorkspaceUpdateRequest): Promise<WorkspaceUpdate> {
  return invoke('next_workspace_update', { request });
}

export function navigateWorkspace(intent: NavigationIntent): Promise<void> {
  return invoke('navigate_workspace', { intent });
}

function indexRows(transcript: TranscriptView): Map<string, number> {
  return new Map(transcript.items.map((item, index) => [item.itemId, index]));
}

function reuseRows(previous: WorkspaceSnapshot, incoming: WorkspaceSnapshot, positions: Map<string, number>): WorkspaceSnapshot {
  if (incoming.workspace?.workspaceId !== previous.workspace?.workspaceId ||
      incoming.navigation.selectedChat !== previous.navigation.selectedChat ||
      incoming.transcript.generation !== previous.transcript.generation) return incoming;
  const items = incoming.transcript.items.map((row) => {
    const at = positions.get(row.itemId);
    const prior = at === undefined ? undefined : previous.transcript.items[at];
    return prior?.revision === row.revision ? prior : row;
  });
  return { ...incoming, transcript: { ...incoming.transcript, items } };
}

function applyStream(transcript: TranscriptView, change: StreamChange, positions: Map<string, number>): TranscriptView {
  if (change === 'completed') return { ...transcript, completed: true };
  const items = transcript.items.slice();
  function updateItem(itemId: string, update: (item: TranscriptItem) => TranscriptItem) {
    const index = positions.get(itemId);
    if (index === undefined) {
      positions.set(itemId, items.length);
      const boundary = itemId.indexOf('/');
      items.push(update({
        itemId, text: '', completed: false, role: 'assistant', revision: 0,
        turnId: boundary === -1 ? '' : itemId.slice(0, boundary), commands: [], localImages: [], attachments: [],
      }));
    } else {
      items[index] = update(items[index]!);
    }
  }
  if ('itemCompleted' in change) {
    updateItem(change.itemCompleted, (item) => item.completed ? item :
      { ...item, completed: true, revision: item.revision + 1 });
  } else if ('finalItem' in change) {
    updateItem(change.finalItem.itemId, () => change.finalItem);
  } else {
    for (const batch of change.text) {
      if (batch.text) updateItem(batch.itemId, (item) => item.completed ? item :
        { ...item, text: item.text + batch.text, revision: item.revision + 1 });
    }
  }
  return { ...transcript, items };
}

function evictTurns(transcript: TranscriptView, turns: string[]): TranscriptView {
  if (!turns.length) return transcript;
  const evicted = new Set(turns);
  return { ...transcript, items: transcript.items.filter((item) => !evicted.has(item.turnId)) };
}

export async function observeWorkspace(
  receive: (snapshot: WorkspaceSnapshot) => void,
  signal: AbortSignal,
) {
  let { subscriptionId, snapshot } = await subscribeWorkspace();
  if (signal.aborted) return;
  let positions = indexRows(snapshot.transcript);
  receive(snapshot);
  while (!signal.aborted) {
    const update = await nextWorkspaceUpdate({ subscriptionId, afterRevision: snapshot.revision });
    if (signal.aborted || update === 'retired') return;
    if (update === 'idle') continue;
    const revision = update === 'resync' ? null
      : 'changed' in update ? update.changed.revision
      : 'navigation' in update ? update.navigation.revision
      : 'history' in update ? update.history.revision
      : update.stream.revision;
    if (update === 'resync' || revision !== snapshot.revision + 1) {
      const latest = await subscribeWorkspace();
      if (signal.aborted) return;
      subscriptionId = latest.subscriptionId;
      snapshot = reuseRows(snapshot, latest.snapshot, positions);
      positions = indexRows(snapshot.transcript);
    } else if ('changed' in update) {
      snapshot = reuseRows(snapshot, update.changed, positions);
      positions = indexRows(snapshot.transcript);
    } else if ('navigation' in update) {
      snapshot = { ...snapshot, ...update.navigation };
    } else if ('history' in update) {
      const { revision, navigation, insertions, evictedTurns } = update.history;
      const items = snapshot.transcript.items.slice();
      for (const insertion of insertions) items.splice(insertion.position, 0, ...insertion.rows);
      const transcript = evictTurns({ ...snapshot.transcript, items }, evictedTurns);
      snapshot = { ...snapshot, revision, navigation, transcript };
      positions = indexRows(transcript);
    } else {
      const { revision, change, evictedTurns } = update.stream;
      const transcript = evictTurns(applyStream(snapshot.transcript, change, positions), evictedTurns);
      snapshot = {
        ...snapshot,
        revision,
        transcript,
      };
      if (evictedTurns.length) positions = indexRows(transcript);
    }
    receive(snapshot);
  }
}
