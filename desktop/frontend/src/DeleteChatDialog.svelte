<script lang="ts">
  import { onMount } from 'svelte';

  let { title, busy, cancel, confirm }: {
    title: string;
    busy: boolean;
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

<dialog bind:this={dialog} aria-label="Delete Chat Permanently"
  oncancel={(event) => { event.preventDefault(); if (!busy) cancel(); }}>
  <h2>Delete Chat Permanently?</h2>
  <p>{title}</p>
  <footer>
    <button type="button" bind:this={cancelButton} disabled={busy} onclick={cancel}>Cancel</button>
    <button type="button" disabled={busy} onclick={confirm}>Delete Chat Permanently</button>
  </footer>
</dialog>

<style>
  dialog { max-inline-size: min(30rem, 80vw); overflow-wrap: anywhere; }
  h2 { margin: 0; font-size: 1rem; }
  footer { display: flex; justify-content: flex-end; gap: 0.5rem; }
</style>
