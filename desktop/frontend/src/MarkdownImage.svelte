<script lang="ts">
  import type { MarkdownTargetRequest } from './generated/workspace';
  import { loadTranscriptImage } from './projectIpc';

  const formats = ['', 'image/png', 'image/jpeg', 'image/gif', 'image/webp'];
  let { request, alt }: { request: MarkdownTargetRequest; alt: string } = $props();
  let preview = $state<string>();

  $effect(() => {
    let retired = false;
    let url: string | undefined;
    preview = undefined;
    void loadTranscriptImage(request).then((payload) => {
      if (retired) return;
      const mime = formats[new Uint8Array(payload)[0] ?? 0];
      if (!mime) return;
      url = URL.createObjectURL(new Blob([payload.slice(1)], { type: mime }));
      preview = url;
    }).catch(() => {});
    return () => {
      retired = true;
      if (url) URL.revokeObjectURL(url);
    };
  });
</script>

{#if preview}
  <img src={preview} {alt} onerror={() => { preview = undefined; }} />
{:else}
  {alt}
{/if}
