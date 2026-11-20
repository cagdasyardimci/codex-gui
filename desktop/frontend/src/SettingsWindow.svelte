<script lang="ts">
  import { onMount } from 'svelte';
  import type { SettingsView } from './generated/workspace';
  import { closeSettings, openSettings, refreshSettings, signOutSettings } from './settingsIpc';

  let { close, accountBusy }: { close: () => void; accountBusy: boolean } = $props();
  const session = crypto.randomUUID();
  let dialog: HTMLDialogElement;
  let tab = $state<'account' | 'usage' | 'configuration'>('account');
  let view = $state<SettingsView>();
  let confirming = $state(false);
  let busy = $state(false);
  let retired = false;

  const labels: Record<string, string> = {
    model_provider: 'Provider', model: 'Default Model', review_model: 'Review Model',
    model_reasoning_effort: 'Reasoning Effort', model_verbosity: 'Verbosity', service_tier: 'Service Tier',
    approval_policy: 'Approval Policy', approvals_reviewer: 'Approval Reviewer', sandbox_mode: 'Sandbox Mode',
    web_search: 'Web Search', forced_login_method: 'Sign-in Method',
  };

  onMount(() => {
    dialog.showModal();
    void read(() => openSettings(session));
    return () => {
      retired = true;
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
    else close();
  }
</script>

<dialog bind:this={dialog} aria-label="Settings" oncancel={escape} onkeydown={(event) => event.stopPropagation()}>
  <header>
    <h2>Settings</h2>
    <div class="controls">
      <button type="button" disabled={busy} onclick={() => void read(() => refreshSettings(session))}>Refresh Settings</button>
      <button type="button" onclick={close}>Close</button>
    </div>
  </header>
  <nav aria-label="Settings Sections">
    <button type="button" aria-pressed={tab === 'account'} onclick={() => { tab = 'account'; confirming = false; }}>Account</button>
    <button type="button" aria-pressed={tab === 'usage'} onclick={() => { tab = 'usage'; confirming = false; }}>Usage &amp; Billing</button>
    <button type="button" aria-pressed={tab === 'configuration'} onclick={() => { tab = 'configuration'; confirming = false; }}>Configuration</button>
  </nav>

  {#if view && tab === 'account'}
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
    </section>
  {:else if view && tab === 'configuration'}
    <section aria-label="Effective Configuration">
      <dl>
        {#each view.configuration as item (item.key)}
          <dt>{item.managed ? 'Managed ' : ''}{labels[item.key]}</dt><dd>{item.value}</dd>
        {/each}
      </dl>
    </section>
  {/if}
</dialog>

<style>
  dialog { background: Canvas; color: CanvasText; inline-size: min(42rem, 86vw); min-block-size: 17rem; max-block-size: 80vh;
    border: 1px solid var(--workspace-divider); border-radius: 0.6rem; padding: 1rem; }
  header, nav, .controls { display: flex; align-items: center; flex-wrap: wrap; gap: 0.55rem; }
  header { justify-content: space-between; }
  h2 { margin: 0; font-size: 1.2rem; }
  nav { margin-block: 1rem 0.7rem; padding-block-end: 0.5rem; border-block-end: 1px solid var(--workspace-divider); }
  nav button[aria-pressed="true"] { background: color-mix(in srgb, CanvasText 15%, Canvas); }
  dl { display: grid; grid-template-columns: minmax(10rem, max-content) 1fr; gap: 0.5rem 0.85rem; }
  dd { margin: 0; overflow-wrap: anywhere; }
  .limits dd { display: flex; flex-wrap: wrap; align-items: center; gap: 0.5rem; }
  meter { width: 4.5rem; }
  table { inline-size: 100%; border-collapse: collapse; }
  th, td { padding: 0.4rem; border-block-end: 1px solid var(--workspace-divider); text-align: start; }
</style>
