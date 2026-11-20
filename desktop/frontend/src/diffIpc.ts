import { invoke } from '@tauri-apps/api/core';
import type {
  ChatRequest, DiffActionRequest, DiffChangesRequest, DiffFileView, DiffMarkerRequest, DiffMediaRequest,
  DiffPatchRequest, DiffPatchView, DiffReferences, DraftAttachmentScope, MarkdownNode,
} from './generated/workspace';

export function readChanges(request: DiffChangesRequest): Promise<DiffFileView[]> {
  return invoke('checkout_changes', { request });
}

export function closeChanges(scope: DraftAttachmentScope, viewId: string): Promise<void> {
  return invoke('close_checkout_changes', { scope, viewId });
}

export function diffReferences(scope: DraftAttachmentScope): Promise<DiffReferences> {
  return invoke('checkout_diff_references', { scope });
}

export function readPatch(request: DiffPatchRequest): Promise<DiffPatchView> {
  return invoke('checkout_patch', { request });
}

export function markDiff(request: DiffMarkerRequest): Promise<void> {
  return invoke('mark_checkout_change', { request });
}

export function comparedMedia(request: DiffMediaRequest): Promise<ArrayBuffer> {
  return invoke('checkout_diff_media', { request });
}

export function comparedMarkdown(request: DiffMediaRequest): Promise<MarkdownNode[] | null> {
  return invoke('checkout_diff_markdown', { request });
}

export function performDiffAction(request: DiffActionRequest): Promise<void> {
  return invoke('checkout_diff_action', { request });
}

export function countChatChanges(request: ChatRequest): Promise<number> {
  return invoke('count_chat_changes', { request });
}
