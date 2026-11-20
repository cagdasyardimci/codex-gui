export async function waitFor(description: string, condition: () => boolean) {
  const deadline = performance.now() + 9000;
  while (!condition()) {
    if (performance.now() > deadline) throw new Error(description);
    await new Promise<void>((resolve) => setTimeout(resolve, 20));
  }
}

function button(label: string) {
  return Array.from(document.querySelectorAll('button'))
    .find((control) => control.textContent?.trim() === label && !control.disabled);
}

export async function click(label: string) {
  await waitFor(`Could not press ${label}`, () => !!button(label));
  button(label)?.click();
}

export function editor() {
  const control = document.querySelector<HTMLTextAreaElement>('textarea[aria-label="Message"]');
  if (!control) throw new Error('Could not find the mounted composer');
  return control;
}

export function typeText(value: string, composing = false) {
  const control = editor();
  control.value = value;
  control.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText', isComposing: composing }));
}
