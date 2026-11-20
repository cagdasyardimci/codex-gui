<script lang="ts">
  import type { QueueCommand, QueueView } from './generated/workspace';

  let { queue, disabled, draftOccupied, command }: {
    queue: QueueView;
    disabled: boolean;
    draftOccupied: boolean;
    command: (value: QueueCommand) => void;
  } = $props();

  function move(index: number, offset: number) {
    const ids = queue.entries.map((entry) => entry.id);
    const targetIndex = index + offset;
    if (targetIndex < 0 || targetIndex >= ids.length) return;
    [ids[index], ids[targetIndex]] = [ids[targetIndex], ids[index]];
    command({ reorder: ids });
  }
</script>

{#if queue.entries.length || queue.saved.length || queue.detached.length || queue.recover}
  <section class="workspace-queue" aria-label="Queued follow-ups">
    {#if queue.entries.length}
      <ul>
        {#each queue.entries as entry, index (entry.id)}
          <li class="queue-entry">
            {#if entry.text}<span class="queue-input">{entry.text}</span>{/if}
            <div class="queue-entry-actions">
              <button type="button" disabled={disabled || entry.reserved || draftOccupied}
                onclick={() => command({ edit: entry.id })}>Edit</button>
              <button type="button" disabled={disabled || entry.reserved || index === 0}
                onclick={() => move(index, -1)}>Move Up</button>
              <button type="button" disabled={disabled || entry.reserved || index === queue.entries.length - 1}
                onclick={() => move(index, 1)}>Move Down</button>
              <button type="button" disabled={disabled || entry.reserved}
                onclick={() => command({ delete: entry.id })}>Delete</button>
              {#if queue.activeTurn}
                {@const turnId = queue.activeTurn}
                <button type="button" disabled={disabled || entry.reserved}
                  onclick={() => command({ steer: { entryId: entry.id, turnId } })}>Steer</button>
              {/if}
            </div>
          </li>
        {/each}
      </ul>
    {/if}
    {#each queue.saved as entry (entry.id)}
      {#if entry.text}<div class="queue-entry"><span class="queue-input">{entry.text}</span></div>{/if}
    {/each}
    {#each queue.detached as entry (entry.id)}
      <div class="queue-entry">
        {#if entry.text}<span class="queue-input">{entry.text}</span>{/if}
        <div class="queue-entry-actions">
          <button type="button" disabled={disabled || draftOccupied}
            onclick={() => command({ restore: entry.id })}>Restore Draft</button>
        </div>
      </div>
    {/each}
    {#if queue.resume}
      {@const id = queue.resume}
      <button type="button" {disabled} onclick={() => command({ resume: id })}>Resume Queue</button>
    {/if}
    {#if queue.resumeSaved}
      {@const id = queue.resumeSaved}
      <button type="button" {disabled} onclick={() => command({ resumeSaved: id })}>Resume Saved Queue</button>
    {/if}
    {#if queue.recover}
      <button type="button" {disabled} onclick={() => command('recover')}>Recover Queue</button>
    {/if}
  </section>
{/if}
