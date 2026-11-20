import { invoke } from '@tauri-apps/api/core';
import type { SettingsSelection, SettingsView } from './generated/workspace';

export function openSettings(session: string): Promise<SettingsView> {
  return invoke('open_settings', { session });
}

export function refreshSettings(session: string): Promise<SettingsView> {
  return invoke('refresh_settings', { session });
}

export function closeSettings(session: string): Promise<void> {
  return invoke('close_settings', { session });
}

export function signOutSettings(selection: SettingsSelection): Promise<SettingsView> {
  return invoke('sign_out_settings', { selection });
}
