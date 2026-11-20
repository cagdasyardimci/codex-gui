import { invoke } from '@tauri-apps/api/core';
import type { InstructionsView, RedeemUsageReset, SaveInstructions, SetEffortVisibility, SettingsSelection, SettingsView, SettingsWriteOutcome, WriteSettingsValue } from './generated/workspace';

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

export function deleteSettingsMemories(selection: SettingsSelection): Promise<SettingsView> {
  return invoke('delete_settings_memories', { selection });
}

export function redeemSettingsReset(update: RedeemUsageReset): Promise<SettingsView> {
  return invoke('redeem_settings_reset', { update });
}

export function readSettingsInstructions(session: string): Promise<InstructionsView> {
  return invoke('read_settings_instructions', { session });
}

export function saveSettingsInstructions(update: SaveInstructions): Promise<InstructionsView> {
  return invoke('save_settings_instructions', { update });
}
