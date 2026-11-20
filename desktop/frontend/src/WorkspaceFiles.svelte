<script lang="ts">
  import { onMount, tick } from 'svelte';
  import type {
    DraftAttachmentScope, FileTabView, FileToolsChange, FileToolsView, OpenFileSearchHit, ProjectBrowseEntry, ProjectFolder, ProjectPathId,
  } from './generated/workspace';
  import { browseProjectFiles, changeFileTools, FileEdits, openFileSearchHit, readFileTab, sameFileScope, type FileViewPositions } from './fileTools';
  import ImagePreview from './ImagePreview.svelte';

  let { scope, edits, positions, blocked, opened = $bindable(false) }: {
    scope: DraftAttachmentScope;
    edits: FileEdits;
    positions: FileViewPositions;
    blocked: boolean;
    opened?: boolean;
  } = $props();

  let view = $state.raw<FileToolsView>();
  let folders = $state.raw<ProjectFolder[]>([]);
  let entries = $state.raw<ProjectBrowseEntry[]>([]);
  let nextOffset = $state<number | null>(null);
  let catalogRevision: string | undefined;
  let busy = $state(false);
  let requestNumber = 0;
  let browseNumber = 0;
  let browsing = $state(false);
  let field = $state<HTMLTextAreaElement>();
  let imageScroller = $state<HTMLDivElement>();
  let loaded = $state<string>();
  let text = $state('');
  let composing = $state(false);
  let reload = $state(0);
  let reveal: { tab: string; line: number } | undefined;
  const active = $derived(view?.tabs.find((item) => item.id === view?.selected));
  const activeId = $derived(active?.id);
  const activeKind = $derived(active?.kind);
  const activeIndex = $derived(view?.tabs.findIndex((item) => item.id === activeId) ?? -1);

  function adopt(next: FileToolsView) {
    view = next;
    opened = next.open;
  }

  async function refresh(scope: DraftAttachmentScope) {
    const expected = ++requestNumber;
    try {
      const next = await changeFileTools({ scope, change: 'inspect' });
      if (expected !== requestNumber) return;
      folders = positions.folders.get(next.sessionId) ?? [];
      adopt(next);
    } catch (error) {
      if (expected === requestNumber) console.error(error);
    }
  }

  $effect(() => {
    if (!blocked) void refresh(scope);
  });

  async function update(change: FileToolsChange | OpenFileSearchHit) {
    if (blocked || busy || composing) return false;
    const captured = scope;
    const expected = ++requestNumber;
    busy = true;
    try {
      await edits.flush();
      let next: FileToolsView;
      let line: number | undefined;
      if (typeof change === 'object' && 'session' in change) {
        ({ view: next, line } = await openFileSearchHit(change));
      } else {
        next = await changeFileTools({ scope: captured, change });
      }
      if (expected !== requestNumber || !sameFileScope(scope, captured)) return false;
      const retained = new Set(next.tabs.map((tab) => tab.id));
      for (const tab of view?.tabs ?? []) {
        if (!retained.has(tab.id)) positions.tabs.delete(tab.id);
      }
      adopt(next);
      if (line !== undefined && next.selected) {
        reveal = { tab: next.selected, line };
        reload += 1;
      }
      return true;
    } catch (error) {
      if (expected === requestNumber && error !== 'staleSelection' && error !== 'retiredWorkspace') console.error(error);
      return false;
    } finally {
      busy = false;
    }
  }

  export async function toggle() {
    const captured = scope;
    if (!view) await refresh(captured);
    if (sameFileScope(scope, captured)) await update({ show: !view?.open });
  }

  export async function openPath(path: ProjectPathId, keep: boolean) {
    return update({ open: { path, keep } });
  }

  export async function openMatch(request: OpenFileSearchHit) {
    return update(request);
  }

  function moveSelected(direction: -1 | 1) {
    if (activeIndex < 0 || !activeId || !view) return;
    const before = view.tabs[activeIndex + (direction < 0 ? -1 : 2)]?.id ?? null;
    void update({ move: { tabId: activeId, before } });
  }

  function browseTo(next: ProjectFolder[]) {
    folders = next;
    if (view) positions.folders.set(view.sessionId, next);
  }

  async function loadFolder(captured: DraftAttachmentScope, folder: ProjectFolder | undefined, offset = 0) {
    const expected = ++browseNumber;
    browsing = true;
    if (offset === 0) {
      entries = [];
      nextOffset = null;
    }
    try {
      const page = await browseProjectFiles({ workspaceId: captured.workspaceId, folder: folder?.id ?? null, offset });
      if (expected !== browseNumber || !sameFileScope(scope, captured)) return;
      if (offset > 0 && page.revision !== catalogRevision) {
        await loadFolder(captured, folder);
        return;
      }
      catalogRevision = page.revision;
      entries = offset === 0 ? page.entries : [...entries, ...page.entries];
      nextOffset = page.nextOffset;
    } catch (error) {
      if (expected === browseNumber && error === 'staleSelection' && folder) browseTo([]);
    } finally {
      if (expected === browseNumber) browsing = false;
    }
  }

  $effect(() => {
    const captured = scope;
    const folder = folders.at(-1);
    if (opened) void loadFolder(captured, folder);
    return () => { browseNumber += 1; };
  });

  $effect(() => {
    const captured = scope;
    const id = activeId;
    const kind = activeKind;
    void reload;
    loaded = undefined;
    composing = false;
    if (!opened || !id || kind !== 'text') return;
    let retired = false;
    void (async () => {
      try {
        await edits.flush();
        const bytes = await readFileTab({ scope: captured, tabId: id });
        if (retired) return;
        text = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(bytes);
        loaded = id;
        const position = positions.tabs.get(id);
        await tick();
        if (retired || !field) return;
        if (reveal?.tab === id) {
          revealLine(field, reveal.line);
          reveal = undefined;
        } else if (position) {
          field.setSelectionRange(position.first, position.last, position.direction);
          field.scrollTop = position.top;
          field.scrollLeft = position.left;
        }
      } catch (error) {
        if (!retired) console.error(error);
      }
    })();
    return () => { retired = true; };
  });

  $effect(() => {
    const element = imageScroller;
    const id = activeId;
    if (!element || !id) return;
    const restore = () => {
      const position = positions.tabs.get(id);
      if (position) {
        element.scrollTop = position.top;
        element.scrollLeft = position.left;
      }
    };
    element.addEventListener('load', restore, true);
    restore();
    return () => element.removeEventListener('load', restore, true);
  });

  function rememberText(tabId: string, element: HTMLTextAreaElement) {
    positions.tabs.set(tabId, {
      top: element.scrollTop, left: element.scrollLeft, first: element.selectionStart, last: element.selectionEnd,
      direction: element.selectionDirection ?? 'none',
    });
  }

  function revealLine(element: HTMLTextAreaElement, line: number) {
    const value = element.value;
    let start = 0;
    for (let number = 1; number < line; number++) {
      const end = value.indexOf('\n', start);
      if (end < 0) return;
      start = end + 1;
    }
    const end = value.indexOf('\n', start);
    element.focus({ preventScroll: true });
    element.setSelectionRange(start, end < 0 ? value.length : end);
    const height = Number.parseFloat(getComputedStyle(element).lineHeight);
    if (Number.isFinite(height)) element.scrollTop = Math.max(0, (line - 1) * height - element.clientHeight / 3);
    element.scrollLeft = 0;
  }

  function rememberImage(tabId: string, element: HTMLDivElement) {
    positions.tabs.set(tabId, { top: element.scrollTop, left: element.scrollLeft, first: 0, last: 0, direction: 'none' });
  }

  function edit(tab: FileTabView, element: HTMLTextAreaElement, inComposition: boolean) {
    if (!view || activeId !== tab.id || loaded !== tab.id) return;
    const next = element.value;
    if (!inComposition && new TextEncoder().encode(next).byteLength > 8 * 1024 * 1024) {
      element.value = text;
      return;
    }
    text = next;
    rememberText(tab.id, element);
    if (inComposition) return;
    edits.queue({ sessionId: view.sessionId, tabId: tab.id, text: next });
    if (!tab.dirty || tab.preview) {
      view = { ...view, tabs: view.tabs.map((current) => current.id === tab.id
        ? { ...current, dirty: true, preview: false } : current) };
    }
  }

  let discardDialog = $state<HTMLDialogElement>();
  $effect(() => {
    if (view?.discard && discardDialog && !discardDialog.open) discardDialog.showModal();
  });

  function cancelDiscard() {
    if (view) view = { ...view, discard: null };
  }

  onMount(() => () => { requestNumber += 1; });
</script>

{#if opened && view}
  <aside class:wide={view.wide} class="project-files" aria-label="Project Files">
    <header>
      <button type="button" disabled={busy || blocked} onclick={() => void update({ widen: !view?.wide })}>
        {view.wide ? 'Narrow File Pane' : 'Expand File Pane'}
      </button>
      <button type="button" disabled={busy || blocked} onclick={() => void update({ show: false })}>Hide Files</button>
    </header>
    <nav class="file-browser" aria-label="Project File Browser">
      {#if folders.length}
        <div class="folder-path">
          <button type="button" disabled={blocked} onclick={() => browseTo(folders.slice(0, -1))}>Parent Folder</button>
          <span>{folders.map((folder) => folder.name).join('/')}</span>
        </div>
      {/if}
      {#each entries as entry ('folder' in entry ? JSON.stringify(entry.folder.id) : JSON.stringify(entry.file.id))}
        {#if 'folder' in entry}
          {@const folder = entry.folder}
          <button class="folder" type="button" disabled={blocked} onclick={() => browseTo([...folders, folder])}>{folder.name}</button>
        {:else}
          {@const file = entry.file}
          <button type="button" disabled={blocked || busy} onclick={() => void openPath(file.id, false)}>{file.displayPath.split('/').at(-1)}</button>
        {/if}
      {/each}
      {#if nextOffset !== null}
        <button type="button" disabled={blocked || browsing} onclick={() => void loadFolder(scope, folders.at(-1), nextOffset ?? 0)}>More Files</button>
      {/if}
    </nav>
    {#if view.tabs.length}
      <nav class="file-tabs" aria-label="Open Files">
        {#each view.tabs as tab (tab.id)}
          <div class="file-tab" class:preview={tab.preview} class:dirty={tab.dirty} data-file-tab={tab.id}>
            <button type="button" aria-current={activeId === tab.id ? 'true' : undefined} title={tab.path}
              disabled={blocked || busy} onclick={() => void update({ select: tab.id })}>{tab.path.split(/[/\\]/).at(-1)}</button>
            <button type="button" aria-label={`Close ${tab.path}`} disabled={blocked || busy}
              onclick={() => void update({ close: tab.id })}>×</button>
          </div>
        {/each}
      </nav>
    {/if}
    {#if active}
      {@const tab = active}
      <div class="file-tab-actions">
        {#if tab.preview}
          <button type="button" disabled={blocked || busy} onclick={() => void update({ keep: tab.id })}>Keep Tab</button>
        {/if}
        {#if activeIndex > 0}
          <button type="button" disabled={blocked || busy} onclick={() => moveSelected(-1)}>Move Tab Left</button>
        {/if}
        {#if activeIndex < view.tabs.length - 1}
          <button type="button" disabled={blocked || busy} onclick={() => moveSelected(1)}>Move Tab Right</button>
        {/if}
      </div>
      {#key tab.id}
        {#if tab.kind === 'text' && loaded === tab.id}
          <textarea bind:this={field} aria-label={`Edit ${tab.path}`} value={text} readonly={blocked || busy}
            spellcheck="false" wrap="off"
            oninput={(event) => edit(tab, event.currentTarget, composing || (event instanceof InputEvent && event.isComposing))}
            oncompositionstart={() => { composing = true; }}
            oncompositionend={(event) => { composing = false; edit(tab, event.currentTarget, false); }}
            onselect={(event) => rememberText(tab.id, event.currentTarget)}
            onscroll={(event) => rememberText(tab.id, event.currentTarget)}></textarea>
        {:else if tab.kind === 'raster'}
          <div class="file-image" bind:this={imageScroller} onscroll={(event) => rememberImage(tab.id, event.currentTarget)}>
            <ImagePreview load={() => readFileTab({ scope, tabId: tab.id }, true)} alt={tab.path} />
          </div>
        {/if}
      {/key}
    {/if}
  </aside>
{/if}

{#if view?.discard}
  {@const discard = view.discard}
  {@const file = view.tabs.find((tab) => tab.id === discard.tabId)}
  <dialog bind:this={discardDialog} aria-label="Close File" oncancel={(event) => { event.preventDefault(); cancelDiscard(); }}>
    {#if file}<h2>{file.path}</h2>{/if}
    <button type="button" disabled={busy} onclick={cancelDiscard}>Cancel</button>
    <button type="button" disabled={busy} onclick={() => void update({ discard })}>Discard Changes</button>
  </dialog>
{/if}

<style>
  .project-files {
    flex: 0 0 min(34vw, 27rem); display: flex; flex-direction: column; gap: 0.3rem; padding: 0.65rem;
    min-inline-size: 12rem; min-block-size: 0; overflow: hidden;
    background: var(--workspace-panel); border-inline-start: 1px solid var(--workspace-divider);
  }
  .project-files.wide { flex-basis: min(49vw, 46rem); }
  header, .file-tabs, .file-tab, .folder-path, .file-tab-actions { display: flex; align-items: center; gap: 0.25rem; }
  .file-browser { display: flex; flex-direction: column; align-items: flex-start; max-block-size: 11rem; overflow: auto; }
  .folder { font-weight: 600; }
  .file-tabs { overflow: auto; flex-shrink: 0; }
  .file-tab { flex-shrink: 0; border-block-end: 2px solid transparent; }
  .file-tab.preview { font-style: italic; }
  .file-tab.dirty { border-block-end-color: Highlight; }
  .file-tab button[aria-current="true"] { background: color-mix(in srgb, Highlight 20%, Canvas); }
  textarea { flex: 1; font: 0.88rem/1.4 ui-monospace, monospace; min-block-size: 5rem; resize: none; }
  .file-image { flex: 1; overflow: auto; }
  .file-image :global(img) { display: block; max-inline-size: 100%; }
</style>
