import { invoke } from '@tauri-apps/api/core';
import type {
  DraftAttachmentScope, FileActionRequest, FileActionsView, FileSaveView, FileSearchPage, FileTabEdit,
  FileTabRead, FileToolsRequest, FileToolsView, MarkdownNode, OpenFileSearchHit, OpenedFileSearchHit,
  ProjectBrowsePage, ProjectBrowseRequest, ProjectFolder, ReadFileSearch, StartFileSearch,
} from './generated/workspace';

export function changeFileTools(request: FileToolsRequest): Promise<FileToolsView> {
  return invoke('change_file_tools', { request });
}

export function browseProjectFiles(request: ProjectBrowseRequest): Promise<ProjectBrowsePage> {
  return invoke('browse_project_files', { request });
}

export function readFileTab(request: FileTabRead, raster = false): Promise<ArrayBuffer> {
  return invoke('read_file_tab', { request, raster });
}

export function saveFileTab(request: FileTabRead): Promise<FileSaveView> {
  return invoke('save_file_tab', { request });
}

export function fileTabActions(target: FileTabRead): Promise<FileActionsView> {
  return invoke('file_tab_actions', { target });
}

export function performFileAction(request: FileActionRequest): Promise<void> {
  return invoke('perform_file_action', { request });
}

export function renderFileMarkdown(target: FileTabRead): Promise<MarkdownNode[] | null> {
  return invoke('render_file_markdown', { target });
}

export function startFileSearch(request: StartFileSearch): Promise<string> {
  return invoke('start_file_search', { request });
}

export function readFileSearch(request: ReadFileSearch): Promise<FileSearchPage> {
  return invoke('read_file_search', { request });
}

export function cancelFileSearch(session: string): Promise<void> {
  return invoke('cancel_file_search', { session });
}

export function openFileSearchHit(request: OpenFileSearchHit): Promise<OpenedFileSearchHit> {
  return invoke('open_file_search_hit', { request });
}

export function sameFileScope(first: DraftAttachmentScope, second: DraftAttachmentScope) {
  return first.workspaceId === second.workspaceId && first.draftId === second.draftId && first.chatId === second.chatId;
}

export type FileViewPositions = {
  tabs: Map<string, { top: number; left: number; first: number; last: number; direction: 'forward' | 'backward' | 'none' }>;
  folders: Map<string, ProjectFolder[]>;
  modes: Map<string, { preview: boolean; wrap: boolean }>;
};

export class FileEdits {
  private pending = new Map<string, FileTabEdit>();
  private writing?: Promise<void>;
  private timer?: number;

  queue(edit: FileTabEdit) {
    this.pending.set(edit.tabId, edit);
    window.clearTimeout(this.timer);
    this.timer = window.setTimeout(() => void this.flush()?.catch(console.error), 80);
  }

  flush() {
    window.clearTimeout(this.timer);
    if (!this.writing && this.pending.size) {
      this.writing = this.write().finally(() => { this.writing = undefined; });
    }
    return this.writing;
  }

  private async write() {
    while (this.pending.size) {
      const edit = this.pending.values().next().value!;
      this.pending.delete(edit.tabId);
      try {
        await invoke('edit_file_tab', { request: edit });
      } catch (error) {
        if (!this.pending.has(edit.tabId)) this.pending.set(edit.tabId, edit);
        throw error;
      }
    }
  }
}
