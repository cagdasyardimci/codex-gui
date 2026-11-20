<script lang="ts">
  import type { DraftAttachmentScope, FeedbackRating, TranscriptItem, TranscriptRowRequest } from './generated/workspace';
  import MarkdownView from './MarkdownView.svelte';
  import ImagePreview from './ImagePreview.svelte';
  import { loadTranscriptAttachment, reuseComposerAttachment } from './projectIpc';

  let { item, request, attachmentScope, copy, onCopyFocus, edit, branch, bookmark, bookmarked, feedback, readAloud, reading }: {
    item: TranscriptItem;
    request?: TranscriptRowRequest;
    attachmentScope?: DraftAttachmentScope;
    copy: (item: TranscriptItem) => Promise<void> | void;
    onCopyFocus: () => void;
    edit?: (item: TranscriptItem) => void;
    branch?: (item: TranscriptItem) => void;
    bookmark?: (item: TranscriptItem, bookmarked: boolean) => void;
    bookmarked?: boolean;
    feedback?: (rating: FeedbackRating) => void;
    readAloud?: (item: TranscriptItem) => void;
    reading?: boolean;
  } = $props();

  async function copyResponse() {
    try {
      await copy(item);
    } catch (error) {
      console.error(error);
    }
  }
</script>

{#if item.role === 'commands'}
  <article class="transcript-item" data-item-id={item.itemId} data-turn-id={item.turnId}>
    <details class="transcript-commands">
      <summary>{item.commands.length === 1 ? item.commands[0]?.command : 'Commands'}</summary>
      <ul>
        {#each item.commands as command (command.id)}
          <li>
            {#if item.commands.length > 1}<pre>{command.command}</pre>{/if}
            {#if command.output}<pre>{command.output}</pre>{/if}
          </li>
        {/each}
      </ul>
    </details>
  </article>
{:else}
  <article class="transcript-item" data-item-id={item.itemId} data-turn-id={item.turnId} aria-label={item.role === 'user' ? 'You' : 'Codex'}>
    <div class="transcript-item-header">
      <span aria-hidden="true">{item.role === 'user' ? 'You' : 'Codex'}</span>
    <div class="transcript-row-actions">
    {#if item.role === 'assistant' && item.completed && item.text}
        <button class="transcript-copy" type="button" aria-label="Copy response"
          onpointerdown={(event) => event.preventDefault()} onfocus={onCopyFocus} onclick={copyResponse}>Copy</button>
      {/if}
    {#if edit}
      <button class="transcript-copy transcript-edit" type="button" aria-label="Edit sent prompt"
        onpointerdown={(event) => event.preventDefault()} onclick={() => edit?.(item)}>Edit</button>
    {/if}
    {#if readAloud}
      <button class="transcript-copy" type="button" onpointerdown={(event) => event.preventDefault()}
        onclick={() => readAloud?.(item)}>{reading ? 'Stop Reading' : 'Read Aloud'}</button>
    {/if}
    {#if bookmark}
      <button class="transcript-copy" type="button" aria-pressed={!!bookmarked}
        aria-label={bookmarked ? 'Remove response bookmark' : 'Bookmark response'}
        onpointerdown={(event) => event.preventDefault()}
        onclick={() => bookmark?.(item, !bookmarked)}>{bookmarked ? 'Remove Bookmark' : 'Bookmark'}</button>
    {/if}
    {#if branch}
      <button class="transcript-copy" type="button" aria-label="Branch in new chat"
        onpointerdown={(event) => event.preventDefault()} onclick={() => branch?.(item)}>Branch</button>
    {/if}
    {#if feedback}
      <button class="transcript-copy" type="button" onpointerdown={(event) => event.preventDefault()}
        onclick={() => feedback?.('good_result')}>Good Result</button>
      <button class="transcript-copy" type="button" onpointerdown={(event) => event.preventDefault()}
        onclick={() => feedback?.('bad_result')}>Bad Result</button>
    {/if}
    </div>
    </div>
    {#if item.text}
      <MarkdownView source={item.text} request={item.role === 'assistant' && item.completed ? request : undefined} />
    {/if}
    {#if request && item.attachments.length}
      {@const row = request}
      <ul class="transcript-attachments" aria-label="Attachments">
        {#each item.attachments as attachment (attachment.id)}
          {@const media = { row, attachmentId: attachment.id }}
          <li>
            {#if attachment.image}
              <ImagePreview load={() => loadTranscriptAttachment(media)} alt={attachment.label} downloadOriginal />
            {:else}<span>{attachment.label}</span>{/if}
            {#if attachmentScope}
              {@const scope = attachmentScope}
              <button type="button" aria-label={`Attach ${attachment.label} to draft`}
                onclick={() => { void reuseComposerAttachment({ scope, media }).catch(() => {}); }}>Attach</button>
            {/if}
          </li>
        {/each}
      </ul>
    {/if}
  </article>
{/if}
