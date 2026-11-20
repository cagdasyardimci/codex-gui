import { invoke } from '@tauri-apps/api/core';
import type { ChildHistoryTarget, WorkspaceSnapshot } from './generated/workspace';
import { click, clickByLabel, waitFor } from './fixtureControls';
import { rejectsStale } from './markdownProbe';
import { navigateWorkspace, openInspectorSource, readChildHistory, readInspectorSourceDetail, revealInspectorAttachment } from './projectIpc';

const FIRST = 'history-first';
const SECOND = 'history-second';
const WEB = 'https://example.invalid/guide';

export async function verifyInspector(visible: () => WorkspaceSnapshot | null) {
  const selected = () => visible()?.navigation.selectedChat;
  const inspector = (kind: string) => document.querySelector(`aside[aria-label="${kind} Inspector"]`);
  try {
    await click('First fixture chat');
    await waitFor('The first chat did not inspect its own sources and subagents', () =>
      selected() === FIRST && visible()?.navigation.inspector.agents.length === 2 &&
      visible()?.navigation.inspector.sources.length === 2);
    const workspaceId = visible()!.workspace!.workspaceId;
    const first = { workspaceId, chatId: FIRST };
    const attachment = visible()!.transcript.items.find((row) => row.attachments.length)!;
    const media = {
      row: { ...first, itemId: attachment.itemId, generation: visible()!.transcript.generation, revision: attachment.revision },
      attachmentId: attachment.attachments[0]!.id,
    };
    await clickByLabel('Inspect inspector.png');
    await waitFor('The summary source did not open the captured preview', () =>
      !!inspector('Sources')?.querySelector('img[alt="inspector.png"]'));
    await click('Show Source in Folder');
    await revealInspectorAttachment(media);

    await click(WEB);
    await click('Open Source');
    const webSource = visible()!.navigation.inspector.sources.find((source) => source.label === WEB)!;
    const savedSource = { scope: first, sourceId: webSource.id, revision: webSource.revision };
    await openInspectorSource(savedSource);
    await rejectsStale(openInspectorSource({ ...savedSource, sourceId: 'unrecorded-link' }));
    await click('fixture · lookup');
    await waitFor('The source inspector did not show the recorded invocation output', () =>
      inspector('Sources')?.querySelector('[aria-label="Source Details"]')?.textContent?.includes('Lookup fixture result') === true);
    const detail = visible()!.navigation.inspector.sources.find((source) => source.label === 'fixture · lookup')!;
    const savedDetail = { scope: first, sourceId: detail.id, revision: detail.revision };
    await rejectsStale(readInspectorSourceDetail({ ...savedDetail, revision: crypto.randomUUID() }));

    await click('Second fixture chat');
    await waitFor('Switching chats carried the previous inspector or its sources', () =>
      selected() === SECOND && !inspector('Sources') && visible()?.navigation.inspector.agents.length === 0);
    await rejectsStale(openInspectorSource(savedSource));
    await rejectsStale(readInspectorSourceDetail(savedDetail));
    await rejectsStale(revealInspectorAttachment(media));
    await click('Commands');
    await click('second command');
    await waitFor('The command inspector did not show the owning chat output', () =>
      inspector('Commands')?.querySelector('[aria-label="Command Output"]')?.textContent === 'second output');

    await click('First fixture chat');
    await waitFor('Returning did not restore the chat-specific source selection', () =>
      selected() === FIRST &&
      inspector('Sources')?.querySelector('[aria-label="Source Details"]')?.textContent?.includes('Lookup fixture result') === true);
    await click('Subagents');
    await click('Review notes');
    await waitFor('The live child read did not receive the coalesced update', () =>
      inspector('Subagents')?.textContent?.includes('The child reported an updated result.') === true);
    const child = inspector('Subagents')!;
    if (child.querySelector('[data-child-item="child-turn-01/response"]')) throw new Error('Earlier child history was already rendered');
    await click('Load Earlier Messages');
    await waitFor('The child page did not prepend earlier results', () =>
      !!child.querySelector('[data-child-item="child-turn-01/response"]') &&
      child.textContent?.includes('The child reported an updated result.') === true && selected() === FIRST);
    await click('Back to Subagents');
    const unknown: ChildHistoryTarget = { scope: first, agentId: 'unrecorded-child', selection: crypto.randomUUID() };
    await rejectsStale(readChildHistory({ target: unknown, action: 'open' }));
    const slow: ChildHistoryTarget = { scope: first, agentId: 'inspector-child-slow', selection: crypto.randomUUID() };
    const retired = rejectsStale(readChildHistory({ target: slow, action: 'open' }));
    await navigateWorkspace({ openChat: { workspaceId, chatId: SECOND } });
    await retired;
    await waitFor('The late child read replaced the destination chat’s inspector', () =>
      selected() === SECOND && !inspector('Subagents') &&
      inspector('Commands')?.querySelector('[aria-label="Command Output"]')?.textContent === 'second output');
    await invoke('verify_attachments_result', { failure: null });
  } catch (error) {
    await invoke('verify_attachments_result', { failure: String(error) });
  }
}
