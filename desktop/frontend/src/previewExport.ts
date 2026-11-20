import { invoke } from '@tauri-apps/api/core';

export async function savePreviewImage(image: Blob, kind: 'image' | 'diagram' = 'image'): Promise<void> {
  const bytes = await image.arrayBuffer();
  await invoke('save_preview_image', bytes, { headers: { 'x-codex-preview-kind': kind } });
}

export async function exportDiagram(image: HTMLImageElement): Promise<void> {
  const scale = Math.min(2, 2400 / Math.max(image.naturalWidth, image.naturalHeight));
  const canvas = document.createElement('canvas');
  canvas.width = Math.max(1, Math.round(image.naturalWidth * scale));
  canvas.height = Math.max(1, Math.round(image.naturalHeight * scale));
  const context = canvas.getContext('2d');
  if (!context) return;
  context.drawImage(image, 0, 0, canvas.width, canvas.height);
  const png = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, 'image/png'));
  if (png) await savePreviewImage(png, 'diagram');
}
