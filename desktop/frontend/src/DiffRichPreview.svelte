<script lang="ts">
  import type { DiffContentView, DiffPatchRequest } from './generated/workspace';
  import { comparedMarkdown, comparedMedia, performDiffAction } from './diffIpc';
  import ImagePreview from './ImagePreview.svelte';
  import MarkdownView from './MarkdownView.svelte';
  import PdfPreview from './PdfPreview.svelte';
  import SvgPreview from './SvgPreview.svelte';

  let { target, content }: { target: DiffPatchRequest; content: DiffContentView } = $props();
  const request = $derived({ target, side: content.side });
  let page = $state(1);

  function download() {
    return performDiffAction({ target, action: { exportFile: content.side } });
  }
</script>

<div class="diff-rich-preview" aria-label={`${content.side === 'before' ? 'Previous' : 'Compared'} File Preview`}>
  {#if content.rich === 'raster'}
    <ImagePreview load={() => comparedMedia(request)} alt={content.path} {download} />
  {:else if content.rich === 'pdf'}
    <PdfPreview name={content.path} load={() => comparedMedia(request)} bind:pageNumber={page} />
  {:else if content.rich === 'svg' && content.text !== null}
    <SvgPreview source={content.text} alt={content.path} {download} />
  {:else if content.rich === 'markdown' && content.text !== null}
    <MarkdownView source={content.text} renderKey={`${target.fileId}:${content.side}`}
      render={() => comparedMarkdown(request)} />
  {/if}
</div>

<style>
  .diff-rich-preview { overflow: auto; max-block-size: 42%; flex-shrink: 0; border-block-start: 1px solid var(--workspace-divider); }
  .diff-rich-preview :global(img) { max-inline-size: 100%; max-block-size: 24rem; }
  .diff-rich-preview :global(dialog.expanded-preview img) { max-inline-size: none; max-block-size: none; }
</style>
