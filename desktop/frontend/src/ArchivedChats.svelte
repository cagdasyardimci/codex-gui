<script lang="ts">
  import { onMount } from 'svelte';
  import type { ArchiveCatalog, ArchivedChat, ArchiveTarget, RestoreArchive, WorkspaceId } from './generated/workspace';
  import { readArchive } from './projectIpc';

  let { workspaceId, restore, close }: {
    workspaceId: WorkspaceId | null;
    restore: (request: RestoreArchive) => Promise<void>;
    close: () => void;
  } = $props();

  const pageSize = 30;
  let dialog: HTMLDialogElement;
  let field: HTMLInputElement;
  let catalog = $state.raw<ArchiveCatalog>();
  let query = $state('');
  let project = $state('');
  let sort = $state<'updated' | 'created' | 'title'>('updated');
  let limit = $state(pageSize);
  let loading = $state(false);
  let restoring = $state(false);
  let readTicket = 0;
  let mounted = false;

  const projects = $derived.by(() => [...new Map((catalog?.chats ?? []).map((chat) => [chat.path, chat.project])).entries()]
    .sort(([leftPath, left], [rightPath, right]) => left.localeCompare(right) || leftPath.localeCompare(rightPath)));
  const terms = $derived(fold(query).trim().split(/\s+/u).filter(Boolean));
  const matching = $derived((catalog?.chats ?? [])
    .filter((chat) => (!project || chat.path === project) &&
      terms.every((term) => fold(`${chat.title}\n${chat.preview}\n${chat.project}\n${chat.path}`).includes(term)))
    .sort((left, right) => {
      const order = sort === 'title' ? left.title.localeCompare(right.title) :
        sort === 'created' ? right.createdAt - left.createdAt : right.updatedAt - left.updatedAt;
      return order || left.id.localeCompare(right.id);
    }));
  const groups = $derived.by(() => {
    const groups = new Map<string, ArchivedChat[]>();
    for (const chat of matching.slice(0, limit)) {
      if (!groups.has(chat.path)) groups.set(chat.path, []);
      groups.get(chat.path)!.push(chat);
    }
    return [...groups.values()];
  });

  onMount(() => {
    mounted = true;
    dialog.showModal();
    field.focus();
    void load();
    return () => { mounted = false; readTicket += 1; };
  });

  function fold(value: string) {
    return value.normalize('NFKD').replace(/\p{M}/gu, '').toLowerCase();
  }

  async function load() {
    const ticket = ++readTicket;
    loading = true;
    try {
      const result = await readArchive({ workspaceId });
      if (ticket !== readTicket) return;
      catalog = result;
      if (project && !result.chats.some((chat) => chat.path === project)) project = '';
    } catch (error) {
      if (ticket === readTicket && error !== 'staleSelection' && error !== 'retiredWorkspace') console.error(error);
    } finally {
      if (ticket === readTicket) loading = false;
    }
  }

  async function restoreTarget(target: ArchiveTarget) {
    const captured = catalog;
    if (restoring || !captured) return;
    restoring = true;
    readTicket += 1;
    loading = false;
    try {
      await restore({ revision: captured.revision, target });
      if (!mounted) return;
      catalog = { ...captured, chats: captured.chats.filter((chat) =>
        'chat' in target ? chat.id !== target.chat : chat.path !== target.project) };
    } catch (error) {
      if (error !== 'staleSelection' && error !== 'retiredWorkspace') console.error(error);
    } finally {
      if (mounted) {
        await load();
        restoring = false;
      }
    }
  }
</script>

<dialog bind:this={dialog} aria-label="Archived Chats"
  oncancel={(event) => { event.preventDefault(); if (!restoring) close(); }}>
  <h2>Archived Chats</h2>
  <div class="filters">
    <input type="search" aria-label="Search Archived Chats" bind:this={field} bind:value={query}
      oninput={() => { limit = pageSize; }} />
    <label>Project
      <select bind:value={project} onchange={() => { limit = pageSize; }}>
        <option value="">All Projects</option>
        {#each projects as [path, label] (path)}<option value={path}>{label}</option>{/each}
      </select>
    </label>
    <label>Sort
      <select bind:value={sort} onchange={() => { limit = pageSize; }}>
        <option value="updated">Last Updated</option>
        <option value="created">Created</option>
        <option value="title">Title</option>
      </select>
    </label>
  </div>
  {#each groups as chats (chats[0]!.path)}
    {@const first = chats[0]!}
    <section aria-label={first.project}>
      <header>
        <h3 title={first.path}>{first.project}</h3>
        <button type="button" aria-label={`Restore chats in ${first.project}`} disabled={restoring}
          onclick={() => void restoreTarget({ project: first.path })}>Restore Project</button>
      </header>
      {#each chats as chat (chat.id)}
        <div class="archived-chat" data-archived-chat={chat.id}>
          <div>
            <strong>{chat.title}</strong>
            {#if chat.preview && chat.preview !== chat.title}<div>{chat.preview}</div>{/if}
          </div>
          <button type="button" aria-label={`Restore ${chat.title}`} disabled={restoring}
            onclick={() => void restoreTarget({ chat: chat.id })}>Restore Chat</button>
        </div>
      {/each}
    </section>
  {/each}
  <footer>
    {#if matching.length > limit}<button type="button" onclick={() => { limit += pageSize; }}>Show More</button>{/if}
    <button type="button" disabled={loading || restoring} onclick={() => void load()}>Refresh Archive</button>
    <button type="button" disabled={restoring} onclick={close}>Close</button>
  </footer>
</dialog>

<style>
  dialog { color: CanvasText; background: Canvas; border: 1px solid var(--workspace-divider);
    border-radius: 0.65rem; inline-size: min(43rem, 86vw); max-block-size: 77vh; padding: 1rem; }
  h2, h3 { margin: 0; font-size: 1rem; }
  .filters, header, footer, .archived-chat { display: flex; flex-wrap: wrap; align-items: baseline; gap: 0.45rem; }
  .filters { margin-block: 0.7rem; }
  header, .archived-chat { justify-content: space-between; }
  section { border-block-start: 1px solid var(--workspace-divider); padding-block: 0.55rem; }
  .archived-chat { margin-block-start: 0.35rem; overflow-wrap: anywhere; }
  .archived-chat > div { flex: 1 1 15rem; min-width: 0; }
  footer { justify-content: flex-end; }
</style>
