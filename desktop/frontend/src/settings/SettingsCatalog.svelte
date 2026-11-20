<script lang="ts">
  import type { MarketplaceSettings, SettingsCatalog, SettingsCatalogKind, SettingsIntegrationAction } from '../generated/workspace';
  import { readSettingsCatalog, type ApplyIntegration, type IntegrationScope } from '../settingsIpc';

  let { kind, scope, canAddMarketplace, busy, apply }: {
    kind: SettingsCatalogKind;
    scope?: IntegrationScope;
    canAddMarketplace: boolean;
    busy: boolean;
    apply: ApplyIntegration;
  } = $props();
  let catalog = $state.raw<SettingsCatalog>();
  let reading = $state(false);
  let generation = 0;
  let search = $state('');
  let filter = $state<'all' | 'installed' | 'markets'>('all');
  let marketDraft = $state<{ source: string; reference: string; owner: string }>();
  let confirm = $state<{ action: SettingsIntegrationAction; label: string; title: string; scope: IntegrationScope }>();
  const titles: Record<SettingsCatalogKind, string> = {plugins: 'Plugins', skills: 'Skills', hooks: 'Hooks'};
  const title = $derived(titles[kind]);
  const needle = $derived(search.trim().toLocaleLowerCase());

  $effect(() => {
    if (scope) void reload(scope, kind);
    else { generation += 1; catalog = undefined; }
    return () => { generation += 1; };
  });

  async function reload(captured: IntegrationScope, catalogKind: SettingsCatalogKind) {
    const token = ++generation;
    reading = true;
    catalog = undefined;
    try {
      const loaded = await readSettingsCatalog(captured.selection, catalogKind);
      if (token === generation) catalog = loaded;
    } catch (error) {
      if (token === generation) console.error(error);
    } finally {
      if (token === generation) reading = false;
    }
  }

  function includes(text: string) {
    return !needle || text.toLocaleLowerCase().includes(needle);
  }

  function visiblePlugins(market: MarketplaceSettings) {
    return market.plugins.filter((plugin) => (filter !== 'installed' || plugin.installed) &&
      (includes(market.title) || includes(plugin.title) || includes(plugin.description ?? '')));
  }

  function prepare(action: SettingsIntegrationAction, label: string, title: string) {
    if (scope) confirm = { action, label, title, scope };
  }

  function run(action: SettingsIntegrationAction) {
    if (scope) void apply(action, scope);
  }

  async function addMarketplace() {
    if (!scope || !marketDraft || scope.owner !== marketDraft.owner || busy) return;
    const source = marketDraft.source.trim();
    if (!source) return;
    if (await apply({type: 'addMarketplace', source, reference: marketDraft.reference.trim() || null}, scope)) {
      marketDraft = undefined;
      filter = 'markets';
    }
  }
</script>

<section aria-label={title}>
  <div class="controls">
    <button type="button" disabled={busy || reading || !scope} onclick={() => {
      if (scope) void reload(scope, kind);
    }}>Refresh {title}</button>
    {#if kind === 'plugins'}
      <label>Search Plugins <input type="search" bind:value={search} /></label>
      <label>Catalog
        <select bind:value={filter}><option value="all">All Plugins</option>
          <option value="installed">Installed Plugins</option><option value="markets">Marketplaces</option>
        </select>
      </label>
      {#if canAddMarketplace}
        <button type="button" disabled={busy || !scope || !!marketDraft} onclick={() => {
          if (scope) marketDraft = {source: '', reference: '', owner: scope.owner};
        }}>Add Marketplace</button>
      {/if}
    {/if}
  </div>
  {#if marketDraft}
    <form onsubmit={(event) => { event.preventDefault(); void addMarketplace(); }}>
      <label>Marketplace Source <input type="text" bind:value={marketDraft.source} /></label>
      <label>Git Reference <input type="text" bind:value={marketDraft.reference} /></label>
      <button type="button" onclick={() => { marketDraft = undefined; }}>Cancel Marketplace</button>
      <button type="submit" disabled={!canAddMarketplace || busy || scope?.owner !== marketDraft.owner || !marketDraft.source.trim()}>Save Marketplace</button>
    </form>
  {/if}
  {#if confirm}
    <div class="controls" aria-label={confirm.label}>
      <span>{confirm.title}</span>
      <button type="button" onclick={() => { confirm = undefined; }}>Cancel</button>
      <button type="button" disabled={busy || reading} onclick={() => {
        if (!confirm) return;
        const pending = $state.snapshot(confirm);
        confirm = undefined;
        void apply(pending.action, pending.scope);
      }}>{confirm.label}</button>
    </div>
  {/if}
  {#if catalog?.type === 'plugins'}
    {#each catalog.items as market}
      {@const plugins = visiblePlugins(market)}
      {#if filter === 'markets' ? includes(market.title) : plugins.length > 0}
        <article aria-label={market.title}>
          <h3>{market.title}</h3>
          {#if filter === 'markets'}
            {#if market.editable}
              <div class="controls">
                <button type="button" disabled={busy || reading} aria-label={`Upgrade ${market.title}`}
                  onclick={() => run({type: 'upgradeMarketplace', name: market.name})}>Upgrade</button>
                <button type="button" disabled={busy || reading} aria-label={`Remove ${market.title}`}
                  onclick={() => prepare({type: 'removeMarketplace', name: market.name}, 'Remove Marketplace', market.title)}>Remove…</button>
              </div>
            {/if}
          {:else}
            <ul>
              {#each plugins as plugin}
                <li>
                  <span>{plugin.title}</span>
                  {#if plugin.description}<span>{plugin.description}</span>{/if}
                  {#if plugin.installed}
                    <label><input type="checkbox" checked={plugin.enabled} disabled={busy || reading || !plugin.canToggle}
                      aria-label={`Enable ${plugin.title}`} onchange={(event) => {
                        const enabled = event.currentTarget.checked;
                        event.currentTarget.checked = plugin.enabled;
                        run({type: 'togglePlugin', marketplace: market.name, id: plugin.id, enabled});
                      }} />Enabled</label>
                    {#if plugin.removable}
                      <button type="button" disabled={busy || reading} aria-label={`Uninstall ${plugin.title}`}
                        onclick={() => prepare({type: 'removePlugin', marketplace: market.name, id: plugin.id}, 'Uninstall Plugin', plugin.title)}>Uninstall…</button>
                    {/if}
                  {:else if plugin.canInstall}
                    <button type="button" disabled={busy || reading} aria-label={`Install ${plugin.title}`}
                      onclick={() => prepare({type: 'installPlugin', marketplace: market.name, id: plugin.id}, 'Install Plugin', plugin.title)}>Install…</button>
                  {/if}
                </li>
              {/each}
            </ul>
          {/if}
        </article>
      {/if}
    {/each}
  {:else if catalog?.type === 'skills'}
    <ul>
      {#each catalog.items as skill (skill.id)}
        <li>
          <label><input type="checkbox" checked={skill.enabled} disabled={busy || reading || !skill.editable}
            onchange={(event) => {
              const enabled = event.currentTarget.checked;
              event.currentTarget.checked = skill.enabled;
              run({type: 'toggleSkill', id: skill.id, enabled});
            }} />{skill.name}</label>
          {#if skill.description}<span>{skill.description}</span>{/if}
        </li>
      {/each}
    </ul>
  {:else if catalog?.type === 'hooks'}
    <ul>
      {#each catalog.items as hook}
        <li>
          <label><input type="checkbox" checked={hook.enabled} disabled={busy || reading || !hook.editable}
            onchange={(event) => {
              const enabled = event.currentTarget.checked;
              event.currentTarget.checked = hook.enabled;
              run({type: 'toggleHook', key: hook.key, enabled});
            }} />{hook.event}</label>
          <span>{hook.path}</span>
          {#if hook.editable && !hook.trusted}
            <button type="button" disabled={busy || reading} aria-label={`Trust ${hook.event}`}
              onclick={() => prepare({type: 'trustHook', key: hook.key}, 'Trust Hook', hook.path)}>Trust…</button>
          {/if}
        </li>
      {/each}
    </ul>
  {/if}
</section>

<style>
  section, article { display: grid; gap: 0.6rem; }
  h3 { margin: 0; font-size: 1rem; }
  form, .controls, li { display: flex; align-items: center; flex-wrap: wrap; gap: 0.55rem; }
  ul { display: grid; gap: 0.55rem; padding: 0; list-style: none; margin: 0; }
  li span { overflow-wrap: anywhere; }
</style>
