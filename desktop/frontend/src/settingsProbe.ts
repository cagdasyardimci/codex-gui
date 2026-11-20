import { invoke } from '@tauri-apps/api/core';
import type { WorkspaceSnapshot } from './generated/workspace';
import { click, waitFor } from './fixtureControls';
import { closeSettings, openSettings, readSettingsInstructions, refreshSettings, saveSettingsInstructions, signOutSettings, writeSettings } from './settingsIpc';
import { rejectsStale } from './markdownProbe';

export async function verifySettings(visible: () => WorkspaceSnapshot | null) {
  const window = () => document.querySelector<HTMLDialogElement>('dialog[aria-label="Settings"][open]');
  const contains = (text: string) => window()?.textContent?.includes(text) === true;
  const profile = (name: string) => invoke('set_settings_fixture_profile', { profile: name });
  const refresh = () => click('Refresh Settings', window()!);
  const composerEffort = () => document.querySelector<HTMLSelectElement>('.composer-settings select[aria-label="Reasoning effort"]');
  const checkbox = (label: string) => [...(window()?.querySelectorAll<HTMLLabelElement>('label') ?? [])]
    .find((entry) => entry.textContent?.trim() === label)?.querySelector<HTMLInputElement>('input[type="checkbox"]');
  const configuration = (label: string) => window()?.querySelector<HTMLSelectElement>(`select[aria-label="${label}"]`);
  const settled = (label: string) => [...(window()?.querySelectorAll<HTMLButtonElement>('button') ?? [])]
    .some((button) => button.textContent === label && !button.disabled);
  try {
    await waitFor('The initial workspace account was missing', () => visible()?.navigation.account.identity === 'first@example.invalid');
    await click('First fixture chat');
    await waitFor('The captured chat did not receive the advertised effort', () =>
      visible()?.navigation.selectedChat === 'history-first' && [...(composerEffort()?.options ?? [])]
        .some((option) => option.value === 'minimal'));
    composerEffort()!.value = 'minimal';
    composerEffort()!.dispatchEvent(new Event('change', { bubbles: true }));
    await waitFor('The composer did not select the advertised effort', () =>
      visible()?.navigation.composerSettings?.selection.effort === 'minimal');
    await click('Settings');
    await waitFor('Settings did not read its own account', () => contains('first@example.invalid') && contains('openai'));
    await click('Usage & Billing', window()!);
    await waitFor('Usage did not distinguish missing values from zero', () => {
      const meters = [...window()!.querySelectorAll('meter')];
      const rows = [...window()!.querySelectorAll('tbody tr')].map((row) => [...row.children].map((cell) => cell.textContent?.trim()));
      return meters.length === 1 && meters[0]?.value === 0 && contains('Weekly Limit') &&
        JSON.stringify(rows) === JSON.stringify([['2026-10-28', '0'], ['2026-10-29', '250']]);
    });
    await click('Configuration', window()!);
    await waitFor('Settings did not display the effective managed policy', () =>
      contains('Managed Approval Policy') && contains('on-request') && contains('settings-fixture-model') &&
      !contains('fixture-secret-must-stay-native'));
    if (configuration('Approval Policy')) throw new Error('The managed approval policy was editable');
    const verbosity = configuration('Verbosity')!;
    verbosity.value = 'high';
    verbosity.dispatchEvent(new Event('change', { bubbles: true }));
    await click('Save Verbosity', window()!);
    await waitFor('The confirmed verbosity did not survive a reread of the user layer', () =>
      settled('Refresh Settings') && configuration('Verbosity')?.value === 'high');
    checkbox('Compress Local Chat History')!.click();
    await click('Save Compress Local Chat History', window()!);
    await waitFor('Compression did not survive a new Settings connection', () =>
      settled('Refresh Settings') && checkbox('Compress Local Chat History')?.checked === true);
    if (!checkbox('medium')?.disabled) throw new Error('A required effort could be hidden');
    checkbox('minimal')!.click();
    await waitFor('Changing effort visibility retargeted the current chat selection', () =>
      settled('Refresh Settings') && checkbox('minimal')?.checked === false &&
      visible()?.navigation.hiddenReasoningEfforts.includes('minimal') === true && composerEffort()?.value === 'minimal');

    await click('Close', window()!);
    await waitFor('Settings did not close after editing', () => !window());
    await click('Second fixture chat');
    await waitFor('The hidden effort was still offered to a chat without that selection', () =>
      visible()?.navigation.selectedChat === 'history-second' && !!composerEffort() &&
      ![...composerEffort()!.options].some((option) => option.value === 'minimal'));
    await click('First fixture chat');
    await waitFor('Reopening the original chat did not retain its hidden effort', () =>
      visible()?.navigation.selectedChat === 'history-first' && composerEffort()?.value === 'minimal');
    const edits = crypto.randomUUID();
    const beforeWrite = await openSettings(edits);
    const selection = { session: edits, revision: beforeWrite.revision };
    if (beforeWrite.compression?.enabled !== true) throw new Error('Compression reset when Settings reopened');
    await rejectsStale(writeSettings({ selection, key: 'approval_policy', value: 'never' }));
    const unconfirmed = await writeSettings({ selection, key: 'model_reasoning_summary', value: 'concise' });
    if (unconfirmed.confirmed || unconfirmed.view.configuration.find((entry) => entry.key === 'model_reasoning_summary')?.value !== 'detailed') {
      throw new Error('The unacknowledged write replayed or hid the newer value');
    }
    await profile('first');
    await rejectsStale(writeSettings({ selection: { session: edits, revision: unconfirmed.view.revision },
      key: 'model_verbosity', value: 'high' }));
    await closeSettings(edits);
    await click('Settings');
    await waitFor('Settings did not reopen after a version conflict', () => contains('first@example.invalid'));
    await click('Personalization', window()!);
    const instructions = () => window()?.querySelector<HTMLTextAreaElement>('textarea[aria-label="Codex Instructions"]');
    function editInstructions(text: string) {
      const field = instructions()!;
      field.value = text;
      field.dispatchEvent(new Event('input', { bubbles: true }));
    }
    await waitFor('Personalization did not expose the scoped memories and instructions', () =>
      !!checkbox('Enable Codex Memories') && instructions()?.readOnly === false);
    if (instructions()!.value !== '') throw new Error('Missing instructions did not open as an empty editor');
    checkbox('Enable Codex Memories')!.click();
    await click('Save Enable Codex Memories', window()!);
    await waitFor('The memory group did not publish its effective setting', () =>
      settled('Refresh Settings') && checkbox('Enable Codex Memories')?.checked === true &&
      checkbox('Allow Memories from Tool-assisted Chats')?.disabled === false);
    checkbox('Allow Memories from Tool-assisted Chats')!.click();
    await click('Save Allow Memories from Tool-assisted Chats', window()!);
    await waitFor('Tool-assisted memory policy did not persist', () =>
      settled('Refresh Settings') && checkbox('Allow Memories from Tool-assisted Chats')?.checked === false);
    await click('Delete Memories…', window()!);
    await click('Cancel', window()!);
    await waitFor('Cancelling memory deletion did not restore the original control', () => settled('Delete Memories…'));
    await click('Delete Memories…', window()!);
    await click('Delete Memories', window()!);
    await waitFor('Confirmed memory deletion did not return to Personalization', () =>
      settled('Delete Memories…') && instructions()?.readOnly === false);

    editInstructions('Created instructions café.\n');
    await click('Save Instructions', window()!);
    await waitFor('Saving from an absent instructions file did not establish a revision', () =>
      instructions()?.readOnly === false && !settled('Save Instructions') && instructions()?.value === 'Created instructions café.\n');
    await invoke('external_settings_instructions_fixture');
    const retainedText = 'Keep this unsaved draft 日本語.\n';
    editInstructions(retainedText);
    await click('Save Instructions', window()!);
    await waitFor('An external instructions edit replaced the unsaved draft', () =>
      instructions()?.value === retainedText && settled('Save Instructions'));
    await click('Reload Instructions…', window()!);
    await click('Cancel Reload', window()!);
    if (instructions()?.value !== retainedText) throw new Error('Cancelling reload replaced the editor draft');
    await click('Reload Instructions…', window()!);
    await click('Reload Instructions', window()!);
    await waitFor('Reload did not retrieve the external instructions', () =>
      instructions()?.value === 'External instructions\nReview the next draft.\n');
    editInstructions('# Final Codex instructions\nPreserve café and 日本語.\n');
    await click('Save Instructions', window()!);
    await waitFor('The reloaded instruction revision did not save', () =>
      instructions()?.readOnly === false && !settled('Save Instructions'));
    await click('Configuration', window()!);

    await profile('bedrock');
    await refresh();
    await waitFor('Refreshing the active Settings presentation retained the previous provider policy', () =>
      contains('bedrock') && contains('never') && !contains('on-request') &&
      checkbox('Compress Local Chat History')?.disabled === true);
    await click('Account', window()!);
    await waitFor('Provider change leaked the previous account or its mutation control', () =>
      contains('bedrock') && !contains('first@example.invalid') && !contains('Sign Out'));
    await click('Close', window()!);
    await waitFor('Closing Settings did not return to its originating control', () =>
      !window() && document.activeElement?.textContent === 'Settings');

    await profile('first');
    const stale = crypto.randomUUID();
    const captured = await openSettings(stale);
    if (!captured.account.canSignOut) throw new Error('The fixture account did not have sign-out authority');
    await profile('second');
    try {
      await signOutSettings({ session: stale, revision: captured.revision });
      throw new Error('A previous account retained sign-out authority');
    } catch (error) {
      if (error !== 'staleSelection') throw error;
    }
    await closeSettings(stale);

    await profile('delayed');
    const retired = crypto.randomUUID();
    const oldRead = openSettings(retired).then(() => 'published', (error: unknown) => error);
    let started = false;
    await waitFor('The old Settings session did not start its sensitive usage read', () => {
      if (!started) void invoke<boolean>('settings_usage_fixture_started').then((published) => { started ||= published; });
      return started;
    });
    await closeSettings(retired);
    await profile('second');
    const fresh = crypto.randomUUID();
    const newView = await openSettings(fresh);
    if (newView.account.email !== 'second@example.invalid' || await oldRead === 'published') {
      throw new Error('A retired sensitive read crossed Settings sessions');
    }
    try {
      await refreshSettings(retired);
      throw new Error('A closed Settings presentation could refresh its backend');
    } catch (error) {
      if (error !== 'staleSelection') throw error;
    }
    const instructionRevision = (await readSettingsInstructions(fresh)).revision;
    await closeSettings(fresh);
    await rejectsStale(saveSettingsInstructions({ session: fresh, revision: instructionRevision, text: 'Retired edit' }));

    await click('Settings');
    await waitFor('Reopening Settings did not show only the current account', () => contains('second@example.invalid') &&
      !contains('first@example.invalid'));
    await click('Sign Out…', window()!);
    await click('Cancel', window()!);
    await waitFor('Cancelling sign-out changed the captured account', () => contains('second@example.invalid') && contains('Sign Out…'));
    await click('Sign Out…', window()!);
    await click('Sign Out', window()!);
    await waitFor('Confirmed sign-out did not retire both account projections', () => {
      const settled = [...window()!.querySelectorAll<HTMLButtonElement>('button')].some((button) =>
        button.textContent === 'Refresh Settings' && !button.disabled);
      return settled && !contains('second@example.invalid') && !contains('Sign Out') &&
        visible()?.navigation.account.identity === null && visible()?.navigation.account.permitsTurns === false;
    });
    await invoke('verify_account_result', { failure: null });
  } catch (error) {
    await invoke('verify_account_result', { failure: String(error) });
  }
}
