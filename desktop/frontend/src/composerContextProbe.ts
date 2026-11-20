import { invoke } from '@tauri-apps/api/core';
import { addComposerContext, composerContextCatalog } from './projectIpc';
import type { DraftAttachmentScope, WorkspaceSnapshot } from './generated/workspace';
import { click, clickByLabel, editor, typeText, waitFor } from './fixtureControls';
import { rejectsStale } from './markdownProbe';

const FIRST = 'history-first';
const ORIGINAL = 'Select this exact phrase.';
const TOKEN_TEXT = 'Before 👩🏽‍💻 @Review after';
const REPLACED = 'Before 👩🏽‍💻  after';
const LABELS = ['notes.txt', 'notes.txt:2–3', 'Review fixture', 'Project note'];

export async function verifyComposerContext(visible: () => WorkspaceSnapshot | null) {
  try {
    const draft = () => visible()?.navigation.draft;
    const labels = () => draft()?.attachments.map((attachment) => attachment.label).join('\n');
    await click('First fixture chat');
    await waitFor('The context draft did not load', () => visible()?.navigation.selectedChat === FIRST && !!draft());
    const workspaceId = visible()?.workspace?.workspaceId;
    const draftId = draft()?.id;
    if (!workspaceId || !draftId) throw new Error('The context draft had no owner');
    const scope: DraftAttachmentScope = { workspaceId, chatId: FIRST, draftId };
    await invoke('seed_composer_context_fixture', { scope });
    typeText(ORIGINAL);
    await waitFor('The context fixture did not persist the draft', () => draft()?.text === ORIGINAL);
    editor().setSelectionRange(7, 11);
    await click('Add Context');
    const picker = await filter('notes');
    await click('notes.txt', picker);
    await waitFor('The plus menu did not preserve text and selection', () => labels() === LABELS[0] &&
      editor().value === ORIGINAL && document.activeElement === editor() &&
      editor().selectionStart === 7 && editor().selectionEnd === 11);

    await click('Add Context');
    await filter('notes');
    await clickByLabel('Select lines in notes.txt');
    await setNumber('First line', '2');
    await setNumber('Last line', '3');
    await click('Add Code Range');
    await waitFor('The selected source range did not join the draft', () => labels() === LABELS.slice(0, 2).join('\n'));

    const control = editor();
    control.value = TOKEN_TEXT;
    const caret = TOKEN_TEXT.indexOf(' after');
    control.setSelectionRange(caret, caret);
    control.dispatchEvent(new InputEvent('input', { bubbles: true }));
    await clickByLabel('Add Review fixture');
    await waitFor('Selecting a skill did not replace just the active token', () => labels() === LABELS.slice(0, 3).join('\n') &&
      editor().value === REPLACED && draft()?.text === REPLACED && document.activeElement === editor() &&
      editor().selectionStart === TOKEN_TEXT.indexOf('@'));

    await click('Add Context');
    await clickByLabel('Add Project note');
    await waitFor('The project context did not preserve pending text', () => labels() === LABELS.join('\n') && draft()?.text === REPLACED);
    const choices = await composerContextCatalog(scope);
    const skill = choices.find((choice) => choice.label === LABELS[2]);
    if (!skill || choices.some((choice) => choice.label === 'Disabled fixture')) throw new Error('The skill catalog exposed an invalid choice');
    await click('Second fixture chat');
    await waitFor('The other chat inherited composer context', () => visible()?.navigation.selectedChat === 'history-second' && !labels());
    await rejectsStale(addComposerContext({ scope, expectedText: REPLACED, replaceToken: null, replaceCommand: null,
      target: { catalog: skill.id } }));
    await click('First fixture chat');
    await waitFor('Reopening the chat did not restore its selected context', () => labels() === LABELS.join('\n') && editor().value === REPLACED);
    await click('Send');
    await waitFor('The context turn did not complete', () => !labels() && visible()?.navigation.actions.stop === null &&
      !!visible()?.transcript.items.some((item) => item.text === 'The attachment was received.'));
    await invoke('verify_attachments_result', { failure: null });
  } catch (error) {
    await invoke('verify_attachments_result', { failure: String(error) });
  }
}

async function filter(query: string) {
  const control = () => document.querySelector<HTMLInputElement>('input[aria-label="Search context"]');
  await waitFor('The context picker did not offer search', () => !!control());
  const field = control()!;
  field.value = query;
  field.dispatchEvent(new InputEvent('input', { bubbles: true }));
  const picker = field.closest('.composer-context-picker');
  if (!picker) throw new Error('The context search had no owning picker');
  return picker;
}

async function setNumber(label: string, value: string) {
  const field = () => [...document.querySelectorAll<HTMLInputElement>('.composer-context-range input')]
    .find((input) => input.labels?.[0]?.textContent?.trim() === label);
  await waitFor(`The context picker did not offer ${label}`, () => !!field());
  const input = field()!;
  input.value = value;
  input.dispatchEvent(new InputEvent('input', { bubbles: true }));
}
