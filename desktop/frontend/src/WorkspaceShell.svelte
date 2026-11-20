<script lang="ts">
  import { onMount, tick } from 'svelte';
  import type { DraftEdit, NavigationIntent, WorkspaceSnapshot } from './generated/workspace';
  import { navigateWorkspace, observeWorkspace, pickWorkspace } from './projectIpc';
  import { verifyHistory } from './historyProbe';
  import { verifyAccount } from './accountProbe';
  import { verifyWindowsSetup } from './windowsSetupProbe';
  import './workspace.css';

  let { verify }: { verify?: 'initial' | 'restore' | 'account' | 'windowsSetup' } = $props();
  let snapshot = $state<WorkspaceSnapshot | null>(null);
  let editor = $state<HTMLTextAreaElement>();
  let draftId: string | undefined;
  let text = $state('');
  let composing = false;
  let actionPending = $state(false);
  let pending: DraftEdit | null = null;
  let saving: Promise<void> | null = null;
  const workspace = $derived(snapshot?.workspace);
  const navigation = $derived(snapshot?.navigation);

  function receive(current: WorkspaceSnapshot) {
    snapshot = current;
    if (draftId !== current.navigation.draft?.id) {
      draftId = current.navigation.draft?.id;
      text = current.navigation.draft?.text ?? '';
      composing = false;
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
    if (actionPending || composing) return;
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

  function handleShortcut(event: KeyboardEvent) {
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
    else if (verify) void verifyHistory(verify, () => snapshot);
    return () => lifecycle.abort();
  });
</script>

<svelte:window onkeydown={handleShortcut} />

<main class="workspace" aria-label="Codex GUI">
  <header class="workspace-header">
    <button type="button" disabled={actionPending} onclick={() => void act(pickWorkspace)}>Open Project…</button>
    {#if workspace}
      <h1 title={workspace.projectPath}>{workspace.projectPath.split(/[\/\\]+/).filter(Boolean).at(-1) ?? workspace.projectPath}</h1>
      <button type="button" disabled={actionPending} onclick={() => workspaceAction('clearProject')}>Clear Project</button>
      <button type="button" disabled={actionPending} onclick={() => workspaceAction('refresh')}>Refresh</button>
      <button type="button" disabled={actionPending} onclick={() => workspaceAction('reconnect')}>Reconnect</button>
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
            disabled={actionPending} onclick={() => openChat(chat.id)}>{chat.title}</button>
        {/each}
      </nav>
    {/if}
    <section class="workspace-conversation" aria-label="Conversation">
      <div class="workspace-transcript">
        {#each snapshot?.transcript.items ?? [] as item (item.itemId)}
          <article class="transcript-item" aria-label={item.role === 'user' ? 'You' : 'Codex'}>
            <span aria-hidden="true">{item.role === 'user' ? 'You' : 'Codex'}</span>
            <p>{item.text}</p>
          </article>
        {/each}
      </div>
      {#if navigation?.retryable && navigation.writeAccess === 'ready'}
        <button class="workspace-retry" type="button" disabled={actionPending} onclick={retryChat}>Retry</button>
      {/if}
      {#if navigation?.draft}
        <textarea class="workspace-composer" aria-label="Message" rows="4" bind:this={editor}
          value={text} oncompositionstart={() => { composing = true; }}
          oncompositionend={(event) => {
            composing = false;
            acceptText(event.currentTarget.value, false);
          }}
          oninput={(event) => acceptText(event.currentTarget.value, event instanceof InputEvent && event.isComposing)}></textarea>
      {/if}
    </section>
  </div>
</main>
