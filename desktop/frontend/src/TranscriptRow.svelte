<script lang="ts">
  import type { TranscriptItem, TranscriptRowRequest } from './generated/workspace';
  import MarkdownView from './MarkdownView.svelte';
  import ImagePreview from './ImagePreview.svelte';
  import { loadTranscriptAttachment } from './projectIpc';

  let { item, request, copy, onCopyFocus }: {
    item: TranscriptItem;
    request?: TranscriptRowRequest;
    copy: (item: TranscriptItem) => Promise<void> | void;
    onCopyFocus: () => void;
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
      {#if item.role === 'assistant' && item.completed && item.text}
        <button class="transcript-copy" type="button" aria-label="Copy response"
          onpointerdown={(event) => event.preventDefault()} onfocus={onCopyFocus} onclick={copyResponse}>Copy</button>
      {/if}
    </div>
    {#if item.text}
      <MarkdownView source={item.text} request={item.role === 'assistant' && item.completed ? request : undefined} />
    {/if}
    {#if request && item.attachments.length}
      {@const row = request}
      <ul class="transcript-attachments" aria-label="Attachments">
        {#each item.attachments as attachment (attachment.id)}
          <li><ImagePreview load={() => loadTranscriptAttachment({ row, attachmentId: attachment.id })} alt={attachment.label} /></li>
        {/each}
      </ul>
    {/if}
  </article>
{/if}
