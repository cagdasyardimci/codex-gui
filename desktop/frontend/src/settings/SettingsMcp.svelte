<script lang="ts">
  import type { McpSettingsForm, SettingsIntegrations } from '../generated/workspace';
  import { readSettingsMcp, type ApplyIntegration, type IntegrationScope } from '../settingsIpc';

  let { integrations, scope, busy, apply }: {
    integrations?: SettingsIntegrations;
    scope?: IntegrationScope;
    busy: boolean;
    apply: ApplyIntegration;
  } = $props();
  let draft = $state<{ owner: string; name: string; existing: boolean; form: McpSettingsForm }>();
  let remove = $state<{ name: string; scope: IntegrationScope }>();
  let loading = $state(false);

  function add() {
    if (!scope) return;
    draft = { owner: scope.owner, name: '', existing: false, form: {
      transport: 'standardIo', endpoint: '', arguments: '', environment: '', environmentVariables: '',
      workingDirectory: '', headers: '', environmentHeaders: '', tokenVariable: '',
    } };
  }

  async function edit(name: string) {
    if (!scope || loading) return;
    const captured = scope;
    loading = true;
    try {
      const form = await readSettingsMcp(captured.selection, name);
      if (scope?.selection.revision === captured.selection.revision) {
        draft = { owner: captured.owner, name, existing: true, form };
      }
    } catch (error) {
      console.error(error);
    } finally {
      loading = false;
    }
  }

  async function save() {
    if (!draft || !scope || draft.owner !== scope.owner || busy) return;
    const {name, existing, form} = $state.snapshot(draft);
    if (await apply({type: 'saveMcp', name, existing, form}, scope)) draft = undefined;
  }
</script>

<section aria-label="MCP Servers">
  {#if draft}
    <form onsubmit={(event) => { event.preventDefault(); void save(); }}>
      <label>Server Name <input bind:value={draft.name} readonly={draft.existing} maxlength="128" /></label>
      <label>Transport
        <select bind:value={draft.form.transport}>
          <option value="standardIo">Standard I/O</option><option value="http">HTTP</option>
        </select>
      </label>
      {#if draft.form.transport === 'standardIo'}
        <label>Command <input bind:value={draft.form.endpoint} /></label>
        <label>Arguments <textarea rows="3" bind:value={draft.form.arguments} spellcheck="false"></textarea></label>
        <label>Environment Variables (Name=Value) <textarea rows="3" bind:value={draft.form.environment} spellcheck="false"></textarea></label>
        <label>Environment Variable Names <textarea rows="2" bind:value={draft.form.environmentVariables} spellcheck="false"></textarea></label>
        <label>Working Directory <input bind:value={draft.form.workingDirectory} /></label>
      {:else}
        <label>Server URL <input bind:value={draft.form.endpoint} /></label>
        <label>HTTP Headers (Name=Value) <textarea rows="3" bind:value={draft.form.headers} spellcheck="false"></textarea></label>
        <label>Environment Headers (Name=Variable) <textarea rows="3" bind:value={draft.form.environmentHeaders} spellcheck="false"></textarea></label>
        <label>Bearer Token Variable <input bind:value={draft.form.tokenVariable} /></label>
      {/if}
      <div class="controls">
        <button type="button" onclick={() => { draft = undefined; }}>Cancel MCP Server</button>
        <button type="submit" disabled={busy || scope?.owner !== draft.owner || !draft.name.trim() || !draft.form.endpoint.trim()}>Save MCP Server</button>
      </div>
    </form>
  {:else}
    {#if integrations?.canAddMcp}
      <button type="button" disabled={busy || loading} onclick={add}>Add MCP Server</button>
    {/if}
    <ul>
      {#each integrations?.mcpServers ?? [] as server (server.name)}
        <li>
          <label><input type="checkbox" checked={server.enabled} disabled={busy || !server.editable}
            onchange={(event) => {
              const enabled = event.currentTarget.checked;
              event.currentTarget.checked = server.enabled;
              if (scope) void apply({type: 'toggleMcp', name: server.name, enabled}, scope);
            }} />{server.name}</label>
          {#if server.editable}
            <button type="button" disabled={busy || loading} aria-label={`Edit ${server.name}`} onclick={() => void edit(server.name)}>Edit</button>
            <button type="button" disabled={busy || loading} aria-label={`Remove ${server.name}`} onclick={() => {
              if (scope) remove = {name: server.name, scope};
            }}>Remove…</button>
          {/if}
          {#if server.canAuthenticate}
            <button type="button" disabled={busy || loading} aria-label={`Authenticate ${server.name}`} onclick={() => {
              if (scope) void apply({type: 'authenticateMcp', name: server.name}, scope);
            }}>Authenticate</button>
          {/if}
        </li>
      {/each}
    </ul>
    {#if remove}
      <div class="controls" aria-label="Remove MCP Server">
        <span>{remove.name}</span>
        <button type="button" onclick={() => { remove = undefined; }}>Cancel</button>
        <button type="button" disabled={busy} onclick={() => {
          if (!remove) return;
          const pending = remove;
          remove = undefined;
          void apply({type: 'removeMcp', name: pending.name}, pending.scope);
        }}>Remove MCP Server</button>
      </div>
    {/if}
  {/if}
</section>

<style>
  form { display: grid; gap: 0.55rem; }
  form label { display: grid; gap: 0.2rem; }
  form textarea { resize: vertical; }
  ul { display: grid; gap: 0.55rem; padding: 0; list-style: none; }
  li, .controls { display: flex; align-items: center; flex-wrap: wrap; gap: 0.5rem; }
</style>
