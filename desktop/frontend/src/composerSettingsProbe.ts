import { invoke } from '@tauri-apps/api/core';
import type { DraftAttachmentScope, WorkspaceSnapshot } from './generated/workspace';
import { navigateWorkspace } from './projectIpc';
import { click, typeText, waitFor } from './fixtureControls';
import { rejectsStale } from './markdownProbe';

const FIRST = 'history-first';

export async function verifyComposerSettings(visible: () => WorkspaceSnapshot | null) {
  try {
    const settings = () => visible()?.navigation.composerSettings;
    const selected = () => settings()?.selection;
    const fullDialog = () => document.querySelector('dialog[aria-label="Full Access"][open]');
    await click('First fixture chat');
    await waitFor('The composer did not load configured permissions and model metadata', () =>
      visible()?.navigation.selectedChat === FIRST && settings()?.effectiveModelId === 'baseline-model' &&
      selected()?.permissions === 'configured');
    const workspaceId = visible()?.workspace?.workspaceId;
    const draftId = visible()?.navigation.draft?.id;
    if (!workspaceId || !draftId) throw new Error('The composer setting owner was missing');
    const scope: DraftAttachmentScope = { workspaceId, chatId: FIRST, draftId };

    await pick('Model', 'alternative-model');
    await waitFor('The alternative model was not selected', () => selected()?.modelId === 'alternative-model');
    await pick('Reasoning effort', 'high');
    await waitFor('The advertised effort was not selected', () => selected()?.effort === 'high');
    await pick('Speed', 'fixture-turbo');
    await waitFor('The model-specific speed was not selected', () => selected()?.serviceTier === 'fixture-turbo');
    await pick('Permissions', 'approveForMe');
    await waitFor('The review preset was not selected', () => selected()?.permissions === 'approveForMe');

    await pick('Permissions', 'fullAccess');
    await waitFor('Full Access was not presented for confirmation', () => !!fullDialog());
    await click('Cancel');
    await waitFor('Cancelling Full Access changed permissions', () => !fullDialog() && selected()?.permissions === 'approveForMe');
    const captured = settings()!;
    const fullRequest = { scope, revision: captured.revision,
      selection: { ...captured.selection, permissions: 'fullAccess' as const }, confirmFullAccess: false };
    await rejectsStale(navigateWorkspace({ setComposerSettings: fullRequest }));
    await click('Second fixture chat');
    await waitFor('The other chat inherited the settings', () => visible()?.navigation.selectedChat === 'history-second' &&
      selected()?.permissions === 'configured');
    await rejectsStale(navigateWorkspace({ setComposerSettings: { ...fullRequest, confirmFullAccess: true } }));
    await click('First fixture chat');
    await waitFor('The original chat did not restore its selections', () => visible()?.navigation.selectedChat === FIRST &&
      selected()?.modelId === 'alternative-model' && selected()?.effort === 'high' &&
      selected()?.serviceTier === 'fixture-turbo' && selected()?.permissions === 'approveForMe');

    const beginTurn = async (text: string) => {
      typeText(text);
      await waitFor('The settings fixture did not persist the prompt', () => visible()?.navigation.draft?.text === text);
      await click('Send');
      await waitFor('The settings fixture did not admit Send', () => !!visible()?.navigation.actions.stop);
    };
    const settle = () => waitFor('The settings fixture turn did not finish', () =>
      visible()?.navigation.actions.stop === null && visible()?.navigation.draft?.text === '');

    await beginTurn('Capture the first settings.');
    await pick('Speed', 'default');
    await waitFor('The in-flight settings change did not apply', () => selected()?.serviceTier === 'default');
    await pick('Permissions', 'fullAccess');
    await waitFor('The confirmation did not reopen for the original workspace', () => !!fullDialog());
    await click('Enable Full Access');
    await waitFor('Full Access was not applied to the captured chat', () => selected()?.permissions === 'fullAccess');
    await settle();
    await beginTurn('Use confirmed Full Access.');
    await settle();

    await pick('Model', '');
    await waitFor('Configured Model did not restore the baseline effort catalog', () =>
      settings()?.effectiveModelId === 'baseline-model' && selected()?.effort === null);
    await pick('Permissions', 'configured');
    await waitFor('Configured Permissions did not replace the preset', () => selected()?.permissions === 'configured');
    await pick('Speed', '');
    await waitFor('Configured Speed did not replace the explicit setting', () => selected()?.serviceTier === null);
    await beginTurn('Use configured permissions.');
    await settle();
    await invoke('verify_attachments_result', { failure: null });
  } catch (error) {
    await invoke('verify_attachments_result', { failure: String(error) });
  }
}

async function pick(label: string, value: string) {
  const select = () => document.querySelector<HTMLSelectElement>(`select[aria-label="${CSS.escape(label)}"]:enabled`);
  await waitFor(`The ${label} control did not offer ${value}`, () => !![...(select()?.options ?? [])].find((option) => option.value === value));
  const field = select()!;
  field.value = value;
  field.dispatchEvent(new Event('change', { bubbles: true }));
}
