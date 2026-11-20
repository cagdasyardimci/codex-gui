export function preserveMarkdownSelection(root: HTMLElement, signal: AbortSignal, apply: () => void) {
  function reveal() {
    if (signal.aborted) return true;
    const selection = window.getSelection();
    if (selection && !selection.isCollapsed && selection.rangeCount && selection.getRangeAt(0).intersectsNode(root)) {
      return false;
    }
    document.removeEventListener('selectionchange', reveal);
    apply();
    return true;
  }
  if (!reveal()) document.addEventListener('selectionchange', reveal, { signal });
}
