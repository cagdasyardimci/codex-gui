<script lang="ts">
  import PreviewViewer from './PreviewViewer.svelte';
  import { savePreviewImage } from './previewExport';

  const formats = ['', 'image/png', 'image/jpeg', 'image/gif', 'image/webp'];
  let { load, alt, download, downloadOriginal = false }: {
    load: () => Promise<ArrayBuffer>;
    alt: string;
    download?: () => Promise<void>;
    downloadOriginal?: boolean;
  } = $props();
  let preview = $state.raw<{ url: string; file: Blob }>();
  let decoded = $state(false);
  let expanded = $state(false);

  $effect(() => {
    let retired = false;
    let url: string | undefined;
    preview = undefined;
    decoded = false;
    expanded = false;
    void load().then((payload) => {
      if (retired) return;
      const mime = formats[new Uint8Array(payload)[0] ?? 0];
      if (!mime) return;
      const file = new Blob([payload.slice(1)], { type: mime });
      url = URL.createObjectURL(file);
      preview = { url, file };
    }).catch(() => {});
    return () => {
      retired = true;
      if (url) URL.revokeObjectURL(url);
    };
  });
</script>

{#if preview}
  <img src={preview.url} {alt} onload={() => { decoded = true; }} onerror={() => { preview = undefined; }} />
  {#if decoded && (download || downloadOriginal)}
    {@const file = preview.file}
    <button type="button" aria-label={alt ? `Expand ${alt}` : 'Expand Image'}
      onclick={(event) => { event.currentTarget.focus({ preventScroll: true }); expanded = true; }}>Expand</button>
    {#if expanded}
      <PreviewViewer source={preview.url} label={alt || 'Image'} close={() => { expanded = false; }}
        download={download ?? (() => savePreviewImage(file))} />
    {/if}
  {/if}
{:else}
  {alt}
{/if}
