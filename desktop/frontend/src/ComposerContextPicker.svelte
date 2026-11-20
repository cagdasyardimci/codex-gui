<script lang="ts">
  import { onMount, tick } from 'svelte';
  import type { ComposerChoice, ComposerContextTarget, DraftAttachmentScope, ProjectPathMatch } from './generated/workspace';
  import { composerContextCatalog, searchProjectPaths } from './projectIpc';

  let { scope, fromButton, initialQuery, skillsOnly = false, choose, close }: {
    scope: DraftAttachmentScope; fromButton: boolean; initialQuery: string;
    skillsOnly?: boolean;
    choose: (target: ComposerContextTarget) => void; close: () => void;
  } = $props();
  let filter = $state('');
  let search = $state<HTMLInputElement>();
  let files = $state<ProjectPathMatch[]>([]);
  let catalog = $state<ComposerChoice[]>([]);
  let selected = $state(0);
  let sourceRange = $state<ProjectPathMatch>();
  let first = $state(1);
  let last = $state(1);
  const query = $derived(fromButton ? filter : initialQuery);
  const visibleChoices = $derived(catalog.filter((choice) => (!skillsOnly || choice.kind === 'skill') &&
    choice.label.toLowerCase().includes(query.toLowerCase())));
  const matches = $derived([...files.map((file) => ({ file })), ...visibleChoices.map((choice) => ({ choice }))]);

  onMount(() => {
    let retired = false;
    void composerContextCatalog(scope).then((choices) => { if (!retired) catalog = choices; }).catch(() => {});
    if (fromButton) void tick().then(() => search?.focus());
    return () => { retired = true; };
  });

  $effect(() => {
    const input = query;
    const workspaceId = scope.workspaceId;
    let retired = false;
    selected = 0;
    files = [];
    if (skillsOnly) return;
    const delay = setTimeout(() => {
      void searchProjectPaths({ workspaceId, query: input }).then((results) => {
        if (!retired) files = results;
      }).catch(() => {});
    }, 70);
    return () => { retired = true; clearTimeout(delay); };
  });

  export function keyboard(event: KeyboardEvent) {
    if (event.isComposing) return false;
    if (event.key === 'Escape') {
      close();
    } else if (event.key === 'ArrowDown' && matches.length) {
      selected = (selected + 1) % matches.length;
    } else if (event.key === 'ArrowUp' && matches.length) {
      selected = (selected + matches.length - 1) % matches.length;
    } else if ((event.key === 'Enter' || event.key === 'Tab') && !sourceRange && matches[selected]) {
      const match = matches[selected]!;
      if ('file' in match) choose({ file: { path: match.file.id, lines: null } });
      else choose({ catalog: match.choice.id });
    } else return false;
    event.preventDefault();
    return true;
  }
</script>

<div class="composer-context-picker" aria-label={skillsOnly ? 'Choose skill' : 'Add context'} role="group">
  {#if fromButton}<input type="search" aria-label={skillsOnly ? 'Search skills' : 'Search context'} bind:this={search} bind:value={filter} onkeydown={keyboard} />{/if}
  {#if sourceRange}
    {@const entry = sourceRange}
    <div class="composer-context-range">
      <label>First line <input type="number" min="1" bind:value={first} /></label>
      <label>Last line <input type="number" min="1" bind:value={last} /></label>
      <button type="button" disabled={!Number.isInteger(first) || !Number.isInteger(last) || first < 1 || last < first || last - first > 127}
        onclick={() => choose({ file: { path: entry.id, lines: { first, last } } })}>Add Code Range</button>
      <button type="button" onclick={() => { sourceRange = undefined; }}>Back</button>
    </div>
  {:else if matches.length}
    <ul>
      {#each matches as match, index}
        <li class:chosen={selected === index}>
          {#if 'file' in match}
            {@const file = match.file}
            <button type="button" onclick={() => choose({ file: { path: file.id, lines: null } })}>{file.displayPath}</button>
            <button type="button" aria-label={`Select lines in ${file.displayPath}`} onclick={() => { sourceRange = file; }}>Lines</button>
          {:else}
            {@const choice = match.choice}
            <button type="button" aria-label={`Add ${choice.label}`} onclick={() => choose({ catalog: choice.id })}>{choice.label}</button>
          {/if}
        </li>
      {/each}
    </ul>
  {/if}
</div>

<style>
  .composer-context-picker {
    border: 1px solid var(--workspace-divider);
    border-radius: 0.45rem;
    padding: 0.4rem;
  }
  .composer-context-picker > input {
    width: 100%;
    box-sizing: border-box;
  }
  ul {
    max-height: 9rem;
    overflow: auto;
    list-style: none;
    margin: 0;
    padding: 0.2rem 0;
  }
  li, .composer-context-range {
    display: flex;
    gap: 0.4rem;
    align-items: center;
    padding: 0.2rem;
  }
  li.chosen { background: color-mix(in srgb, Highlight 18%, Canvas); }
  .composer-context-range { flex-wrap: wrap; }
  .composer-context-range input { width: 5em; }
</style>
