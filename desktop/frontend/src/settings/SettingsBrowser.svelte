<script lang="ts">
  import type { BrowserChoice, BrowserPermission, BrowserPermissionEdit, BrowserSettings, BrowserSiteSettings } from '../generated/workspace';
  import type { ApplyIntegration, IntegrationScope } from '../settingsIpc';

  let { browser, scope, busy, apply }: {
    browser?: BrowserSettings;
    scope?: IntegrationScope;
    busy: boolean;
    apply: ApplyIntegration;
  } = $props();
  const labels: Record<BrowserPermission, string> = {
    access: 'Browse', downloads: 'Downloads', uploads: 'Uploads', siteTools: 'Site Tools',
  };
  const permissions = Object.keys(labels) as BrowserPermission[];
  let draft = $state<{
    origin: string;
    existing: boolean;
    owner: string;
    edits: Partial<Record<BrowserPermission, BrowserChoice | null>>;
  }>();
  let remove = $state<{ origin: string; scope: IntegrationScope }>();
  const currentSite = $derived(browser?.sites.find((site) => site.origin === draft?.origin));

  function choice(event: Event) {
    const select = event.currentTarget as HTMLSelectElement;
    return select.value === 'allow' || select.value === 'deny' ? select.value : null;
  }

  function edit(site?: BrowserSiteSettings) {
    if (!scope) return;
    draft = { origin: site?.origin ?? '', existing: !!site, owner: scope.owner, edits: {} };
  }

  function editPermission(permission: BrowserPermission, value: BrowserChoice | null) {
    if (!draft) return;
    const prior = currentSite?.permissions.find((setting) => setting.permission === permission)?.choice ?? null;
    if (prior === value) delete draft.edits[permission];
    else draft.edits[permission] = value;
  }

  async function save() {
    if (!scope || !draft || draft.owner !== scope.owner || busy) return;
    const { origin, existing, edits } = $state.snapshot(draft);
    const updates: BrowserPermissionEdit[] = [];
    for (const permission of permissions) {
      if (permission in edits) updates.push({permission, choice: edits[permission] ?? null});
    }
    if (await apply({type: 'saveBrowserSite', origin, existing, edits: updates}, scope)) draft = undefined;
  }
</script>

{#snippet choices()}
  <option value="">Use Default</option><option value="allow">Allow</option><option value="deny">Block</option>
{/snippet}

<section aria-label="Browser">
  {#if browser}
    <div class="controls">
      {#if browser.enabled}
        <label><input type="checkbox" checked={browser.enabled.enabled} disabled={busy || browser.enabled.managed}
          onchange={(event) => {
            if (!browser?.enabled || !scope) return;
            const enabled = event.currentTarget.checked;
            event.currentTarget.checked = browser.enabled.enabled;
            void apply({type: 'setBrowserEnabled', enabled}, scope);
          }} />Browser Use</label>
      {/if}
      {#if browser.siteTools}
        <label><input type="checkbox" checked={browser.siteTools.enabled} disabled={busy || browser.siteTools.managed}
          onchange={(event) => {
            if (!browser?.siteTools || !scope) return;
            const enabled = event.currentTarget.checked;
            event.currentTarget.checked = browser.siteTools.enabled;
            void apply({type: 'setBrowserSiteTools', enabled}, scope);
          }} />Browser Site Tools</label>
      {/if}
      <label>Browser History Access
        <select value={browser.history ?? ''} disabled={busy || browser.historyManaged} onchange={(event) => {
          const selected = choice(event);
          event.currentTarget.value = browser?.history ?? '';
          if (scope) void apply({type: 'setBrowserHistory', choice: selected}, scope);
        }}>{@render choices()}</select>
      </label>
    </div>
    <fieldset>
      <legend>Default Site Permissions</legend>
      {#each browser.defaults as permission (permission.permission)}
        <label>{labels[permission.permission]}
          <select value={permission.choice ?? ''} disabled={busy || permission.managed} onchange={(event) => {
            const selected = choice(event);
            event.currentTarget.value = permission.choice ?? '';
            if (scope) void apply({type: 'setBrowserDefault', edit: {permission: permission.permission, choice: selected}}, scope);
          }}>{@render choices()}</select>
        </label>
      {/each}
    </fieldset>
  {/if}
  {#if draft}
    <form onsubmit={(event) => { event.preventDefault(); void save(); }}>
      <label>Site Origin <input type="text" bind:value={draft.origin} readonly={draft.existing} /></label>
      <fieldset>
        <legend>Site Permissions</legend>
        {#each permissions as permission (permission)}
          {@const setting = currentSite?.permissions.find((item) => item.permission === permission)}
          {@const selected = permission in draft.edits ? draft.edits[permission] : setting?.choice}
          <label>{labels[permission]}
            <select value={selected ?? ''} disabled={busy || setting?.managed === true}
              onchange={(event) => editPermission(permission, choice(event))}>{@render choices()}</select>
          </label>
        {/each}
      </fieldset>
      <div class="controls">
        <button type="button" onclick={() => { draft = undefined; }}>Cancel Site</button>
        <button type="submit" disabled={busy || scope?.owner !== draft.owner || !draft.origin.trim() || !Object.keys(draft.edits).length}>
          Save Site
        </button>
      </div>
    </form>
  {:else if browser}
    {#if browser.canAddSite}<button type="button" disabled={busy} onclick={() => edit()}>Add Site</button>{/if}
    <ul>
      {#each browser.sites as site (site.origin)}
        <li>
          <span>{site.origin}</span>
          {#if site.permissions.some((permission) => !permission.managed)}
            <button type="button" disabled={busy} aria-label={`Edit ${site.origin}`} onclick={() => edit(site)}>Edit</button>
          {:else}
            {#each site.permissions as permission (permission.permission)}
              {#if permission.choice}<span>{labels[permission.permission]} · {permission.choice === 'allow' ? 'Allow' : 'Block'}</span>{/if}
            {/each}
          {/if}
          {#if site.removable}
            <button type="button" disabled={busy} aria-label={`Remove ${site.origin}`} onclick={() => {
              if (scope) remove = {origin: site.origin, scope};
            }}>Remove…</button>
          {/if}
        </li>
      {/each}
    </ul>
    {#if remove}
      <div class="controls" aria-label="Remove Site">
        <span>{remove.origin}</span>
        <button type="button" onclick={() => { remove = undefined; }}>Cancel</button>
        <button type="button" disabled={busy} onclick={() => {
          if (!remove) return;
          const pending = remove;
          remove = undefined;
          void apply({type: 'removeBrowserSite', origin: pending.origin}, pending.scope);
        }}>Remove Site</button>
      </div>
    {/if}
  {/if}
</section>

<style>
  section, form { display: grid; gap: 0.6rem; }
  section > button { justify-self: start; }
  .controls, li, fieldset { display: flex; align-items: center; gap: 0.55rem; flex-wrap: wrap; }
  li span { overflow-wrap: anywhere; }
  ul { display: grid; gap: 0.55rem; padding: 0; list-style: none; margin: 0; }
</style>
