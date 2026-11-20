<script lang="ts">
  import { onMount } from 'svelte';
  import type { NotificationEdit, NotificationView, TaskAlertSound, TaskCompletionAlerts } from '../generated/workspace';
  import { importNotificationSound, readNotifications, requestNotifications, updateNotifications } from './notificationIpc';

  let view = $state.raw<NotificationView>();
  let busy = $state(false);
  let retired = false;
  const sounds: { id: TaskAlertSound; label: string }[] = [
    { id: 'default', label: 'Default' }, { id: 'classic', label: 'Classic' }, { id: 'none', label: 'None' },
    { id: 'basso', label: 'Basso' }, { id: 'glass', label: 'Glass' }, { id: 'ping', label: 'Ping' },
    { id: 'pop', label: 'Pop' }, { id: 'purr', label: 'Purr' }, { id: 'tink', label: 'Tink' },
  ];

  onMount(() => {
    void run(readNotifications);
    return () => { retired = true; };
  });

  async function run(operation: () => Promise<NotificationView>) {
    if (busy) return;
    busy = true;
    try {
      const updated = await operation();
      if (!retired) view = updated;
    } catch (error) {
      console.error(error);
    } finally {
      if (!retired) busy = false;
    }
  }

  function edit(edit: NotificationEdit) {
    const revision = view?.revision;
    if (revision) void run(() => updateNotifications({ revision, edit }));
  }

  function perform(action: (revision: string) => Promise<NotificationView>) {
    const revision = view?.revision;
    if (revision) void run(() => action(revision));
  }
</script>

{#if view}
  <section aria-label="Notifications">
    {#if view.mayRequestPermission}
      <button type="button" disabled={busy} onclick={() => perform(requestNotifications)}>Allow Notifications</button>
    {/if}
    <fieldset disabled={busy}>
      <legend>Task Alerts</legend>
      <label>Task Completion
        <select aria-label="Task Completion" value={view.completions}
          onchange={(event) => edit({type: 'setCompletions', value: event.currentTarget.value as TaskCompletionAlerts})}>
          <option value="always">Always</option>
          <option value="whenUnfocused">Only When Unfocused</option>
          <option value="never">Never</option>
        </select>
      </label>
      <label>
        <input aria-label="Permission Requests" type="checkbox" checked={view.permissions}
          onchange={(event) => edit({type: 'setPermissions', enabled: event.currentTarget.checked})} />Permission Requests
      </label>
      <label>
        <input aria-label="Questions" type="checkbox" checked={view.questions}
          onchange={(event) => edit({type: 'setQuestions', enabled: event.currentTarget.checked})} />Questions
      </label>
    </fieldset>
    <fieldset disabled={busy}>
      <legend>Alert Sound</legend>
      <label>Sound
        <select aria-label="Sound" value={view.sound}
          onchange={(event) => edit({type: 'setSound', sound: event.currentTarget.value as TaskAlertSound})}>
          {#each sounds as sound (sound.id)}<option value={sound.id}>{sound.label}</option>{/each}
          <option value="custom" disabled={!view.customName} hidden={!view.customName}>{view.customName ?? 'Custom'}</option>
        </select>
      </label>
    </fieldset>
    <button type="button" disabled={busy} onclick={() => perform(importNotificationSound)}>Import Sound…</button>
  </section>
{/if}

<style>
  section, fieldset { display: grid; gap: 0.55rem; }
  fieldset { padding: 0.65rem; }
  button { justify-self: start; }
  label { display: flex; align-items: center; flex-wrap: wrap; gap: 0.5rem; }
</style>
