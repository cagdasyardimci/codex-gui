<script lang="ts">
  import { onMount, tick } from 'svelte';
  import type { MessageSearchPage } from './generated/workspace';
  import type { MessageSearchIndex, SearchHit } from './messageSearchIndex';

  let { index, revision, blocked, load, choose, close }: {
    index: MessageSearchIndex;
    revision: number;
    blocked: boolean;
    load: (chatId: string, restart: boolean) => Promise<MessageSearchPage>;
    choose: (hit: SearchHit) => void;
    close: () => void;
  } = $props();

  let dialog: HTMLDialogElement;
  let field: HTMLInputElement;
  let query = $state('');
  let hits = $state.raw<SearchHit[]>([]);
  let row = $state(0);
  let loading = $state(false);
  let fetched = $state.raw(new Map<string, boolean>());
  let composing = false;
  const selected = $derived(Math.min(row, Math.max(0, hits.length - 1)));
  const nextPage = $derived.by(() => {
    void revision;
    const chats = index.targets();
    return chats.find((chat) => !chat.covered && !fetched.has(chat.chatId)) ??
      chats.find((chat) => fetched.get(chat.chatId) ?? (chat.earlier || chat.partial));
  });

  onMount(() => {
    dialog.showModal();
    field.focus();
  });

  $effect(() => {
    const term = query;
    const version = revision;
    const cancel = new AbortController();
    hits = [];
    row = 0;
    void index.find(term, cancel.signal).then((results) => {
      if (!cancel.signal.aborted && index.revision === version) hits = results;
    });
    return () => cancel.abort();
  });

  async function loadNext() {
    const next = nextPage;
    if (!next || loading || blocked) return;
    loading = true;
    try {
      const page = await load(next.chatId, !fetched.has(next.chatId));
      fetched = new Map(fetched).set(next.chatId, page.more);
      field?.focus();
    } catch (error) {
      if (error !== 'staleSelection' && error !== 'retiredWorkspace') console.error(error);
    } finally {
      loading = false;
    }
  }

  function keyboard(event: KeyboardEvent) {
    if (event.isComposing || composing || event.altKey || event.ctrlKey || event.metaKey) return;
    if (event.key === 'Escape') {
      event.preventDefault();
      if (!blocked) close();
    } else if (event.target === field && !blocked && hits.length) {
      if (event.key === 'Enter') {
        event.preventDefault();
        choose(hits[selected]!);
      } else if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
        event.preventDefault();
        row = (selected + hits.length + (event.key === 'ArrowDown' ? 1 : -1)) % hits.length;
        void tick().then(() => document.getElementById(`message-search-result-${row}`)?.scrollIntoView({ block: 'nearest' }));
      }
    }
  }
</script>

<dialog bind:this={dialog} aria-label="Search Messages" onkeydown={keyboard}
  oncancel={(event) => { event.preventDefault(); if (!composing && !blocked) close(); }}>
  <h2>Search Messages</h2>
  <!-- svelte-ignore a11y_autofocus (Opening the modal directs typing to its search field.) -->
  <input class="control-compact" type="search" role="combobox" aria-label="Search Message Contents" autofocus
    aria-controls="message-search-results" aria-expanded={hits.length > 0} aria-autocomplete="list"
    aria-activedescendant={hits.length ? `message-search-result-${selected}` : undefined}
    bind:this={field} bind:value={query}
    oncompositionstart={() => { composing = true; }} oncompositionend={() => { composing = false; }} />
  <div id="message-search-results" role="listbox" aria-label="Messages">
    {#each hits as hit, position (JSON.stringify([hit.chatId, hit.itemId]))}
      <button id={`message-search-result-${position}`} role="option" type="button" tabindex="-1"
        aria-selected={selected === position} disabled={blocked} onclick={() => choose(hit)}>
        <strong>{hit.chatTitle}</strong>
        <span>{hit.before}<mark>{hit.match}</mark>{hit.after}</span>
      </button>
    {/each}
  </div>
  <footer>
    {#if nextPage}<button type="button" disabled={blocked || loading} onclick={() => void loadNext()}>Search More Messages</button>{/if}
    <button type="button" disabled={blocked} onclick={close}>Close</button>
  </footer>
</dialog>

<style>
  dialog { inline-size: min(46rem, 87vw); max-block-size: 75vh; }
  h2 { font-size: 1rem; margin: 0 0 0.65rem; }
  input { inline-size: 100%; }
  [role="listbox"] { display: grid; gap: 0.25rem; max-block-size: 53vh; overflow: auto; margin-block: 0.5rem; }
  [role="option"] { display: grid; gap: 0.15rem; overflow-wrap: anywhere; text-align: start; }
  footer { display: flex; justify-content: flex-end; gap: 0.45rem; }
</style>
