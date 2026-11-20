use std::{io::Cursor, path::Path};

use codex_gui_core::{
    files::{FilePrefix, MAX_EDIT_BYTES},
    ipc::{FilePreviewKind, FilePreviewRequest, FileTabKind, IpcError},
};
use image::{ImageFormat, ImageReader, Limits};
use tauri::{State, WebviewWindow, ipc::Response};

use crate::{
    file_actions_ipc::{capture, validate},
    project_ipc::ProjectIpc,
    transcript_ipc::inline_raster_payload,
};

const MAX_PREVIEW_BYTES: u64 = 20 * 1024 * 1024;
const MAX_EDGE: u32 = 8192;
const MAX_PIXELS: u64 = 16 * 1024 * 1024;

pub(crate) fn document_kind(path: &Path, prefix: &FilePrefix) -> FileTabKind {
    let extension = path
        .extension()
        .and_then(|ext| ext.to_str())
        .unwrap_or_default()
        .to_ascii_lowercase();
    if prefix.length <= MAX_PREVIEW_BYTES {
        if raster_format(&prefix.bytes)
            .is_some_and(|format| format != ImageFormat::Bmp || extension == "bmp")
        {
            return FileTabKind::Raster;
        }
        if prefix.bytes.starts_with(b"%PDF-") || (extension == "pdf" && is_pdf(&prefix.bytes)) {
            return FileTabKind::Pdf;
        }
    }
    let text_extension = !matches!(
        extension.as_str(),
        "pdf" | "png" | "jpg" | "jpeg" | "gif" | "tif" | "tiff" | "bmp" | "heic" | "webp"
    );
    let utf8 = match std::str::from_utf8(&prefix.bytes) {
        Ok(_) => true,
        Err(error) => error.error_len().is_none() && prefix.length > prefix.bytes.len() as u64,
    };
    let text_prefix = !prefix.bytes.contains(&0) && utf8;
    if text_extension && prefix.length <= MAX_EDIT_BYTES && text_prefix {
        FileTabKind::Text
    } else {
        FileTabKind::Other
    }
}

#[tauri::command]
pub async fn read_file_preview(
    window: WebviewWindow,
    project: State<'_, ProjectIpc>,
    request: FilePreviewRequest,
) -> Result<Response, IpcError> {
    let source = capture(&window, &project, &request.target, false).await?;
    let expected = match request.kind {
        FilePreviewKind::Raster => FileTabKind::Raster,
        FilePreviewKind::Pdf => FileTabKind::Pdf,
    };
    if source.kind != expected {
        return Err(IpcError::StaleSelection);
    }
    let (source, bytes) = tauri::async_runtime::spawn_blocking(move || {
        let bytes = source.preview_bytes(MAX_PREVIEW_BYTES)?;
        let preview = match request.kind {
            FilePreviewKind::Raster => raster_preview(bytes)?,
            FilePreviewKind::Pdf if is_pdf(&bytes) => bytes,
            FilePreviewKind::Pdf => return Err(IpcError::StaleSelection),
        };
        Ok::<_, IpcError>((source, preview))
    })
    .await
    .map_err(|_| IpcError::ProjectUnavailable)??;
    validate(&window, &project, &request.target, &source).await?;
    Ok(Response::new(bytes))
}

fn is_pdf(bytes: &[u8]) -> bool {
    bytes
        .get(..bytes.len().min(1024))
        .is_some_and(|head| head.windows(5).any(|window| window == b"%PDF-"))
}

fn raster_format(bytes: &[u8]) -> Option<ImageFormat> {
    let format = image::guess_format(bytes).ok()?;
    matches!(
        format,
        ImageFormat::Png
            | ImageFormat::Jpeg
            | ImageFormat::Gif
            | ImageFormat::WebP
            | ImageFormat::Tiff
            | ImageFormat::Bmp
    )
    .then_some(format)
}

pub(crate) fn raster_preview(bytes: Vec<u8>) -> Result<Vec<u8>, IpcError> {
    let format = raster_format(&bytes).ok_or(IpcError::ProjectUnavailable)?;
    let (width, height) = ImageReader::with_format(Cursor::new(&bytes), format)
        .into_dimensions()
        .map_err(|_| IpcError::ProjectUnavailable)?;
    if width == 0
        || height == 0
        || width > MAX_EDGE
        || height > MAX_EDGE
        || u64::from(width) * u64::from(height) > MAX_PIXELS
    {
        return Err(IpcError::ProjectUnavailable);
    }
    match format {
        ImageFormat::Tiff | ImageFormat::Bmp => {
            let mut decoder = ImageReader::with_format(Cursor::new(bytes), format);
            let mut limits = Limits::default();
            limits.max_image_width = Some(MAX_EDGE);
            limits.max_image_height = Some(MAX_EDGE);
            limits.max_alloc = Some(64 * 1024 * 1024);
            decoder.limits(limits);
            let image = decoder.decode().map_err(|_| IpcError::ProjectUnavailable)?;
            let preview = if width > 2048 || height > 2048 {
                image.thumbnail(2048, 2048)
            } else {
                image
            };
            let mut output = Cursor::new(Vec::new());
            preview
                .write_to(&mut output, ImageFormat::Png)
                .map_err(|_| IpcError::ProjectUnavailable)?;
            inline_raster_payload(output.into_inner())
        }
        _ => inline_raster_payload(bytes),
    }
}
