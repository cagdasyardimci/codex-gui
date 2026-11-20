import { invoke } from '@tauri-apps/api/core';
import type { DraftAttachmentRequest, DraftAttachmentScope, ImageAnnotation, WorkspaceSnapshot } from './generated/workspace';
import { readComposerAnnotations, saveComposerAnnotations } from './projectIpc';
import { click, clickByLabel, editor, typeText, waitFor } from './fixtureControls';
import { rejectsStale } from './markdownProbe';

const FIRST = 'history-first';
const NAMES = ['picked.png', 'unannotated.png', 'last.png'];
const DRAFT = 'Review the selected images.';

export async function verifyImageAnnotations(visible: () => WorkspaceSnapshot | null) {
  try {
    const draft = () => visible()?.navigation.draft;
    await click('First fixture chat');
    await waitFor('The annotation fixture did not select its draft', () => visible()?.navigation.selectedChat === FIRST && !!draft());
    typeText(DRAFT);
    await waitFor('The original annotation draft did not persist', () => draft()?.text === DRAFT);
    await click('Attach Files');
    await waitFor('The three ordered fixture images were missing', () =>
      draft()?.attachments.map((attachment) => attachment.label).join(',') === NAMES.join(','));
    const workspaceId = visible()?.workspace?.workspaceId;
    const draftId = draft()?.id;
    if (!workspaceId || !draftId) throw new Error('The annotation editor had no draft scope');
    const scope: DraftAttachmentScope = { workspaceId, chatId: FIRST, draftId };
    const requests = draft()!.attachments.map((attachment): DraftAttachmentRequest => ({ scope, attachmentId: attachment.id }));
    const first = requests[0]!;
    const middle = requests[1]!;
    const last = requests[2]!;

    await open(NAMES[0]!);
    await place(0.25, 0.5, 'Discard this comment.');
    await click('Cancel');
    await waitFor('Cancel did not close the image editor', () => !annotationDialog());
    if ((await readComposerAnnotations(first)).annotations.length) throw new Error('Cancel saved a comment');

    await open(NAMES[0]!);
    await place(0.25, 0.5, 'Review the upper left.');
    const zoom = annotationDialog()?.querySelector<HTMLInputElement>('input[type="range"]');
    if (!zoom) throw new Error('The image zoom control was missing');
    const previousWidth = markerImage().getBoundingClientRect().width;
    zoom.value = '150';
    zoom.dispatchEvent(new Event('input', { bubbles: true }));
    await waitFor('The zoom did not resize the displayed image', () => markerImage().getBoundingClientRect().width > previousWidth * 1.4);
    await place(0.75, 0.125, 'Review the top edge.');
    await click('Save');
    await waitFor('Save did not stage the original image comments', () => !annotationDialog() && draft()?.attachments[0]?.annotationCount === 2);
    const saved = await readComposerAnnotations(first);
    checkAnnotation(saved.annotations[0], 0.25, 0.5, 'Review the upper left.');
    checkAnnotation(saved.annotations[1], 0.75, 0.125, 'Review the top edge.');
    const unannotated = await readComposerAnnotations(middle);
    if (unannotated.annotations.length || unannotated.digest === saved.digest) throw new Error('Annotation ownership crossed images');
    await rejectsStale(saveComposerAnnotations({ attachment: first, digest: unannotated.digest,
      original: saved.annotations, annotations: [] }));

    await click('Second fixture chat');
    await waitFor('Switching chats did not hide the image draft', () => visible()?.navigation.selectedChat === 'history-second' && !draft()?.attachments.length);
    await rejectsStale(readComposerAnnotations(first));
    await click('First fixture chat');
    await open(NAMES[0]!);
    await waitFor('Reopening did not restore the first image’s comment markers', () =>
      annotationDialog()?.querySelectorAll('.annotation-marker').length === 2 &&
      annotationDialog()?.querySelector('textarea')?.value === 'Review the upper left.');
    await click('Cancel');

    await open(NAMES[2]!);
    await place(0.5, 0.5, 'Review the center separately.');
    await click('Save');
    await waitFor('Saving comments rewrote the composer or changed image order', () =>
      !annotationDialog() && editor().value === DRAFT && draft()?.text === DRAFT &&
      draft()?.attachments.map((attachment) => attachment.annotationCount).join(',') === '2,0,1');
    await click('Send');
    await waitFor('The annotated image turn did not complete', () => !draft()?.attachments.length &&
      visible()?.navigation.actions.stop === null && !!visible()?.transcript.items.some((item) => item.text === 'The attachment was received.'));
    await invoke('verify_attachments_result', { failure: null });
  } catch (error) {
    await invoke('verify_attachments_result', { failure: String(error) });
  }
}

function annotationDialog() {
  return document.querySelector<HTMLDialogElement>('dialog.image-annotation-editor[open]');
}

async function open(name: string) {
  await clickByLabel(`Annotate ${name}`);
  await waitFor('The captured image did not decode in its annotation editor', () =>
    !!annotationDialog()?.querySelector<HTMLImageElement>('img')?.naturalWidth);
}

function markerImage() {
  const image = annotationDialog()?.querySelector<HTMLImageElement>('img');
  if (!image) throw new Error('The image annotation surface disappeared');
  return image;
}

async function place(x: number, y: number, text: string) {
  const oldCount = annotationDialog()?.querySelectorAll('.annotation-marker').length ?? 0;
  const image = markerImage();
  const bounds = image.getBoundingClientRect();
  image.dispatchEvent(new MouseEvent('click', { bubbles: true, detail: 1,
    clientX: bounds.left + x * bounds.width, clientY: bounds.top + y * bounds.height }));
  await waitFor('The measured point did not create a comment marker', () =>
    annotationDialog()?.querySelectorAll('.annotation-marker').length === oldCount + 1);
  const control = annotationDialog()?.querySelector('textarea');
  if (!control) throw new Error('The comment editor was absent');
  control.value = text;
  control.dispatchEvent(new InputEvent('input', { bubbles: true, data: text }));
}

function checkAnnotation(annotation: ImageAnnotation | undefined, x: number, y: number, text: string) {
  if (!annotation || Math.abs(annotation.x - x) > 0.005 || Math.abs(annotation.y - y) > 0.005 || annotation.text !== text) {
    throw new Error('The saved annotation differed from its normalized image coordinate');
  }
}
