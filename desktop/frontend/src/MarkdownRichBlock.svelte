<script module lang="ts">
  export const richBlockPhase = new WeakMap<HTMLElement, string>();
</script>

<script lang="ts">
  import { preserveMarkdownSelection } from './markdownSelection';

  let { source, kind, fallback }: {
    source: string;
    kind: 'inlineMath' | 'displayMath' | 'diagram';
    fallback: string;
  } = $props();
  let diagramUrl = $state<string>();
  let diagramLoaded = $state(false);
  let acceptDiagram: (() => void) | undefined;
  let discardDiagram: (() => void) | undefined;

  function prepare(node: HTMLElement) {
    const lifetime = new AbortController();
    let objectUrl: string | undefined;
    richBlockPhase.set(node, 'mount');
    void render(node).catch((error: unknown) => {
      const message = error instanceof Error && error.message.startsWith('SVG ') ? error.message : undefined;
      richBlockPhase.set(node, message ?? (error instanceof Error ? error.name : 'render failure'));
      releaseImage();
    });

    async function render(target: HTMLElement) {
      if (kind === 'diagram') {
        const { diagram } = await import('./markdownDiagram');
        richBlockPhase.set(node, 'render');
        const result = await diagram(source, lifetime.signal);
        if (!result || lifetime.signal.aborted) return;
        objectUrl = URL.createObjectURL(result);
        richBlockPhase.set(node, 'decode');
        acceptDiagram = () => {
          richBlockPhase.set(node, 'present');
          preserveMarkdownSelection(target, lifetime.signal, () => { diagramLoaded = true; });
        };
        discardDiagram = () => {
          richBlockPhase.set(node, 'decode failure');
          releaseImage();
          diagramUrl = undefined;
        };
        diagramUrl = objectUrl;
      } else {
        const { formula } = await import('./markdownFormula');
        if (lifetime.signal.aborted) return;
        const result = formula(source, kind === 'displayMath');
        if (result) preserveMarkdownSelection(target, lifetime.signal, () => target.replaceChildren(result));
      }
    }

    function releaseImage() {
      if (!objectUrl) return;
      URL.revokeObjectURL(objectUrl);
      objectUrl = undefined;
    }

    return { destroy() {
      lifetime.abort();
      releaseImage();
      acceptDiagram = undefined;
      discardDiagram = undefined;
    } };
  }
</script>

{#if kind === 'diagram'}
  <div class="markdown-diagram" use:prepare>
    {#if diagramUrl}
      <img src={diagramUrl} alt="Mermaid diagram" hidden={!diagramLoaded}
        onload={() => acceptDiagram?.()} onerror={() => discardDiagram?.()} />
    {/if}
    {#if !diagramLoaded}<pre><code data-language="mermaid">{fallback}</code></pre>{/if}
  </div>
{:else}
  <span class:markdown-inline-math={kind === 'inlineMath'} class:markdown-display-math={kind === 'displayMath'}
    use:prepare>{fallback}</span>
{/if}
