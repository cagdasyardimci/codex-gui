<script lang="ts">
  import { onMount } from 'svelte';
  import type { DraftAttachmentRequest, DraftImageAnnotations, ImageAnnotation } from './generated/workspace';
  import { loadComposerImage, saveComposerAnnotations } from './projectIpc';
  import ImagePreview from './ImagePreview.svelte';

  let { attachment, original, title, close }: {
    attachment: DraftAttachmentRequest; original: DraftImageAnnotations; title: string; close: () => void;
  } = $props();
  let dialog = $state<HTMLDialogElement>();
  let annotations = $state<ImageAnnotation[]>([]);
  let selectedId = $state<string>();
  let zoom = $state(100);
  let saving = $state(false);
  const selected = $derived(annotations.find((annotation) => annotation.id === selectedId));

  onMount(() => {
    annotations = original.annotations.map((annotation) => ({ ...annotation }));
    selectedId = annotations[0]?.id;
    dialog?.showModal();
    return () => { dialog?.close(); };
  });

  function place(event: MouseEvent) {
    if (saving || annotations.length >= Math.max(32, original.annotations.length)) return;
    const control = event.currentTarget as HTMLButtonElement;
    const image = control.querySelector('img');
    if (!image?.naturalWidth) return;
    const rect = image.getBoundingClientRect();
    const fraction = (value: number) => Math.max(0, Math.min(1, value));
    const x = event.detail ? fraction((event.clientX - rect.left) / rect.width) : 0.5;
    const y = event.detail ? fraction((event.clientY - rect.top) / rect.height) : 0.5;
    const id = crypto.randomUUID();
    annotations.push({ id, x, y, text: '' });
    selectedId = id;
  }

  function remove(id: string) {
    const index = annotations.findIndex((annotation) => annotation.id === id);
    if (index < 0 || saving) return;
    annotations.splice(index, 1);
    selectedId = annotations[Math.min(index, annotations.length - 1)]?.id;
  }

  async function save() {
    if (saving || annotations.some((annotation) => !annotation.text.trim())) return;
    saving = true;
    try {
      await saveComposerAnnotations({ attachment, digest: original.digest, original: original.annotations,
        annotations: $state.snapshot(annotations) });
      close();
    } catch {
      saving = false;
    }
  }
</script>

<dialog class="image-annotation-editor" aria-label={`Annotate ${title}`} bind:this={dialog}
  oncancel={(event) => { event.preventDefault(); if (!saving) close(); }}>
  <div class="annotation-controls">
    <strong>{title}</strong>
    <label>Zoom <input type="range" min="50" max="200" step="25" bind:value={zoom} /></label>
  </div>
  <div class="annotation-canvas">
    <div class="annotation-image" style:width={`${zoom * 4}px`}>
      <button type="button" class="annotation-placement" aria-label="Place comment on image" onclick={place}>
        <ImagePreview load={() => loadComposerImage(attachment)} alt={title} />
      </button>
      {#each annotations as annotation, index (annotation.id)}
        <button type="button" class="annotation-marker" class:selected={selectedId === annotation.id}
          aria-label={`Edit comment ${index + 1}`} style:left={`${annotation.x * 100}%`} style:top={`${annotation.y * 100}%`}
          onclick={() => { selectedId = annotation.id; }}>{index + 1}</button>
      {/each}
    </div>
  </div>
  {#if selected}
    <div class="annotation-controls">
      <textarea aria-label="Comment" rows="3" maxlength="4096" value={selected.text}
        oninput={(event) => { if (selected) selected.text = event.currentTarget.value; }}></textarea>
      <button type="button" disabled={saving} onclick={() => { if (selected) remove(selected.id); }}>Remove Comment</button>
    </div>
  {/if}
  <div class="annotation-controls annotation-actions">
    <button type="button" disabled={saving} onclick={close}>Cancel</button>
    <button type="button" disabled={saving || annotations.some((annotation) => !annotation.text.trim())}
      onclick={() => void save()}>Save</button>
  </div>
</dialog>

<style>
  .image-annotation-editor {
    box-sizing: border-box;
    width: min(42rem, calc(100vw - 2rem));
    max-height: min(50rem, calc(100vh - 2rem));
    padding: 1rem;
    border: 1px solid var(--workspace-divider);
    border-radius: 0.6rem;
    background: var(--workspace-canvas);
    color: CanvasText;
  }

  .image-annotation-editor::backdrop {
    background: rgb(0 0 0 / 35%);
  }

  .annotation-canvas {
    overflow: auto;
    max-height: 50vh;
    padding: 0.8rem;
  }

  .annotation-image {
    position: relative;
    margin-inline: auto;
  }

  .annotation-placement {
    display: block;
    width: 100%;
    padding: 0;
    border: 0;
    background: transparent;
    cursor: crosshair;
  }

  .annotation-placement :global(img) {
    display: block;
    width: 100%;
    height: auto;
  }

  .annotation-marker {
    position: absolute;
    transform: translate(-50%, -50%);
    border: 1px solid Canvas;
    min-width: 1.6rem;
    min-height: 1.6rem;
    border-radius: 50%;
    background: CanvasText;
    color: Canvas;
  }

  .annotation-marker.selected {
    outline: 2px solid Highlight;
  }

  .annotation-controls {
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: 0.6rem;
    margin-block: 0.5rem;
  }

  .annotation-controls textarea {
    flex: 1;
    min-width: 0;
  }

  .annotation-actions {
    justify-content: flex-end;
    margin-bottom: 0;
  }
</style>
