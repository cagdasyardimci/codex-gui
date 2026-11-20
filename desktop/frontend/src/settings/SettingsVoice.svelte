<script lang="ts">
  import { invoke } from '@tauri-apps/api/core';
  import { onDestroy } from 'svelte';
  import type { PreviewVoice, SettingsSelection, VoiceSettingsView, WorkspaceId } from '../generated/workspace';
  import { SpeechPlayback } from '../speechPlayback';

  let { view, selection, workspaceId, synthetic, save }: {
    view: VoiceSettingsView;
    selection: SettingsSelection;
    workspaceId: WorkspaceId | null;
    synthetic: boolean;
    save: (voice: string) => Promise<boolean | undefined>;
  } = $props();

  let choosing = $state(false);
  let choice = $state('');
  let saving = $state(false);
  let playback: SpeechPlayback | undefined;

  const languages = $derived([...new Set(view.voices.map((voice) => voice.language).filter(Boolean))]
    .sort((left, right) => (left ?? '').localeCompare(right ?? '')));
  const selectedLabel = $derived(view.voices.find((voice) => voice.id === view.selected)?.label ?? 'Default');

  function play(choice: string) {
    playback?.stop();
    const voice = choice || view.defaultVoice;
    if (!voice || !view.preview || !view.voices.some((entry) => entry.id === voice)) return;
    const player = new SpeechPlayback(synthetic);
    playback = player;
    player.start((id, events) => {
      const request: PreviewVoice = { selection, workspaceId, id, voice };
      return invoke('preview_voice', { request, events });
    });
  }

  function open() {
    choice = view.selected;
    choosing = true;
  }

  function close() {
    playback?.stop();
    playback = undefined;
    choosing = false;
  }

  async function done() {
    playback?.stop();
    playback = undefined;
    if (choice === view.selected || view.managed) {
      close();
      return;
    }
    saving = true;
    try {
      if (await save(choice)) close();
    } finally {
      saving = false;
    }
  }

  onDestroy(() => playback?.stop());
</script>

<section aria-label="Voice">
  {#if choosing}
    <label>
      Voice
      <select aria-label="Voice" value={choice} disabled={saving}
        onchange={(event) => { choice = event.currentTarget.value; play(choice); }}>
        <option value="">Default</option>
        {#each view.voices.filter((voice) => !voice.language) as voice (voice.id)}
          <option value={voice.id}>{voice.label}</option>
        {/each}
        {#each languages as language (language)}
          <optgroup label={language ?? ''}>
            {#each view.voices.filter((voice) => voice.language === language) as voice (voice.id)}
              <option value={voice.id}>{voice.label}</option>
            {/each}
          </optgroup>
        {/each}
      </select>
    </label>
    {#if view.preview && (choice || view.defaultVoice)}<button type="button" disabled={saving} onclick={() => play(choice)}>Play Sample</button>{/if}
    <button type="button" disabled={saving} onclick={close}>Cancel</button>
    <button type="button" disabled={saving || (view.managed && choice !== view.selected)}
      onclick={() => void done()}>Done</button>
  {:else}
    <div>Default Voice <span id="configured-voice">{selectedLabel}</span></div>
    <button type="button" onclick={open}>Choose Voice…</button>
  {/if}
</section>
