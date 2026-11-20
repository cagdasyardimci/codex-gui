<script lang="ts">
  import { parsePatch, splitRows, type DiffLine } from './diffPresentation';
  import type { DiffPatchView } from './generated/workspace';

  let { patch, split, busy, mark }: {
    patch: DiffPatchView;
    split: boolean;
    busy: boolean;
    mark: (hunk: number, reviewed: boolean) => void;
  } = $props();
  let expanded = $state<Record<string, boolean>>({});
  const presentation = $derived(parsePatch(patch.text));
  const changeLayout = $derived(split ? 'split' : 'unified');
</script>

{#snippet number(value: number | undefined)}
  <span class="line-number" aria-hidden="true">{value ?? ''}</span>
{/snippet}

{#snippet rows(lines: DiffLine[])}
  {#if split}
    {#each splitRows(lines) as pair}
      {#if pair.note}
        <div class="note"><span>{pair.note.raw}</span></div>
      {:else}
        <div class="split-row">
          <div class={pair.before?.kind}>
            {@render number(pair.before?.before)}<span>{pair.before?.raw ?? ''}</span>
          </div>
          <div class={pair.after?.kind}>
            {@render number(pair.after?.after)}<span>{pair.after?.raw ?? ''}</span>
          </div>
        </div>
      {/if}
    {/each}
  {:else}
    {#each lines as line}
      <div class={line.kind}>{@render number(line.before)}{@render number(line.after)}<span>{line.raw}</span></div>
    {/each}
  {/if}
{/snippet}

<div class="diff-patch" data-layout={changeLayout} aria-label="Patch">
  {#if presentation}
    {#if split}<div class="split-row sides"><span>Before</span><span>After</span></div>{/if}
    {#if presentation.header}<pre>{presentation.header}</pre>{/if}
    {#each presentation.hunks as hunk, index}
      <div class="hunk-heading">
        <code>{hunk.heading}</code>
        <button type="button" disabled={busy} aria-label={`Mark Hunk ${index + 1} Reviewed`}
          aria-pressed={patch.reviewedHunks.includes(index)}
          onclick={() => mark(index, !patch.reviewedHunks.includes(index))}>Reviewed</button>
      </div>
      {#each hunk.runs as run, position}
        {@const key = `${index}:${position}`}
        {#if run.unchanged && run.lines.length > 8}
          {#if expanded[key]}
            {@render rows(run.lines)}
            <button class="context-button" type="button" aria-expanded="true"
              onclick={() => { expanded[key] = false; }}>Collapse Context</button>
          {:else}
            {@render rows(run.lines.slice(0, 3))}
            <button class="context-button" type="button" aria-expanded="false"
              onclick={() => { expanded[key] = true; }}>Show {run.lines.length - 6} More Lines</button>
            {@render rows(run.lines.slice(-3))}
          {/if}
        {:else}
          {@render rows(run.lines)}
        {/if}
      {/each}
    {/each}
  {:else}
    <pre>{patch.text}</pre>
  {/if}
</div>

<style>
  .diff-patch {
    flex: 1; min-block-size: 0; overflow: auto;
    font: 0.8rem / 1.5 ui-monospace, monospace; tab-size: 4;
  }
  .diff-patch pre { font: inherit; white-space: pre; }
  .diff-patch span:not(.line-number) { white-space: pre; }
  .hunk-heading { display: flex; align-items: center; justify-content: space-between; gap: 0.5rem; background: var(--workspace-canvas); }
  .hunk-heading button, .context-button { flex: none; user-select: none; }
  .split-row { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); min-inline-size: 20rem; }
  .split-row > div { min-inline-size: 0; }
  .split-row > div span:not(.line-number) { white-space: pre-wrap; overflow-wrap: anywhere; }
  .split-row > div + div { border-inline-start: 1px solid var(--workspace-divider); }
  .sides span { padding-inline: 0.35rem; }
  .line-number { display: inline-block; inline-size: 3.4em; text-align: end; padding-inline-end: 0.4em; opacity: 0.7; user-select: none; }
  .add { background: color-mix(in srgb, #27a269 16%, transparent); }
  .delete { background: color-mix(in srgb, #df4747 16%, transparent); }
</style>
