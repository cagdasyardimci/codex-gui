<script lang="ts">
  import { invoke } from '@tauri-apps/api/core';
  import { onMount, tick } from 'svelte';
  import { probeMedia } from './mediaProbe';
  import { observeWorkspace, pickWorkspace, readWorkspace } from './projectIpc';
  import { verifyWorkspaceSubscription } from './workspaceProbe';
  import type { IpcError, TranscriptItem, WorkspaceView } from './generated/workspace';

  let text = $state('');
  let transcript = $state<HTMLPreElement>();
  let mode = $state<'none' | 'streaming' | 'media' | null>(null);
  let workspace = $state<WorkspaceView | null>(null);
  let picking = $state(false);

  async function openProject() {
    picking = true;
    try {
      await pickWorkspace();
    } catch (error) {
      console.error(error);
    } finally {
      picking = false;
    }
  }

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
    void invoke<'none' | 'streaming' | 'media'>('verification_mode')
      .then(async (verification) => {
        if (lifecycle.signal.aborted) return;
        mode = verification;
        if (verification === 'none') {
          await observeWorkspace((snapshot) => { workspace = snapshot.workspace; }, lifecycle.signal);
        }
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

<main aria-label="Codex GUI Beta">
  {#if mode === 'none'}
    <button type="button" disabled={picking} onclick={() => void openProject()}>Open Project…</button>
    {#if workspace}<h1>{workspace.projectPath}</h1>{/if}
  {:else if mode === 'streaming'}
    <pre aria-label="Fixture output" bind:this={transcript}>{text}</pre>
  {/if}
</main>

<style>
  :global(html) {
    color-scheme: light dark;
    background: Canvas;
    color: CanvasText;
  }

  :global(body) {
    margin: 0;
  }

  main {
    box-sizing: border-box;
    margin-inline: auto;
    max-width: 52rem;
    padding: 2rem;
  }

  button {
    font: inherit;
    padding: 0.4rem 0.7rem;
  }

  pre {
    font: 0.9rem / 1.5 ui-monospace, monospace;
    overflow-wrap: anywhere;
    white-space: pre-wrap;
  }
</style>
