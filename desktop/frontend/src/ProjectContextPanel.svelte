<script lang="ts">
  import { onMount } from 'svelte';
  import type {
    AccountModel, ComposerChoice, DraftAttachmentScope, ProjectContextChange, ProjectContextView,
    ProjectItemEdit, ProjectPromptEdit,
  } from './generated/workspace';
  import { composerContextCatalog, readProjectContext } from './projectIpc';
  import { visibleEfforts } from './reasoningEfforts';

  let { scope, models, hiddenEfforts, blocked, draftText, bookmarkKey, submit, close }: {
    scope: DraftAttachmentScope;
    models: AccountModel[];
    hiddenEfforts: string[];
    blocked: boolean;
    draftText: string;
    bookmarkKey: string;
    submit: (scope: DraftAttachmentScope, revision: number, change: ProjectContextChange) => Promise<void>;
    close: () => void;
  } = $props();

  let view = $state.raw<ProjectContextView>();
  let item = $state<ProjectItemEdit>();
  let prompt = $state<ProjectPromptEdit>();
  let skills = $state.raw<ComposerChoice[]>([]);
  let modelChoice = $state('');
  let effortChoice = $state('');
  let ready = $state(false);
  let busy = $state(false);
  let current = true;
  const context = $derived(view?.context);
  const model = $derived(modelChoice
    ? models.find((model) => model.id === modelChoice) : models.find((model) => model.isDefault));

  function report(error: unknown) {
    if (error !== 'staleSelection' && error !== 'retiredWorkspace') console.error(error);
  }

  async function refresh() {
    const loaded = await readProjectContext(scope);
    if (!current) return;
    view = loaded;
    if (!ready) {
      modelChoice = loaded.context.modelPreference?.modelID ?? '';
      effortChoice = loaded.context.modelPreference?.effort ?? '';
      ready = true;
    }
  }

  onMount(() => {
    void composerContextCatalog(scope).then((choices) => {
      if (current) skills = choices.filter((choice) => choice.kind === 'skill');
    }).catch(report);
    return () => { current = false; };
  });

  $effect(() => {
    bookmarkKey;
    void refresh().catch(report);
  });

  async function change(change: ProjectContextChange, completed?: () => void, refreshAfter = true) {
    if (!view || busy || blocked) return;
    const revision = view.revision;
    busy = true;
    try {
      await submit(scope, revision, change);
      if (!current) return;
      completed?.();
      if (refreshAfter) await refresh();
    } catch (error) {
      report(error);
      if (current && error === 'staleSelection') {
        await refresh().catch(report);
      }
    } finally {
      busy = false;
    }
  }

  function startItem() {
    prompt = undefined;
    item = { id: null, kind: 'note', title: '', body: '', referencePath: null, isIncluded: false };
  }

  function startPrompt() {
    item = undefined;
    prompt = { id: null, title: '', instructions: '' };
  }

  function saveModel() {
    void change({ setModel: { modelID: modelChoice || null, effort: effortChoice || null } });
  }
</script>

<aside class="project-context" aria-label="Project Context">
  <header>
    <h2>Project Context</h2>
    <button type="button" onclick={close}>Close</button>
  </header>

  <section aria-labelledby="project-context-items">
    <h3 id="project-context-items">Context Items</h3>
    <button type="button" disabled={!ready || blocked || busy} onclick={startItem}>Add Context Item</button>
    {#each context?.items ?? [] as entry (entry.id)}
      <div class="project-entry">
        <button type="button" disabled={busy || blocked} onclick={() => { prompt = undefined; item = { ...entry }; }}>{entry.title}</button>
        <label><input type="checkbox" checked={entry.isIncluded} disabled={busy || blocked}
          onchange={(event) => {
            const control = event.currentTarget;
            const isIncluded = control.checked;
            control.checked = entry.isIncluded;
            if (item?.id === entry.id) item.isIncluded = isIncluded;
            void change({ includeItem: { id: entry.id, isIncluded } });
          }} /> Include {entry.title}</label>
      </div>
    {/each}
    {#if item}
      <form onsubmit={(event) => {
        event.preventDefault();
        if (item) void change({ saveItem: { ...item, referencePath: item.referencePath || null } }, () => { item = undefined; });
      }}>
        <label>Title <input required maxlength="240" bind:value={item.title} /></label>
        <label>Type
          <select bind:value={item.kind}>
            <option value="specification">Specification</option>
            <option value="referenceFile">Reference File</option>
            <option value="note">Note</option>
            <option value="decision">Decision</option>
          </select>
        </label>
        <label>Reference Path <input maxlength="240" value={item.referencePath ?? ''}
          oninput={(event) => { if (item) item.referencePath = event.currentTarget.value; }} /></label>
        <label>Content <textarea rows="4" maxlength="16000" bind:value={item.body}></textarea></label>
        <label><input type="checkbox" bind:checked={item.isIncluded} /> Include in Requests</label>
        <div class="project-entry">
          <button type="submit" disabled={busy || blocked || !item.title.trim()}>Save Context Item</button>
          <button type="button" disabled={busy} onclick={() => { item = undefined; }}>Cancel</button>
          {#if item.id}
            {@const id = item.id}
            <button type="button" disabled={busy || blocked}
              onclick={() => void change({ removeItem: id }, () => { item = undefined; })}>Remove Context Item</button>
          {/if}
        </div>
      </form>
    {/if}
  </section>

  <section aria-labelledby="project-saved-prompts">
    <h3 id="project-saved-prompts">Saved Prompts</h3>
    <button type="button" disabled={!ready || blocked || busy} onclick={startPrompt}>Add Saved Prompt</button>
    {#each context?.savedPrompts ?? [] as saved (saved.id)}
      <div class="project-entry">
        <button type="button" disabled={busy || blocked}
          onclick={() => { item = undefined; prompt = { ...saved }; }}>{saved.title}</button>
        <button type="button" disabled={busy || blocked} aria-label={`Insert ${saved.title}`}
          onclick={() => void change({ insertPrompt: { id: saved.id, expectedText: draftText } }, close, false)}>Insert</button>
      </div>
    {/each}
    {#if prompt}
      <form onsubmit={(event) => {
        event.preventDefault();
        if (prompt) void change({ savePrompt: { ...prompt } }, () => { prompt = undefined; });
      }}>
        <label>Prompt Title <input required maxlength="240" bind:value={prompt.title} /></label>
        <label>Instructions <textarea required rows="4" maxlength="16000" bind:value={prompt.instructions}></textarea></label>
        <div class="project-entry">
          <button type="submit" disabled={busy || blocked || !prompt.title.trim() || !prompt.instructions.trim()}>Save Prompt</button>
          <button type="button" disabled={busy} onclick={() => { prompt = undefined; }}>Cancel</button>
          {#if prompt.id}
            {@const id = prompt.id}
            <button type="button" disabled={busy || blocked}
              onclick={() => void change({ removePrompt: id }, () => { prompt = undefined; })}>Remove Saved Prompt</button>
          {/if}
        </div>
      </form>
    {/if}
  </section>

  <section aria-labelledby="project-defaults">
    <h3 id="project-defaults">Defaults</h3>
    <label>Default Skill
      <select disabled={!ready || blocked || busy} value={context?.selectedSkill ? 'selected' : ''}
        onchange={(event) => {
          const choice = event.currentTarget.value;
          event.currentTarget.value = context?.selectedSkill ? 'selected' : '';
          void change({ setSkill: choice || null });
        }}>
        <option value="">No Default Skill</option>
        {#if context?.selectedSkill}<option value="selected" disabled>{context.selectedSkill.name}</option>{/if}
        {#each skills as skill (skill.id)}
          {#if skill.label !== context?.selectedSkill?.name}<option value={skill.id}>{skill.label}</option>{/if}
        {/each}
      </select>
    </label>
    <label>Default Model
      <select disabled={!ready || blocked || busy} bind:value={modelChoice} onchange={() => { effortChoice = ''; }}>
        <option value="">Backend Default</option>
        {#each models as option (option.id)}<option value={option.id}>{option.name}</option>{/each}
      </select>
    </label>
    <label>Default Effort
      <select disabled={!ready || blocked || busy} bind:value={effortChoice}>
        <option value="">Model Default</option>
        {#each visibleEfforts(model?.efforts ?? [], hiddenEfforts, effortChoice) as effort (effort.reasoningEffort)}
          <option value={effort.reasoningEffort}>{effort.reasoningEffort}</option>
        {/each}
      </select>
    </label>
    <div class="project-entry">
      <button type="button" disabled={!ready || blocked || busy} onclick={saveModel}>Save Model Defaults</button>
      {#if context?.modelPreference}
        <button type="button" disabled={busy || blocked}
          onclick={() => void change({ setModel: null }, () => { modelChoice = ''; effortChoice = ''; })}>Use Configured Defaults</button>
      {/if}
    </div>
  </section>

  {#if context?.bookmarks.length}
    <section aria-labelledby="project-bookmarks">
      <h3 id="project-bookmarks">Bookmarks</h3>
      {#each context.bookmarks as bookmark (bookmark.id)}
        <div class="project-entry">
          <button type="button" disabled={busy || blocked}
            onclick={() => void change({ openBookmark: bookmark.id }, close, false)}>{bookmark.label}</button>
          <button type="button" disabled={busy || blocked} aria-label={`Remove bookmark ${bookmark.label}`}
            onclick={() => void change({ removeBookmark: bookmark.id })}>Remove</button>
        </div>
      {/each}
    </section>
  {/if}
</aside>

<style>
  .project-context { flex: 0 0 clamp(15rem, 31vw, 23rem); overflow: auto; padding: 0.75rem;
    border-inline-start: 1px solid var(--workspace-divider); background: var(--workspace-panel); }
  header, .project-entry { display: flex; align-items: center; flex-wrap: wrap; gap: 0.4rem; }
  header { justify-content: space-between; }
  h2, h3 { margin: 0; font-size: 1em; }
  section, form, label { display: grid; gap: 0.35rem; }
  section { margin-block: 0.85rem; }
  form { padding: 0.5rem; border: 1px solid var(--workspace-divider); border-radius: 0.45rem; }
  button { justify-self: start; }
  input:not([type="checkbox"]), select, textarea { box-sizing: border-box; width: 100%; font: inherit; }
  label:has(input[type="checkbox"]) { display: flex; gap: 0.3rem; align-items: center; }
</style>
