<script lang="ts">
  import { onMount } from 'svelte';
  import type { SentPromptEdit } from './generated/workspace';

  let { prompt, applying, submit, cancel }: {
    prompt: SentPromptEdit; applying: boolean; submit: (text: string) => void; cancel: () => void;
  } = $props();
  let dialog: HTMLDialogElement;
  let control: HTMLTextAreaElement;
  let text = $state('');
  const edited = $derived(text !== prompt.text && (!!text.trim() || !!prompt.attachments.length));

  onMount(() => {
    text = prompt.text;
    dialog.showModal();
    control.focus();
  });
</script>

<dialog bind:this={dialog} aria-label="Edit Sent Prompt"
  oncancel={(event) => { event.preventDefault(); if (!applying) cancel(); }}>
  <form onsubmit={(event) => { event.preventDefault(); if (edited && !applying) submit(text); }}>
    <h2>Edit Sent Prompt</h2>
    <textarea aria-label="Revised Prompt" rows="9" bind:this={control} bind:value={text} readonly={applying}></textarea>
    {#if prompt.attachments.length}
      <ul aria-label="Attachments">
        {#each prompt.attachments as title}<li>{title}</li>{/each}
      </ul>
    {/if}
    <div>
      <button type="button" onclick={cancel} disabled={applying}>Cancel</button>
      <button type="submit" disabled={!edited || applying}>Fork and Send</button>
    </div>
  </form>
</dialog>

<style>
  dialog { background: Canvas; color: CanvasText; width: min(35rem, 82vw); border-radius: 0.5rem;
    border: 1px solid var(--workspace-divider); padding: 1rem; }
  h2 { margin: 0; font-size: 1rem; }
  form { display: grid; gap: 0.65rem; }
  textarea { padding: 0.45rem; resize: vertical; }
  ul { margin: 0; padding-inline-start: 1.5rem; }
  form > div { display: flex; justify-content: flex-end; gap: 0.45rem; }
</style>
