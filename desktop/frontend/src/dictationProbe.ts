import { Channel, invoke } from '@tauri-apps/api/core';
import { click, typeText, waitFor } from './fixtureControls';
import type { DictationEvent, WorkspaceSnapshot } from './generated/workspace';

const DETAILS = 'What would you like to improve?';
const AREA = 'Which part of codex-gui would you like to review?';
const PHRASE = 'what your country can do for you';

function input(prompt: string) {
  const field = document.querySelector<HTMLInputElement>(`.interaction-card input[aria-label="${CSS.escape(prompt)}"]`);
  if (!field) throw new Error(`Could not find ${prompt}`);
  return field;
}

function fill(prompt: string, text: string) {
  const field = input(prompt);
  field.value = text;
  field.dispatchEvent(new InputEvent('input', { bubbles: true }));
  return field.closest('fieldset')!;
}

export async function verifyQuestionDictation(visible: () => WorkspaceSnapshot | null) {
  try {
    await waitFor('The dictation project did not load', () => !!visible()?.navigation.actions.send);
    const prompt = 'Fixture mixed questions for dictation';
    typeText(prompt);
    await waitFor('The dictation prompt did not reach the draft', () => visible()?.navigation.draft?.text === prompt);
    await click('Send');
    await click('Approve');
    await waitFor('The two captured questions did not appear', () =>
      !!document.querySelector(`input[aria-label="${CSS.escape(DETAILS)}"]`));
    const target = visible()!;
    const owner = target.navigation.chats.find((chat) => chat.id === target.navigation.selectedChat);
    const request = target.navigation.actions.interactions.find((item) => 'questions' in item.content);
    if (!owner || !request || !target.workspace) throw new Error('Could not capture the dictation question');
    const details = fill(DETAILS, 'Manual answer after denial');
    await click('Dictate Answer', details);
    await waitFor('Denied capture did not restore the dictate action', () =>
      [...details.querySelectorAll('button')].some((button) => button.textContent === 'Dictate Answer'));
    if (input(DETAILS).value !== 'Manual answer after denial' || input(DETAILS).disabled) {
      throw new Error('Denied capture replaced or disabled manual input');
    }

    await click('Dictate Answer', details);
    await waitFor('Fixture capture did not start', () => [...details.querySelectorAll('button')]
      .some((button) => button.textContent === 'Insert Dictation' && !button.disabled));
    await click('Second fixture chat');
    await waitFor('The captured question did not retire when switching chats', () => visible()?.navigation.selectedChat === 'history-second' &&
      !document.querySelector(`input[aria-label="${CSS.escape(DETAILS)}"]`));
    const staleAccepted = await invoke('start_question_dictation', {
      target: { workspaceId: target.workspace.workspaceId, interactionId: request.id, questionId: 'details' },
      id: crypto.randomUUID(), events: new Channel<DictationEvent>(),
    }).then(() => true, () => false);
    if (staleAccepted) throw new Error('A hidden question obtained microphone access');

    await click(owner.title);
    await waitFor('The original question did not return', () =>
      visible()?.navigation.selectedChat === owner.id && !!document.querySelector(`input[aria-label="${CSS.escape(AREA)}"]`));
    fill(DETAILS, 'Typed answer on the first question');
    const area = fill(AREA, 'Keep my draft.');
    await click('Dictate Answer', area);
    await click('Insert Dictation', area);
    await waitFor('The local recognizer did not finish within the fixture deadline', () =>
      [...area.querySelectorAll('button')].some((button) => button.textContent === 'Dictate Answer'), 40_000);
    const speech = input(AREA).value;
    if (!speech.toLowerCase().includes(PHRASE)) throw new Error(`Unexpected offline fixture transcription: ${speech}`);
    if (!speech.startsWith('Keep my draft. ') || input(DETAILS).value !== 'Typed answer on the first question') {
      throw new Error('Dictation replaced a manual answer or reached the wrong question');
    }
    await click('Submit Answers');
    await waitFor('The captured answer did not finish the original turn', () => !visible()?.navigation.actions.stop);
    await invoke('verify_voice_result', { failure: null, evidence: { owner: owner.id, speech } });
  } catch (error) {
    await invoke('verify_voice_result', { failure: String(error), evidence: {} });
  }
}
