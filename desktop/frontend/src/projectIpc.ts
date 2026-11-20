import { invoke } from '@tauri-apps/api/core';
import type {
  NavigationIntent, ProjectPathMatch, ProjectPathRequest, StreamChange, TranscriptItem, TranscriptView, WorkspaceId, WorkspaceRequest, WorkspaceSnapshot, WorkspaceSubscription,
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

export function subscribeWorkspace(): Promise<WorkspaceSubscription> {
  return invoke('subscribe_workspace');
}

export function nextWorkspaceUpdate(request: WorkspaceUpdateRequest): Promise<WorkspaceUpdate> {
  return invoke('next_workspace_update', { request });
}

export function navigateWorkspace(intent: NavigationIntent): Promise<void> {
  return invoke('navigate_workspace', { intent });
}

function applyStream(transcript: TranscriptView, change: StreamChange): TranscriptView {
  if (change === 'completed') return { ...transcript, completed: true };
  const items = transcript.items.slice();
  function updateItem(itemId: string, update: (item: TranscriptItem) => TranscriptItem) {
    const index = items.findIndex((item) => item.itemId === itemId);
    if (index === -1) {
      items.push(update({ itemId, text: '', completed: false, role: 'assistant' }));
    } else {
      items[index] = update(items[index]!);
    }
  }
  if ('itemCompleted' in change) {
    updateItem(change.itemCompleted, (item) => ({ ...item, completed: true }));
  } else if ('finalItem' in change) {
    updateItem(change.finalItem.itemId, () => change.finalItem);
  } else {
    for (const batch of change.text) {
      updateItem(batch.itemId, (item) => item.completed ? item : { ...item, text: item.text + batch.text });
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
  receive(snapshot);
  while (!signal.aborted) {
    const update = await nextWorkspaceUpdate({ subscriptionId, afterRevision: snapshot.revision });
    if (signal.aborted || update === 'retired') return;
    if (update === 'idle') continue;
    const revision = update === 'resync' ? null
      : 'changed' in update ? update.changed.revision
      : 'navigation' in update ? update.navigation.revision
      : update.stream.revision;
    if (update === 'resync' || revision !== snapshot.revision + 1) {
      ({ subscriptionId, snapshot } = await subscribeWorkspace());
      if (signal.aborted) return;
    } else if ('changed' in update) {
      snapshot = update.changed;
    } else if ('navigation' in update) {
      snapshot = { ...snapshot, ...update.navigation };
    } else {
      snapshot = {
        ...snapshot,
        revision: update.stream.revision,
        transcript: applyStream(snapshot.transcript, update.stream.change),
      };
    }
    receive(snapshot);
  }
}
