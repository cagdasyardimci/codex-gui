import { invoke } from '@tauri-apps/api/core';
import type { NotificationUpdate, NotificationView } from '../generated/workspace';

export function readNotifications(): Promise<NotificationView> {
  return invoke('read_notification_preferences');
}

export function updateNotifications(update: NotificationUpdate): Promise<NotificationView> {
  return invoke('update_notification_preferences', { update });
}

export function requestNotifications(revision: string): Promise<NotificationView> {
  return invoke('request_notification_permission', { revision });
}

export function importNotificationSound(revision: string): Promise<NotificationView> {
  return invoke('import_notification_sound', { revision });
}
