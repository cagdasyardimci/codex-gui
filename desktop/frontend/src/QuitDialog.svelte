<script lang="ts">
  import { onMount } from 'svelte';
  import type { FileQuitAction } from './generated/workspace';

  let { busy, stopOnly, fileAction, cancel, confirm }: {
    busy: boolean;
    stopOnly: boolean;
    fileAction: FileQuitAction | null;
    cancel: () => void;
    confirm: () => void;
  } = $props();
  let dialog: HTMLDialogElement;
  let cancelButton: HTMLButtonElement;

  onMount(() => {
    dialog.showModal();
    cancelButton.focus();
  });
</script>

<dialog class="quit-dialog" aria-labelledby="quit-heading" bind:this={dialog}
  oncancel={(event) => { event.preventDefault(); if (!busy) cancel(); }}>
  <h2 id="quit-heading">{stopOnly ? 'Stop All Codex Work' : 'Quit Codex GUI'}</h2>
  <div class="quit-actions">
    <button type="button" bind:this={cancelButton} disabled={busy} onclick={cancel}>Cancel</button>
    <button type="button" disabled={busy} onclick={confirm}>
      {#if stopOnly}Stop All
      {:else if fileAction === 'save'}Save and Quit
      {:else if fileAction === 'discard'}Discard Changes and Quit
      {:else}Stop and Quit
      {/if}
    </button>
  </div>
</dialog>
