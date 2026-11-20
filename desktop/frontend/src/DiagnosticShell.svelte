<script lang="ts">
  import { Channel, invoke } from '@tauri-apps/api/core';
  import { onMount, tick } from 'svelte';
  import { probeMedia } from './mediaProbe';
  import { pickWorkspace, readWorkspace } from './projectIpc';
  import type { IpcError, WorkspaceView } from './generated/workspace';

  type StreamMessage = { type: 'delta'; text: string } | { type: 'complete' };

  let text = $state('');
  let transcript = $state<HTMLPreElement>();
  let mode = $state<'none' | 'streaming' | 'media' | null>(null);
  let workspace = $state<WorkspaceView | null>(null);
  let picking = $state(false);

  async function openProject() {
    picking = true;
    try {
      const workspaceId = await pickWorkspace();
      if (workspaceId !== null) {
        workspace = await readWorkspace({ workspaceId });
      }
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

  async function runFixture() {
    const scopeVerified = await workspaceScopeVerified();
    const deltas: string[] = [];
    const output = new Channel<StreamMessage>();
    const delivered = new Promise<void>((resolve) => {
      output.onmessage = (message) => {
        if (message.type === 'delta') {
          deltas.push(message.text);
          text += message.text;
        } else {
          resolve();
        }
      };
    });
    await Promise.all([invoke('stream_fixture', { output }), delivered]);
    await tick();
    await invoke('verify_fixture_result', { scopeVerified, deltas, rendered: transcript?.textContent ?? '' });
  }

  onMount(() => {
    void invoke<'none' | 'streaming' | 'media'>('verification_mode')
      .then(async (verification) => {
        mode = verification;
        if (verification === 'streaming') await runFixture();
        if (verification === 'media') await invoke('verify_media_result', { evidence: await probeMedia() });
      })
      .catch(console.error);
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
