<script lang="ts">
  import { onMount } from 'svelte';
  import type { AccountModel, ChatRow, ContextUsage, SlashCommand } from './generated/workspace';

  let { command, chats, models, effective, usage, workspace, chat, fullAccess, choose, close } : {
    command: SlashCommand;
    chats: ChatRow[];
    models: AccountModel[];
    effective?: AccountModel;
    usage: ContextUsage | null;
    workspace: string;
    chat?: string;
    fullAccess: boolean;
    choose: (choice: string | null, confirmed: boolean) => void;
    close: () => void;
  } = $props();
  let dialog: HTMLDialogElement;
  let query = $state('');
  const matchingChats = $derived(chats.filter((row) =>
    row.title.toLowerCase().includes(query.toLowerCase()) || row.id.toLowerCase().includes(query.toLowerCase())));
  const title = $derived(command === 'status' ? 'Conversation Details' : command === 'plan' ? 'Conversation Mode' :
    command === 'permissions' ? (fullAccess ? 'Full Access' : 'Permissions') :
    command === 'resume' ? 'Resume Chat' : command === 'model' ? 'Choose Model' : 'Reasoning Effort');

  onMount(() => {
    dialog.showModal();
  });
</script>

<dialog bind:this={dialog} aria-label={title} oncancel={(event) => { event.preventDefault(); close(); }}>
  <header><h2>{title}</h2><button type="button" onclick={close}>Close</button></header>
  {#if command === 'status'}
    <dl>
      {#if chat}<dt>Chat</dt><dd>{chat}</dd>{/if}
      <dt>Project</dt><dd>{workspace}</dd>
      {#if effective}<dt>Model</dt><dd>{effective.name}</dd>{/if}
      {#if usage}
        <dt>Context Tokens</dt><dd>{usage.tokens.toLocaleString()}</dd>
        {#if usage.window}
          <dt>Context Window</dt><dd>{usage.window.toLocaleString()}</dd>
          <dt>Context Used</dt><dd>{Math.min(100, Math.round(usage.tokens / usage.window * 100))}%</dd>
        {/if}
      {/if}
    </dl>
  {:else if command === 'plan'}
    <div class="choices">
      <button type="button" onclick={() => choose('plan', true)}>Reapply Plan</button>
      <button type="button" onclick={() => choose('default', true)}>Use Default</button>
    </div>
  {:else if command === 'resume'}
    <input type="search" aria-label="Find Chat" bind:value={query} />
    <div class="choices">
      {#each matchingChats as row (row.id)}
        <button type="button" onclick={() => choose(row.id, false)}>{row.title}</button>
      {/each}
    </div>
  {:else if command === 'model'}
    <div class="choices">
      {#each models as model (model.id)}
        <button type="button" onclick={() => choose(model.id, false)}>{model.name}</button>
      {/each}
    </div>
  {:else if command === 'reasoning'}
    <div class="choices">
      {#each effective?.efforts ?? [] as effort (effort.reasoningEffort)}
        <button type="button" onclick={() => choose(effort.reasoningEffort, false)}>{effort.reasoningEffort}</button>
      {/each}
    </div>
  {:else if command === 'permissions'}
    <div class="choices">
      {#if fullAccess}
        <p>{workspace}</p>
        <button type="button" onclick={() => choose(null, true)}>Enable Full Access</button>
      {:else}
        <button type="button" onclick={() => choose('ask', false)}>Ask for Approval</button>
        <button type="button" onclick={() => choose('auto', false)}>Approve for Me</button>
        <button type="button" onclick={() => choose('full', false)}>Full Access…</button>
      {/if}
    </div>
  {/if}
</dialog>

<style>
  dialog { background: Canvas; color: CanvasText; max-width: min(34rem, 80vw); border: 1px solid var(--workspace-divider);
    border-radius: 0.5rem; padding: 1rem; }
  header { display: flex; justify-content: space-between; align-items: center; gap: 1.25rem; margin-bottom: 0.65rem; }
  h2 { font-size: 1rem; margin: 0; }
  .choices { display: grid; gap: 0.35rem; max-height: 50vh; overflow: auto; }
  input { box-sizing: border-box; width: 100%; margin-bottom: 0.5rem; }
  dl { display: grid; grid-template-columns: auto 1fr; gap: 0.5rem 1rem; }
  dd { margin: 0; overflow-wrap: anywhere; }
</style>
