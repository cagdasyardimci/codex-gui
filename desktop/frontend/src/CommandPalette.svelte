<script lang="ts">
  import { onMount, tick } from 'svelte';
  import { filterPalette, type PaletteEntry, type PaletteMode } from './commandPalette';

  let { mode, entries, lookup, blocked, choose, close }: {
    mode: PaletteMode;
    entries: PaletteEntry[];
    lookup?: (query: string) => Promise<PaletteEntry[]>;
    blocked: boolean;
    choose: (entry: PaletteEntry) => void;
    close: () => void;
  } = $props();

  let dialog: HTMLDialogElement;
  let search: HTMLInputElement;
  let query = $state('');
  let row = $state(0);
  let loaded = $state.raw<{ query: string; matches: PaletteEntry[] }>();
  let composing = false;
  const labels: Record<PaletteMode, { title: string; field: string }> = {
    commands: { title: 'Command Palette', field: 'Search Commands' },
    projects: { title: 'Choose Project', field: 'Search Projects' },
    chats: { title: 'Choose Chat', field: 'Search Chats' },
    files: { title: 'Quick Open', field: 'Search Project Files' },
  };
  const { title, field: fieldName } = $derived(labels[mode]);
  const results = $derived.by(() => {
    if (!lookup) return filterPalette(entries, query);
    return loaded?.query === query ? loaded.matches : [];
  });
  const highlighted = $derived(Math.min(row, Math.max(0, results.length - 1)));

  onMount(() => {
    dialog.showModal();
    search.focus();
  });

  $effect(() => {
    const read = lookup;
    const term = query;
    if (!read) return;
    let current = true;
    const timer = window.setTimeout(() => {
      void read(term).then((matches) => { if (current) loaded = { query: term, matches }; }).catch(console.error);
    }, term ? 75 : 0);
    return () => { current = false; window.clearTimeout(timer); };
  });

  function keyboard(event: KeyboardEvent) {
    if (event.isComposing || composing || event.altKey || event.ctrlKey || event.metaKey) return;
    if (event.key === 'Escape') {
      event.preventDefault();
      close();
      return;
    }
    if (blocked || !results.length) return;
    if (event.key === 'Enter') {
      if (event.target !== search && event.target instanceof HTMLButtonElement) return;
      event.preventDefault();
      choose(results[highlighted]!);
      return;
    }
    if (event.key !== 'ArrowUp' && event.key !== 'ArrowDown') return;
    event.preventDefault();
    const next = highlighted + (event.key === 'ArrowDown' ? 1 : -1);
    row = (next + results.length) % results.length;
    const id = `palette-result-${row}`;
    void tick().then(() => document.getElementById(id)?.scrollIntoView({ block: 'nearest' }));
  }
</script>

<dialog bind:this={dialog} aria-label={title} onkeydown={keyboard}
  oncancel={(event) => { event.preventDefault(); if (!composing) close(); }}>
  <h2>{title}</h2>
  <!-- svelte-ignore a11y_autofocus (Opening the dialog directs typing to its search field.) -->
  <input class="control-compact" type="search" role="combobox" aria-label={fieldName} aria-expanded={results.length > 0} autofocus
    aria-controls="palette-results" aria-autocomplete="list"
    aria-activedescendant={results.length ? `palette-result-${highlighted}` : undefined}
    bind:this={search} bind:value={query} oninput={() => { row = 0; }}
    oncompositionstart={() => { composing = true; }} oncompositionend={() => { composing = false; }} />
  <div id="palette-results" role="listbox" aria-label={title}>
    {#each results as entry, index (entry.id)}
      <button id={`palette-result-${index}`} type="button" role="option" tabindex="-1" aria-selected={index === highlighted}
        disabled={blocked} onclick={() => choose(entry)}>
        <span>{entry.title}</span>
        {#if entry.detail}<span class="palette-detail">{entry.detail}</span>{/if}
      </button>
    {/each}
  </div>
  <button class="palette-close" type="button" onclick={close}>Close</button>
</dialog>

<style>
  dialog { inline-size: min(37rem, 86vw); max-block-size: 74vh; }
  h2 { margin: 0 0 0.65rem; font-size: 1rem; }
  input { width: 100%; }
  [role="listbox"] { display: grid; gap: 0.22rem; margin-block: 0.6rem; max-block-size: 48vh; overflow: auto; }
  [role="option"] { display: grid; gap: 0.2rem; overflow: hidden; }
  .palette-detail { font-size: 0.88em; overflow-wrap: anywhere; }
  .palette-close { display: block; margin-inline-start: auto; }
</style>
