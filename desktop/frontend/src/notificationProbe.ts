import { invoke } from '@tauri-apps/api/core';
import { tick } from 'svelte';
import { click, typeText, waitFor } from './fixtureControls';
import type { TaskAlertCategory, WorkspaceSnapshot } from './generated/workspace';
import { navigateWorkspace } from './projectIpc';

type Outcome = { denied: number; delivered: { key: { projectId: string; chatId: string }; category: TaskAlertCategory }[] };

const outcomes = () => invoke<Outcome>('notification_fixture_outcomes');
const configure = (allowed: boolean, focused: boolean) => invoke('configure_notification_fixture', { allowed, focused });
const SECOND = 'history-second';

export async function verifyNotifications(visible: () => WorkspaceSnapshot | null) {
  const errors: string[] = [];
  const report = console.error;
  console.error = (...values) => {
    errors.push(values.map(String).join(' '));
    report(...values);
  };
  const selected = () => visible()?.navigation.selectedChat;
  const approval = () => visible()?.navigation.actions.interactions.find((entry) => 'approval' in entry.content);
  const question = () => visible()?.navigation.actions.interactions.find((entry) => 'questions' in entry.content);
  const dialog = () => document.querySelector<HTMLDialogElement>('dialog[aria-label="Settings"][open]');
  const field = <T extends HTMLInputElement | HTMLSelectElement>(label: string) =>
    dialog()?.querySelector<T>(`[aria-label="${label}"]`);
  const press = (label: string) => click(label, dialog()!);
  const noWrite = () => visible()?.navigation.actions.stop === null;

  async function settings() {
    await click('Settings');
    await waitFor('Settings did not open for notification preferences', () => !!dialog());
    await press('Notifications');
    await waitFor('Notification preferences did not load', () => !!field('Task Completion'));
  }
  async function select(label: string, value: string) {
    const input = field<HTMLSelectElement>(label)!;
    input.value = value;
    input.dispatchEvent(new Event('change', { bubbles: true }));
    await tick();
    await waitFor(`The notification choice for ${label} did not settle`, () => {
      const control = field<HTMLSelectElement>(label);
      return control?.value === value && !control.matches(':disabled');
    });
  }
  async function send(text: string) {
    typeText(text);
    await waitFor('The fixture did not capture the message draft', () =>
      visible()?.navigation.draft?.text === text && visible()?.navigation.actions.send === true);
    await click('Send');
    await waitFor('The coding approval was not raised', () => !!approval());
  }
  async function respondApproval(current: NonNullable<ReturnType<typeof approval>>) {
    if (!('approval' in current.content)) throw new Error('The pending alert was not an approval');
    const decision = current.content.approval.choices.find((choice) => choice.label === 'Approve');
    if (!decision) throw new Error('The offered approval choice did not exist');
    await navigateWorkspace({ respond: { workspaceId: visible()!.workspace!.workspaceId,
      interactionId: current.id, response: { decision: decision.index } } });
  }
  async function respondQuestion(current: NonNullable<ReturnType<typeof question>>) {
    if (!('questions' in current.content) || current.content.questions.length !== 1) throw new Error('The fixture question changed');
    await navigateWorkspace({ respond: { workspaceId: visible()!.workspace!.workspaceId,
      interactionId: current.id, response: { answers: [{id: current.content.questions[0]!.id, values: ['Composer']}] } } });
  }
  async function openAlert(index: number, owner: string) {
    await invoke('activate_notification_fixture', { index });
    await waitFor('Opening a notification did not select its owning chat', () => selected() === owner);
  }
  async function switchAway() {
    await click('Second fixture chat');
    await waitFor('The other chat did not take focus while the task continued', () =>
      selected() === SECOND && !visible()?.navigation.actions.interactions.length);
  }
  async function pickSound(choice: string, title: string) {
    await invoke('choose_notification_fixture_sound', { choice });
    const button = [...(dialog()?.querySelectorAll('button') ?? [])].find((button) => button.textContent?.trim() === 'Import Sound…');
    let clicked = false;
    button?.addEventListener('click', () => { clicked = true; }, { once: true });
    await press('Import Sound…');
    await tick();
    try {
      await waitFor(`Importing ${choice} replaced the selected sound or failed to settle`, () => {
        const sound = field<HTMLSelectElement>('Sound');
        return sound?.value === 'custom' && !sound.matches(':disabled') &&
          sound.selectedOptions[0]?.textContent === title;
      });
    } catch (error) {
      const native = await invoke<unknown>('read_notification_preferences');
      const sound = field<HTMLSelectElement>('Sound');
      throw new Error(`${error} ${JSON.stringify({clicked, selection: sound?.value, title: sound?.selectedOptions[0]?.textContent, native})}`);
    }
  }
  try {
    await waitFor('The notification checkout did not load', () =>
      !!visible()?.workspace && visible()?.navigation.writeAccess === 'ready' &&
      (visible()?.navigation.chats.length ?? 0) >= 2);
    await settings();
    await select('Task Completion', 'whenUnfocused');
    await pickSound('wav', 'Fixture WAV');
    await pickSound('aiff', 'Fixture AIFF');
    await pickSound('caf', 'Fixture CAF');
    await pickSound('invalid', 'Fixture CAF');
    await pickSound('long', 'Fixture CAF');
    await pickSound('cancel', 'Fixture CAF');
    await press('Close');
    await configure(false, true);
    await send('Notification fixture one');
    const owner = selected()!;
    if (!owner || owner === SECOND) throw new Error('The coding turn had no separate owner');
    const blocked = approval()!;
    const denied = await waitForOutcome('The denied approval was not evaluated', (state) => state.denied === 1);
    if (denied.delivered.length) throw new Error('Denied OS permission posted an alert');
    await configure(true, true);
    await switchAway();
    await respondApproval(blocked);
    const first = await waitForOutcome('The hidden question did not notify', (state) => state.delivered.length >= 1);
    if (first.delivered.length !== 1 || first.delivered[0]?.category !== 'question' ||
        first.delivered[0]?.key.chatId !== owner || selected() !== SECOND) {
      throw new Error('Enabling permission replayed the old alert or changed the visible chat');
    }
    await openAlert(0, owner);
    await waitFor('The notification target did not expose its question', () => !!question());
    await respondQuestion(question()!);
    await waitFor('The focused completion did not settle', noWrite);
    await configure(true, false);
    await settings();
    field<HTMLInputElement>('Questions')!.click();
    await tick();
    await waitFor('Changing the question setting did not settle', () => {
      const control = field<HTMLInputElement>('Questions');
      return control?.checked === false && !control.matches(':disabled');
    });
    await press('Close');

    await send('Notification fixture two');
    const working = await waitForOutcome('A permitted approval did not notify', (state) => state.delivered.length >= 2);
    if (working.delivered.length !== 2 || working.delivered[1]?.category !== 'permission' ||
        working.delivered[1]?.key.chatId !== owner) throw new Error('Changing focus replayed a completed turn');
    await respondApproval(approval()!);
    await waitFor('The second question did not arrive independently of its alert', () => !!question());
    const hidden = question()!;
    await switchAway();
    await respondQuestion(hidden);
    const finished = await waitForOutcome('The hidden unfocused completion did not notify', (state) => state.delivered.length >= 3);
    if (finished.delivered.map((entry) => entry.category).join() !== 'question,permission,completion' ||
        finished.delivered[2]?.key.chatId !== owner || selected() !== SECOND) {
      throw new Error('The hidden task completion changed notification category or owner');
    }
    await openAlert(2, owner);
    await waitFor('Opening the completion lost its exact chat history', () =>
      document.querySelector('.workspace-transcript')?.textContent?.includes('Notification fixture two') === true);
    await settings();
    field<HTMLInputElement>('Questions')!.click();
    await tick();
    await waitFor('Re-enabling the question preference did not settle', () => {
      const control = field<HTMLInputElement>('Questions');
      return control?.checked === true && !control.matches(':disabled');
    });
    const committed = await invoke<{questions: boolean}>('read_notification_preferences');
    if (!committed.questions) throw new Error('The question preference was still disabled on disk');
    await press('Close');
    if ((await outcomes()).delivered.length !== 3) throw new Error('Re-enabling a category replayed a previous question');
    await invoke('verify_notifications_result', { failure: null });
  } catch (error) {
    await invoke('verify_notifications_result', { failure: [String(error), ...errors.slice(-5)].join('\n') });
  } finally {
    console.error = report;
  }
}

async function waitForOutcome(description: string, ready: (outcome: Outcome) => boolean) {
  const deadline = performance.now() + 9000;
  do {
    const outcome = await outcomes();
    if (ready(outcome)) return outcome;
    await new Promise<void>((resolve) => setTimeout(resolve, 40));
  } while (performance.now() < deadline);
  throw new Error(description);
}
