<script lang="ts">
  import { tick } from 'svelte';
  import type { AccountModel, ComposerPermissions, ComposerSelection, ComposerSelectionView, ComposerSettingsRequest,
    DraftAttachmentScope } from './generated/workspace';
  import { navigateWorkspace } from './projectIpc';

  let { scope, view, models, disabled, workspaceLabel }: {
    scope: DraftAttachmentScope; view: ComposerSelectionView; models: AccountModel[]; disabled: boolean; workspaceLabel: string;
  } = $props();
  let busy = $state(false);
  let confirm = $state.raw<ComposerSettingsRequest>();
  let dialog = $state<HTMLDialogElement>();
  const effective = $derived(models.find((model) => model.id === view.effectiveModelId));

  function chooseModel(event: Event & { currentTarget: HTMLSelectElement }) {
    const field = event.currentTarget;
    const id = field.value || null;
    field.value = view.selection.modelId ?? '';
    const model = models.find((option) => option.id === (id ?? view.defaultModelId));
    const effort = model?.efforts.some((option) => option.reasoningEffort === view.selection.effort) ? view.selection.effort : null;
    const tier = view.selection.serviceTier === 'default' || model?.serviceTiers.some((option) => option.id === view.selection.serviceTier)
      ? view.selection.serviceTier : null;
    void choose({ ...view.selection, modelId: id, effort, serviceTier: tier });
  }

  function chooseEffort(event: Event & { currentTarget: HTMLSelectElement }) {
    const field = event.currentTarget;
    const effort = field.value || null;
    field.value = view.selection.effort ?? '';
    void choose({ ...view.selection, effort });
  }

  function chooseTier(event: Event & { currentTarget: HTMLSelectElement }) {
    const field = event.currentTarget;
    const serviceTier = field.value || null;
    field.value = view.selection.serviceTier ?? '';
    void choose({ ...view.selection, serviceTier });
  }

  async function choosePermissions(event: Event & { currentTarget: HTMLSelectElement }) {
    const field = event.currentTarget;
    const permissions = field.value as ComposerPermissions;
    field.value = view.selection.permissions;
    const selection = { ...view.selection, permissions };
    if (permissions === 'fullAccess' && view.selection.permissions !== 'fullAccess') {
      confirm = { scope, revision: view.revision, selection, confirmFullAccess: true };
      await tick();
      dialog?.showModal();
    } else {
      await choose(selection);
    }
  }

  function cancel() {
    dialog?.close();
    confirm = undefined;
  }

  async function apply(request: ComposerSettingsRequest) {
    if (busy || disabled) return;
    busy = true;
    try { await navigateWorkspace({ setComposerSettings: request }); }
    catch {}
    finally { busy = false; }
  }

  function choose(selection: ComposerSelection) {
    return apply({ scope, revision: view.revision, selection, confirmFullAccess: false });
  }

  async function enableFullAccess() {
    const captured = confirm;
    cancel();
    if (captured) await apply(captured);
  }
</script>

<div class="composer-settings" role="group" aria-label="Composer settings">
  <select aria-label="Model" value={view.selection.modelId ?? ''} disabled={disabled || busy || !models.length} onchange={chooseModel}>
    <option value="">{view.usesProjectDefaults ? 'Project Default Model' : 'Configured Model'}</option>
    {#each models as model (model.id)}<option value={model.id}>{model.name}</option>{/each}
  </select>
  <select aria-label="Reasoning effort" value={view.selection.effort ?? ''} disabled={disabled || busy || !effective?.efforts.length} onchange={chooseEffort}>
    <option value="">Default Effort</option>
    {#each effective?.efforts ?? [] as effort (effort.reasoningEffort)}
      <option value={effort.reasoningEffort}>{effort.reasoningEffort === 'xhigh' ? 'Extra High' : effort.reasoningEffort}</option>
    {/each}
  </select>
  <select aria-label="Speed" value={view.selection.serviceTier ?? ''} disabled={disabled || busy || !effective} onchange={chooseTier}>
    <option value="">Configured Speed</option>
    <option value="default">Standard</option>
    {#each effective?.serviceTiers.filter((tier) => tier.id !== 'default') ?? [] as tier (tier.id)}
      <option value={tier.id}>{tier.name}</option>
    {/each}
  </select>
  <select aria-label="Permissions" value={view.selection.permissions} disabled={disabled || busy} onchange={choosePermissions}>
    <option value="configured">Configured Permissions</option>
    <option value="askForApproval">Ask for Approval</option>
    <option value="approveForMe">Approve for Me</option>
    <option value="fullAccess">Full Access</option>
  </select>
</div>

{#if confirm}
  <dialog class="composer-full-access" aria-label="Full Access" bind:this={dialog}
    oncancel={(event) => { event.preventDefault(); cancel(); }}>
    <strong>Full Access</strong>
    <p>{workspaceLabel}</p>
    <div>
      <button type="button" onclick={cancel}>Cancel</button>
      <button type="button" onclick={() => void enableFullAccess()}>Enable Full Access</button>
    </div>
  </dialog>
{/if}

<style>
  .composer-settings {
    display: flex;
    flex-wrap: wrap;
    gap: 0.4rem;
  }

  .composer-full-access {
    border: 1px solid var(--workspace-divider);
    border-radius: 0.5rem;
    color: CanvasText;
    background: var(--workspace-canvas);
    padding: 1rem;
  }

  .composer-full-access div {
    display: flex;
    justify-content: flex-end;
    gap: 0.5rem;
    margin-top: 1rem;
  }
</style>
