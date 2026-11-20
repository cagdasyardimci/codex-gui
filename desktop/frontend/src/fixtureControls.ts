export async function waitFor(description: string, condition: () => boolean) {
  const deadline = performance.now() + 9000;
  while (!condition()) {
    if (performance.now() > deadline) throw new Error(description);
    await new Promise<void>((resolve) => setTimeout(resolve, 20));
  }
}

function button(label: string, within: ParentNode) {
  return Array.from(within.querySelectorAll('button'))
    .find((control) => (control.querySelector('.chat-title')?.textContent ?? control.textContent)?.trim() === label &&
      !control.matches(':disabled') && !control.closest('[hidden]'));
}

export async function click(label: string, within: ParentNode = document) {
  await waitFor(`Could not press ${label}`, () => !!button(label, within));
  button(label, within)?.click();
}

export async function clickByLabel(label: string) {
  const control = () => document.querySelector<HTMLButtonElement>(`button[aria-label="${CSS.escape(label)}"]:enabled`);
  await waitFor(`Could not press ${label}`, () => !!control());
  control()?.click();
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
