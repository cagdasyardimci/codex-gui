<script lang="ts">
  import { onMount, tick } from 'svelte';
  import type { AppearanceView, InstructionsView, SettingsIntegrationAction, SettingsSelection, SettingsView, UsageResetOffer, WorkspaceId } from './generated/workspace';
  import {
    changeSettingsIntegration, closeSettings, deleteSettingsMemories, openSettings, readSettingsInstructions, redeemSettingsReset, refreshSettings,
    saveSettingsInstructions, setEffortVisibility, signOutSettings, writeSettings,
    type IntegrationScope,
  } from './settingsIpc';
  import SettingsBrowser from './settings/SettingsBrowser.svelte';
  import SettingsCatalog from './settings/SettingsCatalog.svelte';
  import SettingsMcp from './settings/SettingsMcp.svelte';
  import SettingsAppearance from './settings/SettingsAppearance.svelte';
  import SettingsVoice from './settings/SettingsVoice.svelte';
  import SettingsNotifications from './settings/SettingsNotifications.svelte';
  import SettingsConnections from './settings/SettingsConnections.svelte';
  import { matchSettings, settingsSections, type SettingsMatch, type SettingsSection } from './settings/settingsSearch';

  let { close, accountBusy, appearance, appearanceChanged, workspaceId, syntheticSpeech }: {
    close: () => void;
    accountBusy: boolean;
    appearance?: AppearanceView;
    appearanceChanged: (value: AppearanceView) => void;
    workspaceId: WorkspaceId | null;
    syntheticSpeech: boolean;
  } = $props();
  const session = crypto.randomUUID();
  let dialog: HTMLDialogElement;
  let tab = $state<SettingsSection>('account');
  let search = $state('');
  const matches = $derived(matchSettings(search).filter((entry) => entry.section !== 'voice' || !!view?.voice));
  let view = $state<SettingsView>();
  const integrationScope = $derived(view && {
    selection: { session, revision: view.revision }, owner: view.integrationOwner,
  });
  let confirming = $state(false);
  let busy = $state(false);
  let edits = $state<Record<string, string | boolean | null>>({});
  let retired = false;
  let reset = $state.raw<{ selection: SettingsSelection; offer: UsageResetOffer }>();
  let deleteMemories = $state(false);
  let reloadInstructions = $state(false);
  let instructions = $state<InstructionsView>();
  let instructionText = $state('');
  let instructionsBusy = $state(false);
  const instructionDirty = $derived(!!instructions && instructionText !== instructions.text);

  const labels: Record<string, string> = {
    model_provider: 'Provider', model: 'Default Model', review_model: 'Review Model',
    model_reasoning_effort: 'Reasoning Effort', model_verbosity: 'Verbosity', service_tier: 'Service Tier',
    model_reasoning_summary: 'Reasoning Summary',
    approval_policy: 'Approval Policy', approvals_reviewer: 'Approval Reviewer', sandbox_mode: 'Sandbox Mode',
    web_search: 'Web Search', forced_login_method: 'Sign-in Method',
  };

  onMount(() => {
    dialog.showModal();
    void read(() => openSettings(session));
    return () => {
      retired = true;
      if (dialog.open) dialog.close();
      void closeSettings(session).catch(console.error);
    };
  });

  async function read(operation: () => Promise<SettingsView>) {
    if (busy) return;
    busy = true;
    view = undefined;
    try {
      const next = await operation();
      if (!retired) view = next;
    } catch (error) {
      if (!retired) console.error(error);
    } finally {
      if (!retired) busy = false;
    }
  }

  function signOut() {
    if (!view?.account.canSignOut || accountBusy) return;
    const selection = { session, revision: view.revision };
    confirming = false;
    void read(() => signOutSettings(selection));
  }

  function selectTab(next: SettingsSection) {
    tab = next;
    confirming = false;
    deleteMemories = false;
    reloadInstructions = false;
    reset = undefined;
    if (next === 'personalization' && view?.instructionsAvailable && !instructions) void loadInstructions();
  }

  async function openSearchMatch(match: SettingsMatch) {
    search = '';
    selectTab(match.section);
    await tick();
    const label = match.focus;
    const field = label && (dialog.querySelector<HTMLElement>(`[aria-label="${CSS.escape(label)}"]:not(section):not([disabled])`)
      ?? [...dialog.querySelectorAll<HTMLButtonElement>('button:enabled')].find((button) => button.textContent?.trim() === label));
    const target = field || dialog.querySelector<HTMLElement>('nav button[aria-pressed="true"]');
    target?.focus();
  }

  function prepareReset(offer: UsageResetOffer) {
    if (!view || busy) return;
    reset = { selection: { session, revision: view.revision }, offer };
  }

  function useReset() {
    const pending = reset;
    if (!pending || busy) return;
    reset = undefined;
    void read(() => redeemSettingsReset({ selection: pending.selection, creditId: pending.offer.id }));
  }

  function clearMemories() {
    if (!view?.memories || busy) return;
    const selection = { session, revision: view.revision };
    deleteMemories = false;
    void read(() => deleteSettingsMemories(selection));
  }

  async function loadInstructions() {
    if (instructionsBusy) return;
    reloadInstructions = false;
    instructionsBusy = true;
    try {
      const next = await readSettingsInstructions(session);
      if (!retired) {
        instructions = next;
        instructionText = next.text;
      }
    } catch (error) {
      if (!retired) console.error(error);
    } finally {
      if (!retired) instructionsBusy = false;
    }
  }

  async function saveInstructions() {
    if (!instructions || !instructionDirty || instructionsBusy) return;
    const text = instructionText;
    instructionsBusy = true;
    try {
      const next = await saveSettingsInstructions({ session, revision: instructions.revision, text });
      if (!retired) {
        instructions = next;
        if (instructionText === text) instructionText = next.text;
      }
    } catch (error) {
      if (!retired) console.error(error);
    } finally {
      if (!retired) instructionsBusy = false;
    }
  }

  async function saveConfiguration(key: string) {
    if (!view || busy || !(key in edits)) return;
    const selection = { session, revision: view.revision };
    const draft = edits[key]!;
    const value = key === 'memories.disable_on_external_context' ? !draft : draft;
    busy = true;
    try {
      const result = await writeSettings({ selection, key, value });
      if (!retired) {
        view = result.view;
        if (result.confirmed) delete edits[key];
        return result.confirmed;
      }
    } catch (error) {
      if (!retired) console.error(error);
    } finally {
      if (!retired) busy = false;
    }
  }

  async function showEffort(effort: string, visible: boolean) {
    if (!view || busy) return;
    const selection = { session, revision: view.revision };
    busy = true;
    try {
      const next = await setEffortVisibility({ selection, effort, visible });
      if (!retired) view = next;
    } catch (error) {
      if (!retired) console.error(error);
    } finally {
      if (!retired) busy = false;
    }
  }

  async function applyIntegration(action: SettingsIntegrationAction, scope: IntegrationScope): Promise<boolean> {
    if (!view || busy || view.integrationOwner !== scope.owner || view.revision !== scope.selection.revision) return false;
    busy = true;
    try {
      const result = await changeSettingsIntegration({ ...scope, action });
      if (retired) return false;
      view = result.view;
      return result.confirmed;
    } catch (error) {
      if (!retired) console.error(error);
      return false;
    } finally {
      if (!retired) busy = false;
    }
  }

  function windowName(minutes: number | null) {
    if (!minutes) return 'Usage Limit';
    if (minutes === 10_080) return 'Weekly Limit';
    if (minutes % 1_440 === 0) return `${minutes / 1_440}-Day Limit`;
    if (minutes % 60 === 0) return `${minutes / 60}-Hour Limit`;
    return `${minutes}-Minute Limit`;
  }

  function resetTime(seconds: number | null) {
    if (seconds === null) return;
    const time = new Date(seconds * 1000);
    if (Number.isFinite(time.getTime())) return time;
  }

  function escape(event: Event) {
    event.preventDefault();
    if (confirming) confirming = false;
    else if (deleteMemories) deleteMemories = false;
    else if (reloadInstructions) reloadInstructions = false;
    else if (reset) reset = undefined;
    else if (search.trim()) search = '';
    else close();
  }
</script>

{#snippet toggleSetting(key: string, label: string, current: boolean, managed: boolean)}
  <div class="edit-setting">
    <label><input type="checkbox" checked={key in edits ? edits[key] === true : current}
      disabled={managed || busy} onchange={(event) => { edits[key] = event.currentTarget.checked; }} />{label}</label>
    {#if !managed}<button type="button" disabled={busy || !(key in edits) || edits[key] === current}
      onclick={() => void saveConfiguration(key)}>Save {label}</button>{/if}
  </div>
{/snippet}

<dialog bind:this={dialog} aria-label="Settings" oncancel={escape} onkeydown={(event) => event.stopPropagation()}>
  <header>
    <h2>Settings</h2>
    <div class="controls">
      <input type="search" aria-label="Search Settings" placeholder="Search Settings" bind:value={search}
        onkeydown={(event) => {
          if (event.key === 'Enter' && !event.isComposing && matches[0]) {
            event.preventDefault();
            void openSearchMatch(matches[0]);
          }
        }} />
      <button type="button" disabled={busy} onclick={() => {
        reset = undefined;
        void read(() => refreshSettings(session));
      }}>Refresh Settings</button>
      <button type="button" onclick={close}>Close</button>
    </div>
  </header>
  {#if search.trim()}
    <nav aria-label="Settings Search Results">
      {#each matches as match (match.label)}
        <button type="button" onclick={() => void openSearchMatch(match)}>{match.label}</button>
      {/each}
    </nav>
  {:else}
    <nav aria-label="Settings Sections">
      {#each settingsSections as section (section.id)}
        {#if section.id !== 'voice' || view?.voice}
          <button type="button" aria-pressed={tab === section.id} onclick={() => selectTab(section.id)}>{section.title}</button>
        {/if}
      {/each}
    </nav>
  {/if}

  <div hidden={!!search.trim()}>
  {#if tab === 'appearance'}
    <SettingsAppearance view={appearance} changed={appearanceChanged} />
  {:else if tab === 'notifications'}
    <SettingsNotifications />
  {:else if tab === 'connections'}
    <SettingsConnections {session} {workspaceId} />
  {:else if tab === 'voice' && view?.voice}
    <SettingsVoice view={view.voice} selection={{ session, revision: view.revision }} {workspaceId}
      synthetic={syntheticSpeech} save={(voice) => {
        edits['realtime.voice'] = voice || null;
        return saveConfiguration('realtime.voice');
      }} />
  {:else if view && tab === 'account'}
    <section aria-label="Account">
      <dl>
        {#if view.account.email}<dt>Email</dt><dd>{view.account.email}</dd>{/if}
        {#if view.account.plan}<dt>Plan</dt><dd>{view.account.plan}</dd>{/if}
        {#if view.account.provider}<dt>Provider</dt><dd>{view.account.provider}</dd>{/if}
      </dl>
      {#if view.account.canSignOut}
        {#if confirming}
          <div class="controls" aria-label="Sign Out">
            <button type="button" onclick={() => { confirming = false; }}>Cancel</button>
            <button type="button" disabled={accountBusy} onclick={signOut}>Sign Out</button>
          </div>
        {:else}
          <button type="button" disabled={accountBusy} onclick={() => { confirming = true; }}>Sign Out…</button>
        {/if}
      {/if}
    </section>
  {:else if view && tab === 'usage'}
    <section aria-label="Usage and Billing">
      {#if view.limits.length}
        <dl class="limits">
          {#each view.limits as limit}
            {@const resets = resetTime(limit.resetsAt)}
            <dt>{limit.name} {windowName(limit.minutes)}</dt>
            <dd>
              {#if limit.remainingPercent !== null}
                <meter min="0" max="100" value={limit.remainingPercent}
                  aria-label={`${limit.name} ${windowName(limit.minutes)} Remaining`}></meter>
                <span>{limit.remainingPercent.toLocaleString(undefined, { maximumFractionDigits: 1 })}% Remaining</span>
              {/if}
              {#if resets}
                <time datetime={resets.toISOString()}>{resets.toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' })}</time>
              {/if}
            </dd>
          {/each}
        </dl>
      {/if}
      {#if view.dailyUsage?.length}
        <table aria-label="Daily Token Usage">
          <thead><tr><th scope="col">Date</th><th scope="col">Tokens</th></tr></thead>
          <tbody>
            {#each view.dailyUsage as day (day.date)}
              <tr><td><time datetime={day.date}>{day.date}</time></td><td>{day.tokens.toLocaleString()}</td></tr>
            {/each}
          </tbody>
        </table>
      {/if}
      {#if view.resetBalance !== null}
        <dl aria-label="Usage Resets"><dt>Usage Reset Credits</dt><dd>{view.resetBalance.toLocaleString()}</dd></dl>
      {/if}
      {#if reset}
        <div class="controls" aria-label="Use Usage Reset">
          <span>{reset.offer.title}</span>
          <button type="button" onclick={() => { reset = undefined; }}>Cancel</button>
          <button type="button" disabled={busy} onclick={useReset}>Use Reset</button>
        </div>
      {:else if view.resetOffers.length}
        <ul class="reset-offers" aria-label="Available Usage Resets">
          {#each view.resetOffers as offer (offer.id)}
            {@const expires = resetTime(offer.expiresAt)}
            <li>
              <span>{offer.title}</span>
              {#if expires}<time datetime={expires.toISOString()}>{expires.toLocaleDateString(undefined, { dateStyle: 'medium' })}</time>{/if}
              <button type="button" disabled={busy} aria-label={`Use ${offer.title}`} onclick={() => prepareReset(offer)}>Use Reset…</button>
            </li>
          {/each}
        </ul>
      {/if}
    </section>
  {:else if view && tab === 'configuration'}
    <section aria-label="Effective Configuration">
      <dl>
        {#each view.configuration as item (item.key)}
          {@const label = labels[item.key] ?? item.key}
          {@const selection = item.key in edits ? edits[item.key] ?? '' : item.value}
          <dt>{item.managed ? 'Managed ' : ''}{label}</dt>
          <dd>
            {#if item.choices.length}
              <div class="edit-setting">
                <select aria-label={label} value={selection} disabled={busy}
                  onchange={(event) => { edits[item.key] = event.currentTarget.value || null; }}>
                  {#if !item.choices.includes(String(selection))}
                    <option value={String(selection)} disabled>{selection || 'Default'}</option>
                  {/if}
                  {#each item.choices as choice (choice)}<option value={choice}>{choice || 'Default'}</option>{/each}
                </select>
                <button type="button" disabled={busy || !(item.key in edits) || (edits[item.key] ?? '') === item.value}
                  onclick={() => void saveConfiguration(item.key)}>Save {label}</button>
              </div>
            {:else}
              {item.value}
            {/if}
          </dd>
        {/each}
      </dl>
      {#if view.networkAccess}
        {@render toggleSetting('sandbox_workspace_write.network_access', 'Network Access',
          view.networkAccess.enabled, view.networkAccess.managed)}
      {/if}
      {#if view.compression}
        {@render toggleSetting('features.local_thread_store_compression', 'Compress Local Chat History',
          view.compression.enabled, view.compression.managed)}
      {/if}
      {#if view.efforts.length}
        <fieldset>
          <legend>Available Reasoning Efforts</legend>
          {#each view.efforts as effort (effort.effort)}
            <label><input type="checkbox" checked={effort.visible} disabled={busy || effort.required}
              onchange={(event) => {
                const visible = event.currentTarget.checked;
                event.currentTarget.checked = effort.visible;
                void showEffort(effort.effort, visible);
              }} />{effort.effort === 'xhigh' ? 'Extra High' : effort.effort}</label>
          {/each}
        </fieldset>
      {/if}
    </section>
  {:else if view && tab === 'personalization'}
    {#if view.memories}
      <section aria-label="Memories">
        {@render toggleSetting('features.memories', 'Enable Codex Memories',
          view.memories.enabled.enabled, view.memories.enabled.managed)}
        {@render toggleSetting('memories.disable_on_external_context', 'Allow Memories from Tool-assisted Chats',
          view.memories.allowExternalContext.enabled, view.memories.allowExternalContext.managed || !view.memories.enabled.enabled)}
        {#if deleteMemories}
          <div class="controls" aria-label="Delete Memories">
            <button type="button" onclick={() => { deleteMemories = false; }}>Cancel</button>
            <button type="button" disabled={busy} onclick={clearMemories}>Delete Memories</button>
          </div>
        {:else}
          <button type="button" disabled={busy} onclick={() => { deleteMemories = true; }}>Delete Memories…</button>
        {/if}
      </section>
    {/if}
    {#if view.instructionsAvailable}
      <section class="instructions" aria-label="Codex Instructions">
        <label>Codex Instructions
          <textarea rows="8" aria-label="Codex Instructions" spellcheck="false"
            readonly={!instructions || instructionsBusy} bind:value={instructionText}></textarea>
        </label>
        <div class="controls">
          <button type="button" disabled={!instructionDirty || instructionsBusy}
            onclick={() => void saveInstructions()}>Save Instructions</button>
          {#if reloadInstructions}
            <button type="button" onclick={() => { reloadInstructions = false; }}>Cancel Reload</button>
            <button type="button" disabled={instructionsBusy} onclick={() => void loadInstructions()}>Reload Instructions</button>
          {:else}
            <button type="button" disabled={instructionsBusy}
              onclick={() => { if (instructionDirty) reloadInstructions = true; else void loadInstructions(); }}>Reload Instructions…</button>
          {/if}
        </div>
      </section>
    {/if}
  {:else if tab === 'mcp'}
    <SettingsMcp integrations={view?.integrations} scope={integrationScope} {busy} apply={applyIntegration} />
  {:else if tab === 'browser'}
    <SettingsBrowser browser={view?.integrations.browser} scope={integrationScope} {busy} apply={applyIntegration} />
  {:else if tab === 'plugins' || tab === 'skills' || tab === 'hooks'}
    {#key tab}
      <SettingsCatalog kind={tab} scope={integrationScope} canAddMarketplace={view?.integrations.canAddMarketplace ?? false}
        {busy} apply={applyIntegration} />
    {/key}
  {/if}
  </div>
</dialog>

<style>
  @font-face {
    font-family: "Settings Inter";
    src: url('./assets/Inter-SemiBold.woff2') format('woff2');
    font-weight: 600;
    font-display: swap;
  }
  dialog { background: var(--workspace-canvas); color: var(--workspace-text); inline-size: min(42rem, 86vw); min-block-size: 17rem; max-block-size: 80vh;
    border: 1px solid var(--workspace-divider); border-radius: 0.6rem; padding: 1rem; }
  header, nav, .controls { display: flex; align-items: center; flex-wrap: wrap; gap: 0.55rem; }
  header { justify-content: space-between; }
  h2 { margin: 0; font: 600 calc(var(--workspace-ui-size, 14px) + 4px) / 1.33 var(--workspace-ui-font, "Settings Inter"), system-ui, sans-serif; }
  nav { margin-block: 1rem 0.7rem; padding-block-end: 0.5rem; border-block-end: 1px solid var(--workspace-divider); }
  nav button[aria-pressed="true"] { background: color-mix(in srgb, CanvasText 15%, Canvas); }
  dl { display: grid; grid-template-columns: minmax(10rem, max-content) 1fr; gap: 0.5rem 0.85rem; }
  dd { margin: 0; overflow-wrap: anywhere; }
  .limits dd { display: flex; flex-wrap: wrap; align-items: center; gap: 0.5rem; }
  .edit-setting, fieldset { display: flex; flex-wrap: wrap; align-items: center; gap: 0.45rem; }
  fieldset { margin-block-start: 0.7rem; }
  .reset-offers { display: grid; gap: 0.4rem; list-style: none; margin: 0; padding: 0; }
  .reset-offers li { display: flex; flex-wrap: wrap; align-items: center; gap: 0.6rem; }
  .instructions { display: grid; gap: 0.55rem; margin-block-start: 1rem; }
  textarea { box-sizing: border-box; inline-size: 100%; resize: vertical; }
  meter { width: 4.5rem; }
  table { inline-size: 100%; border-collapse: collapse; }
  th, td { padding: 0.4rem; border-block-end: 1px solid var(--workspace-divider); text-align: start; }
</style>
