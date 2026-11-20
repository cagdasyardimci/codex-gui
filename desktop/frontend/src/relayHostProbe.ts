import { invoke } from '@tauri-apps/api/core';
import { click, waitFor } from './fixtureControls';
import type { RemoteHostPhase, RemoteHostView, WorkspaceSnapshot } from './generated/workspace';

async function waitHost(phase: RemoteHostPhase) {
  const until = performance.now() + 9000;
  do {
    const host = await invoke<RemoteHostView>('relay_host_fixture_view');
    if (host.phase === phase) return host;
    await new Promise((resolve) => setTimeout(resolve, 35));
  } while (performance.now() < until);
  throw new Error(`Expected the relay host to become ${phase}`);
}

async function toggle(label: string, checked: boolean) {
  const control = () => document.querySelector<HTMLInputElement>(`input[aria-label="${CSS.escape(label)}"]:enabled`);
  await waitFor(`Could not change ${label}`, () => !!control());
  if (control()?.checked !== checked) control()?.click();
}

async function connections() {
  await click('Settings');
  await click('Connections');
}

export async function verifyRelayHost(visible: () => WorkspaceSnapshot | null) {
  try {
    await waitFor('The managed checkout was not mounted', () => visible()?.workspace?.projectPath.endsWith('Managed relay checkout') === true);
    await connections();
    await toggle('Keep Computer Awake', true);
    await toggle('Allow Connections', true);
    await waitHost('duplicate');
    await click('Refresh Connections');
    await waitHost('duplicate');
    await toggle('Allow Connections', false);
    await waitHost('disabled');
    await toggle('Allow Connections', true);
    const first = await waitHost('connected');
    await click('Close');
    const hidden = await waitHost('connected');
    if (!first.keepAwake || !hidden.keepAwake) throw new Error('Closing Settings retired the host');

    await invoke('select_fixture_checkout', { secondary: true });
    await waitFor('The source checkout was not mounted', () => visible()?.workspace?.projectPath.endsWith('Source relay checkout') === true);
    await click('Reconnect');
    await connections();
    await waitHost('connected');
    await click('Close');
    await invoke('select_fixture_checkout', { secondary: false });
    await connections();
    await waitHost('connected');
    await toggle('Allow Connections', false);
    const disabled = await waitHost('disabled');
    await invoke('verify_voice_result', { failure: null, evidence: { first, hidden, disabled } });
  } catch (error) {
    await invoke('verify_voice_result', { failure: String(error), evidence: {} });
  }
}
