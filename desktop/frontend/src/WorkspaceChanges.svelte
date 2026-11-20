<script lang="ts">
  import { tick, untrack } from 'svelte';
  import type {
    DiffAction, DiffComparison, DiffFileView, DiffPatchView, DiffReferences, DiffSide, DraftAttachmentScope,
  } from './generated/workspace';
  import { closeChanges, diffReferences, markDiff, performDiffAction, readChanges, readPatch } from './diffIpc';
  import DiffPatch from './DiffPatch.svelte';
  import DiffRichPreview from './DiffRichPreview.svelte';

  let { scope, preferred, lastTurnId, lastTurnRevision }: {
    scope: DraftAttachmentScope;
    preferred: 'uncommitted' | 'lastTurn';
    lastTurnId?: string;
    lastTurnRevision?: string | null;
  } = $props();
  let comparison = $state<DiffComparison>('uncommitted');
  let base = $state('');
  let target = $state('');
  const viewId = crypto.randomUUID();
  let references = $state<DiffReferences>();
  let files = $state<DiffFileView[]>([]);
  let patch = $state<DiffPatchView | null>(null);
  let selected = $state<string | null>(null);
  let preview = $state<DiffSide>();
  let refreshing = $state(false);
  let busy = $state(false);
  let split = $state(false);
  let filter = $state('');
  let nav = $state<HTMLElement>();
  let revision = 0;

  const matches = $derived(files.filter((file) => {
    const query = filter.trim().toLocaleLowerCase();
    return !query || file.path.toLocaleLowerCase().includes(query) || file.renamedFrom?.toLocaleLowerCase().includes(query);
  }));
  const selectedIndex = $derived(matches.findIndex((file) => file.fileId === selected));
  const capturedPreview = $derived(patch?.contents.find((content) => content.side === preview));

  $effect(() => {
    const owner = scope;
    let retired = false;
    references = undefined;
    void diffReferences(owner).then((result) => { if (!retired) references = result; }).catch(console.error);
    return () => {
      retired = true;
      revision += 1;
      void closeChanges(owner, viewId).catch(console.error);
    };
  });

  $effect(() => {
    comparison = preferred === 'lastTurn' && !untrack(() => lastTurnId) ? 'uncommitted' : preferred;
  });

  $effect(() => {
    const mode = comparison;
    if (mode === 'lastTurn') {
      void lastTurnId;
      void lastTurnRevision;
    }
    untrack(() => { void refresh(mode); });
  });

  async function refresh(mode: DiffComparison) {
    const expected = ++revision;
    refreshing = true;
    busy = false;
    selected = null;
    patch = null;
    preview = undefined;
    files = [];
    try {
      const found = await readChanges({ scope, viewId, comparison: mode });
      if (revision === expected) files = found;
    } catch (error) {
      console.error(error);
    } finally {
      if (revision === expected) refreshing = false;
    }
  }

  async function openPatch(fileId: string, focus = false) {
    if (busy || refreshing || !fileId || !files.some((file) => file.fileId === fileId)) return;
    const expected = ++revision;
    selected = fileId;
    patch = null;
    preview = undefined;
    if (focus) {
      await tick();
      if (revision !== expected) return;
      const button = nav?.querySelector<HTMLButtonElement>(`button[data-file-id="${CSS.escape(fileId)}"]`);
      button?.scrollIntoView({ block: 'nearest' });
      button?.focus({ preventScroll: true });
    }
    try {
      const result = await readPatch({ scope, fileId });
      if (revision === expected && result.fileId === fileId) patch = result;
    } catch (error) {
      console.error(error);
    }
  }

  async function mark(hunk: number | null, reviewed: boolean) {
    const captured = patch;
    if (!captured || busy) return;
    const expected = revision;
    busy = true;
    try {
      await markDiff({ target: { scope, fileId: captured.fileId }, hunk, reviewed });
      if (revision !== expected) return;
      if (hunk === null) patch = { ...captured, reviewed };
      else patch = {
        ...captured,
        reviewedHunks: reviewed ? [...captured.reviewedHunks, hunk] : captured.reviewedHunks.filter((index) => index !== hunk),
      };
    } catch (error) {
      console.error(error);
    } finally {
      if (revision === expected) busy = false;
    }
  }

  async function act(action: DiffAction) {
    if (!patch || busy) return;
    const expected = revision;
    busy = true;
    try {
      await performDiffAction({ target: { scope, fileId: patch.fileId }, action });
    } catch (error) {
      console.error(error);
    } finally {
      if (revision === expected) busy = false;
    }
  }
</script>

<aside class="workspace-changes" aria-label="Checkout Changes">
  <div class="change-controls">
    <label>Compare
      <select aria-label="Comparison" value={JSON.stringify(comparison)}
        onchange={(event) => { comparison = JSON.parse(event.currentTarget.value); }}>
        <option value={JSON.stringify('uncommitted')}>Uncommitted</option>
        <option value={JSON.stringify('staged')}>Staged</option>
        <option value={JSON.stringify('unstaged')}>Unstaged</option>
        {#if lastTurnId}<option value={JSON.stringify('lastTurn')}>Last Turn</option>{/if}
        {#if references?.upstream}
          <option value={JSON.stringify({ branch: null })}>Upstream</option>
        {/if}
        {#if references?.branches.length}
          <optgroup label="Branches">
            {#each references.branches as branch (branch.reference)}
              <option value={JSON.stringify({ branch: branch.reference })}>{branch.label}</option>
            {/each}
          </optgroup>
        {/if}
        {#if references?.commits.length}
          <optgroup label="Recent Commits">
            {#each references.commits as commit (commit.reference)}
              <option value={JSON.stringify({ commit: commit.reference })}>{commit.label}</option>
            {/each}
          </optgroup>
        {/if}
        {#if typeof comparison === 'object' && 'between' in comparison}
          <option value={JSON.stringify(comparison)}>Revisions</option>
        {/if}
      </select>
    </label>
    <button type="button" disabled={refreshing || busy} onclick={() => void refresh(comparison)}>Refresh Changes</button>
  </div>
  <details>
    <summary>Compare Revisions</summary>
    <form class="change-controls" onsubmit={(event) => {
      event.preventDefault();
      comparison = { between: { base: base.trim(), target: target.trim() } };
    }}>
      <input aria-label="Base Revision" placeholder="Base Revision" maxlength="512" bind:value={base} />
      <input aria-label="Target Revision" placeholder="Target Revision" maxlength="512" bind:value={target} />
      <button type="submit" disabled={!base.trim() || !target.trim() || busy}>Compare</button>
    </form>
  </details>
  <input type="search" aria-label="Filter Changed Files" placeholder="Filter Changed Files" bind:value={filter} />
  {#if matches.length}
    <div class="change-controls">
      <select aria-label="Jump to File" value={selected ?? ''} disabled={busy}
        onchange={(event) => void openPatch(event.currentTarget.value, true)}>
        <option value="" disabled>Jump to File</option>
        {#each matches as file (file.fileId)}<option value={file.fileId}>{file.path}</option>{/each}
      </select>
      <button type="button" disabled={busy || selectedIndex <= 0}
        onclick={() => void openPatch(matches[selectedIndex - 1]!.fileId, true)}>Previous File</button>
      <button type="button" disabled={busy || selectedIndex + 1 >= matches.length}
        onclick={() => void openPatch(matches[selectedIndex + 1]!.fileId, true)}>Next File</button>
    </div>
  {/if}
  <nav class="changes-files" aria-label="Changed Files" bind:this={nav}>
    {#each matches as file (file.fileId)}
      <button type="button" data-file-id={file.fileId} aria-current={selected === file.fileId ? 'true' : undefined}
        disabled={refreshing || busy} onclick={() => void openPatch(file.fileId)}>
        {file.path}{#if file.renamedFrom}<small>{file.renamedFrom}</small>{/if}
      </button>
    {/each}
  </nav>
  {#if patch}
    <div class="change-controls">
      <button type="button" aria-pressed={!split} onclick={() => { split = false; }}>Unified</button>
      <button type="button" aria-pressed={split} onclick={() => { split = true; }}>Split</button>
      <button type="button" aria-label="Mark File Reviewed" aria-pressed={patch.reviewed} disabled={busy}
        onclick={() => void mark(null, !patch?.reviewed)}>Reviewed</button>
      <button type="button" disabled={busy} onclick={() => void act('copyPatch')}>Copy Patch</button>
      {#if patch.exportable}<button type="button" disabled={busy} onclick={() => void act('exportPatch')}>Export Patch</button>{/if}
    </div>
    {#each patch.contents as content (content.side)}
      {@const side = content.side === 'before' ? 'Before' : 'After'}
      <div class="change-controls">
        {#if content.rich}
          <button type="button" aria-pressed={preview === content.side}
            onclick={() => { preview = preview === content.side ? undefined : content.side; }}>Preview {side}</button>
        {/if}
        <button type="button" disabled={busy} onclick={() => void act({ exportFile: content.side })}>Export {side}</button>
        {#each content.editors as editor (editor.id)}
          <button type="button" disabled={busy}
            onclick={() => void act({ openEditor: { side: content.side, editor: editor.id } })}>Open {side} in {editor.label}</button>
        {/each}
      </div>
    {/each}
    {#if capturedPreview}
      {#key `${patch.fileId}:${capturedPreview.side}`}
        <DiffRichPreview target={{ scope, fileId: patch.fileId }} content={capturedPreview} />
      {/key}
    {/if}
    {#key patch.fileId}
      <DiffPatch {patch} {split} {busy} mark={(hunk, reviewed) => void mark(hunk, reviewed)} />
    {/key}
  {/if}
</aside>

<style>
  .change-controls { display: flex; flex-wrap: wrap; gap: 0.25rem; }
  .change-controls select { max-inline-size: 14rem; }
  .changes-files small { display: block; }
  .changes-files button[aria-current="true"] { background: color-mix(in srgb, CanvasText 15%, Canvas); }
</style>
