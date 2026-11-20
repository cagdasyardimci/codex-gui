import { invoke } from '@tauri-apps/api/core';
import { click, waitFor } from './fixtureControls';
import type { WorkspaceSnapshot } from './generated/workspace';
import { navigateWorkspace } from './projectIpc';

const OLDEST_VOICE = 'First words before any coding turn.';
const OLDER_VOICE = 'An earlier spoken reply.';
const RECENT_VOICE = 'A recent spoken reply.';
const VOICE_ONLY_EARLIER = 'The first voice-only exchange.';
const VOICE_ONLY_RECENT = 'The latest voice-only exchange.';
const LIVE_VOICE = 'Another voice-only utterance.';
const LEGACY_VOICE = 'Legacy speech says <hello>.';
const INLINE = 'Shared **in chat**.';

export async function verifyVoiceHistory(
  mode: 'voiceHistory' | 'voiceHistoryRestore', visible: () => WorkspaceSnapshot | null,
) {
  const selected = () => visible()?.navigation.selectedChat;
  const items = () => visible()?.transcript.items ?? [];
  const speech = () => items().filter((item) => item.spoken).map((item) => item.text);
  const has = (text: string) => items().some((row) => row.text === text);
  const forbidden = () => items().some((row) =>
    row.text.includes('Do not display this voice status') || row.text.includes('<realtime_delegation>') ||
    row.text.includes('::codex-realtime-inline{}'));
  try {
    if (mode === 'voiceHistory') {
      await click('Mixed voice history');
      await waitFor('The recent speech did not join its coding history', () => selected() === 'history-first' &&
        has(RECENT_VOICE) && has(INLINE) && !forbidden());
      if (has(OLDER_VOICE) || has(OLDEST_VOICE)) throw new Error('Older speech arrived before its turn page');
      const read = visible()!;
      const older = read.navigation.olderHistory;
      if (!older || older.speech || !read.workspace) throw new Error('No older coding page to load');
      await navigateWorkspace({ loadOlderHistory: { workspaceId: read.workspace.workspaceId,
        chatId: 'history-first', ticket: older.ticket } });
      await waitFor('Older speech did not follow the earlier coding page', () =>
        has(OLDER_VOICE) && has(OLDEST_VOICE) && !forbidden());
      if (speech().join('|') !== [OLDEST_VOICE, OLDER_VOICE, RECENT_VOICE].join('|') ||
          visible()?.transcript.generation !== read.transcript.generation) {
        throw new Error('Paging changed speech order or replaced the reading window');
      }

      await click('Legacy voice history');
      await waitFor('Legacy speech did not replace its internal envelope', () =>
        selected() === 'history-second' && speech().includes(LEGACY_VOICE) && !forbidden());
      await click('Voice-only history');
    }
    await waitFor('The voice-only chat did not restore its recent speech', () =>
      selected() === 'voice-only' && speech().includes(VOICE_ONLY_RECENT));
    await waitFor('The live event did not publish on the voice-only chat', () => speech().includes(LIVE_VOICE));
    if (has(VOICE_ONLY_EARLIER) || speech().filter((text) => text === VOICE_ONLY_RECENT).length !== 1) {
      throw new Error('The first speech page contained an old or duplicated entry');
    }
    await click('Load Earlier Messages');
    await waitFor('Paging reached no earlier voice-only speech', () => has(VOICE_ONLY_EARLIER));
    const recorded = speech();
    if (recorded.join('|') !== [VOICE_ONLY_EARLIER, VOICE_ONLY_RECENT, LIVE_VOICE].join('|')) {
      throw new Error('The speech-only history did not stay ordered after paging');
    }
    await invoke('verify_voice_result', { failure: null, evidence: { phase: mode, speech: recorded } });
  } catch (error) {
    await invoke('verify_voice_result', { failure: String(error), evidence: {} });
  }
}
