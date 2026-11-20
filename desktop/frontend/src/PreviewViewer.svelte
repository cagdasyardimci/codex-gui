<script lang="ts">
  let { source, label, close, download, downloadLabel = 'Download Original' }: {
    source: string;
    label: string;
    close: () => void;
    download?: (image: HTMLImageElement) => Promise<void>;
    downloadLabel?: string;
  } = $props();
  let dialog = $state<HTMLDialogElement>();
  let image = $state<HTMLImageElement>();
  let viewportWidth = $state(0);
  let viewportHeight = $state(0);
  let intrinsicWidth = $state(0);
  let intrinsicHeight = $state(0);
  let zoom = $state<number>();
  let exporting = $state(false);
  const fit = $derived(intrinsicWidth && intrinsicHeight && viewportWidth && viewportHeight
    ? Math.min(1, Math.max(1, viewportWidth - 24) / intrinsicWidth, Math.max(1, viewportHeight - 24) / intrinsicHeight)
    : 1);
  const scale = $derived(zoom ?? fit);

  $effect(() => {
    const element = dialog;
    if (!element) return;
    const previous = document.activeElement;
    element.showModal();
    return () => {
      element.close();
      if (previous instanceof HTMLElement && previous.isConnected) previous.focus({ preventScroll: true });
    };
  });

  function keyboard(event: KeyboardEvent) {
    event.stopPropagation();
    if (event.key === 'Escape' && !event.isComposing) {
      event.preventDefault();
      close();
    }
  }

  async function save() {
    if (!image || !intrinsicWidth || !download || exporting) return;
    exporting = true;
    try {
      await download(image);
    } catch (error) {
      console.error(error);
    } finally {
      exporting = false;
    }
  }
</script>

<dialog class="expanded-preview" bind:this={dialog} aria-label={label}
  oncancel={(event) => { event.preventDefault(); close(); }}
  onkeydown={keyboard}>
  <div class="viewer">
    <div class="controls" aria-label="Preview Controls">
      <button type="button" onclick={() => { zoom = undefined; }} aria-pressed={zoom === undefined}>Fit</button>
      <button type="button" onclick={() => { zoom = Math.max(0.02, scale / 1.5); }}
        disabled={!intrinsicWidth || scale <= 0.02}>Zoom Out</button>
      <button type="button" onclick={() => { zoom = Math.min(8, scale * 1.5); }}
        disabled={!intrinsicWidth || scale >= 8}>Zoom In</button>
      {#if download}<button type="button" disabled={!intrinsicWidth || exporting} onclick={() => void save()}>{downloadLabel}</button>{/if}
      <button type="button" onclick={close}>Close</button>
    </div>
    <div class="surface" bind:clientWidth={viewportWidth} bind:clientHeight={viewportHeight}>
      <img src={source} alt={label} bind:this={image} draggable="false"
        style:width={intrinsicWidth ? `${intrinsicWidth * scale}px` : 'auto'}
        style:height={intrinsicHeight ? `${intrinsicHeight * scale}px` : 'auto'}
        onload={() => {
          intrinsicWidth = image?.naturalWidth ?? 0;
          intrinsicHeight = image?.naturalHeight ?? 0;
        }} />
    </div>
  </div>
</dialog>

<style>
  dialog {
    box-sizing: border-box;
    inline-size: min(92vw, 90rem);
    block-size: min(88vh, 64rem);
    max-inline-size: none;
    max-block-size: none;
    background: Canvas;
    color: CanvasText;
    border: 1px solid color-mix(in srgb, CanvasText 30%, Canvas);
    border-radius: 0.7rem;
    padding: 0;
  }
  dialog::backdrop { background: rgb(0 0 0 / 56%); }
  .viewer { display: flex; flex-direction: column; block-size: 100%; }
  .controls { display: flex; flex-wrap: wrap; gap: 0.4rem; padding: 0.65rem; justify-content: end; }
  .surface { display: flex; flex: 1; min-block-size: 0; overflow: auto; padding: 12px; }
  .surface img { flex: none; margin: auto; max-inline-size: none; max-block-size: none; }
</style>
