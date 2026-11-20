use super::*;

pub(crate) struct FileTabCapture {
    pub checkout: CheckoutIdentity,
    pub relative: PathBuf,
    pub bytes: Option<Vec<u8>>,
    pub edit_revision: u32,
    pub kind: FileTabKind,
    files: CheckoutFiles,
    link: FileLink,
}

impl FileTabCapture {
    pub fn path(&self) -> Result<PathBuf, IpcError> {
        self.files.validate(self.link.id).map_err(file_error)?;
        Ok(self.checkout.canonical_path().join(&self.relative))
    }

    pub fn same_document(&self, other: &Self) -> bool {
        self.edit_revision == other.edit_revision
            && self
                .files
                .same_file(self.link.id, &other.files, other.link.id)
    }

    pub fn preview_bytes(&self, limit: u64) -> Result<Vec<u8>, IpcError> {
        self.files
            .read_limited(self.link.id, limit)
            .map(|read| read.bytes)
            .map_err(file_error)
    }
}

impl NavigationHandle {
    pub async fn capture_file_tab(
        &self,
        request: FileTabRead,
        include_bytes: bool,
    ) -> Result<FileTabCapture, IpcError> {
        let (reply, result) = oneshot::channel();
        self.request(Action::CaptureFileTab(request, include_bytes, reply))
            .await?;
        result.await.map_err(|_| IpcError::ProjectUnavailable)
    }
}

impl Navigation {
    pub(in crate::navigation) fn capture_file_tools_tab(
        &self,
        request: FileTabRead,
        include_bytes: bool,
    ) -> Result<FileTabCapture, IpcError> {
        let key = self.file_tools_key(&request.scope)?;
        let document = self
            .file_tools
            .sessions
            .get(&key)
            .ok_or(IpcError::StaleSelection)?
            .document(request.tab_id)?;
        if self.quit.is_some() || document.saving.is_some() {
            return Err(IpcError::StaleSelection);
        }
        document
            .files
            .validate(document.link.id)
            .map_err(file_error)?;
        let bytes = if include_bytes {
            Some(if let Some(edit) = &document.edit {
                document.encode_edit(edit).into_owned().into_bytes()
            } else {
                document
                    .files
                    .read(document.link.id)
                    .map_err(file_error)?
                    .bytes
            })
        } else {
            None
        };
        Ok(FileTabCapture {
            checkout: key.0,
            relative: document.relative.clone(),
            bytes,
            edit_revision: document.revision,
            kind: document.kind,
            files: document
                .files
                .duplicate(document.link.id)
                .map_err(file_error)?,
            link: document.link.clone(),
        })
    }
}
