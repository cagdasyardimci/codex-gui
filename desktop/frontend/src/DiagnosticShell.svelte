<script lang="ts">
  import { Channel, invoke } from '@tauri-apps/api/core';
  import { onMount, tick } from 'svelte';
  import { probeMedia } from './mediaProbe';

  type StreamMessage = { type: 'delta'; text: string } | { type: 'complete' };

  let running = $state(false);
  let text = $state('');
  let transcript: HTMLPreElement;

  async function runFixture(verify = false) {
    running = true;
    text = '';
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
    try {
      await Promise.all([invoke('stream_fixture', { output }), delivered]);
      if (verify) {
        await tick();
        await invoke('verify_fixture_result', { deltas, rendered: transcript.textContent ?? '' });
      }
    } catch (error) {
      console.error(error);
    } finally {
      running = false;
    }
  }

  onMount(() => {
    void invoke<'none' | 'streaming' | 'media'>('verification_mode')
      .then(async (mode) => {
        if (mode === 'streaming') await runFixture(true);
        if (mode === 'media') await invoke('verify_media_result', { evidence: await probeMedia() });
      })
      .catch(console.error);
  });
</script>

<main aria-label="Codex GUI Beta">
  <button type="button" disabled={running} onclick={() => void runFixture()}>Run fixture</button>
  <pre aria-label="Fixture output" bind:this={transcript}>{text}</pre>
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
