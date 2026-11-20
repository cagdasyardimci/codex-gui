<script lang="ts">
  import { tick } from 'svelte';
  import type {
    SidebarChange, SidebarChat, SidebarChatKey, SidebarGroup, SidebarProject, SidebarSort,
    SidebarView,
  } from './generated/workspace';

  let { view, selectedChat, blocked, newChat, change, reveal } : {
    view: SidebarView;
    selectedChat: string | null | undefined;
    blocked: boolean;
    newChat?: () => void;
    change: (revision: string, change: SidebarChange) => Promise<void>;
    reveal: (revision: string, projectId: string) => Promise<void>;
  } = $props();

  let dragged = $state.raw<{ key: SidebarChatKey; revision: string; pinned: boolean }>();
  let edit = $state.raw<{ project?: SidebarProject; chat?: SidebarChat }>();
  let draftTitle = $state('');
  let dialog = $state<HTMLDialogElement>();
  let nameField = $state<HTMLInputElement>();
  let sourceControl: HTMLElement | null = null;
  let saving = $state(false);
  let archive = $state.raw<{ project: SidebarProject; revision: string; control: HTMLElement | null }>();
  let archiveDialog = $state<HTMLDialogElement>();
  let archiveCancel = $state<HTMLButtonElement>();
  const pinnedProjects = $derived(view.projects.filter((project) => project.pinned));
  const ordinaryProjects = $derived(view.projects.filter((project) => !project.pinned));
  const pinned = $derived(view.chats.filter((chat) => chat.pinned));
  const ordinary = $derived(view.chats.filter((chat) => !chat.pinned));

  function report(error: unknown) {
    if (error !== 'staleSelection' && error !== 'retiredWorkspace') console.error(error);
  }

  function apply(intent: SidebarChange) {
    if (!view.revision || blocked) return;
    void change(view.revision, intent).catch(report);
  }

  function titleEditor(entry: { project: SidebarProject } | { chat: SidebarChat }, button: HTMLElement) {
    edit = entry;
    draftTitle = ('project' in entry ? entry.project : entry.chat).title;
    sourceControl = button;
    void tick().then(() => {
      dialog?.showModal();
      nameField?.focus();
      nameField?.select();
    });
  }

  function dismissTitle() {
    if (saving) return;
    edit = undefined;
    sourceControl?.focus();
  }

  async function saveTitle() {
    if (!edit || !view.revision || saving || blocked || !draftTitle.trim()) return;
    const intent = edit.project
      ? { renameProject: { projectId: edit.project.id, title: draftTitle } }
      : edit.chat ? { renameChat: { key: edit.chat.key, title: draftTitle } } : null;
    if (!intent) return;
    saving = true;
    try {
      await change(view.revision, intent);
      edit = undefined;
      await tick();
      sourceControl?.focus();
    } catch (error) {
      report(error);
    } finally {
      saving = false;
    }
  }

  function changeGroup(event: Event & { currentTarget: HTMLSelectElement }) {
    const value = event.currentTarget.value as SidebarGroup;
    event.currentTarget.value = view.group;
    apply({ group: value });
  }

  function changeSort(event: Event & { currentTarget: HTMLSelectElement }) {
    const value = event.currentTarget.value as SidebarSort;
    event.currentTarget.value = view.sort;
    apply({ sort: value });
  }

  function showInFolder(project: SidebarProject) {
    if (view.revision && !blocked) void reveal(view.revision, project.id).catch(report);
  }

  function drag(event: DragEvent, chat: SidebarChat) {
    if (!event.dataTransfer || !view.revision || blocked || view.sort !== 'manual') {
      event.preventDefault();
      return;
    }
    dragged = { key: chat.key, revision: view.revision, pinned: chat.pinned };
    event.dataTransfer.effectAllowed = 'move';
    event.dataTransfer.setData('application/x-codex-chat', JSON.stringify(chat.key));
  }

  function allowDrop(event: DragEvent, chat: SidebarChat) {
    if (!dragged || dragged.revision !== view.revision || dragged.pinned !== chat.pinned ||
        view.group === 'byProject' && !chat.pinned && dragged.key.projectId !== chat.key.projectId) return false;
    event.preventDefault();
    if (event.dataTransfer) event.dataTransfer.dropEffect = 'move';
    return true;
  }

  function drop(event: DragEvent & { currentTarget: HTMLButtonElement }, chat: SidebarChat) {
    const source = dragged;
    if (!source || !allowDrop(event, chat)) return;
    dragged = undefined;
    const bounds = event.currentTarget.getBoundingClientRect();
    const after = event.clientY > bounds.top + bounds.height / 2;
    void change(source.revision, { moveChat: { source: source.key, target: chat.key, after } }).catch(report);
  }

  function closeMenu(event: MouseEvent & { currentTarget: HTMLButtonElement }) {
    const menu = event.currentTarget.closest('details');
    if (menu) menu.open = false;
    return menu?.querySelector('summary') ?? event.currentTarget;
  }

  function askArchive(project: SidebarProject, control: HTMLElement | null) {
    if (!view.revision || blocked) return;
    archive = { project, revision: view.revision, control };
    void tick().then(() => {
      archiveDialog?.showModal();
      archiveCancel?.focus();
    });
  }

  function closeArchive() {
    const capture = archive;
    archive = undefined;
    void tick().then(() => capture?.control?.focus());
  }

  function archiveProject() {
    const capture = archive;
    if (!capture || blocked) return;
    closeArchive();
    void change(capture.revision, { archiveProject: capture.project.id }).catch(report);
  }
</script>

{#snippet projectRow(project: SidebarProject)}
  <div class="sidebar-project-row" data-sidebar-project={project.id}>
    <button class="sidebar-main" type="button" aria-current={view.activeProject === project.id ? 'true' : undefined}
      disabled={blocked} title={project.path} onclick={() => apply({ openProject: project.id })}>{project.title}</button>
    <details class="sidebar-row-menu">
      <summary aria-label={`Actions for ${project.title}`}>⋯</summary>
      <div>
        <button type="button" onclick={(event) => titleEditor({ project }, closeMenu(event))} disabled={blocked}>Rename Project</button>
        <button type="button" onclick={(event) => {
          closeMenu(event);
          apply({ pinProject: { projectId: project.id, pinned: !project.pinned } });
        }} disabled={blocked}>{project.pinned ? 'Unpin Project' : 'Pin Project'}</button>
        <button type="button" onclick={(event) => { closeMenu(event); showInFolder(project); }} disabled={blocked}>Show in Folder</button>
        <button type="button" onclick={(event) => askArchive(project, closeMenu(event))} disabled={blocked}>Archive Project Chats…</button>
      </div>
    </details>
  </div>
{/snippet}

{#snippet chatRow(chat: SidebarChat)}
  <div class="sidebar-chat-row" data-sidebar-chat={chat.key.chatId} data-sidebar-project-id={chat.key.projectId}>
    <button class="chat-row sidebar-main" class:unread={chat.unread} type="button"
      aria-current={view.activeProject === chat.key.projectId && chat.key.chatId === selectedChat ? 'true' : undefined}
      disabled={blocked} draggable={view.sort === 'manual'}
      ondragstart={(event) => drag(event, chat)} ondragover={(event) => allowDrop(event, chat)}
      ondragend={() => { dragged = undefined; }} ondrop={(event) => drop(event, chat)}
      onclick={() => apply({ openChat: chat.key })}>
      <span class="chat-title">{chat.title}</span>
      {#if chat.preview && chat.preview !== chat.title}<span class="chat-preview" title={chat.preview}>{chat.preview}</span>{/if}
    </button>
    <details class="sidebar-row-menu">
      <summary aria-label={`Actions for ${chat.title}`}>⋯</summary>
      <div>
        {#if view.activeProject === chat.key.projectId}
          <button type="button" onclick={(event) => titleEditor({ chat }, closeMenu(event))} disabled={blocked}>Rename Chat</button>
        {/if}
        <button type="button" onclick={(event) => {
          closeMenu(event);
          apply({ pinChat: { key: chat.key, pinned: !chat.pinned } });
        }} disabled={blocked}>{chat.pinned ? 'Unpin Chat' : 'Pin Chat'}</button>
        <button type="button" onclick={(event) => {
          closeMenu(event);
          apply({ markUnread: { key: chat.key, unread: !chat.unread } });
        }} disabled={blocked}>{chat.unread ? 'Mark Read' : 'Mark Unread'}</button>
        <button type="button" onclick={(event) => {
          closeMenu(event);
          apply({ archiveChat: chat.key });
        }} disabled={blocked}>Archive Chat</button>
      </div>
    </details>
  </div>
{/snippet}

{#if newChat}<button type="button" disabled={blocked} onclick={newChat}>New Chat</button>{/if}
<details class="sidebar-options">
  <summary>Sidebar Options</summary>
  <label>Organize
    <select aria-label="Organize Sidebar" value={view.group} onchange={changeGroup} disabled={blocked}>
      <option value="byProject">By Project</option>
      <option value="oneList">In One List</option>
    </select>
  </label>
  <label>Sort
    <select aria-label="Sort Chats" value={view.sort} onchange={changeSort} disabled={blocked}>
      <option value="lastUpdated">Last Updated</option>
      <option value="manual">Manual Order</option>
    </select>
  </label>
</details>
{#if pinned.length || pinnedProjects.length}
  <section aria-label="Pinned">
    <h2>Pinned</h2>
    {#each pinned as chat (JSON.stringify(chat.key))}{@render chatRow(chat)}{/each}
    {#each pinnedProjects as project (project.id)}
      {@render projectRow(project)}
      {#if view.group === 'byProject' && project.id === view.activeProject}
        {#each ordinary.filter((chat) => chat.key.projectId === project.id) as chat (chat.key.chatId)}{@render chatRow(chat)}{/each}
      {/if}
    {/each}
  </section>
{/if}
{#if ordinaryProjects.length}
  <section aria-label="Projects">
    <h2>Projects</h2>
    {#each ordinaryProjects as project (project.id)}
      {@render projectRow(project)}
      {#if view.group === 'byProject' && project.id === view.activeProject}
        {#each ordinary.filter((chat) => chat.key.projectId === project.id) as chat (chat.key.chatId)}{@render chatRow(chat)}{/each}
      {/if}
    {/each}
  </section>
{/if}
{#if view.group === 'oneList' && ordinary.length}
  <section aria-label="Recents">
    <h2>Recents</h2>
    {#each ordinary as chat (JSON.stringify(chat.key))}{@render chatRow(chat)}{/each}
  </section>
{/if}

{#if edit}
  {@const title = edit.project ? 'Rename Project' : 'Rename Chat'}
  <dialog bind:this={dialog} aria-label={title} oncancel={(event) => { event.preventDefault(); dismissTitle(); }}>
    <form onsubmit={(event) => { event.preventDefault(); void saveTitle(); }}>
      <h2>{title}</h2>
      <label>Name <input bind:this={nameField} bind:value={draftTitle} maxlength="240" required /></label>
      <div>
        <button type="button" disabled={saving} onclick={dismissTitle}>Cancel</button>
        <button type="submit" disabled={!draftTitle.trim() || saving}>Save Name</button>
      </div>
    </form>
  </dialog>
{/if}

{#if archive}
  <dialog bind:this={archiveDialog} aria-label="Archive Project Chats"
    oncancel={(event) => { event.preventDefault(); closeArchive(); }}>
    <h2>Archive Chats in {archive.project.title}</h2>
    <button type="button" bind:this={archiveCancel} onclick={closeArchive}>Cancel</button>
    <button type="button" disabled={blocked || view.revision !== archive.revision} onclick={archiveProject}>Archive Chats</button>
  </dialog>
{/if}

<style>
  section { display: grid; gap: 0.2rem; }
  h2 { font-size: 0.9rem; margin: 0.3rem 0 0.2rem; }
  .sidebar-project-row, .sidebar-chat-row { display: flex; align-items: flex-start; min-width: 0; gap: 0.25rem; }
  .sidebar-main { flex: 1 1 0; min-width: 0; overflow: hidden; text-overflow: ellipsis; }
  .sidebar-project-row .sidebar-main { font-weight: 600; white-space: nowrap; }
  .unread .chat-title { font-weight: 700; }
  .sidebar-options { margin-block-end: 0.25rem; }
  .sidebar-options label { display: grid; justify-content: start; margin-block-start: 0.35rem; }
  .sidebar-row-menu summary { cursor: pointer; padding: 0.35rem; list-style: none; }
  .sidebar-row-menu > div { display: grid; gap: 0.25rem; position: absolute; z-index: 1;
    padding: 0.3rem; background: Canvas; border: 1px solid var(--workspace-divider); border-radius: 0.45rem; }
  dialog { background: Canvas; color: CanvasText; border: 1px solid var(--workspace-divider); border-radius: 0.5rem; }
  form { display: grid; gap: 0.65rem; }
  form > div { display: flex; justify-content: flex-end; gap: 0.45rem; }
  form input { margin-inline-start: 0.5rem; }
</style>
