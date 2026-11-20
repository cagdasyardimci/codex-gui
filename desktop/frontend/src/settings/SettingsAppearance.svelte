<script lang="ts">
  import { onMount } from 'svelte';
  import type { AppearanceAccent, AppearanceEdit, AppearanceMode, AppearanceView, ColorRole, TypefaceRole } from '../generated/workspace';
  import { copyDesktopTheme, exportDesktopTheme, hexColor, readDesktopFonts, updateDesktopAppearance } from '../desktopAppearance';

  let { view, changed }: { view?: AppearanceView; changed: (value: AppearanceView) => void } = $props();
  let fonts = $state<string[]>([]);
  let busy = $state(false);
  let exporting = $state(false);
  let retired = false;
  const roles: { role: TypefaceRole; title: string; range: [number, number] }[] = [
    { role: 'ui', title: 'UI', range: [11, 16] },
    { role: 'content', title: 'Content', range: [12, 24] },
    { role: 'code', title: 'Code', range: [8, 24] },
  ];
  const colors: { role: ColorRole; label: string }[] = [
    { role: 'background', label: 'Background' },
    { role: 'foreground', label: 'Foreground' },
    { role: 'accent', label: 'Accent Color' },
    { role: 'diffAdded', label: 'Added Lines' },
    { role: 'diffRemoved', label: 'Removed Lines' },
    { role: 'skill', label: 'Skill Color' },
  ];
  const accents: AppearanceAccent[] = ['default', 'blue', 'green', 'yellow', 'pink', 'orange', 'purple', 'black'];

  onMount(() => {
    void readDesktopFonts().then((choices) => { if (!retired) fonts = choices; }).catch(console.error);
    return () => { retired = true; };
  });

  async function edit(change: AppearanceEdit) {
    if (!view || busy) return;
    const { selection } = view;
    busy = true;
    try {
      changed(await updateDesktopAppearance({ selection, edit: change }));
    } catch (error) {
      console.error(error);
    } finally {
      if (!retired) busy = false;
    }
  }

  function setColor(role: ColorRole, text: string) {
    const hex = text.trim().replace(/^#/, '');
    if (/^[0-9a-f]{6}$/i.test(hex)) void edit({type: 'setColor', role, color: parseInt(hex, 16)});
  }

  async function output(exportingTheme: boolean) {
    if (!view || (exportingTheme && exporting)) return;
    const { selection } = view;
    if (exportingTheme) exporting = true;
    try {
      await (exportingTheme ? exportDesktopTheme(selection) : copyDesktopTheme(selection));
    } catch (error) {
      console.error(error);
    } finally {
      if (!retired && exportingTheme) exporting = false;
    }
  }
</script>

{#if view}
  <section aria-label="Appearance">
    <fieldset disabled={busy}>
      <legend>Visual Style</legend>
      <label>Appearance Mode
        <select aria-label="Appearance Mode" value={view.mode} onchange={(event) =>
          void edit({type: 'setMode', mode: event.currentTarget.value as AppearanceMode})}>
          <option value="system">System</option><option value="light">Light</option><option value="dark">Dark</option>
        </select>
      </label>
      <label>Theme
        <select aria-label="Theme" value={view.profile.presetId ?? ''} onchange={(event) =>
          void edit({type: 'setPreset', preset: event.currentTarget.value || null})}>
          <option value="">Default</option>
          {#each view.presets as preset (preset.id)}<option value={preset.id}>{preset.label}</option>{/each}
        </select>
      </label>
      <label>Accent
        <select aria-label="Accent" value={view.profile.namedAccent ?? ''} onchange={(event) => {
          if (event.currentTarget.value) void edit({type: 'setAccent', accent: event.currentTarget.value as AppearanceAccent});
        }}>
          <option value="" disabled>Custom</option>
          {#each accents as accent (accent)}<option value={accent}>{accent[0]!.toUpperCase() + accent.slice(1)}</option>{/each}
        </select>
      </label>
      <label>Contrast <input aria-label="Contrast" type="range" min="0" max="100" value={view.profile.contrast}
        onchange={(event) => void edit({type: 'setContrast', value: event.currentTarget.valueAsNumber})} /></label>
      <label><input type="checkbox" checked={view.profile.translucentSidebar}
        onchange={(event) => void edit({type: 'setTranslucency', enabled: event.currentTarget.checked})} />Translucent Sidebar</label>
      <label><input type="checkbox" checked={view.profile.colorizeMessages}
        onchange={(event) => void edit({type: 'setMessageColors', enabled: event.currentTarget.checked})} />Colorize Messages</label>
    </fieldset>
    <fieldset disabled={busy}>
      <legend>Colors</legend>
      {#each colors as item (item.role)}
        {@const hex = hexColor(item.role === 'accent' ? view.resolvedAccent : view.profile.colors[item.role])}
        <div class="color">
          <label>{item.label}
            <input aria-label={item.label} type="color" value={hex} onchange={(event) => setColor(item.role, event.currentTarget.value)} />
          </label>
          <input aria-label={`${item.label} Hex`} type="text" maxlength="7" size="7" spellcheck="false" value={hex}
            onchange={(event) => setColor(item.role, event.currentTarget.value)} />
        </div>
      {/each}
    </fieldset>
    <fieldset disabled={busy}>
      <legend>Typography</legend>
      {#each roles as { role, title, range } (role)}
        {@const selected = view.profile.fonts[role] ?? ''}
        <div class="font">
          <label>{title} Font
            <select aria-label={`${title} Font`} value={selected}
              onchange={(event) => void edit({type: 'setFont', role, family: event.currentTarget.value || null})}>
              <option value="">{role === 'content' ? 'Same as UI Font' : 'System'}</option>
              {#if selected && !fonts.includes(selected)}<option value={selected}>{selected}</option>{/if}
              {#each fonts as font (font)}<option value={font}>{font}</option>{/each}
            </select>
          </label>
          <label>{title} Font Size
            <input aria-label={`${title} Font Size`} type="number" min={range[0]} max={range[1]} step="1"
              value={view.profile.sizes[role]} onchange={(event) => {
                const size = event.currentTarget.valueAsNumber;
                if (Number.isFinite(size)) void edit({type: 'setSize', role, size: Math.round(Math.max(range[0], Math.min(range[1], size)))});
              }} />
          </label>
        </div>
      {/each}
    </fieldset>
    <div class="controls">
      <button type="button" disabled={busy} onclick={() => void output(false)}>Copy Theme</button>
      <button type="button" disabled={busy || exporting} onclick={() => void output(true)}>Export Theme…</button>
    </div>
  </section>
{/if}

<style>
  section, fieldset { display: grid; gap: 0.6rem; }
  fieldset { padding: 0.65rem; }
  label, .color, .font, .controls { display: flex; gap: 0.55rem; align-items: center; flex-wrap: wrap; }
  label > select { max-inline-size: min(15rem, 100%); }
  input[type="number"] { width: 3.7rem; }
  input[type="color"] { padding: 0; inline-size: 2.25rem; block-size: 1.65rem; border: 1px solid var(--workspace-divider); }
</style>
