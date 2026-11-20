<script lang="ts">
  import { onMount, tick } from 'svelte';
  import type { DraftAttachmentScope, FileSearchPage, FileSearchResult, OpenFileSearchHit } from './generated/workspace';
  import { cancelFileSearch, readFileSearch, startFileSearch } from './fileTools';

  let { scope, blocked, choose, close }: {
    scope: DraftAttachmentScope;
    blocked: boolean;
    choose: (hit: OpenFileSearchHit) => void;
    close: () => void;
  } = $props();

  let dialog: HTMLDialogElement;
  let field: HTMLInputElement;
  let query = $state('');
  let mask = $state('');
  let session = $state.raw<{ id: string; query: string; mask: string }>();
  let page = $state.raw<FileSearchPage>({ matches: [], nextCursor: null });
  let row = $state(0);
  let busy = $state(false);
  let composing = $state(false);
  const active = $derived(session?.query === query.trim() && session.mask === mask.trim() ? session : undefined);
  const selected = $derived(Math.min(row, Math.max(0, page.matches.length - 1)));

  onMount(() => {
    dialog.showModal();
    field.focus({ preventScroll: true });
  });

  function report(error: unknown) {
    if (error !== 'staleSelection' && error !== 'retiredWorkspace') console.error(error);
  }

  $effect(() => {
    const expectedScope = scope;
    const term = query.trim();
    const filter = mask.trim();
    const composingInput = composing;
    session = undefined;
    page = { matches: [], nextCursor: null };
    row = 0;
    busy = false;
    if (!term || composingInput) return;
    let retired = false;
    let opened: string | undefined;
    async function start() {
      try {
        opened = await startFileSearch({ scope: expectedScope, query: term, mask: filter });
        if (retired) {
          await cancelFileSearch(opened);
          return;
        }
        session = { id: opened, query: term, mask: filter };
        const first = await readFileSearch({ session: opened, cursor: null });
        if (!retired) page = first;
      } catch (error) {
        if (!retired) report(error);
      }
    }
    const timer = window.setTimeout(() => void start(), 100);
    return () => {
      retired = true;
      window.clearTimeout(timer);
      if (opened) void cancelFileSearch(opened).catch(report);
    };
  });

  async function more() {
    const current = active;
    const cursor = page.nextCursor;
    if (!current || !cursor || busy || blocked) return;
    busy = true;
    try {
      const next = await readFileSearch({ session: current.id, cursor });
      if (active === current) {
        page = { matches: [...page.matches, ...next.matches], nextCursor: next.nextCursor };
        field.focus({ preventScroll: true });
      }
    } catch (error) {
      report(error);
    } finally {
      if (active === current) busy = false;
    }
  }

  function open(item: FileSearchResult) {
    if (active && !composing && !busy && !blocked) choose({ session: active.id, id: item.id });
  }

  function keyboard(event: KeyboardEvent) {
    if (composing || event.isComposing || event.altKey || event.ctrlKey || event.metaKey) return;
    if (event.key === 'Escape') {
      event.preventDefault();
      close();
      return;
    }
    if (!active || blocked || busy || !page.matches.length || event.target !== field) return;
    if (event.key === 'Enter') {
      event.preventDefault();
      open(page.matches[selected]!);
    } else if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
      event.preventDefault();
      const count = page.matches.length;
      row = (selected + count + (event.key === 'ArrowDown' ? 1 : -1)) % count;
      void tick().then(() => document.getElementById(`file-search-match-${row}`)?.scrollIntoView({ block: 'nearest' }));
    }
  }
</script>

<dialog bind:this={dialog} aria-label="Search Files" onkeydown={keyboard}
  oncancel={(event) => { event.preventDefault(); if (!composing) close(); }}>
  <h2>Search Files</h2>
  <div class="inputs">
    <label>Find in Project Files
      <!-- svelte-ignore a11y_autofocus (The opened search accepts typing in this field.) -->
      <input bind:this={field} bind:value={query} type="search" role="combobox" autofocus maxlength="1024"
        aria-controls="file-search-results" aria-expanded={page.matches.length > 0} aria-autocomplete="list"
        aria-activedescendant={page.matches.length ? `file-search-match-${selected}` : undefined}
        oncompositionstart={() => { composing = true; }} oncompositionend={() => { composing = false; }} />
    </label>
    <label>File Types
      <input bind:value={mask} type="search" maxlength="256"
        oncompositionstart={() => { composing = true; }} oncompositionend={() => { composing = false; }} />
    </label>
  </div>
  <div id="file-search-results" role="listbox" aria-label="File Matches">
    {#each page.matches as match, index (match.id)}
      <button id={`file-search-match-${index}`} type="button" role="option" tabindex="-1" aria-selected={index === selected}
        disabled={busy || blocked} onclick={() => open(match)}>
        <strong>{match.path}:{match.line}</strong><span>{match.excerpt}</span>
      </button>
    {/each}
  </div>
  <footer>
    {#if page.nextCursor}<button type="button" disabled={busy || blocked} onclick={() => void more()}>More Matches</button>{/if}
    <button type="button" onclick={close}>Close</button>
  </footer>
</dialog>

<style>
  dialog { color: CanvasText; background: Canvas; border: 1px solid var(--workspace-divider); border-radius: 0.65rem;
    inline-size: min(46rem, 87vw); max-block-size: 75vh; padding: 1rem; }
  h2 { margin: 0 0 0.65rem; font-size: 1rem; }
  .inputs { display: grid; grid-template-columns: 2fr 1fr; gap: 0.5rem; }
  label { display: grid; gap: 0.2rem; }
  input { box-sizing: border-box; min-inline-size: 0; inline-size: 100%; font: inherit; padding: 0.45rem; }
  [role="listbox"] { display: grid; gap: 0.2rem; max-block-size: 49vh; overflow: auto; margin-block: 0.6rem; }
  [role="option"] { display: grid; gap: 0.15rem; text-align: start; overflow-wrap: anywhere; }
  [role="option"][aria-selected="true"] { background: var(--workspace-hover); }
  footer { display: flex; justify-content: flex-end; gap: 0.4rem; }
</style>
