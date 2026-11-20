<script lang="ts">
  import type { PDFDocumentLoadingTask, PDFDocumentProxy, RenderTask } from 'pdfjs-dist';
  import workerUrl from 'pdfjs-dist/legacy/build/pdf.worker.min.mjs?url';

  let { load, name, pageNumber = $bindable(1) }: {
    load: () => Promise<ArrayBuffer>;
    name: string;
    pageNumber?: number;
  } = $props();

  let doc = $state.raw<PDFDocumentProxy>();
  let canvas = $state<HTMLCanvasElement>();
  let ready = $state(false);
  let input = $state<HTMLInputElement>();
  let annotationMode: number | undefined;

  $effect(() => {
    const data = load;
    let retired = false;
    let task: PDFDocumentLoadingTask | undefined;
    doc = undefined;
    void (async () => {
      try {
        const [pdf, bytes] = await Promise.all([import('pdfjs-dist/legacy/build/pdf.mjs'), data()]);
        if (retired) return;
        pdf.GlobalWorkerOptions.workerSrc = workerUrl;
        task = pdf.getDocument({
          data: new Uint8Array(bytes),
          disableAutoFetch: true, disableRange: true, disableStream: true, enableXfa: false,
          useWasm: false, useWorkerFetch: false, disableFontFace: true, useSystemFonts: true,
          maxImageSize: 8 * 1024 * 1024, canvasMaxAreaInBytes: 32 * 1024 * 1024,
        });
        const loaded = await task.promise;
        if (retired) return;
        annotationMode = pdf.AnnotationMode.DISABLE;
        pageNumber = Math.max(1, Math.min(pageNumber, loaded.numPages));
        doc = loaded;
      } catch (error) {
        if (!retired) console.error(error);
      }
    })();
    return () => {
      retired = true;
      void task?.destroy().catch(() => {});
    };
  });

  $effect(() => {
    const output = canvas;
    const selected = pageNumber;
    const document = doc;
    ready = false;
    if (!document || !output) return;
    let retired = false;
    let render: RenderTask | undefined;
    void document.getPage(selected).then((page) => {
      if (retired) return;
      const original = page.getViewport({ scale: 1 });
      const { width, height } = original;
      if (!Number.isFinite(width * height) || width <= 0 || height <= 0) return;
      const scale = Math.min(1.5, 1800 / Math.max(width, height), Math.sqrt(2_500_000 / (width * height)));
      const viewport = page.getViewport({ scale });
      output.width = Math.max(1, Math.floor(viewport.width));
      output.height = Math.max(1, Math.floor(viewport.height));
      render = page.render({ canvas: output, viewport, annotationMode });
      return render.promise.then(() => { if (!retired) ready = true; });
    }).catch((error) => { if (!retired) console.error(error); });
    return () => {
      retired = true;
      render?.cancel();
    };
  });

  function go(page: number) {
    if (!doc || !Number.isInteger(page) || page < 1 || page > doc.numPages) {
      if (input) input.value = String(pageNumber);
      return;
    }
    pageNumber = page;
  }
</script>

{#if doc}
  <div class="pdf-preview" aria-label="PDF Preview">
    <nav aria-label="PDF Pages">
      <button type="button" disabled={pageNumber === 1} onclick={() => go(pageNumber - 1)}>Previous Page</button>
      <input aria-label="Page" bind:this={input} type="number" min="1" max={doc.numPages}
        value={pageNumber} onchange={(event) => go(event.currentTarget.valueAsNumber)} />
      <button type="button" disabled={pageNumber === doc.numPages} onclick={() => go(pageNumber + 1)}>Next Page</button>
    </nav>
    <div class="page" role="img" aria-label={`${name}, page ${pageNumber}`}>
      <canvas bind:this={canvas} aria-hidden="true" data-rendered-page={ready ? pageNumber : undefined}
        class:ready></canvas>
    </div>
  </div>
{/if}

<style>
  .pdf-preview { min-block-size: 0; flex: 1; display: flex; flex-direction: column; gap: 0.3rem; }
  nav { display: flex; align-items: center; gap: 0.25rem; flex-wrap: wrap; }
  input { inline-size: 4rem; }
  .page { flex: 1; overflow: auto; min-block-size: 0; }
  canvas { display: block; max-inline-size: 100%; block-size: auto; visibility: hidden; }
  canvas.ready { visibility: visible; }
</style>
