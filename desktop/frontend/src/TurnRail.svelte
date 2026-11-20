<script lang="ts">
  import { onDestroy } from 'svelte';
  import type { NavigationIntent, TurnRailView, TurnRailRequest, WorkspaceId } from './generated/workspace';
  import { navigateWorkspace } from './projectIpc';

  let { rail, workspaceId, chatId }: { rail: TurnRailView; workspaceId: WorkspaceId; chatId: string } = $props();
  let hovered = $state<string>();
  let focused = $state<string>();
  let timer: ReturnType<typeof setTimeout> | undefined;
  let marks = $state<HTMLDivElement>();

  function request(turnId: string): TurnRailRequest {
    return { workspaceId, chatId, railId: rail.id, turnId };
  }

  function dispatch(intent: NavigationIntent) {
    void navigateWorkspace(intent).catch((error) => {
      if (error !== 'staleSelection' && error !== 'retiredWorkspace') console.error(error);
    });
  }

  function show(turnId: string) {
    if (hovered === turnId) return;
    if (hovered) hide(hovered);
    hovered = turnId;
    const target = request(turnId);
    timer = setTimeout(() => dispatch({ previewTurn: target }), 150);
  }

  function hide(turnId: string) {
    if (hovered !== turnId) return;
    clearTimeout(timer);
    hovered = undefined;
    dispatch({ cancelTurnPreview: request(turnId) });
  }

  function jump(turnId: string) {
    clearTimeout(timer);
    hovered = undefined;
    dispatch({ jumpToTurn: request(turnId) });
  }

  function focusNeighbor(event: KeyboardEvent, index: number) {
    let next: number;
    switch (event.key) {
      case 'ArrowUp': next = Math.max(0, index - 1); break;
      case 'ArrowDown': next = Math.min(rail.turns.length - 1, index + 1); break;
      case 'Home': next = 0; break;
      case 'End': next = rail.turns.length - 1; break;
      default: return;
    }
    event.preventDefault();
    marks?.querySelectorAll<HTMLButtonElement>('button[data-turn-reference]')[next]?.focus();
  }

  onDestroy(() => clearTimeout(timer));
</script>

<nav class="turn-rail" aria-label="Conversation turns">
  <div class="turn-rail-marks" bind:this={marks}>
    {#if rail.earlier}
      {@const ticket = rail.earlier}
      <button type="button" class="turn-rail-earlier" aria-label="Load earlier turn references"
        onclick={() => dispatch({ loadTurnReferences: { workspaceId, chatId, railId: rail.id, ticket } })}>↑</button>
    {/if}
    {#each rail.turns as turn, index (turn.id)}
      <button type="button" class="turn-rail-mark" data-turn-reference={turn.id}
        aria-label={turn.title ? `Jump to ${turn.title}` : `Jump to turn ${index + 1}`}
        tabindex={(focused ?? rail.turns[0]?.id) === turn.id ? 0 : -1}
        onmouseenter={() => show(turn.id)} onmouseleave={() => hide(turn.id)}
        onfocus={() => { focused = turn.id; show(turn.id); }} onblur={() => hide(turn.id)}
        onkeydown={(event) => focusNeighbor(event, index)} onclick={() => jump(turn.id)}></button>
    {/each}
  </div>
  {#if rail.preview && rail.preview.turnId === hovered}
    <aside class="turn-rail-preview" aria-label="Turn preview">
      {#if rail.preview.prompt}<p>{rail.preview.prompt}</p>{/if}
      {#if rail.preview.response}<p>{rail.preview.response}</p>{/if}
    </aside>
  {/if}
</nav>

<style>
  .turn-rail {
    position: relative;
    flex: 0 0 auto;
    width: 1.4rem;
    min-height: 0;
  }

  .turn-rail-marks {
    display: flex;
    flex-direction: column;
    max-height: 100%;
    overflow-y: auto;
    scrollbar-width: none;
  }

  .turn-rail .turn-rail-mark, .turn-rail .turn-rail-earlier {
    position: relative;
    flex: 0 0 1rem;
    padding: 0;
    border: 0;
    background: transparent;
  }

  .turn-rail-mark::before {
    position: absolute;
    top: 50%;
    width: 0.65rem;
    inset-inline-start: 0.4rem;
    height: 2px;
    border-radius: 1px;
    background: currentColor;
    opacity: 0.45;
    content: '';
  }

  .turn-rail-mark:is(:hover, :focus)::before {
    opacity: 1;
  }

  .turn-rail .turn-rail-earlier {
    text-align: center;
  }

  .turn-rail-preview {
    position: absolute;
    inset-inline-end: 100%;
    inset-block-start: 0;
    z-index: 2;
    box-sizing: border-box;
    width: min(22rem, 68vw);
    max-height: 55vh;
    overflow: hidden;
    padding: 0.65rem 0.85rem;
    border: 1px solid var(--workspace-divider);
    border-radius: 0.5rem;
    background: var(--workspace-canvas);
    white-space: pre-wrap;
    overflow-wrap: anywhere;
    pointer-events: none;
  }

  .turn-rail-preview p {
    margin: 0.35rem 0;
  }
</style>
