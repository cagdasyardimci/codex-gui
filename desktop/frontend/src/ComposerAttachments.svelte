<script lang="ts">
  import type { DraftAttachmentScope, DraftAttachmentView } from './generated/workspace';
  import { loadComposerImage, removeComposerAttachment } from './projectIpc';
  import ImagePreview from './ImagePreview.svelte';

  let { scope, attachments }: { scope: DraftAttachmentScope; attachments: DraftAttachmentView[] } = $props();
</script>

<ul class="composer-attachments" aria-label="Draft attachments">
  {#each attachments as attachment (attachment.id)}
    <li>
      {#if attachment.image}
        <ImagePreview load={() => loadComposerImage({ scope, attachmentId: attachment.id })} alt={attachment.label} />
      {/if}
      <span>{attachment.label}</span>
      <button type="button" aria-label={`Remove ${attachment.label}`}
        onclick={() => { void removeComposerAttachment({ scope, attachmentId: attachment.id }).catch(() => {}); }}>×</button>
    </li>
  {/each}
</ul>
