import { invoke } from '@tauri-apps/api/core';
import type { DesktopVoice } from './desktopVoice';
import { click, clickByLabel, typeText, waitFor } from './fixtureControls';
import type { VoiceCallView, WorkspaceSnapshot } from './generated/workspace';
import type { VoiceMediaEvidence } from './voiceMedia';
import { navigateWorkspace, readProjectContext } from './projectIpc';

async function untilMedia(read: () => Promise<VoiceMediaEvidence>, matches: (value: VoiceMediaEvidence) => boolean) {
  const deadline = performance.now() + 9_000;
  for (;;) {
    const result = await read();
    if (matches(result)) return result;
    if (performance.now() > deadline) throw new Error('The voice media state did not settle: ' + JSON.stringify(result));
    await new Promise<void>((resolve) => setTimeout(resolve, 40));
  }
}

export async function verifyVoice(
  visible: () => WorkspaceSnapshot | null, current: () => VoiceCallView | null, voice: DesktopVoice,
) {
  const errors: string[] = [];
  const log = console.error;
  console.error = (...values) => { errors.push(values.map(String).join(' ')); log(...values); };
  const navigation = () => visible()?.navigation;
  const selected = () => navigation()?.selectedChat;
  const draft = () => navigation()?.draft;
  const floating = () => !!document.querySelector('.voice-floating');
  const inline = () => !!document.querySelector('.voice-controls:not(.voice-floating)');
  async function send(text: string) {
    typeText(text);
    await waitFor('The voice fixture message was not saved', () =>
      draft()?.text === text && navigation()?.actions.send === true);
    await click('Send');
    await waitFor('The voice fixture message was not acknowledged', () => draft()?.text === '');
  }

  try {
    await click('New Chat');
    await waitFor('The new-chat composer was not selected for voice', () => selected() === null && !!draft());
    const originalDraft = draft()!.id;
    await click('Start Voice Call');
    await waitFor('Realtime negotiation did not activate the creating chat', () => current()?.phase === 'active' &&
      selected() === current()?.chatId && draft()?.id === originalDraft && inline());
    const owner = current()!;
    const media = () => voice.fixtureMedia(owner);
    const duplex = await untilMedia(media, (value) => value.receiving && value.sending &&
      !value.microphoneMuted && !value.speakerMuted);

    await click('Mute Microphone');
    await untilMedia(media, (value) => value.microphoneMuted && !value.speakerMuted);
    await click('Second fixture chat');
    await waitFor('The call did not float over the other active chat', () => selected() === 'history-second' &&
      current()?.id === owner.id && floating());
    await click('Mute Speaker');
    await untilMedia(media, (value) => value.microphoneMuted && value.speakerMuted);
    await click('Unmute Microphone');
    await untilMedia(media, (value) => !value.microphoneMuted && value.speakerMuted);
    await send('A coding request in the other chat');
    await waitFor('The other chat did not finish the normal coding turn', () =>
      navigation()?.actions.stop === null && !!visible()?.transcript.items.some((row) =>
        row.role === 'assistant' && row.completed && row.text.includes('Completed the coding request.')));
    await click('New Voice Chat');
    await waitFor('Returning to the owner did not restore inline controls', () => selected() === owner.chatId &&
      current()?.id === owner.id && inline());
    await click('Unmute Speaker');
    await untilMedia(media, (value) => !value.microphoneMuted && !value.speakerMuted);
    await send('Text to the captured voice call');

    const workspaceId = visible()?.workspace?.workspaceId;
    if (!workspaceId || !draft()?.id) throw new Error('The call lost its composer owner');
    const scope = { workspaceId, chatId: owner.chatId, draftId: draft()!.id };
    await invoke('drop_composer_attachment_fixture', { scope });
    await waitFor('The voice fixture attachment did not arrive', () => draft()?.attachments.length === 1);
    await send('A coding request with an attachment');
    await waitFor('The attached coding turn did not finish during the call', () =>
      navigation()?.actions.stop === null && current()?.id === owner.id &&
      !!visible()?.transcript.items.some((row) => row.role === 'assistant' && row.completed &&
        row.text.includes('Completed the coding request.')));

    typeText('/skills');
    await waitFor('The slash command did not enter the captured composer', () => draft()?.text === '/skills');
    await click('Send');
    await clickByLabel('Add Review fixture');
    await waitFor('The slash command did not stage its skill', () =>
      draft()?.text === '' && draft()?.attachments.some((entry) => entry.label === 'Review fixture') === true);

    const project = await readProjectContext(scope);
    await navigateWorkspace({ editProjectContext: { scope, revision: project.revision, change: { saveItem: {
      id: null, kind: 'note', title: 'Voice fixture context', body: 'Preserve the captured project context.',
      referencePath: null, isIncluded: true,
    } } } });
    await waitFor('The project context did not become composer input', () => !!navigation()?.projectHasInput);
    await send('A coding request with project context and a skill');
    await waitFor('The structured coding turn did not settle during the call', () =>
      navigation()?.actions.stop === null && current()?.id === owner.id && draft()?.attachments.length === 0);
    const captured = await readProjectContext(scope);
    const entry = captured.context.items.find((item) => item.title === 'Voice fixture context');
    if (!entry) throw new Error('The voice fixture project note was not saved');
    await navigateWorkspace({ editProjectContext: { scope, revision: captured.revision, change: { removeItem: entry.id } } });
    await waitFor('The removed project context still occupies the draft', () => navigation()?.projectHasInput === false);

    await invoke('drop_composer_attachment_fixture', { scope });
    await waitFor('The held coding turn did not capture its attachment', () => draft()?.attachments.length === 1);
    await send('Hold this fixture turn');
    await waitFor('There is no active turn to queue on', () => !!navigation()?.queue?.activeTurn && !navigation()?.queue?.busy);
    if (!navigation()?.queue?.enabled) {
      await click('Queue Follow-ups');
      await waitFor('Queue follow-ups were not enabled', () => navigation()?.queue?.enabled === true);
    }
    typeText('Original queued input');
    await waitFor('The queued input was not persisted', () => draft()?.text === 'Original queued input');
    await click('Queue');
    await waitFor('The queued entry did not arrive', () =>
      navigation()?.queue?.entries[0]?.text === 'Original queued input' && draft()?.text === '');
    await click('Edit', document.querySelector('.workspace-queue')!);
    await waitFor('Queue editing did not populate the captured entry', () => !!navigation()?.queue?.editing);
    typeText('Revised queued input');
    await waitFor('The queue edit was not persisted', () => draft()?.text === 'Revised queued input');
    await click('Save Queue Edit');
    await waitFor('The saved queue edit did not update the entry', () =>
      !navigation()?.queue?.editing && navigation()?.queue?.entries[0]?.text === 'Revised queued input');
    await click('End Call');
    await waitFor('The closed call left capture controls mounted or changed the queue edit', () =>
      !current() && !inline() && !floating() && navigation()?.queue?.entries[0]?.text === 'Revised queued input');
    await invoke('verify_voice_result', { failure: null, evidence: { owner, duplex } });
  } catch (error) {
    await invoke('verify_voice_result', { failure: [String(error), ...errors.slice(-5)].join('\n'), evidence: {} });
  } finally {
    console.error = log;
  }
}
