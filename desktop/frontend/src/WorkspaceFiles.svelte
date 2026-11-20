<script lang="ts">
  import { onMount, tick } from 'svelte';
  import type {
    DraftAttachmentScope, FileAction, FileActionsView, FileTabRead, FileTabView, FileToolsChange, FileToolsView, MarkdownFileProperty,
    OpenFileSearchHit, ProjectBrowseEntry, ProjectFolder, ProjectPathId,
  } from './generated/workspace';
  import { browseProjectFiles, changeFileTools, exportFileImage, exportFileMarkdownImage, FileEdits, fileMarkdownImage, fileTabActions, openFileMarkdownLink,
    openFileSearchHit, performFileAction, readFilePreview, readFileTab, renderFileMarkdown, sameFileScope, saveFileTab, type FileViewPositions } from './fileTools';
  import ImagePreview from './ImagePreview.svelte';
  import MarkdownView from './MarkdownView.svelte';
  import PdfPreview from './PdfPreview.svelte';
  import SvgPreview from './SvgPreview.svelte';

  let { scope, edits, positions, revision, blocked, opened = $bindable(false) }: {
    scope: DraftAttachmentScope;
    edits: FileEdits;
    positions: FileViewPositions;
    revision: number;
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
  let preview = $state(false);
  let wraps = $state(false);
  let searching = $state(false);
  let findText = $state('');
  let findField = $state<HTMLInputElement>();
  let actions = $state.raw<{ target: FileTabRead; available: FileActionsView }>();
  let properties = $state.raw<MarkdownFileProperty[]>([]);
  let pdfPage = $state(1);
  const active = $derived(view?.tabs.find((item) => item.id === view?.selected));
  const activeId = $derived(active?.id);
  const activeKind = $derived(active?.kind);
  const activeIndex = $derived(view?.tabs.findIndex((item) => item.id === activeId) ?? -1);
  const svg = $derived(activeKind === 'text' && /\.svg$/iu.test(active?.path ?? ''));
  const canPreview = $derived(svg || activeKind === 'text' && /\.(md|markdown)$/iu.test(active?.path ?? ''));

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
    void revision;
    if (!blocked) void refresh(scope);
  });

  $effect(() => {
    const mode = activeId ? positions.modes.get(activeId) : undefined;
    preview = mode?.preview ?? false;
    wraps = mode?.wrap ?? false;
    searching = false;
    findText = '';
    actions = undefined;
    properties = [];
    pdfPage = activeId ? positions.pdfPages.get(activeId) ?? 1 : 1;
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
        if (!retained.has(tab.id)) {
          positions.tabs.delete(tab.id);
          positions.modes.delete(tab.id);
          positions.pdfPages.delete(tab.id);
        }
      }
      adopt(next);
      if (line !== undefined && next.selected) {
        reveal = { tab: next.selected, line };
        const mode = positions.modes.get(next.selected);
        positions.modes.set(next.selected, { preview: false, wrap: mode?.wrap ?? false });
        preview = false;
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

  async function save(tab: FileTabView) {
    if (blocked || busy || composing || tab.saving || activeId !== tab.id) return;
    const target = { scope, tabId: tab.id };
    busy = true;
    try {
      await edits.flush();
      await saveFileTab(target);
    } catch (error) {
      recordFileError(error);
    } finally {
      busy = false;
    }
  }

  function recordFileError(error: unknown) {
    if (error !== 'staleSelection' && error !== 'retiredWorkspace') console.error(error);
  }

  function setMode(tab: string, showPreview: boolean, wrap: boolean) {
    positions.modes.set(tab, { preview: showPreview, wrap });
    preview = showPreview;
    wraps = wrap;
    if (showPreview) searching = false;
  }

  async function switchPreview(tab: string, showPreview: boolean) {
    if (showPreview && field && loaded === tab) rememberText(tab, field);
    if (showPreview) properties = [];
    setMode(tab, showPreview, wraps);
    if (showPreview) return;
    await tick();
    if (activeId === tab && field) restoreTextPosition(tab, field);
  }

  async function showFind() {
    if (!activeId || loaded !== activeId || blocked) return;
    await switchPreview(activeId, false);
    searching = true;
    await tick();
    findField?.focus({ preventScroll: true });
  }

  function matchText(direction: -1 | 1, fromStart = false) {
    if (!field || !findText) return;
    const pattern = [...findText].map((character) => '.+*?^$()[]{}|\\'.includes(character) ? '\\' + character : character).join('');
    const text = field.value;
    const cursor = fromStart ? 0 : direction > 0 ? field.selectionEnd : field.selectionStart;
    let first: RegExpMatchArray | undefined;
    let last: RegExpMatchArray | undefined;
    let found: RegExpMatchArray | undefined;
    for (const match of text.matchAll(new RegExp(pattern, 'giu'))) {
      first ??= match;
      last = match;
      if (direction > 0 && match.index! >= cursor) {
        found = match;
        break;
      }
      if (direction < 0 && match.index! < cursor) found = match;
    }
    const selected = found ?? (direction > 0 ? first : last);
    if (selected?.index !== undefined) scrollRange(field, selected.index, selected.index + selected[0].length);
  }

  function closeFind() {
    searching = false;
    field?.focus({ preventScroll: true });
  }

  function documentKey(event: KeyboardEvent) {
    if (event.isComposing || composing || blocked || !(event.metaKey || event.ctrlKey) || event.altKey || event.shiftKey) return;
    if (event.key.toLowerCase() === 'f') {
      event.preventDefault();
      void showFind();
    } else if (event.key.toLowerCase() === 's' && active) {
      event.preventDefault();
      if (active.dirty) void save(active);
    }
  }

  async function showActions(tab: FileTabView) {
    if (actions) { actions = undefined; return; }
    if (busy || blocked || tab.saving) return;
    const target = { scope, tabId: tab.id };
    try {
      const available = await fileTabActions(target);
      if (activeId === tab.id && sameFileScope(scope, target.scope) && !blocked) actions = { target, available };
    } catch (error) {
      recordFileError(error);
    }
  }

  async function runFileAction(action: FileAction) {
    const shown = actions;
    if (!shown || blocked || busy || activeId !== shown.target.tabId || !sameFileScope(scope, shown.target.scope)) return;
    actions = undefined;
    busy = true;
    try {
      await edits.flush();
      await performFileAction({ target: shown.target, action });
    } catch (error) {
      recordFileError(error);
    } finally {
      busy = false;
    }
  }

  async function loadMarkdown(tabId: string) {
    const target = { scope, tabId };
    const source = text;
    await edits.flush();
    const preview = await renderFileMarkdown(target);
    if (sameFileScope(scope, target.scope) && activeId === tabId && source === text) properties = preview.properties;
    return preview.nodes;
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
        await tick();
        if (retired || !field) return;
        if (reveal?.tab === id) {
          revealLine(field, reveal.line);
          reveal = undefined;
        } else restoreTextPosition(id, field);
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

  function restoreTextPosition(tabId: string, field: HTMLTextAreaElement) {
    const position = positions.tabs.get(tabId);
    if (!position) return;
    field.setSelectionRange(position.first, position.last, position.direction);
    field.scrollTop = position.top;
    field.scrollLeft = position.left;
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
    scrollRange(element, start, end < 0 ? value.length : end);
  }

  function scrollRange(element: HTMLTextAreaElement, start: number, end: number) {
    element.setSelectionRange(start, end);
    const linesAbove = element.value.slice(0, start).split('\n').length - 1;
    const height = Number.parseFloat(getComputedStyle(element).lineHeight);
    if (Number.isFinite(height)) element.scrollTop = Math.max(0, linesAbove * height - element.clientHeight / 3);
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
            <button type="button" aria-label={`Close ${tab.path}`} disabled={blocked || busy || tab.saving}
              onclick={() => void update({ close: tab.id })}>×</button>
          </div>
        {/each}
      </nav>
    {/if}
    {#if active}
      {@const tab = active}
      <div class="file-tab-actions">
        {#if tab.dirty}
          <button type="button" disabled={blocked || busy || tab.saving} onclick={() => void save(tab)}>Save</button>
        {/if}
        {#if canPreview}
          <button type="button" disabled={blocked || busy} onclick={() => void switchPreview(tab.id, !preview)}>
            {preview ? 'View Source' : 'Preview'}
          </button>
        {/if}
        {#if tab.kind === 'text'}
          {#if !preview}
            <button type="button" disabled={blocked} aria-pressed={wraps} onclick={() => setMode(tab.id, false, !wraps)}>Wrap Lines</button>
          {/if}
          <button type="button" disabled={blocked || busy} onclick={() => void showFind()}>Find in File</button>
        {/if}
        <button type="button" aria-expanded={!!actions} disabled={blocked || busy || tab.saving}
          onclick={() => void showActions(tab)}>File Actions</button>
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
      {#if actions}
        <div class="file-tab-actions" role="group" aria-label="File Actions">
          {#if tab.kind === 'text'}<button type="button" onclick={() => void runFileAction('copy')}>Copy Source</button>{/if}
          {#if tab.kind !== 'other'}<button type="button" onclick={() => void runFileAction('export')}>Save As…</button>{/if}
          <button type="button" onclick={() => void runFileAction('reveal')}>Show in Folder</button>
          <button type="button" onclick={() => void runFileAction('openDefault')}>Open in Default App</button>
          {#each actions.available.editors as editor (editor.id)}
            <button type="button" onclick={() => void runFileAction({ openEditor: editor.id })}>Open in {editor.label}</button>
          {/each}
          {#if actions.available.github}<button type="button" onclick={() => void runFileAction('openGitHub')}>Open in GitHub</button>{/if}
        </div>
      {/if}
      {#key tab.id}
        {#if tab.kind === 'text' && loaded === tab.id}
          {#if preview && canPreview}
            {#if svg}
              <div class="file-preview" aria-label="SVG Preview">
                <SvgPreview source={text} alt={tab.path} download={() => exportFileImage({ scope, tabId: tab.id })} />
              </div>
            {:else}
              {@const target = { scope, tabId: tab.id }}
              <div class="file-preview" aria-label="Markdown Preview">
                {#if properties.length}
                  <dl aria-label="File Properties">
                    {#each properties as property (property.key)}
                      <dt>{property.key}</dt><dd>{property.values.join(', ')}</dd>
                    {/each}
                  </dl>
                {/if}
                <MarkdownView source={text} render={() => loadMarkdown(tab.id)} renderKey={JSON.stringify([scope.workspaceId, scope.draftId, tab.id])}
                  loadImage={(resource) => fileMarkdownImage({ target, resource })}
                  downloadImage={(resource) => exportFileMarkdownImage({ target, resource })}
                  openLink={(resource) => openFileMarkdownLink({ target, resource })} />
              </div>
            {/if}
          {:else}
            {#if searching}
              <div class="file-find" role="search" aria-label="Find in File">
                <input type="search" aria-label="Find Text" maxlength="4096" bind:this={findField} value={findText}
                  oninput={(event) => { findText = event.currentTarget.value; matchText(1, true); }}
                  onkeydown={(event) => {
                    if (event.isComposing) return;
                    if (event.key === 'Enter') { event.preventDefault(); matchText(event.shiftKey ? -1 : 1); }
                    else if (event.key === 'Escape') { event.preventDefault(); closeFind(); }
                  }} />
                <button type="button" disabled={!findText} onclick={() => matchText(-1)}>Previous Match</button>
                <button type="button" disabled={!findText} onclick={() => matchText(1)}>Next Match</button>
                <button type="button" onclick={closeFind}>Close Find</button>
              </div>
            {/if}
            <textarea bind:this={field} aria-label={`Edit ${tab.path}`} value={text} readonly={blocked || busy}
              spellcheck="false" wrap={wraps ? 'soft' : 'off'} onkeydown={documentKey}
              oninput={(event) => edit(tab, event.currentTarget, composing || (event instanceof InputEvent && event.isComposing))}
              oncompositionstart={() => { composing = true; }}
              oncompositionend={(event) => { composing = false; edit(tab, event.currentTarget, false); }}
              onselect={(event) => rememberText(tab.id, event.currentTarget)}
              onscroll={(event) => rememberText(tab.id, event.currentTarget)}></textarea>
          {/if}
        {:else if tab.kind === 'raster'}
          <div class="file-image" bind:this={imageScroller} onscroll={(event) => rememberImage(tab.id, event.currentTarget)}>
            <ImagePreview load={() => readFilePreview({ target: { scope, tabId: tab.id }, kind: 'raster' })} alt={tab.path}
              download={() => exportFileImage({ scope, tabId: tab.id })} />
          </div>
        {:else if tab.kind === 'pdf'}
          <PdfPreview name={tab.path} load={() => readFilePreview({ target: { scope, tabId: tab.id }, kind: 'pdf' })}
            bind:pageNumber={() => pdfPage, (page) => {
              if (activeId !== tab.id) return;
              pdfPage = page;
              positions.pdfPages.set(tab.id, page);
            }} />
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
  .file-tab-actions, .file-find { flex-wrap: wrap; }
  .file-find { display: flex; gap: 0.25rem; }
  .file-find input { flex: 1 1 7rem; min-inline-size: 0; }
  .file-browser { display: flex; flex-direction: column; align-items: flex-start; max-block-size: 11rem; overflow: auto; }
  .folder { font-weight: 600; }
  .file-tabs { overflow: auto; flex-shrink: 0; }
  .file-tab { flex-shrink: 0; border-block-end: 2px solid transparent; }
  .file-tab.preview { font-style: italic; }
  .file-tab.dirty { border-block-end-color: Highlight; }
  .file-tab button[aria-current="true"] { background: color-mix(in srgb, Highlight 20%, Canvas); }
  textarea { flex: 1; font: var(--workspace-code-size, 12px) / 1.4 var(--workspace-code-font, ui-monospace), monospace; min-block-size: 5rem; resize: none; }
  .file-image, .file-preview { flex: 1; overflow: auto; }
  .file-image :global(img) { display: block; max-inline-size: 100%; }
  dl { display: grid; grid-template-columns: auto 1fr; gap: 0.25rem 0.5rem; margin: 0 0 0.5rem; }
  dt { font-weight: 600; }
  dd { margin: 0; overflow-wrap: anywhere; }
</style>
