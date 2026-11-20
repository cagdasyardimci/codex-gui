<script lang="ts">
  import { invoke } from '@tauri-apps/api/core';
  import { onMount, tick } from 'svelte';
  import WorkspaceShell from './WorkspaceShell.svelte';
  import { probeMedia } from './mediaProbe';
  import { observeWorkspace, readWorkspace } from './projectIpc';
  import { verifyWorkspaceSubscription } from './workspaceProbe';
  import type { IpcError, TranscriptItem } from './generated/workspace';

  let text = $state('');
  let transcript = $state<HTMLPreElement>();
  type Mode = 'none' | 'streaming' | 'media' | 'history' | 'historyRestore' | 'attachments' | 'annotations' | 'composerContext' | 'composerSettings' | 'projectContext' | 'slashCommands' | 'promptRevision' | 'conversationFork' | 'sidebar' | 'sidebarRestore' | 'commandPalette' | 'account' | 'windowsSetup' | 'turn' | 'activeTurn' | 'queue' | 'diff' | 'quit';
  let mode = $state<Mode | null>(null);

  async function workspaceScopeVerified(): Promise<boolean> {
    const expected: IpcError = 'retiredWorkspace';
    try {
      await readWorkspace({ workspaceId: '00000000-0000-0000-0000-000000000001' });
    } catch (error) {
      if (error !== expected) console.error(error);
      return error === expected;
    }
    return false;
  }

  async function runFixture(subscriptionVerified: boolean, lifecycle: AbortController) {
    const scopeVerified = await workspaceScopeVerified();
    async function report(items: TranscriptItem[], streamRecovered: boolean) {
      await tick();
      await invoke('verify_fixture_result', {
        scopeVerified, subscriptionVerified, streamRecovered, items, rendered: transcript?.textContent ?? '',
      });
    }
    if (!scopeVerified || !subscriptionVerified) {
      await report([], false);
      return;
    }
    const started = await invoke<boolean>('stream_fixture');
    let initialSnapshot = true;
    let recoveredPrefix = false;
    await observeWorkspace(({ transcript: current }) => {
      text = current.items.map((item) => item.text).join('');
      if (initialSnapshot && !started) recoveredPrefix = text.length > 0;
      initialSnapshot = false;
      if (started && text.length > 0) {
        lifecycle.abort();
        window.location.reload();
      } else if (current.completed) {
        lifecycle.abort();
        void report(current.items, recoveredPrefix).catch(console.error);
      }
    }, lifecycle.signal);
  }

  onMount(() => {
    const lifecycle = new AbortController();
    void invoke<Mode>('verification_mode')
      .then(async (verification) => {
        if (lifecycle.signal.aborted) return;
        mode = verification;
        if (verification === 'streaming') {
          const subscription = await verifyWorkspaceSubscription();
          if (subscription === 'reload') window.location.reload();
          else await runFixture(subscription, lifecycle);
        }
        if (verification === 'media') await invoke('verify_media_result', { evidence: await probeMedia() });
      })
      .catch(console.error);
    return () => lifecycle.abort();
  });
</script>

{#if mode === 'none'}
  <WorkspaceShell />
{:else if mode === 'history'}
  <WorkspaceShell verify="initial" />
{:else if mode === 'historyRestore'}
  <WorkspaceShell verify="restore" />
{:else if mode === 'attachments'}
  <WorkspaceShell verify="attachments" />
{:else if mode === 'annotations'}
  <WorkspaceShell verify="annotations" />
{:else if mode === 'composerContext'}
  <WorkspaceShell verify="composerContext" />
{:else if mode === 'composerSettings'}
  <WorkspaceShell verify="composerSettings" />
{:else if mode === 'projectContext'}
  <WorkspaceShell verify="projectContext" />
{:else if mode === 'slashCommands'}
  <WorkspaceShell verify="slashCommands" />
{:else if mode === 'promptRevision'}
  <WorkspaceShell verify="promptRevision" />
{:else if mode === 'conversationFork'}
  <WorkspaceShell verify="conversationFork" />
{:else if mode === 'sidebar' || mode === 'sidebarRestore' || mode === 'commandPalette'}
  <WorkspaceShell verify={mode} />
{:else if mode === 'account'}
  <WorkspaceShell verify="account" />
{:else if mode === 'windowsSetup'}
  <WorkspaceShell verify="windowsSetup" />
{:else if mode === 'turn'}
  <WorkspaceShell verify="turn" />
{:else if mode === 'activeTurn'}
  <WorkspaceShell verify="activeTurn" />
{:else if mode === 'queue'}
  <WorkspaceShell verify="queue" />
{:else if mode === 'diff'}
  <WorkspaceShell verify="diff" />
{:else if mode === 'quit'}
  <WorkspaceShell verify="quit" />
{:else if mode === 'streaming'}
  <main aria-label="Codex GUI Beta">
    <pre aria-label="Fixture output" bind:this={transcript}>{text}</pre>
  </main>
{/if}

<style>
  main {
    box-sizing: border-box;
    margin-inline: auto;
    max-width: 52rem;
    padding: 2rem;
  }

  pre {
    font: 0.9rem / 1.5 ui-monospace, monospace;
    overflow-wrap: anywhere;
    white-space: pre-wrap;
  }
</style>
