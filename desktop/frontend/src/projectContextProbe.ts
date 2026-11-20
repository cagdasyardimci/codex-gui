import { invoke } from '@tauri-apps/api/core';
import type { DraftAttachmentScope, ProjectContextChange, WorkspaceSnapshot } from './generated/workspace';
import { click, clickByLabel, typeText, waitFor } from './fixtureControls';
import { rejectsStale } from './markdownProbe';
import { navigateWorkspace, readProjectContext } from './projectIpc';

const FIRST = 'history-first';
const SECOND = 'history-second';
const TITLE = 'Release design';
const PROMPT = 'Release review';
const INSTRUCTIONS = 'Review the migration boundaries.';
const DRAFT = 'Keep this draft.';

export async function verifyProjectContext(visible: () => WorkspaceSnapshot | null) {
  try {
    const draft = () => visible()?.navigation.draft;
    const selected = () => visible()?.navigation.selectedChat;
    const scope = (): DraftAttachmentScope => {
      const workspaceId = visible()?.workspace?.workspaceId;
      const draftId = draft()?.id;
      if (!workspaceId || !draftId) throw new Error('Project Context lost its project or draft owner');
      return { workspaceId, chatId: selected() ?? null, draftId };
    };
    const edit = (scope: DraftAttachmentScope, revision: number, change: ProjectContextChange) =>
      navigateWorkspace({ editProjectContext: { scope, revision, change } });

    await click('First fixture chat');
    await waitFor('The first draft and model list did not load', () => selected() === FIRST &&
      !!draft() && !!visible()?.navigation.account.models.find((model) => model.id === 'alternative-model'));
    const first = scope();
    await invoke('seed_composer_context_fixture', { scope: first });
    const original = await readProjectContext(first);
    await click('Project Context');
    await click('Add Context Item');
    await setField('Title', TITLE);
    await setField('Type', 'decision');
    await setField('Content', 'Use the release fixture.');
    await setField('Reference Path', 'notes.txt');
    await click('Save Context Item');
    await click(TITLE);
    await setField('Content', 'Qualify the captured build.');
    await click('Save Context Item');
    await waitFor('The context edit form did not save', () => !field('Content'));
    const context = await readProjectContext(first);
    const note = context.context.items.find((item) => item.title === TITLE);
    if (!note || note.body !== 'Qualify the captured build.') throw new Error('Context content changed after Save');
    await rejectsStale(edit(first, original.revision, { removeItem: note.id }));

    await toggle('Include Release design');
    await waitFor('The selected item did not become submission context', () => !!visible()?.navigation.projectHasInput);
    await toggle('Include Release design');
    await waitFor('Disabling the item did not remove submission context', () => visible()?.navigation.projectHasInput === false);
    await toggle('Include Release design');
    await waitFor('Re-enabling the item did not restore submission context', () => !!visible()?.navigation.projectHasInput);
    await click('Add Context Item');
    await setField('Title', 'Temporary decision');
    await click('Save Context Item');
    await click('Temporary decision');
    await click('Remove Context Item');
    await waitFor('Removed context is still editable', () => !field('Content'));

    await click('Add Saved Prompt');
    await setField('Prompt Title', PROMPT);
    await setField('Instructions', 'Original text.');
    await click('Save Prompt');
    await click(PROMPT);
    await setField('Instructions', INSTRUCTIONS);
    await click('Save Prompt');
    await waitFor('The saved prompt did not close after editing', () => !field('Instructions'));
    await click('Add Saved Prompt');
    await setField('Prompt Title', 'Temporary prompt');
    await setField('Instructions', 'Remove this prompt.');
    await click('Save Prompt');
    await click('Temporary prompt');
    await click('Remove Saved Prompt');
    await waitFor('Removed prompt is still editable', () => !field('Instructions'));

    await setField('Default Model', 'alternative-model');
    await setField('Default Effort', 'high');
    await click('Save Model Defaults');
    await waitFor('The composer did not adopt the project model', () =>
      visible()?.navigation.composerSettings?.effectiveModelId === 'alternative-model');
    const skills = () => field<HTMLSelectElement>('Default Skill');
    await waitFor('The project skill catalog did not load', () =>
      [...(skills()?.options ?? [])].some((option) => option.label === 'Review fixture'));
    await setField('Default Skill', [...skills()!.options].find((option) => option.label === 'Review fixture')!.value);
    await waitFor('The skill was not retained', () => skills()?.value === 'selected');
    const captured = await readProjectContext(first);
    const prompt = captured.context.savedPrompts.find((prompt) => prompt.title === PROMPT);
    if (!prompt || prompt.instructions !== INSTRUCTIONS) throw new Error('The edited prompt was not retained');

    typeText(DRAFT);
    await waitFor('The first draft was not saved', () => draft()?.text === DRAFT);
    await click('Second fixture chat');
    await waitFor('The second draft did not open', () => selected() === SECOND && draft()?.id !== first.draftId);
    await rejectsStale(edit(first, captured.revision, { insertPrompt: { id: prompt.id, expectedText: DRAFT } }));
    await rejectsStale(edit(first, captured.revision, { removeItem: note.id }));
    await click('Original fixture response');
    await waitFor('The saved bookmark did not target the old response', () =>
      selected() === FIRST && visible()?.navigation.turnRail?.jump?.itemId === 'first-saved-turn/first-history' &&
      document.querySelector('[data-transcript-slot="first-saved-turn/first-history"]') !== null);
    if (draft()?.text !== DRAFT) throw new Error('Bookmark navigation changed the preserved draft');

    await click('Project Context');
    await clickByLabel(`Insert ${PROMPT}`);
    await waitFor('The saved prompt did not extend the draft without sending', () =>
      draft()?.text === `${DRAFT}\n\n${INSTRUCTIONS}` && !visible()?.navigation.actions.stop);
    await click('Send');
    await waitFor('The captured draft was not admitted', () => !!visible()?.navigation.actions.stop);
    await waitFor('The Project Context turn did not finish', () => !visible()?.navigation.actions.stop && draft()?.text === '');

    await click('Clear Project');
    await waitFor('The captured project grant was not retired', () => !visible()?.workspace);
    await edit(first, captured.revision, { removeItem: note.id }).then(() => {
      throw new Error('A retired checkout accepted a project edit');
    }, (error) => {
      if (error !== 'retiredWorkspace') throw error;
    });
    await invoke('verify_attachments_result', { failure: null });
  } catch (error) {
    await invoke('verify_attachments_result', { failure: String(error) });
  }
}

function field<T extends HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement = HTMLInputElement>(name: string) {
  const labels = document.querySelectorAll('aside[aria-label="Project Context"] label');
  const label = [...labels].find((label) => [...label.childNodes]
    .filter((node) => node.nodeType === Node.TEXT_NODE).map((node) => node.textContent).join('').trim() === name);
  return label?.querySelector<T>('input,select,textarea') ?? undefined;
}

async function setField(name: string, value: string) {
  await waitFor(`The ${name} field was not available`, () => !!field(name) && !field(name)?.disabled);
  const input = field(name)!;
  input.value = value;
  input.dispatchEvent(new Event(input instanceof HTMLSelectElement ? 'change' : 'input', { bubbles: true }));
}

async function toggle(name: string) {
  await waitFor(`The ${name} checkbox was not available`, () => !!field(name) && !field(name)?.disabled);
  field(name)!.click();
}
