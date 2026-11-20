import { invoke } from '@tauri-apps/api/core';
import type { WorkspaceId, WorkspaceRequest, WorkspaceView } from './generated/workspace';

export function pickWorkspace(): Promise<WorkspaceId | null> {
  return invoke('pick_workspace');
}

export function readWorkspace(request: WorkspaceRequest): Promise<WorkspaceView> {
  return invoke('workspace_snapshot', { request });
}
