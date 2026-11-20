import { invoke } from '@tauri-apps/api/core';
import { listen, type UnlistenFn } from '@tauri-apps/api/event';
import type { AppearanceSelection, AppearanceUpdate, AppearanceView } from './generated/workspace';

export function readDesktopAppearance(): Promise<AppearanceView> {
  return invoke('read_desktop_appearance');
}

export function readDesktopFonts(): Promise<string[]> {
  return invoke('desktop_font_families');
}

export function updateDesktopAppearance(update: AppearanceUpdate): Promise<AppearanceView> {
  return invoke('update_desktop_appearance', { update });
}

export function copyDesktopTheme(selection: AppearanceSelection): Promise<void> {
  return invoke('copy_desktop_theme', { selection });
}

export function exportDesktopTheme(selection: AppearanceSelection): Promise<void> {
  return invoke('export_desktop_theme', { selection });
}

export async function observeDesktop(
  update: (view: AppearanceView) => void,
  action: (name: string) => void,
  signal: AbortSignal,
) {
  let announced = false;
  const subscriptions: UnlistenFn[] = [];
  function retire() {
    for (const subscription of subscriptions.splice(0)) subscription();
  }
  signal.addEventListener('abort', retire, { once: true });
  try {
    subscriptions.push(await listen<AppearanceView>('desktop:appearance', ({ payload }) => {
      announced = true;
      if (!signal.aborted) update(payload);
    }));
    subscriptions.push(await listen<string>('desktop:menu', ({ payload }) => {
      if (!signal.aborted) action(payload);
    }));
    const initial = await readDesktopAppearance();
    if (!announced && !signal.aborted) update(initial);
  } catch (error) {
    retire();
    throw error;
  } finally {
    if (signal.aborted) retire();
  }
}

export function hexColor(value: number): string {
  return '#' + (value & 0xffffff).toString(16).padStart(6, '0');
}

export function applyDesktopAppearance(view: AppearanceView) {
  const html = document.documentElement;
  const { colors, sizes, contrast, translucentSidebar, colorizeMessages } = view.profile;
  html.dataset.appearance = view.selection.appearance;
  html.dataset.messageColors = colorizeMessages ? 'on' : 'off';
  const { style } = html;
  style.colorScheme = view.selection.appearance;
  const colorVariables: Record<string, number> = {
    '--workspace-canvas': colors.background, '--workspace-text': colors.foreground,
    '--workspace-focus': view.resolvedAccent, '--workspace-diff-added': colors.diffAdded,
    '--workspace-diff-removed': colors.diffRemoved, '--workspace-skill': colors.skill,
  };
  for (const [variable, color] of Object.entries(colorVariables)) style.setProperty(variable, hexColor(color));
  style.setProperty('--workspace-border-contrast', `${6 + contrast * 0.2}%`);
  style.setProperty('--workspace-sidebar-contrast', translucentSidebar ? '4%' : '0%');
  for (const role of ['ui', 'content', 'code'] as const) {
    style.setProperty(`--workspace-${role}-size`, `${sizes[role]}px`);
    const family = view.resolvedFonts[role];
    if (family) style.setProperty(`--workspace-${role}-font`, JSON.stringify(family));
    else style.removeProperty(`--workspace-${role}-font`);
  }
}
