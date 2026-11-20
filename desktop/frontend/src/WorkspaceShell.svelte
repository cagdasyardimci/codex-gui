<script lang="ts">
  import { onMount, tick } from 'svelte';
  import type { DraftEdit, InteractionAnswer, NavigationIntent, QueueCommand, TranscriptItem, WorkspaceSnapshot } from './generated/workspace';
  import InteractionCard from './InteractionCard.svelte';
  import QuitDialog from './QuitDialog.svelte';
  import WorkspaceChanges from './WorkspaceChanges.svelte';
  import QueuePanel from './QueuePanel.svelte';
  import TranscriptRow from './TranscriptRow.svelte';
  import { copyTranscriptRow, navigateWorkspace, observeWorkspace, pickWorkspace } from './projectIpc';
  import { verifyHistory } from './historyProbe';
  import { verifyAccount } from './accountProbe';
  import { verifyWindowsSetup } from './windowsSetupProbe';
  import { verifyTurn } from './turnProbe';
  import { verifyQueue } from './queueProbe';
  import { verifyDiff } from './diffProbe';
  import { verifyQuit } from './quitProbe';
  import './workspace.css';

  let { verify }: { verify?: 'initial' | 'restore' | 'account' | 'windowsSetup' | 'turn' | 'activeTurn' | 'queue' | 'diff' | 'quit' } = $props();
  let snapshot = $state<WorkspaceSnapshot | null>(null);
  let editor = $state<HTMLTextAreaElement>();
  let transcript = $state<HTMLDivElement>();
  let restoreTabSelection: (() => void) | undefined;
  let draftId: string | undefined;
  let text = $state('');
  let composing = false;
  let actionPending = $state(false);
  let admittingDraft = $state(false);
  let showingChanges = $state(false);
  let confirmingQuit = $state(false);
  let quietQuitTicket: string | undefined;
  let pending: DraftEdit | null = null;
  let saving: Promise<void> | null = null;
  const workspace = $derived(snapshot?.workspace);
  const navigation = $derived(snapshot?.navigation);
  const stopTarget = $derived(navigation?.actions.stop);
  const quit = $derived(navigation?.quit);
  const queue = $derived(navigation?.queue);
  const resumeCommand = $derived(queue?.resume ? { resume: queue.resume } :
    queue?.resumeSaved ? { resumeSaved: queue.resumeSaved } : null);

  function copyResponse(item: TranscriptItem) {
    const chatId = snapshot?.navigation.selectedChat;
    if (!snapshot?.workspace || !chatId) return;
    return copyTranscriptRow({ workspaceId: snapshot.workspace.workspaceId, chatId,
      itemId: item.itemId, generation: snapshot.transcript.generation, revision: item.revision });
  }

  function retainSelectionForTab() {
    restoreTabSelection = undefined;
    const selection = window.getSelection();
    if (!selection || selection.isCollapsed || !transcript) return;
    const { anchorNode, anchorOffset, focusNode, focusOffset } = selection;
    if (!anchorNode || !focusNode || !transcript.contains(anchorNode) || !transcript.contains(focusNode)) return;
    const generation = snapshot?.transcript.generation;
    const restore = () => {
      if (snapshot?.transcript.generation === generation && transcript?.contains(anchorNode) &&
          transcript.contains(focusNode) && selection.isCollapsed) {
        selection.setBaseAndExtent(anchorNode, anchorOffset, focusNode, focusOffset);
      }
    };
    restoreTabSelection = restore;
    setTimeout(() => {
      if (restoreTabSelection === restore) restoreTabSelection = undefined;
    }, 0);
  }

  function focusResponseAction() {
    const restore = restoreTabSelection;
    restoreTabSelection = undefined;
    if (restore) requestAnimationFrame(restore);
  }

  function receive(current: WorkspaceSnapshot) {
    const previous = snapshot?.navigation.draft;
    if (snapshot?.workspace?.workspaceId !== current.workspace?.workspaceId) showingChanges = false;
    snapshot = current;
    if (draftId !== current.navigation.draft?.id) {
      draftId = current.navigation.draft?.id;
      text = current.navigation.draft?.text ?? '';
      composing = false;
    } else if (!composing && !pending && previous?.text !== current.navigation.draft?.text &&
               text === previous?.text) {
      text = current.navigation.draft?.text ?? '';
    }
    const request = current.navigation.quit;
    if (request && !request.confirm && !request.draining && request.ticket !== quietQuitTicket) {
      quietQuitTicket = request.ticket;
      void confirmQuit(request.ticket);
    }
  }

  async function savePending() {
    while (pending) {
      const edit = pending;
      pending = null;
      try {
        await navigateWorkspace({ editDraft: edit });
      } catch (error) {
        pending ??= edit;
        throw error;
      }
    }
  }

  function flushEdits() {
    if (!saving && pending) {
      saving = savePending().finally(() => { saving = null; });
    }
    return saving;
  }

  function acceptText(value: string, inComposition: boolean) {
    text = value;
    if (inComposition || composing || !draftId) return;
    pending = { draftId, text: value };
    void flushEdits()?.catch(console.error);
  }

  async function act(action: () => Promise<unknown>, focusEditor = false) {
    if (actionPending || composing || quit) return;
    actionPending = true;
    try {
      await flushEdits();
      await action();
      if (focusEditor) {
        await tick();
        editor?.focus();
      }
    } catch (error) {
      console.error(error);
    } finally {
      actionPending = false;
    }
  }

  function workspaceAction(action: 'clearProject' | 'newChat' | 'refresh' | 'reconnect' | 'setupSandbox') {
    if (!workspace) return;
    const request = { workspaceId: workspace.workspaceId };
    const intent = { [action]: request } as NavigationIntent;
    void act(() => navigateWorkspace(intent), action === 'newChat');
  }

  function openChat(chatId: string) {
    if (!workspace) return;
    const openChat = { workspaceId: workspace.workspaceId, chatId };
    void act(() => navigateWorkspace({ openChat }));
  }

  function retryChat() {
    if (!workspace || !navigation?.selectedChat) return;
    const retry = { workspaceId: workspace.workspaceId, chatId: navigation.selectedChat };
    void act(() => navigateWorkspace({ retry }));
  }

  function signIn() {
    const signIn = { workspaceId: workspace?.workspaceId ?? null };
    void act(() => navigateWorkspace({ signIn }));
  }

  function cancelSignIn() {
    const ticket = navigation?.account.loginTicket;
    if (ticket) void act(() => navigateWorkspace({ cancelSignIn: { ticket } }));
  }

  async function sendDraft() {
    if (!workspace || !draftId || !navigation?.actions.send || !text.trim() || composing || actionPending) return;
    const send = {
      workspaceId: workspace.workspaceId, chatId: navigation.selectedChat, draftId, text,
      expectedTurn: queue?.activeTurn ?? null,
    };
    admittingDraft = true;
    try {
      await act(() => navigateWorkspace({ send }));
    } finally {
      admittingDraft = false;
    }
  }

  function queueCommand(command: QueueCommand) {
    if (!workspace || !navigation?.selectedChat || !queue || queue.busy) return;
    const request = { workspaceId: workspace.workspaceId, chatId: navigation.selectedChat, revision: queue.revision, command };
    void act(() => navigateWorkspace({ queue: request }), typeof command === 'object' && 'edit' in command);
  }

  function stop() {
    if (!workspace || !stopTarget) return;
    const request = { workspaceId: workspace.workspaceId, target: stopTarget };
    void act(() => navigateWorkspace({ stop: request }));
  }

  function recoverSend() {
    if (!workspace || !draftId) return;
    const request = { workspaceId: workspace.workspaceId, draftId };
    void act(() => navigateWorkspace({ recoverSend: request }));
  }

  function stopLabel() {
    if (stopTarget && 'turn' in stopTarget && stopTarget.turn.threadId !== navigation?.selectedChat) {
      const id = stopTarget.turn.threadId;
      const title = navigation?.chats.find((chat) => chat.id === id)?.title;
      if (title) return `Stop ${title}`;
    }
    return 'Stop';
  }

  function respond(interactionId: string, response: InteractionAnswer) {
    if (!workspace) return;
    const request = { workspaceId: workspace.workspaceId, interactionId, response };
    void act(() => navigateWorkspace({ respond: request }));
  }

  function cancelQuit(ticket: string) {
    return navigateWorkspace({ cancelQuit: { ticket } });
  }

  async function confirmQuit(ticket: string) {
    if (confirmingQuit) return;
    confirmingQuit = true;
    try {
      if (composing && editor) {
        editor.blur();
        composing = false;
        acceptText(editor.value, false);
      }
      await flushEdits();
      await navigateWorkspace({ confirmQuit: { ticket } });
    } catch (error) {
      console.error(error);
      await cancelQuit(ticket).catch((failure) => {
        if (failure !== 'staleSelection') console.error(failure);
      });
    } finally {
      confirmingQuit = false;
    }
  }

  function handleShortcut(event: KeyboardEvent) {
    if (event.key === 'Tab' && !event.defaultPrevented && !event.isComposing) retainSelectionForTab();
    if (event.defaultPrevented || event.isComposing || composing ||
        !(event.metaKey || event.ctrlKey) || event.shiftKey || event.altKey) return;
    switch (event.key.toLowerCase()) {
      case 'o':
        event.preventDefault();
        void act(pickWorkspace);
        break;
      case 'n':
        if (workspace) {
          event.preventDefault();
          workspaceAction('newChat');
        }
        break;
    }
  }

  onMount(() => {
    const lifecycle = new AbortController();
    void observeWorkspace(receive, lifecycle.signal).catch(console.error);
    if (verify === 'account') void verifyAccount(() => snapshot);
    else if (verify === 'windowsSetup') void verifyWindowsSetup(() => snapshot);
    else if (verify === 'turn' || verify === 'activeTurn') void verifyTurn(() => snapshot, verify);
    else if (verify === 'queue') void verifyQueue(() => snapshot);
    else if (verify === 'diff') void verifyDiff(() => snapshot);
    else if (verify === 'quit') void verifyQuit(() => snapshot);
    else if (verify) void verifyHistory(verify, () => snapshot);
    return () => lifecycle.abort();
  });
</script>

<svelte:window onkeydown={handleShortcut} />

<main class="workspace" aria-label="Codex GUI">
  <header class="workspace-header">
    <button type="button" disabled={actionPending} onclick={() => void act(pickWorkspace)}>Open Project…</button>
    {#if navigation?.actions.stopAll}
      <button type="button" disabled={actionPending || !!quit}
        onclick={() => void act(() => navigateWorkspace('stopAll'))}>Stop All…</button>
    {/if}
    {#if workspace}
      <h1 title={workspace.projectPath}>{workspace.projectPath.split(/[\/\\]+/).filter(Boolean).at(-1) ?? workspace.projectPath}</h1>
      <button type="button" disabled={actionPending} onclick={() => workspaceAction('clearProject')}>Clear Project</button>
      <button type="button" disabled={actionPending} onclick={() => workspaceAction('refresh')}>Refresh</button>
      <button type="button" disabled={actionPending} onclick={() => workspaceAction('reconnect')}>Reconnect</button>
      <button type="button" aria-expanded={showingChanges} onclick={() => { showingChanges = !showingChanges; }}>Changes</button>
    {/if}
    {#if navigation?.writeAccess === 'setupSandbox' || navigation?.writeAccess === 'settingUpSandbox'}
      <button type="button" disabled={actionPending || navigation.writeAccess === 'settingUpSandbox'}
        onclick={() => workspaceAction('setupSandbox')}>Set Up Sandbox</button>
    {:else if navigation?.writeAccess === 'updateSandbox' || navigation?.writeAccess === 'updatingSandbox'}
      <button type="button" disabled={actionPending || navigation.writeAccess === 'updatingSandbox'}
        onclick={() => workspaceAction('setupSandbox')}>Update Sandbox</button>
    {/if}
    {#if navigation?.account.loginTicket}
      <button type="button" disabled={actionPending} onclick={cancelSignIn}>Cancel Sign-in</button>
    {:else if !navigation?.account.identity}
      <button type="button" disabled={actionPending} onclick={signIn}>Sign In</button>
    {/if}
  </header>

  <div class="workspace-body">
    {#if workspace}
      <nav class="workspace-sidebar" aria-label="Chats">
        <button type="button" disabled={actionPending} onclick={() => workspaceAction('newChat')}>New Chat</button>
        {#each navigation?.chats ?? [] as chat (chat.id)}
          <button type="button" class="chat-row" aria-current={chat.id === navigation?.selectedChat ? 'true' : undefined}
            disabled={actionPending} onclick={() => openChat(chat.id)}>
            <span class="chat-title">{chat.title}</span>
            {#if chat.preview && chat.preview !== chat.title}
              <span class="chat-preview" title={chat.preview}>{chat.preview}</span>
            {/if}
          </button>
        {/each}
      </nav>
    {/if}
    <section class="workspace-conversation" aria-label="Conversation">
      <div class="workspace-transcript" bind:this={transcript}>
        {#each snapshot?.transcript.items ?? [] as item (item.itemId)}
          <TranscriptRow {item} copy={copyResponse} onCopyFocus={focusResponseAction} />
        {/each}
      </div>
      {#if navigation?.retryable && navigation.writeAccess === 'ready'}
        <button class="workspace-retry" type="button" disabled={actionPending} onclick={retryChat}>Retry</button>
      {/if}
      {#each navigation?.actions.interactions ?? [] as interaction (interaction.id)}
        <InteractionCard {interaction} disabled={actionPending} respond={(answer) => respond(interaction.id, answer)} />
      {/each}
      {#if queue}
        <QueuePanel {queue} disabled={actionPending || queue.busy || !!quit}
          draftOccupied={text !== '' || !!queue.editing} command={queueCommand} />
      {/if}
      {#if navigation?.draft}
        <textarea class="workspace-composer" aria-label="Message" rows="4" bind:this={editor}
          readonly={admittingDraft || confirmingQuit || quit?.draining}
          value={text} oncompositionstart={() => { composing = true; }}
          oncompositionend={(event) => {
            composing = false;
            acceptText(event.currentTarget.value, false);
          }}
          oninput={(event) => acceptText(event.currentTarget.value, event instanceof InputEvent && event.isComposing)}></textarea>
        <div class="composer-actions">
          {#if queue}
            <button type="button" aria-pressed={queue.enabled}
              disabled={actionPending || queue.busy} onclick={() => queueCommand({ enable: !queue.enabled })}>
              Queue Follow-ups
            </button>
          {/if}
          {#if navigation.actions.recover}
            <button type="button" disabled={actionPending} onclick={recoverSend}>Recover Send</button>
          {/if}
          {#if stopTarget}
            <button type="button" disabled={actionPending} onclick={stop}>{stopLabel()}</button>
          {/if}
          {#if queue?.editing}
            {@const edit = queue.editing}
            <button type="button" disabled={actionPending || queue.busy}
              onclick={() => queueCommand({ cancelEdit: edit.id })}>Cancel Edit</button>
            <button type="button" disabled={actionPending || queue.busy || (!text.trim() && !edit.hasContext)}
              onclick={() => queueCommand({ saveEdit: edit.id })}>Save Queue Edit</button>
          {:else if resumeCommand && text === ''}
            <button type="button" disabled={actionPending || queue?.busy}
              onclick={() => { if (resumeCommand) queueCommand(resumeCommand); }}>Resume</button>
          {:else}
            <button type="button" disabled={actionPending || !navigation.actions.send || !text.trim()} onclick={() => void sendDraft()}>
              {queue?.activeTurn ? (queue.enabled ? 'Queue' : 'Steer') : 'Send'}
            </button>
          {/if}
        </div>
      {/if}
    </section>
    {#if showingChanges && workspace}
      <WorkspaceChanges workspaceId={workspace.workspaceId} />
    {/if}
  </div>
  {#if quit?.confirm && !quit.draining}
    <QuitDialog busy={confirmingQuit} stopOnly={quit.stopOnly}
      cancel={() => { if (quit) void cancelQuit(quit.ticket).catch(console.error); }}
      confirm={() => { if (quit) void confirmQuit(quit.ticket); }} />
  {/if}
</main>
