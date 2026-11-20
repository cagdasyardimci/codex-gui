import { invoke } from '@tauri-apps/api/core';
import { click, editor, typeText, waitFor } from './fixtureControls';
import type { InteractionView, WorkspaceSnapshot } from './generated/workspace';
import { navigateWorkspace } from './projectIpc';

const HELD = 'Hold this fixture turn';
const PRESERVED = 'Draft retained while a background turn runs 日本語';
const OTHER = 'history-second';
const ANSWER = 'Faster typing 日本語';
const REPLY = 'Answered in order. Unicode reply 日本語 👩🏽‍💻.';
const QUESTION_TEXT = `What would you like to improve?\n${ANSWER}\n\nWhich part of codex-gui would you like to review?\nComposer\nSettings`;

function transcriptText() {
  return document.querySelector('.workspace-transcript')?.textContent ?? '';
}

async function send(visible: () => WorkspaceSnapshot | null, text: string) {
  typeText(text);
  await waitFor('The displayed text was not retained for Send', () =>
    visible()?.navigation.draft?.text === text && !!visible()?.navigation.actions.send);
  await click('Send');
}

function pendingApproval(visible: () => WorkspaceSnapshot | null) {
  return visible()?.navigation.actions.interactions.find((request) => 'approval' in request.content);
}

function completeAnswers() {
  const fields = [...document.querySelectorAll('.interaction-card input')];
  const free = fields.find((field): field is HTMLInputElement => field instanceof HTMLInputElement && field.type === 'text');
  if (!free) throw new Error('The free-text question was missing');
  free.value = ANSWER;
  free.dispatchEvent(new InputEvent('input', { bubbles: true }));
  for (const label of ['Composer', 'Settings']) {
    const option = [...document.querySelectorAll('.interaction-option')]
      .find((element) => element.textContent?.trim() === label)
      ?.querySelector<HTMLInputElement>('input[type=checkbox]');
    if (!option) throw new Error(`The option ${label} was missing`);
    option.click();
  }
}

async function verifyCompletedTurn(visible: () => WorkspaceSnapshot | null) {
  const workspaceId = visible()?.workspace?.workspaceId;
  if (!workspaceId) throw new Error('The fixture lost its project authority');
  await send(visible, 'Recover this fixture receipt');
  await waitFor('An unresolved send did not expose recovery', () =>
    !!visible()?.navigation.actions.recover && editor().value === 'Recover this fixture receipt');
  const originalChat = visible()?.navigation.selectedChat;
  if (!originalChat) throw new Error('Preparing Send did not adopt the assigned chat');
  await click('Recover Send');
  await waitFor('Recovery did not clear the matched submitted draft', () =>
    !visible()?.navigation.actions.recover && editor().value === '');
  await click('Refresh');
  await waitFor('The recovered message was missing from canonical history', () =>
    transcriptText().includes('Recover this fixture receipt'));

  await send(visible, 'Fixture mixed questions');
  await waitFor('The approval did not reach the active chat', () => !!pendingApproval(visible));
  const approval: InteractionView | undefined = pendingApproval(visible);
  if (!approval || !('approval' in approval.content)) throw new Error('The approval was lost');
  const approve = approval.content.approval.choices.find((choice) => choice.label === 'Approve');
  if (!approve) throw new Error('The offered approval decision was missing');
  const row = visible()?.navigation.chats.find((chat) => chat.id === originalChat);
  if (!row) throw new Error('The original chat row was missing');
  await click('Second fixture chat');
  await waitFor('Switching chats showed the other chat’s approval', () =>
    visible()?.navigation.selectedChat === OTHER && !visible()?.navigation.actions.interactions.length);
  await navigateWorkspace({ respond: { workspaceId, interactionId: approval.id, response: { decision: approve.index } } });
  await click(row.title);
  await waitFor('The original chat did not enable its question controls', () => {
    const fields = [...document.querySelectorAll('.interaction-card input')];
    return visible()?.navigation.selectedChat === originalChat &&
      !!visible()?.navigation.actions.interactions.some((request) => 'questions' in request.content) &&
      fields.length > 0 && fields.every((field) => !field.matches(':disabled'));
  });
  completeAnswers();
  await click('Submit Answers');
  await waitFor('The transcript did not render the ordered questions and answers', () =>
    transcriptText().includes(QUESTION_TEXT) && transcriptText().includes(REPLY) &&
    visible()?.navigation.actions.stop === null);
  await click('Refresh');
  await waitFor('The chat preview did not normalize the ordered reply envelope', () =>
    visible()?.navigation.chats.find((chat) => chat.id === originalChat)?.preview === QUESTION_TEXT &&
    document.querySelector('.chat-row[aria-current="true"] .chat-preview')?.getAttribute('title') === QUESTION_TEXT);
  await click('Changes');
  await click('workflow-notes.txt');
  await waitFor('The captured turn did not publish its attributed edit totals', () => {
    const report = visible()?.navigation.lastTurn;
    return report?.quality === 'exact' && report.totals?.additions === 1 && report.totals.deletions === 1;
  });
  await waitFor('The completed turn’s edit was missing from the selected Git patch', () => {
    const patch = document.querySelector('[aria-label="Patch"]')?.textContent;
    return !!patch?.includes('-Before fixture approval') && patch.includes('+After fixture approval 日本語');
  });
  const comparison = document.querySelector<HTMLSelectElement>('select[aria-label="Comparison"]')!;
  comparison.value = JSON.stringify('lastTurn');
  comparison.dispatchEvent(new Event('change', { bubbles: true }));
  await waitFor('The Git detail was not retired before opening the Last Turn report', () =>
    !document.querySelector('[aria-label="Patch"]'));
  await click('workflow-notes.txt');
  await waitFor('Last Turn did not expose the exact attributed report', () => {
    const patch = document.querySelector('[aria-label="Patch"]')?.textContent;
    return !!patch?.includes('-Before fixture approval') && patch.includes('+After fixture approval 日本語');
  });
}

async function verifyActiveTurn(visible: () => WorkspaceSnapshot | null): Promise<boolean> {
  if (visible()?.navigation.selectedChat === OTHER) {
    const target = visible()?.navigation.actions.stop;
    if (!target || !('turn' in target) || target.turn.threadId === OTHER) {
      throw new Error('Reload retargeted the active turn');
    }
    const title = visible()?.navigation.chats.find((chat) => chat.id === target.turn.threadId)?.title;
    if (!title) throw new Error('The original chat was missing');
    await click(`Stop ${title}`);
    await waitFor('The captured turn did not stop', () =>
      visible()?.navigation.actions.stop === null &&
      visible()?.navigation.selectedChat === OTHER &&
      transcriptText().includes('History in the second chat.'));
    await click(title);
    await waitFor('Returning to the original chat lost its draft', () =>
      visible()?.navigation.selectedChat === target.turn.threadId &&
      visible()?.navigation.draft?.text === PRESERVED && editor().value === PRESERVED);
    return true;
  }
  await send(visible, HELD);
  await waitFor('The continuing turn did not begin', () => {
    const target = visible()?.navigation.actions.stop;
    return !!target && 'turn' in target && target.turn.threadId === visible()?.navigation.selectedChat &&
      visible()?.navigation.draft?.text === '';
  });
  typeText(PRESERVED);
  await waitFor('The active chat’s draft was not saved', () => visible()?.navigation.draft?.text === PRESERVED);
  await click('Second fixture chat');
  await waitFor('Switching away lost the captured turn', () =>
    visible()?.navigation.selectedChat === OTHER && !!visible()?.navigation.actions.stop &&
    transcriptText().includes('History in the second chat.'));
  window.location.reload();
  return false;
}

export async function verifyTurn(visible: () => WorkspaceSnapshot | null, mode: 'turn' | 'activeTurn') {
  try {
    await waitFor('The fixture project did not load', () =>
      !!visible()?.workspace && (visible()?.navigation.chats.length ?? 0) >= 2 &&
      visible()?.navigation.writeAccess === 'ready');
    if (mode === 'activeTurn') {
      if (!await verifyActiveTurn(visible)) return;
    } else {
      await verifyCompletedTurn(visible);
    }
    await invoke('verify_turn_result', { failure: null });
  } catch (error) {
    await invoke('verify_turn_result', { failure: String(error) });
  }
}
