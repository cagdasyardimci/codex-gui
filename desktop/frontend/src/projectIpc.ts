import { invoke } from '@tauri-apps/api/core';
import type {
  WorkspaceId, WorkspaceRequest, WorkspaceSnapshot, WorkspaceSubscription,
  WorkspaceUpdate, WorkspaceUpdateRequest, WorkspaceView,
} from './generated/workspace';

export function pickWorkspace(): Promise<WorkspaceId | null> {
  return invoke('pick_workspace');
}

export function readWorkspace(request: WorkspaceRequest): Promise<WorkspaceView> {
  return invoke('workspace_snapshot', { request });
}

export function subscribeWorkspace(): Promise<WorkspaceSubscription> {
  return invoke('subscribe_workspace');
}

export function nextWorkspaceUpdate(request: WorkspaceUpdateRequest): Promise<WorkspaceUpdate> {
  return invoke('next_workspace_update', { request });
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
    if (update === 'resync' || update.changed.revision !== snapshot.revision + 1) {
      ({ subscriptionId, snapshot } = await subscribeWorkspace());
      if (signal.aborted) return;
    } else {
      snapshot = update.changed;
    }
    receive(snapshot);
  }
}
