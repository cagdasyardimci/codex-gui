import { invoke } from '@tauri-apps/api/core';
import type { SetEffortVisibility, SettingsSelection, SettingsView, SettingsWriteOutcome, WriteSettingsValue } from './generated/workspace';

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

export function writeSettings(update: WriteSettingsValue): Promise<SettingsWriteOutcome> {
  return invoke('write_settings', { update });
}

export function setEffortVisibility(update: SetEffortVisibility): Promise<SettingsView> {
  return invoke('set_effort_visibility', { update });
}
