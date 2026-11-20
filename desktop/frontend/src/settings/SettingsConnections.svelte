<script lang="ts">
  import { invoke } from '@tauri-apps/api/core';
  import { onMount } from 'svelte';
  import type { RemoteHostCommand, RemoteHostView } from '../generated/workspace';

  let { session }: { session: string } = $props();
  let view = $state<RemoteHostView>();
  let busy = $state(false);
  let retired = false;
  let revision = 0;

  async function snapshot() {
    const captured = revision;
    try {
      const next = await invoke<RemoteHostView>('remote_host_snapshot', { session });
      if (!retired && !busy && revision === captured) view = next;
    } catch (error) {
      if (!retired) console.error(error);
    }
  }

  async function change(command: RemoteHostCommand) {
    if (busy) return;
    revision++;
    busy = true;
    try {
      const next = await invoke<RemoteHostView>('change_remote_host', { session, command });
      if (!retired) view = next;
    } catch (error) {
      if (!retired) console.error(error);
    } finally {
      busy = false;
      if (!retired) void snapshot();
    }
  }

  onMount(() => {
    void change('refresh');
    const timer = setInterval(() => { if (!busy) void snapshot(); }, 500);
    return () => { retired = true; clearInterval(timer); };
  });
</script>

<section class="settings-fields" aria-label="Remote access">
  <label class="settings-flag">
    <input type="checkbox" aria-label="Allow Connections" checked={view?.enabled ?? false} disabled={busy || (!view?.available && !view?.enabled)}
      onchange={(event) => void change({ enabled: event.currentTarget.checked })} />
    Allow Connections
  </label>
  <label class="settings-flag">
    <input type="checkbox" aria-label="Keep Computer Awake" checked={view?.keepAwake ?? false} disabled={busy || !view?.available}
      onchange={(event) => void change({ keepAwake: event.currentTarget.checked })} />
    Keep Computer Awake
  </label>
  <button type="button" disabled={busy} onclick={() => void change('refresh')}>Refresh Connections</button>
</section>
