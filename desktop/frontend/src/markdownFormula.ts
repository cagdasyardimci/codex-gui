import katex from 'katex';

const MAX_FORMULA_LENGTH = 8192;

export function formula(source: string, display: boolean): DocumentFragment | undefined {
  if (source.length > MAX_FORMULA_LENGTH) return;
  const fragment = document.createDocumentFragment();
  const stage = document.createElement('span');
  katex.render(source, stage, { displayMode: display, trust: false, throwOnError: true, maxExpand: 256, maxSize: 16 });
  fragment.append(...stage.childNodes);
  return fragment;
}
