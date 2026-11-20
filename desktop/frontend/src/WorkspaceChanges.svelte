<script lang="ts">
  import { onMount } from 'svelte';
  import type { DiffFileView, DiffPatchView, WorkspaceId } from './generated/workspace';
  import { readChanges, readPatch } from './diffIpc';

  let { workspaceId }: { workspaceId: WorkspaceId } = $props();
  let files = $state<DiffFileView[]>([]);
  let patch = $state<DiffPatchView | null>(null);
  let selected = $state<string | null>(null);
  let refreshing = $state(false);
  let revision = 0;

  async function refresh() {
    const expected = ++revision;
    refreshing = true;
    selected = null;
    patch = null;
    try {
      const found = await readChanges({ workspaceId });
      if (revision === expected) files = found;
    } catch (error) {
      if (revision === expected) files = [];
      console.error(error);
    } finally {
      if (revision === expected) refreshing = false;
    }
  }

  async function openPatch(fileId: string) {
    const expected = ++revision;
    selected = fileId;
    patch = null;
    try {
      const result = await readPatch({ workspaceId, fileId });
      if (revision === expected && result.fileId === fileId) patch = result;
    } catch (error) {
      console.error(error);
    }
  }

  onMount(() => {
    void refresh();
    return () => { revision += 1; };
  });
</script>

<aside class="workspace-changes" aria-label="Checkout Changes">
  <button type="button" disabled={refreshing} onclick={() => void refresh()}>Refresh Changes</button>
  <nav class="changes-files" aria-label="Changed Files">
    {#each files as file (file.fileId)}
      <button type="button" data-file-id={file.fileId} aria-current={selected === file.fileId ? 'true' : undefined}
        disabled={refreshing} onclick={() => void openPatch(file.fileId)}>{file.path}</button>
    {/each}
  </nav>
  {#if patch}
    <pre aria-label="Patch">{patch.text}</pre>
  {/if}
</aside>
