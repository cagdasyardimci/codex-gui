<script lang="ts">
  import { preserveMarkdownSelection } from './markdownSelection';

  let { source, kind, fallback }: {
    source: string;
    kind: 'inlineMath' | 'displayMath' | 'diagram';
    fallback: string;
  } = $props();

  function prepare(node: HTMLElement) {
    const lifetime = new AbortController();
    let objectUrl: string | undefined;
    const observer = new IntersectionObserver((entries) => {
      if (!entries.some((entry) => entry.isIntersecting)) return;
      observer.disconnect();
      void render(node).catch(releaseImage);
    });
    observer.observe(node);

    async function render(target: HTMLElement) {
      if (kind === 'diagram') {
        const { diagram } = await import('./markdownDiagram');
        const result = await diagram(source, lifetime.signal);
        if (!result || lifetime.signal.aborted) return;
        objectUrl = URL.createObjectURL(result);
        const image = new Image();
        image.alt = 'Mermaid diagram';
        image.src = objectUrl;
        await image.decode();
        preserveMarkdownSelection(target, lifetime.signal, () => target.replaceChildren(image));
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
      observer.disconnect();
      lifetime.abort();
      releaseImage();
    } };
  }
</script>

{#if kind === 'diagram'}
  <div class="markdown-diagram" use:prepare><pre><code data-language="mermaid">{fallback}</code></pre></div>
{:else}
  <span class:markdown-display-math={kind === 'displayMath'} use:prepare>{fallback}</span>
{/if}
