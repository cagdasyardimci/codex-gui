import { invoke } from '@tauri-apps/api/core';
import { click, waitFor } from './fixtureControls';
import type { AppearanceView } from './generated/workspace';
import { updateDesktopAppearance } from './desktopAppearance';

type WindowEvidence = {
  width: number;
  height: number;
  fullscreen: boolean;
  scale: number;
  zoom: number;
  exportCaptured: boolean;
  exportWritten: boolean;
};

const fixtureState = () => invoke<WindowEvidence>('appearance_fixture_state');
const fixtureAction = (action: string) => invoke('appearance_fixture_action', { action });

export async function verifyAppearance(phase: 'appearance' | 'appearanceRestore', visible: () => AppearanceView | undefined) {
  const dialog = () => document.querySelector<HTMLDialogElement>('dialog[aria-label="Settings"][open]');
  const field = <T extends HTMLInputElement | HTMLSelectElement>(label: string) =>
    dialog()?.querySelector<T>(`[aria-label="${label}"]`);
  const press = (label: string) => click(label, dialog()!);
  const profile = () => visible()?.profile;
  const color = () => getComputedStyle(document.documentElement).backgroundColor;
  const contentPx = () => getComputedStyle(document.documentElement).getPropertyValue('--workspace-content-size').trim();
  async function change(label: string, value: string) {
    await waitFor(`The appearance control ${label} was busy`, () => field(label)?.matches(':disabled') === false);
    const input = field(label);
    if (!input) throw new Error(`Missing appearance control ${label}`);
    input.value = value;
    input.dispatchEvent(new Event('change', { bubbles: true }));
  }
  const mode = async (target: 'light' | 'dark') => {
    await change('Appearance Mode', target);
    await waitFor(`The ${target} mode did not settle`, () =>
      visible()?.mode === target && document.documentElement.dataset.appearance === target);
  };
  try {
    await waitFor('Desktop appearance did not reach the workspace', () => !!visible());
    await fixtureAction('settings');
    await waitFor('The Settings menu did not open Settings', () => !!field('Search Settings'));
    if (phase === 'appearanceRestore') {
      await verifyRestored(visible);
      await invoke('verify_appearance_result', { failure: null, evidence: await fixtureState() });
      return;
    }
    const title = dialog()?.querySelector('h2')!;
    const titleFaces = await document.fonts.load('600 18px "Settings Inter"');
    const titleStyle = getComputedStyle(title);
    const titleBox = title.getBoundingClientRect();
    if (!titleFaces.some((face) => face.status === 'loaded') ||
        !titleStyle.fontFamily.includes('Settings Inter') || titleStyle.fontSize !== '18px' ||
        titleBox.height < 23 || titleBox.height > 25 || titleBox.width < 68 || titleBox.width > 80) {
      throw new Error(`The bundled Settings title did not fit its reference line: ${titleStyle.fontFamily}, ${titleBox.width}×${titleBox.height}`);
    }
    const search = field('Search Settings')!;
    search.value = 'content font size';
    search.dispatchEvent(new Event('input', { bubbles: true }));
    await waitFor('Settings search did not locate the typography control', () =>
      dialog()?.querySelector('nav[aria-label="Settings Search Results"]')?.textContent?.includes('Content Font Size') === true);
    search.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
    await waitFor('The Settings search result did not focus its control', () =>
      document.activeElement === field('Content Font Size'));
    await mode('light');
    if (color() !== 'rgb(255, 255, 255)' || getComputedStyle(document.documentElement).color !== 'rgb(13, 13, 13)') {
      throw new Error('The reference light palette did not reach the installed workspace');
    }
    const menu = () => field<HTMLSelectElement>('UI Font');
    await waitFor('The system font catalog was empty', () => (menu()?.options.length ?? 0) > 1);
    const families = [...menu()!.options].map(({value}) => value).filter(Boolean);
    const family = ['Arial', 'Liberation Sans', 'DejaVu Sans', 'Segoe UI'].find((candidate) => families.includes(candidate)) ?? families[0]!;
    await change('UI Font', family);
    await waitFor('Content did not inherit the selected UI font', () =>
      profile()?.fonts.ui === family && visible()?.resolvedFonts.content === family);
    await updateDesktopAppearance({selection: visible()!.selection,
      edit: {type: 'setFont', role: 'code', family: 'Codex Fixture Uninstalled Typeface'}});
    await waitFor('An uninstalled font did not fall back while retaining its preference', () =>
      profile()?.fonts.code === 'Codex Fixture Uninstalled Typeface' &&
      visible()?.resolvedFonts.code === null && !document.documentElement.style.getPropertyValue('--workspace-code-font'));
    await change('Content Font Size', '19');
    await waitFor('The content type size did not apply', () => contentPx() === '19px');
    await change('Foreground Hex', '#223344');
    await waitFor('The changed color replaced the font or failed to apply', () =>
      profile()?.colors.foreground === 0x22_33_44 && profile()?.fonts.ui === family);
    await press('Copy Theme');
    await press('Export Theme…');
    await waitForNative('Theme export did not capture its profile', (state) => state.exportCaptured);
    await mode('dark');
    if (color() !== 'rgb(17, 17, 17)' || contentPx() !== '15px' || profile()?.fonts.ui !== null) {
      throw new Error('The dark appearance inherited unrelated light preferences');
    }
    await change('Theme', 'nord');
    await waitFor('Selecting a preset did not apply its dark palette', () => profile()?.presetId === 'nord');
    await change('Background Hex', '#243243');
    await waitFor('The dark profile color did not update', () => color() === 'rgb(36, 50, 67)');
    await mode('light');
    if (profile()?.fonts.ui !== family || profile()?.colors.foreground !== 0x22_33_44 || contentPx() !== '19px') {
      throw new Error('Switching modes discarded the previous profile');
    }
    await mode('dark');
    await waitForNative('The captured theme export did not finish writing', (state) => state.exportWritten);
    await press('Close');
    await fixtureAction('resize');
    const regular = await waitForNative('The native window did not resize', normalLayout);
    await fixtureAction('fullscreen');
    await waitForNative('The native menu did not enter fullscreen', (state) => state.fullscreen);
    await fixtureAction('fullscreen');
    await waitForNative('Leaving fullscreen did not restore the regular layout', normalLayout);
    const viewportBefore = innerWidth;
    await fixtureAction('zoomIn');
    await waitForNative('The native zoom action did not apply', (state) => state.zoom === 110);
    await waitFor('Zoom did not change the WebView viewport', () => innerWidth < viewportBefore - 15);
    await invoke('verify_appearance_result', {
      failure: null,
      evidence: { regular, zoomed: await fixtureState(), settingsTitle: { width: titleBox.width, height: titleBox.height },
        font: family, background: color(), viewport: [innerWidth, innerHeight] },
    });
  } catch (error) {
    await invoke('verify_appearance_result', { failure: String(error), evidence: {} });
  }
}

function normalLayout(state: WindowEvidence) {
  return !state.fullscreen && Math.abs(state.width - 900) <= 2 && Math.abs(state.height - 640) <= 2 && state.scale > 0;
}

async function waitForNative(description: string, condition: (state: WindowEvidence) => boolean) {
  const deadline = performance.now() + 9000;
  do {
    const state = await fixtureState();
    if (condition(state)) return state;
    await new Promise<void>((resolve) => setTimeout(resolve, 40));
  } while (performance.now() < deadline);
  throw new Error(description);
}

async function verifyRestored(visible: () => AppearanceView | undefined) {
  await waitForNative('The reopened window did not restore its normal size and zoom', (state) =>
    normalLayout(state) && state.zoom === 110);
  await waitFor('The reopened window did not restore the edited dark profile', () =>
    visible()?.mode === 'dark' && visible()?.profile.presetId === 'nord' &&
    getComputedStyle(document.documentElement).backgroundColor === 'rgb(36, 50, 67)');
}
