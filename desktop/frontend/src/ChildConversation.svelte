<script lang="ts">
  import { onMount } from 'svelte';
  import type { ChatRequest, ChildHistoryAction, ChildHistoryTarget, InspectorAgent, TranscriptItem } from './generated/workspace';
  import { navigateWorkspace, readChildHistory } from './projectIpc';
  import MarkdownView from './MarkdownView.svelte';

  let { scope, agent, revision, back }: {
    scope: ChatRequest;
    agent: InspectorAgent;
    revision: number;
    back: () => void;
  } = $props();

  const MAX_ROWS = 1_000;
  let target: ChildHistoryTarget;
  let current = false;
  let rows = $state.raw<TranscriptItem[]>([]);
  let older = $state<string | null>(null);
  let pending = $state(false);
  let opened = $state(false);
  let seenRevision = $state(0);

  onMount(() => {
    target = { scope, agentId: agent.id, selection: crypto.randomUUID() };
    current = true;
    void read('open');
    return () => {
      current = false;
      void navigateWorkspace({ closeChildHistory: target }).catch(() => {});
    };
  });

  $effect(() => {
    if (opened && !pending && revision !== seenRevision) void read('refresh');
  });

  async function read(action: ChildHistoryAction) {
    if (pending || !current) return;
    pending = true;
    if (typeof action === 'string') seenRevision = revision;
    try {
      const page = await readChildHistory({ target, action });
      if (!current) return;
      const previous = new Map(rows.map((row) => [row.itemId, row]));
      const incoming = new Map(page.rows.map((row) => [row.itemId, row]));
      if (typeof action === 'object') {
        rows = [...incoming.values(), ...rows.filter((row) => !incoming.has(row.itemId))].slice(0, MAX_ROWS);
      } else {
        for (const [id, row] of incoming) previous.set(id, row);
        rows = [...previous.values()].slice(-MAX_ROWS);
      }
      older = page.earlier;
      opened = true;
    } catch (error) {
      if (error !== 'staleSelection' && error !== 'retiredWorkspace') console.error(error);
    } finally {
      if (current) pending = false;
    }
  }
</script>

<section aria-label={`${agent.label} Transcript`} class="child-conversation">
  <header>
    <button type="button" onclick={back}>Back to Subagents</button>
    <h3>{agent.label}</h3>
  </header>
  {#if older}
    {@const page = older}
    <button type="button" disabled={pending} onclick={() => void read({ earlier: page })}>Load Earlier Messages</button>
  {/if}
  {#each rows as row (row.itemId)}
    <div class="child-row" data-child-item={row.itemId}>
      {#if row.role === 'commands'}
        {#each row.commands as command (command.id)}
          <code>{command.command}</code>
          {#if command.output}<pre>{command.output}</pre>{/if}
        {/each}
      {:else if row.text}
        <MarkdownView source={row.text} />
      {/if}
    </div>
  {/each}
</section>

<style>
  header { display: flex; align-items: center; flex-wrap: wrap; gap: 0.45rem; margin-block-end: 0.45rem; }
  h3 { font-size: 0.95rem; margin: 0; }
  .child-row { padding-block: 0.3rem; overflow-wrap: anywhere; }
  pre { white-space: pre-wrap; }
</style>
