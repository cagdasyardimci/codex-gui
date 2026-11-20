<script lang="ts">
  import PreviewViewer from './PreviewViewer.svelte';

  let { source, alt, download }: { source: string; alt: string; download: () => Promise<void> } = $props();
  let preview = $state<string>();
  let decoded = $state(false);
  let expanded = $state(false);
  const svgNamespace = 'http://www.w3.org/2000/svg';
  const allowed = new Set([
    'svg', 'g', 'a', 'defs', 'symbol', 'use', 'title', 'desc', 'path', 'rect', 'circle', 'ellipse', 'line',
    'polyline', 'polygon', 'text', 'tspan', 'textPath', 'linearGradient', 'radialGradient', 'stop', 'mask',
    'clipPath', 'pattern', 'marker',
  ]);

  function sanitized(text: string) {
    if (text.length > 512 * 1024 || /<!doctype/i.test(text)) return undefined;
    const document = new DOMParser().parseFromString(text, 'image/svg+xml');
    const root = document.documentElement;
    if (root.localName !== 'svg' || root.namespaceURI !== svgNamespace) return undefined;
    for (const dimension of ['width', 'height']) {
      const value = root.getAttribute(dimension);
      if (value && Math.abs(Number.parseFloat(value)) > 4096) return undefined;
    }
    const elements = [root, ...root.querySelectorAll('*')];
    if (elements.length > 4000) return undefined;
    for (const element of elements) {
      if (element.namespaceURI !== svgNamespace || !allowed.has(element.localName)) {
        element.remove();
        continue;
      }
      for (const attribute of [...element.attributes]) {
        const name = attribute.localName.toLowerCase();
        const value = attribute.value;
        const hasExternalReference = /url\s*\(/iu.test(value) &&
          value.replace(/url\s*\(\s*['"]?#[\w.:-]+['"]?\s*\)/giu, '').match(/url\s*\(/iu);
        if (name.startsWith('on') || name === 'base' || name === 'src' ||
            (name === 'href' && !/^#[\w.:-]+$/u.test(value)) ||
            (name === 'style' && /[@\\]/u.test(value)) || hasExternalReference) {
          element.removeAttributeNode(attribute);
        }
      }
    }
    return new XMLSerializer().serializeToString(root);
  }

  $effect(() => {
    const safe = sanitized(source);
    preview = undefined;
    decoded = false;
    expanded = false;
    if (!safe) return;
    const uri = URL.createObjectURL(new Blob([safe], { type: 'image/svg+xml' }));
    preview = uri;
    return () => URL.revokeObjectURL(uri);
  });
</script>

{#if preview}
  <img src={preview} {alt} onload={() => { decoded = true; }} onerror={() => { preview = undefined; }} />
  {#if decoded}
    <button type="button" aria-label={`Expand ${alt}`}
      onclick={(event) => { event.currentTarget.focus({ preventScroll: true }); expanded = true; }}>Expand</button>
    {#if expanded}
      <PreviewViewer source={preview} label={alt} {download} close={() => { expanded = false; }} />
    {/if}
  {/if}
{/if}

<style>
  img { display: block; max-inline-size: 100%; }
</style>
