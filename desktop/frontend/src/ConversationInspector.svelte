<script module lang="ts">
  export type InspectorTab = 'sources' | 'commands' | 'subagents';
  export type InspectorSelection = {
    tab: InspectorTab;
    source?: string;
    command?: string;
    agent?: string;
  };
</script>

<script lang="ts">
  import type { ChatRequest, InspectorView, TranscriptCommand } from './generated/workspace';
  import type { SummarySource } from './PinnedSummary.svelte';
  import { openInspectorSource, readInspectorSourceDetail, revealInspectorAttachment } from './projectIpc';
  import ChildConversation from './ChildConversation.svelte';
  import ImagePreview from './ImagePreview.svelte';

  let { scope, selection, view, attachments, commands, choose, close }: {
    scope: ChatRequest;
    selection: InspectorSelection;
    view: InspectorView;
    attachments: SummarySource[];
    commands: TranscriptCommand[];
    choose: (selection: InspectorSelection) => void;
    close: () => void;
  } = $props();

  let opening = $state(false);
  let detail = $state<string>();
  const heading = $derived(selection.tab === 'sources' ? 'Sources' : selection.tab === 'commands' ? 'Commands' : 'Subagents');
  const file = $derived(attachments.find((attachment) => attachment.id === selection.source));
  const source = $derived(view.sources.find((item) => item.id === selection.source));
  const command = $derived(commands.find((item) => item.id === selection.command));
  const agent = $derived(view.agents.find((item) => item.id === selection.agent));
  const categories = $derived([...new Set(view.sources.map((item) => item.category))]);

  $effect(() => {
    const current = selection.tab === 'sources' ? source : undefined;
    const owner = scope;
    let retired = false;
    detail = undefined;
    if (current?.hasDetail) {
      void readInspectorSourceDetail({ scope: owner, sourceId: current.id, revision: current.revision })
        .then((value) => { if (!retired) detail = value; }).catch(() => {});
    }
    return () => { retired = true; };
  });

  async function open(action: () => Promise<void>) {
    if (opening) return;
    opening = true;
    try {
      await action();
    } catch (error) {
      if (error !== 'staleSelection' && error !== 'retiredWorkspace') console.error(error);
    } finally {
      opening = false;
    }
  }
</script>

<aside class="conversation-inspector" aria-label={`${heading} Inspector`}>
  <header>
    <h2>{heading}</h2>
    <button type="button" onclick={close}>Close Inspector</button>
  </header>
  {#if selection.tab === 'sources'}
    <nav aria-label="Conversation Sources">
      {#each attachments as item (item.id)}
        <button type="button" aria-current={selection.source === item.id ? 'true' : undefined}
          onclick={() => choose({ ...selection, source: item.id })}>{item.label}</button>
      {/each}
      {#each categories as category (category)}
        <section aria-label={category}>
          <h3>{category}</h3>
          {#each view.sources.filter((item) => item.category === category) as item (item.id)}
            <button type="button" aria-current={selection.source === item.id ? 'true' : undefined}
              onclick={() => choose({ ...selection, source: item.id })}>{item.label}</button>
          {/each}
        </section>
      {/each}
    </nav>
    {#if file}
      {@const item = file}
      {#key item.media}
        {#if item.load}<div class="source-preview"><ImagePreview load={item.load} alt={item.label} downloadOriginal /></div>{/if}
        <button type="button" disabled={opening} onclick={() => void open(() => revealInspectorAttachment(item.media))}>
          Show Source in Folder
        </button>
      {/key}
    {:else if source}
      {@const item = source}
      {#if detail}<pre aria-label="Source Details">{detail}</pre>{/if}
      {#if item.canOpen}
        <button type="button" disabled={opening}
          onclick={() => void open(() => openInspectorSource({ scope, sourceId: item.id, revision: item.revision }))}>
          Open Source
        </button>
      {/if}
    {/if}
  {:else if selection.tab === 'commands'}
    <nav aria-label="Conversation Commands">
      {#each commands as item (item.id)}
        <button type="button" aria-current={selection.command === item.id ? 'true' : undefined}
          onclick={() => choose({ ...selection, command: item.id })}>{item.command}</button>
      {/each}
    </nav>
    {#if command?.output}<pre aria-label="Command Output">{command.output}</pre>{/if}
  {:else if agent}
    {#key agent.id}
      <ChildConversation {scope} {agent} revision={view.childRevision}
        back={() => choose({ ...selection, agent: undefined })} />
    {/key}
  {:else}
    <nav aria-label="Conversation Subagents">
      {#each view.agents as item (item.id)}
        <button type="button" onclick={() => choose({ ...selection, agent: item.id })}>{item.label}</button>
      {/each}
    </nav>
  {/if}
</aside>

<style>
  .conversation-inspector { flex: 0 1 21rem; inline-size: 21rem; min-inline-size: 12rem; max-inline-size: 37%;
    overflow: auto; border-inline-start: 1px solid var(--workspace-divider); padding: 0.55rem; overflow-wrap: anywhere; }
  header { display: flex; justify-content: space-between; align-items: center; gap: 0.4rem; margin-block-end: 0.5rem; }
  h2 { font-size: 1rem; margin: 0; }
  nav { display: grid; gap: 0.23rem; margin-block-end: 0.6rem; }
  nav > section { display: grid; gap: 0.23rem; }
  h3 { font-size: 0.9rem; margin: 0.15rem 0 0; }
  pre { white-space: pre-wrap; }
  .source-preview :global(img) { display: block; max-inline-size: 100%; max-block-size: 16rem; margin-block-end: 0.45rem; }
</style>
