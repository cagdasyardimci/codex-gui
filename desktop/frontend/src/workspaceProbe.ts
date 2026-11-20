import { invoke } from '@tauri-apps/api/core';
import { nextWorkspaceUpdate, subscribeWorkspace } from './projectIpc';

// An empty projection exists only on the first load of this fixture process.
export async function verifyWorkspaceSubscription(): Promise<'reload' | boolean> {
  const first = await subscribeWorkspace();
  if (first.snapshot.revision !== 0) {
    return first.snapshot.revision >= 3 && first.snapshot.workspace !== null;
  }
  if (first.snapshot.workspace !== null) return false;
  const firstRequest = { subscriptionId: first.subscriptionId, afterRevision: 0 };
  await invoke('change_workspace_fixture', { skipRevision: false });
  const update = await nextWorkspaceUpdate(firstRequest);
  if (typeof update !== 'object' || !('changed' in update) ||
      update.changed.revision !== 1 || !update.changed.workspace) {
    return false;
  }
  await invoke('change_workspace_fixture', { skipRevision: true });
  const lost = await nextWorkspaceUpdate({ ...firstRequest, afterRevision: 1 });
  if (lost !== 'resync') return false;
  const current = await subscribeWorkspace();
  if (current.snapshot.revision !== 3 ||
      !current.snapshot.workspace ||
      current.snapshot.workspace.workspaceId === update.changed.workspace.workspaceId ||
      await nextWorkspaceUpdate({ ...firstRequest, afterRevision: 3 }) !== 'retired') {
    return false;
  }
  return 'reload';
}
