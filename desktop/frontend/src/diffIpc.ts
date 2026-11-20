import { invoke } from '@tauri-apps/api/core';
import type { ChatRequest, DiffFileView, DiffPatchRequest, DiffPatchView, WorkspaceRequest } from './generated/workspace';

export function readChanges(request: WorkspaceRequest): Promise<DiffFileView[]> {
  return invoke('checkout_changes', { request });
}

export function readPatch(request: DiffPatchRequest): Promise<DiffPatchView> {
  return invoke('checkout_patch', { request });
}

export function countChatChanges(request: ChatRequest): Promise<number> {
  return invoke('count_chat_changes', { request });
}
