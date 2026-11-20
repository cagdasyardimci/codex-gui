import { invoke } from '@tauri-apps/api/core';
import type {
  NavigationIntent, ProjectPathMatch, ProjectPathRequest, StreamChange, TranscriptImageDependency, TranscriptItem, TranscriptRowRequest, TranscriptView, WorkspaceId, WorkspaceRequest, WorkspaceSnapshot, WorkspaceSubscription,
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
        turnId: boundary === -1 ? '' : itemId.slice(0, boundary), commands: [], localImages: [],
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
      const { revision, navigation, insertions } = update.history;
      const items = snapshot.transcript.items.slice();
      for (const insertion of insertions) items.splice(insertion.position, 0, ...insertion.rows);
      const transcript = { ...snapshot.transcript, items };
      snapshot = { ...snapshot, revision, navigation, transcript };
      positions = indexRows(transcript);
    } else {
      snapshot = {
        ...snapshot,
        revision: update.stream.revision,
        transcript: applyStream(snapshot.transcript, update.stream.change, positions),
      };
    }
    receive(snapshot);
  }
}
