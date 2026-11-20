import { invoke } from '@tauri-apps/api/core';
import { click, waitFor } from './fixtureControls';
import type { WorkspaceSnapshot } from './generated/workspace';
import { speechFixtureEvidence } from './speechPlayback';

export async function verifyReadAloud(visible: () => WorkspaceSnapshot | null) {
  try {
    await click('Read Aloud first');
    await waitFor('The reading chat did not open', () => visible()?.navigation.selectedChat === 'history-first');
    await click('Read Aloud');
    const first = speechFixtureEvidence()!;
    await waitFor('Segmented audio did not drain', () => first.closed && first.frames === 8000);

    await click('Read Aloud');
    const repeated = speechFixtureEvidence()!;
    await waitFor('Repeat playback did not receive audio', () => repeated.frames > 0 && !repeated.closed);
    await click('Stop Reading');
    await waitFor('Stop Reading did not retire the repeated playback', () => repeated.closed);

    await click('Read Aloud');
    const switched = speechFixtureEvidence()!;
    await waitFor('Playback did not start before switching chats', () => switched.frames > 0 && !switched.closed);
    await click('Read Aloud second');
    await waitFor('Switching chats did not retire playback', () => switched.closed && visible()?.navigation.selectedChat === 'history-second');

    await click('Read Aloud');
    const failed = speechFixtureEvidence()!;
    await waitFor('The provider error did not release playback', () => failed.closed);
    await click('Read Aloud');
    const recovered = speechFixtureEvidence()!;
    await waitFor('Read Aloud could not resume after provider failure', () => recovered.closed && recovered.frames === 4000);
    await invoke('verify_voice_result', { failure: null, evidence: { first, repeated, switched, failed, recovered } });
  } catch (error) {
    await invoke('verify_voice_result', { failure: String(error), evidence: {} });
  }
}
