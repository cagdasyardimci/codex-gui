<script module lang="ts">
  import type { TranscriptMediaRequest } from './generated/workspace';

  export type SummarySource = {
    id: string;
    label: string;
    load?: () => Promise<ArrayBuffer>;
    media: TranscriptMediaRequest;
  };
</script>

<script lang="ts">
  import type { ChatRequest, LastTurnView } from './generated/workspace';
  import { countChatChanges } from './diffIpc';
  import ImagePreview from './ImagePreview.svelte';

  let { scope, lastTurn, checkoutRevision, sources, agentCount, openChanges, openSource, openAgents }: {
    scope: ChatRequest;
    lastTurn: LastTurnView | null | undefined;
    checkoutRevision: number;
    sources: SummarySource[];
    agentCount: number;
    openChanges: () => void;
    openSource: (id: string) => void;
    openAgents: () => void;
  } = $props();

  let files = $state<number>();
  const revision = $derived(lastTurn?.revision ?? lastTurn?.turnId);
  const totals = $derived(lastTurn?.totals);
  $effect(() => {
    const captured = scope;
    void revision;
    void checkoutRevision;
    let current = true;
    void countChatChanges(captured).then((count) => { if (current) files = count; }).catch(() => {});
    return () => { current = false; };
  });
</script>

<aside class="pinned-summary" aria-label="Pinned Chat Summary">
  <div class="summary-changes">
    <button type="button" onclick={openChanges}>Open Changes</button>
    {#if files !== undefined && files > 0}
      <span>{files} {files === 1 ? 'changed file' : 'changed files'}</span>
    {/if}
    {#if totals}
      <dl>
        <dt>Last Turn</dt>
        <dd><span>+{totals.additions}</span> <span>−{totals.deletions}</span></dd>
      </dl>
    {/if}
  </div>
  {#if agentCount > 0}
    <button type="button" onclick={openAgents}>{agentCount} {agentCount === 1 ? 'Subagent' : 'Subagents'}</button>
  {/if}
  {#if sources.length}
    <ul aria-label="Recent Sources">
      {#each sources as source (source.id)}
        <li>
          <button type="button" aria-label={`Inspect ${source.label}`} onclick={() => openSource(source.id)}>
            {#if source.load}<ImagePreview load={source.load} alt={source.label} />
            {:else}{source.label}{/if}
          </button>
        </li>
      {/each}
    </ul>
  {/if}
</aside>

<style>
  .pinned-summary { display: flex; flex-wrap: wrap; align-items: center; gap: 0.4rem 0.65rem;
    margin-block-end: 0.35rem; padding: 0.4rem 0.55rem; border: 1px solid var(--workspace-divider); border-radius: 0.55rem; }
  .summary-changes, dl, ul { display: flex; flex-wrap: wrap; gap: 0.4rem; align-items: center; }
  dl, dd, ul { margin: 0; }
  dl { border-inline-start: 1px solid var(--workspace-divider); padding-inline-start: 0.55rem; }
  ul { list-style: none; padding: 0; }
  li { overflow-wrap: anywhere; }
  li :global(img) { display: block; inline-size: 2.5rem; block-size: 2.5rem; object-fit: contain; border-radius: 0.3rem; }
</style>
