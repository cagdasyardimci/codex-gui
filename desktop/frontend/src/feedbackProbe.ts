import { invoke } from '@tauri-apps/api/core';
import type { FeedbackRating, TranscriptRowRequest, WorkspaceSnapshot } from './generated/workspace';
import { click, waitFor } from './fixtureControls';
import { rejectsStale } from './markdownProbe';
import { navigateWorkspace } from './projectIpc';

const FIRST = 'history-first';
const SECOND = 'history-second';
const THIRD = 'history-third';

export async function verifyFeedback(visible: () => WorkspaceSnapshot | null) {
  const selection = () => visible()?.navigation.selectedChat;
  const feedback = () => visible()?.navigation.feedback;
  const blocked = () => feedback()?.blockedTurns.join(',');
  const ratingButtons = () => [...document.querySelectorAll('.transcript-row-slot button')]
    .filter((control) => ['Good Result', 'Bad Result'].includes(control.textContent?.trim() ?? ''));
  const row = (itemId: string): TranscriptRowRequest => {
    const snapshot = visible()!;
    const item = snapshot.transcript.items.find((candidate) => candidate.itemId === itemId);
    if (!item) throw new Error(`The feedback fixture did not load ${itemId}`);
    return { workspaceId: snapshot.workspace!.workspaceId, chatId: selection()!, itemId,
      generation: snapshot.transcript.generation, revision: item.revision };
  };
  const submit = (target: TranscriptRowRequest, rating: FeedbackRating) =>
    navigateWorkspace({ submitFeedback: { row: target, rating } });

  try {
    await click('First fixture chat');
    await waitFor('The first chat did not offer one pair of feedback actions', () =>
      selection() === FIRST && feedback()?.available === true && ratingButtons().length === 2);
    const first = row('first-feedback-turn/first-response');
    await rejectsStale(submit({ ...first, revision: first.revision + 1 }, 'good_result'));
    await rejectsStale(submit(row('user-only-turn/user-only-prompt'), 'bad_result'));
    await click('Good Result');
    await waitFor('The first feedback did not reserve its turn', () => blocked() === 'first-feedback-turn');
    await click('Second fixture chat');
    await waitFor('The first feedback receipt affected the destination chat', () =>
      selection() === SECOND && feedback()?.available === true && blocked() === '' && ratingButtons().length === 2);
    await rejectsStale(submit(first, 'bad_result'));

    await click('First fixture chat');
    await waitFor('Reopening the first chat offered feedback again', () =>
      selection() === FIRST && blocked() === 'first-feedback-turn' && ratingButtons().length === 0);
    await click('Second fixture chat');
    await waitFor('The second chat did not offer its own feedback action', () =>
      selection() === SECOND && feedback()?.available === true && ratingButtons().length === 2);
    await click('Bad Result');
    await waitFor('The second feedback did not reserve its turn', () => blocked() === 'second-feedback-turn');
    await click('Reconnect');
    await waitFor('An uncertain report lost its reservation after reconnect', () =>
      selection() === SECOND && feedback()?.available === true && blocked() === 'second-feedback-turn' &&
      visible()?.transcript.items.some((item) => item.itemId === 'second-feedback-turn/second-response') === true);
    if (ratingButtons().length) throw new Error('Reconnect offered a duplicate report');
    await rejectsStale(submit(row('second-feedback-turn/second-response'), 'bad_result'));

    await click('Third fixture chat');
    await waitFor('The second chat reservation affected the third chat', () =>
      selection() === THIRD && blocked() === '' && ratingButtons().length === 2);
    await click('Good Result');
    await waitFor('Fresh disabled feedback policy did not retire the controls', () =>
      feedback()?.available === false && blocked() === '' && ratingButtons().length === 0);
    await invoke('verify_attachments_result', { failure: null });
  } catch (error) {
    await invoke('verify_attachments_result', { failure: String(error) });
  }
}
