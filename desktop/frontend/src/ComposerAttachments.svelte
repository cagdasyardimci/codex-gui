<script lang="ts">
  import type { DraftAttachmentRequest, DraftAttachmentScope, DraftAttachmentView, DraftImageAnnotations } from './generated/workspace';
  import { loadComposerImage, readComposerAnnotations, removeComposerAttachment } from './projectIpc';
  import ImagePreview from './ImagePreview.svelte';
  import ImageAnnotationEditor from './ImageAnnotationEditor.svelte';

  let { scope, attachments }: { scope: DraftAttachmentScope; attachments: DraftAttachmentView[] } = $props();
  let editor = $state<{ attachment: DraftAttachmentRequest; original: DraftImageAnnotations; title: string }>();

  async function annotate(attachment: DraftAttachmentView) {
    const request = { scope, attachmentId: attachment.id };
    try {
      const original = await readComposerAnnotations(request);
      if (scope.draftId === request.scope.draftId && attachments.some((item) => item.id === attachment.id)) {
        editor = { attachment: request, original, title: attachment.label };
      }
    } catch {}
  }
</script>

<ul class="composer-attachments" aria-label="Draft attachments">
  {#each attachments as attachment (attachment.id)}
    <li>
      {#if attachment.image}
        <ImagePreview load={() => loadComposerImage({ scope, attachmentId: attachment.id })} alt={attachment.label} />
        <button type="button" aria-label={`Annotate ${attachment.label}`} onclick={() => void annotate(attachment)}>Annotate</button>
      {/if}
      <span>{attachment.label}</span>
      <button type="button" aria-label={`Remove ${attachment.label}`}
        onclick={() => { void removeComposerAttachment({ scope, attachmentId: attachment.id }).catch(() => {}); }}>×</button>
    </li>
  {/each}
</ul>

{#if editor}
  <ImageAnnotationEditor {...editor} close={() => { editor = undefined; }} />
{/if}
