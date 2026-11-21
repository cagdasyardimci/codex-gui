<script lang="ts">
  import { onMount } from 'svelte';
  import type { ReviewDelivery, ReviewTarget } from './generated/workspace';

  let { source, blocked, submit, close }: {
    source: string;
    blocked: boolean;
    submit: (target: ReviewTarget, delivery: ReviewDelivery) => void;
    close: () => void;
  } = $props();

  let dialog: HTMLDialogElement;
  let delivery = $state<ReviewDelivery>('inline');
  let kind = $state<ReviewTarget['type']>('uncommittedChanges');
  let value = $state('');
  const args = $derived(/^[ \t]*\/review(?:\s+([\s\S]*))?$/iu.exec(source)?.[1]?.trim() ?? '');
  const target = $derived(scope(kind, value.trim()));

  onMount(() => {
    const parts = /^(base|commit|custom)\s+([\s\S]+)$/u.exec(args);
    if (parts) {
      kind = parts[1] === 'base' ? 'baseBranch' : parts[1] === 'commit' ? 'commit' : 'custom';
      value = parts[2]!;
    }
    dialog.showModal();
  });

  function scope(type: ReviewTarget['type'], input: string): ReviewTarget | undefined {
    if (type === 'uncommittedChanges') return { type };
    const bytes = new TextEncoder().encode(input).byteLength;
    if (type === 'baseBranch' && bytes > 0 && bytes <= 512 && !/[\s\p{Cc}]/u.test(input)) {
      return { type, branch: input };
    }
    if (type === 'commit' && /^[a-f\d]{7,64}$/iu.test(input)) return { type, sha: input };
    if (type === 'custom' && bytes > 0 && bytes <= 8192 && !input.includes('\0')) {
      return { type, instructions: input };
    }
  }
</script>

<dialog bind:this={dialog} aria-label="Code Review" oncancel={(event) => { event.preventDefault(); close(); }}>
  <form onsubmit={(event) => { event.preventDefault(); if (target && !blocked) submit(target, delivery); }}>
    <div class="controls">
      <label>Review Scope
        <select aria-label="Review Scope" bind:value={kind} disabled={!!args || blocked}
          onchange={() => { value = ''; }}>
          <option value="uncommittedChanges">Uncommitted Changes</option>
          <option value="baseBranch">Base Branch</option>
          <option value="commit">Commit</option>
          <option value="custom">Custom Instructions</option>
        </select>
      </label>
      <label>Delivery
        <select aria-label="Review Delivery" bind:value={delivery} disabled={blocked}>
          <option value="inline">Inline</option>
          <option value="detached">Detached</option>
        </select>
      </label>
    </div>
    {#if kind === 'baseBranch'}
      <label>Branch <input maxlength="512" bind:value readonly={!!args} /></label>
    {:else if kind === 'commit'}
      <label>Commit SHA <input maxlength="64" bind:value readonly={!!args} /></label>
    {:else if kind === 'custom'}
      <label>Instructions <textarea maxlength="8192" rows="5" bind:value readonly={!!args}></textarea></label>
    {/if}
    <div class="controls commands">
      <button type="button" onclick={close}>Cancel</button>
      <button type="submit" disabled={!target || blocked}>Start Review</button>
    </div>
  </form>
</dialog>

<style>
  dialog { inline-size: min(29rem, 80vw); }
  form { display: grid; gap: 0.65rem; }
  .controls { display: flex; gap: 0.55rem; flex-wrap: wrap; }
  label { display: grid; gap: 0.25rem; }
  input, textarea { width: 100%; box-sizing: border-box; }
  .commands { justify-content: end; }
</style>
