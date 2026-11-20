import { invoke } from '@tauri-apps/api/core';
import { click, clickByLabel, waitFor } from './fixtureControls';
import type { WorkspaceSnapshot } from './generated/workspace';
import { navigateWorkspace } from './projectIpc';

const PHONE_CHAT = 'relay-mobile-history';
const MANUAL = 'input[aria-label="Manual Pairing Code"]';
const QR = '[aria-label="Pairing QR code"] canvas';
const PAIRING = 'section[aria-label="Pair a Device"]';

async function beginPairing() {
  await click('Add Device');
  await waitFor('The phone pairing code did not render', () => {
    const canvas = document.querySelector<HTMLCanvasElement>(QR);
    return !!canvas && canvas.width === canvas.height && canvas.width >= 150 &&
      canvas.getContext('2d')?.getImageData(24, 24, 1, 1).data[0] === 0;
  });
}

async function manualCode(value: string) {
  await click('Computer');
  await waitFor('The manual pairing code did not match this request', () =>
    document.querySelector<HTMLInputElement>(MANUAL)?.value === value);
  await click('Copy Pairing Code');
}

function devicePresent(name: string) {
  return [...document.querySelectorAll('[aria-label="Paired Devices"] li > span')]
    .some((row) => row.textContent?.trim() === name);
}

export async function verifyRelayDevices(visible: () => WorkspaceSnapshot | null) {
  try {
    await waitFor('The source checkout did not open', () => visible()?.workspace?.projectPath.endsWith('Source relay checkout') === true);
    await click('Settings');
    await click('Connections');
    const allow = () => document.querySelector<HTMLInputElement>('input[aria-label="Allow Connections"]:enabled');
    await waitFor('The relay host control was not available', () => !!allow());
    allow()?.click();

    await beginPairing();
    await click('Enlarge QR Code');
    await manualCode('FIXTURE-01');
    await click('Close Pairing');
    await waitFor('Closing pairing left its credential mounted', () => !document.querySelector(PAIRING));
    await beginPairing();
    await waitFor('Pairing survived its expiry', () => !document.querySelector(PAIRING));

    await beginPairing();
    await waitFor('The phone was missing after claiming its QR code', () =>
      devicePresent('Fixture Phone') && !document.querySelector(PAIRING));
    await beginPairing();
    await manualCode('FIXTURE-04');
    await waitFor('The computer was missing after claiming its manual code', () =>
      devicePresent('Fixture Phone') && devicePresent('Fixture Computer') && !document.querySelector(PAIRING));

    await clickByLabel('Manage Fixture Phone');
    await click('Revoke Access');
    await waitFor('Revocation removed another device or retained its target', () =>
      !devicePresent('Fixture Phone') && devicePresent('Fixture Computer'));
    await click('Refresh Devices');
    await waitFor('A later device read restored the revoked target', () =>
      !devicePresent('Fixture Phone') && devicePresent('Fixture Computer'));

    await beginPairing();
    await manualCode('FIXTURE-05');
    const current = visible()?.workspace?.workspaceId;
    if (!current) throw new Error('The source checkout was lost');
    await navigateWorkspace({ reconnect: { workspaceId: current } });
    await waitFor('The old pairing credential survived reconnect', () =>
      !document.querySelector(PAIRING) && devicePresent('Fixture Computer'));
    if (devicePresent('Fixture Phone')) throw new Error('Reconnect restored the revoked device');
    await click('Close');
    await click('Refresh');
    await click('Paired phone chat');
    await waitFor('The paired project history did not restore its active turn and approval', () =>
      visible()?.navigation.selectedChat === PHONE_CHAT && !!visible()?.navigation.actions.stop &&
      visible()?.navigation.actions.interactions.some((request) => 'approval' in request.content) === true);
    await click('Reconnect');
    await waitFor('The active phone approval did not return after reconnect', () =>
      visible()?.navigation.selectedChat === PHONE_CHAT && !!visible()?.navigation.actions.stop &&
      visible()?.navigation.actions.interactions.some((request) => 'approval' in request.content) === true);
    await click('Approve');
    await waitFor('The paired turn did not complete in its original chat', () =>
      visible()?.navigation.selectedChat === PHONE_CHAT && visible()?.navigation.actions.stop === null &&
      visible()?.transcript.items.some((item) => item.text === 'The paired turn completed.') === true);
    await click('Settings');
    await click('Connections');
    await waitFor('The reconnected relay host control did not become available', () => !!allow() && allow()?.checked === true);
    allow()?.click();
    await waitFor('The relay remained enabled after turning it off', () => !!allow() && allow()?.checked === false);
    await invoke('verify_voice_result', { failure: null, evidence: { chat: PHONE_CHAT } });
  } catch (error) {
    const host = await invoke('relay_host_fixture_view').catch(String);
    await invoke('verify_voice_result', { failure: `${String(error)} (${JSON.stringify(host)})`, evidence: {} });
  }
}
