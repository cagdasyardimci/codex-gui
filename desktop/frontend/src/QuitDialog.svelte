<script lang="ts">
  import { onMount } from 'svelte';

  let { busy, stopOnly, cancel, confirm }: {
    busy: boolean;
    stopOnly: boolean;
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
    <button type="button" disabled={busy} onclick={confirm}>{stopOnly ? 'Stop All' : 'Stop and Quit'}</button>
  </div>
</dialog>
