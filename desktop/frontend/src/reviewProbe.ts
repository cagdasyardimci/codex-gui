import { click, typeText, waitFor } from './fixtureControls';
import type { ReviewDelivery, WorkspaceSnapshot } from './generated/workspace';

export async function verifyCodeReviews(visible: () => WorkspaceSnapshot | null) {
  const nav = () => visible()?.navigation;
  const result = (text: string) => document.querySelector('.workspace-transcript')?.textContent?.includes(text) === true;
  const dialog = () => document.querySelector<HTMLDialogElement>('dialog[aria-label="Code Review"][open]');
  function stoppedThread() {
    const target = nav()?.actions.stop;
    return target && 'turn' in target ? target.turn.threadId : undefined;
  }

  async function open(command: string) {
    await waitFor('The captured chat did not allow a review', () => nav()?.slashCommands.available.includes('review') === true);
    typeText(command);
    await waitFor('The review draft did not persist', () => nav()?.draft?.text === command);
    await click('Send');
    await waitFor('The captured review form did not open', () => !!dialog());
  }

  function choose(label: string, value: string) {
    const control = dialog()!.querySelector<HTMLSelectElement>(`select[aria-label="${label}"]`)!;
    control.value = value;
    control.dispatchEvent(new Event('change', { bubbles: true }));
  }

  async function submit(delivery: ReviewDelivery) {
    choose('Review Delivery', delivery);
    await click('Start Review', dialog()!);
    await waitFor('Submitting the captured review did not dismiss the form', () => !dialog());
  }

  await open('/review');
  await click('Cancel', dialog()!);
  await waitFor('Cancel changed the review draft or started a turn', () =>
    !dialog() && nav()?.draft?.text === '/review' && !stoppedThread());

  await open('/review uncommitted');
  await submit('inline');
  await waitFor('Inline review did not acquire its original turn', () => stoppedThread() === 'history-first');
  await waitFor('Inline review did not settle in its source transcript', () =>
    result('Reviewed the captured uncommitted changes.') && nav()?.draft?.text === '' && !stoppedThread());

  await open('/review base integration');
  await submit('detached');
  await waitFor('The detached review did not acquire an independent chat and leave the source selected', () =>
    nav()?.selectedChat === 'history-first' && nav()?.draft?.text === '' &&
    nav()?.chats.some((chat) => chat.id === stoppedThread() && chat.title === 'Detached Fixture Review') === true);
  const detached = stoppedThread()!;
  await open('/review commit 0123abc');
  await submit('inline');
  await waitFor('The detached run blocked another review in its original source', () =>
    result('Reviewed the captured commit.') && nav()?.draft?.text === '' && stoppedThread() === detached);

  typeText('The source draft survives the detached review.');
  await waitFor('The source chat did not preserve its draft', () =>
    nav()?.draft?.text === 'The source draft survives the detached review.');
  await click('Detached Fixture Review');
  await waitFor('The detached review did not route Stop to its own turn', () =>
    nav()?.selectedChat === detached && stoppedThread() === detached && !result('Reviewed the captured commit.'));
  await click('Stop');
  await waitFor('The detached review did not stop in its own transcript', () =>
    result('Stopped the detached review.') && !stoppedThread());
  await click('First fixture chat');
  await waitFor('Stopping the detached review changed its source transcript or draft', () =>
    nav()?.selectedChat === 'history-first' && nav()?.draft?.text === 'The source draft survives the detached review.' &&
    result('Reviewed the captured commit.') && !result('Stopped the detached review.'));

  await click('Second fixture chat');
  await waitFor('The second chat did not acquire its original draft before review', () => nav()?.selectedChat === 'history-second');
  await open('/review');
  choose('Review Scope', 'custom');
  await waitFor('Choosing custom review did not provide its instruction field', () => !!dialog()?.querySelector('textarea'));
  const instructions = dialog()!.querySelector('textarea')!;
  instructions.value = 'Check cancellation café.\nPreserve 日本語.';
  instructions.dispatchEvent(new Event('input', { bubbles: true }));
  await submit('inline');
  await waitFor('Custom review did not complete in its initiating chat', () =>
    result('Reviewed the captured instructions.') && nav()?.draft?.text === '' && !stoppedThread());
}
