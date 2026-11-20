<script lang="ts">
  import { invoke } from '@tauri-apps/api/core';
  import { onMount } from 'svelte';
  import type { RemoteDeviceCommand, RemoteDevicesView, RemoteHostCommand, RemoteHostView, RemotePairingView, WorkspaceId } from '../generated/workspace';

  let { session, workspaceId }: { session: string; workspaceId: WorkspaceId | null } = $props();
  let view = $state<RemoteHostView>();
  let busy = $state(false);
  let retired = false;
  let revision = 0;
  const surface = crypto.randomUUID();
  const scope = $derived({ session, surface });
  let devices = $state<RemoteDevicesView>();
  let deviceBusy = $state(false);
  let deviceRevision = 0;
  let opened: Promise<RemoteDevicesView> | undefined;
  let lastWorkspace: WorkspaceId | null;
  let loadedEnvironment: string | null | undefined;
  let nextPairingCheck = 0;
  let device = $state<'phone' | 'computer'>('phone');
  let enlarged = $state(false);
  let confirmRevoke = $state<string>();
  let qr = $state<HTMLCanvasElement>();

  $effect(() => {
    const pairing = devices?.pairing;
    if (qr && pairing && device === 'phone') drawCode(qr, pairing);
  });

  function drawCode(canvas: HTMLCanvasElement, pairing: RemotePairingView) {
    const cell = 6;
    canvas.width = canvas.height = (pairing.width + 8) * cell;
    const context = canvas.getContext('2d');
    if (!context) return;
    context.fillStyle = 'white';
    context.fillRect(0, 0, canvas.width, canvas.height);
    context.fillStyle = 'black';
    pairing.cells.forEach((filled, index) => {
      if (filled) context.fillRect((index % pairing.width + 4) * cell, (Math.floor(index / pairing.width) + 4) * cell, cell, cell);
    });
  }

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

  async function changeDevices(command: RemoteDeviceCommand) {
    if (deviceBusy || retired) return;
    const captured = ++deviceRevision;
    deviceBusy = true;
    try {
      await openDevices();
      const next = await invoke<RemoteDevicesView>('change_relay_devices', { scope, command });
      if (!retired && deviceRevision === captured) devices = next;
    } catch (error) {
      if (!retired) console.error(error);
    } finally {
      if (deviceRevision === captured) deviceBusy = false;
    }
  }

  function openDevices() {
    opened ??= invoke<RemoteDevicesView>('open_relay_devices', { scope }).catch((error) => {
      opened = undefined;
      throw error;
    });
    return opened;
  }

  async function readDevices() {
    const requested = deviceRevision;
    try {
      await openDevices();
      const next = await invoke<RemoteDevicesView>('relay_devices_snapshot', { scope });
      if (retired || deviceRevision !== requested) return;
      if (deviceBusy) {
        if (devices?.environment !== next.environment) {
          devices = next;
          confirmRevoke = undefined;
        } else if (devices?.pairing && !next.pairing) devices = { ...devices, pairing: null };
        return;
      }
      devices = next;
      if (loadedEnvironment !== next.environment) {
        loadedEnvironment = next.environment;
        confirmRevoke = undefined;
        if (next.connected) await changeDevices('refresh');
      } else if (next.pairing && performance.now() >= nextPairingCheck) {
        nextPairingCheck = performance.now() + 1000;
        await changeDevices({ checkPairing: next.pairing.id });
      }
    } catch (error) {
      if (!retired) console.error(error);
    }
  }

  function copyPairingCode(id: string) {
    void invoke('copy_relay_pairing_code', { scope, id }).catch(console.error);
  }

  function closePairing() {
    deviceRevision++;
    deviceBusy = false;
    if (devices) devices = { ...devices, pairing: null };
    void changeDevices('closePairing');
  }

  function beginPairing() {
    device = 'phone';
    enlarged = false;
    nextPairingCheck = performance.now() + 1000;
    void changeDevices('beginPairing');
  }

  onMount(() => {
    lastWorkspace = workspaceId;
    void change('refresh');
    const captured = scope;
    void readDevices();
    const timer = setInterval(() => {
      if (!busy && lastWorkspace !== workspaceId) {
        lastWorkspace = workspaceId;
        void change('refresh');
      } else if (!busy) void snapshot();
      void readDevices();
    }, 400);
    return () => {
      retired = true;
      clearInterval(timer);
      void opened?.then(() => invoke('close_relay_devices', { scope: captured })).catch(console.error);
    };
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
  {#if devices?.connected && view?.phase === 'connected'}
    <div class="controls">
      <button type="button" disabled={deviceBusy || !!devices.pairing} onclick={beginPairing}>Add Device</button>
      <button type="button" disabled={deviceBusy} onclick={() => void changeDevices('refresh')}>Refresh Devices</button>
    </div>
    {#if devices.pairing}
      {@const pairing = devices.pairing}
      <section class="settings-pairing" aria-label="Pair a Device">
        <div class="controls">
          <button type="button" aria-pressed={device === 'phone'} onclick={() => { device = 'phone'; }}>Phone</button>
          <button type="button" aria-pressed={device === 'computer'} onclick={() => { device = 'computer'; }}>Computer</button>
          <button type="button" onclick={closePairing}>Close Pairing</button>
        </div>
        {#if device === 'phone'}
          <div role="img" aria-label="Pairing QR code">
            <canvas aria-hidden="true" class:enlarged bind:this={qr}></canvas>
          </div>
          <button type="button" onclick={() => { enlarged = !enlarged; }}>{enlarged ? 'Reduce QR Code' : 'Enlarge QR Code'}</button>
        {:else}
          <input class="manual-pairing-code" type="text" readonly aria-label="Manual Pairing Code" value={pairing.manualCode} />
          <button type="button" onclick={() => copyPairingCode(pairing.id)}>Copy Pairing Code</button>
        {/if}
      </section>
    {/if}
    {#if devices.devices.length}
      <ul class="paired-devices" aria-label="Paired Devices">
        {#each devices.devices as item (item.id)}
          <li>
            <span>{item.name}</span>
            {#if confirmRevoke === item.id}
              <button type="button" onclick={() => { confirmRevoke = undefined; }}>Cancel</button>
              <button type="button" disabled={deviceBusy} onclick={() => {
                confirmRevoke = undefined;
                void changeDevices({ revoke: item.id });
              }}>Revoke Access</button>
            {:else}
              <button type="button" aria-label={`Manage ${item.name}`} onclick={() => { confirmRevoke = item.id; }}>Manage</button>
            {/if}
          </li>
        {/each}
      </ul>
    {/if}
  {/if}
</section>

<style>
  .settings-pairing { display: grid; gap: 0.625rem; justify-items: start; }
  canvas { display: block; inline-size: 216px; max-inline-size: 100%; image-rendering: pixelated; }
  canvas.enlarged { inline-size: 360px; }
  .manual-pairing-code { font-family: ui-monospace, monospace; font-size: 1.25em; user-select: all; }
  .paired-devices { display: grid; gap: 0.5rem; padding: 0; margin: 0; list-style: none; }
  .paired-devices li { display: flex; align-items: center; gap: 0.5rem; }
  .paired-devices span { flex: 1; overflow-wrap: anywhere; }
</style>
