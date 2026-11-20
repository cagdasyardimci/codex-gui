<script lang="ts">
  import type { MarkdownKind, MarkdownNode, TranscriptRowRequest } from './generated/workspace';
  import { openTranscriptLink, renderTranscriptMarkdown } from './projectIpc';
  import MarkdownImage from './MarkdownImage.svelte';
  import MarkdownRichBlock from './MarkdownRichBlock.svelte';
  import { preserveMarkdownSelection } from './markdownSelection';

  let { source, request }: { source: string; request?: TranscriptRowRequest } = $props();
  let rendered = $state.raw<MarkdownNode[] | null>(null);
  let root = $state<HTMLDivElement>();

  const tags: Partial<Record<MarkdownKind, string>> = {
    paragraph: 'p', heading1: 'h1', heading2: 'h2', heading3: 'h3', heading4: 'h4',
    heading5: 'h5', heading6: 'h6', quote: 'blockquote', bulletList: 'ul', listItem: 'li', emphasis: 'em',
    strong: 'strong', strike: 'del', literal: 'pre', tableRow: 'tr',
  };

  $effect(() => {
    const row = request;
    const element = root;
    rendered = null;
    if (!row || !element || !/[\n\r`*_[\]<>#~&$\\+-]|^\s*\d+[.)]\s|^(?: {4}|\t)/.test(source)) return;
    const lifetime = new AbortController();
    void renderTranscriptMarkdown(row).then((result) => {
      const children = result?.[0]?.children ?? [];
      if (lifetime.signal.aborted || !result || result.length === 1 && result[0]?.kind === 'paragraph' &&
          children.every((node) => node.kind === 'text') && plain(children) === source) return;
      preserveMarkdownSelection(element, lifetime.signal, () => { rendered = result; });
    }).catch(() => {});
    return () => lifetime.abort();
  });

  function plain(nodes: MarkdownNode[] | undefined): string {
    return nodes?.map((node) => node.kind === 'text' || node.kind === 'code' ? node.value ?? '' : plain(node.children)).join('') ?? '';
  }

  function follow(target: string) {
    if (target.startsWith('#')) {
      if (!root) return;
      let fragment: string;
      try { fragment = decodeURIComponent(target.slice(1)); } catch { return; }
      const seen = new Map<string, number>();
      for (const heading of root.querySelectorAll('h1, h2, h3, h4, h5, h6')) {
        const slug = (heading.textContent ?? '').trim().toLowerCase().replace(/[^\p{Letter}\p{Number}_\s-]/gu, '').replace(/\s+/g, '-');
        const ordinal = seen.get(slug) ?? 0;
        seen.set(slug, ordinal + 1);
        if ((ordinal ? `${slug}-${ordinal}` : slug) === fragment) {
          heading.scrollIntoView({ block: 'start' });
          return;
        }
      }
    } else if (request) {
      void openTranscriptLink({ row: request, target }).catch(() => {});
    }
  }
</script>

{#snippet nodes(items?: MarkdownNode[], header = false)}
  {#each items ?? [] as node}
    {@const tag = tags[node.kind]}
    {#if node.kind === 'text'}{node.value}
    {:else if node.kind === 'code'}<code>{node.value}</code>
    {:else if node.kind === 'codeBlock'}
      {#if node.value?.toLowerCase() === 'mermaid'}
        <MarkdownRichBlock source={plain(node.children)} fallback={plain(node.children)} kind="diagram" />
      {:else}<pre><code data-language={node.value}>{plain(node.children)}</code></pre>{/if}
    {:else if node.kind === 'inlineMath' || node.kind === 'displayMath'}
      <MarkdownRichBlock source={node.value ?? ''} fallback={plain(node.children)} kind={node.kind} />
    {:else if node.kind === 'image'}
      {#if node.value && request}
        <MarkdownImage request={{ row: request, target: node.value }} alt={plain(node.children)} />
      {:else}{plain(node.children)}{/if}
    {:else if node.kind === 'link'}
      {#if node.value}<button class="markdown-link" type="button" onclick={() => follow(node.value!)}>{@render nodes(node.children)}</button>
      {:else}{@render nodes(node.children)}{/if}
    {:else if node.kind === 'break'}<br />
    {:else if node.kind === 'rule'}<hr />
    {:else if node.kind === 'checkbox'}<input type="checkbox" disabled checked={node.value === 'true'} />
    {:else if node.kind === 'orderedList'}<ol start={Number(node.value)}>{@render nodes(node.children)}</ol>
    {:else if node.kind === 'table'}
      <table>
        {#each node.children?.filter((part) => part.kind === 'tableHead') ?? [] as head}
          <thead><tr>{@render nodes(head.children, true)}</tr></thead>
        {/each}
        <tbody>{@render nodes(node.children?.filter((part) => part.kind === 'tableRow'))}</tbody>
      </table>
    {:else if node.kind === 'tableCell'}
      {#if header}<th scope="col">{@render nodes(node.children)}</th>{:else}<td>{@render nodes(node.children)}</td>{/if}
    {:else if tag}<svelte:element this={tag}>{@render nodes(node.children)}</svelte:element>
    {/if}
  {/each}
{/snippet}

<div class="markdown-document" bind:this={root}>
  {#if rendered}{@render nodes(rendered)}{:else}<p class="markdown-source">{source}</p>{/if}
</div>
