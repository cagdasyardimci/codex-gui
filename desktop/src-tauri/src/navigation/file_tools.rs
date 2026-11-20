use codex_gui_core::{
    files::{CheckoutFiles, FileError, FileLink, FileRevision, MAX_EDIT_BYTES},
    ipc::{
        DraftAttachmentScope, FileTabDiscard, FileTabEdit, FileTabKind, FileTabRead, FileTabView,
        FileToolsChange, FileToolsRequest, FileToolsView, OpenedFileSearchHit,
    },
};

use super::*;
use crate::transcript_ipc::{inline_raster_payload, raster_type};

#[derive(Default)]
pub(super) struct FileTools {
    sessions: HashMap<(CheckoutIdentity, Uuid), FileSession>,
}

#[derive(Debug, Clone, Copy)]
pub(super) struct CapturedFileDiscard {
    session: Uuid,
    file: FileTabDiscard,
}

struct FileSession {
    id: Uuid,
    open: bool,
    wide: bool,
    selected: Option<Uuid>,
    preview: Option<Uuid>,
    tabs: Vec<Document>,
}

struct Document {
    id: Uuid,
    relative: PathBuf,
    link: FileLink,
    files: CheckoutFiles,
    kind: FileTabKind,
    disk: Option<FileRevision>,
    crlf: bool,
    edit: Option<String>,
    revision: u32,
}

impl NavigationHandle {
    pub async fn open_file_search_hit(
        &self,
        hit: PreparedFileHit,
    ) -> Result<OpenedFileSearchHit, IpcError> {
        let (reply, result) = oneshot::channel();
        self.request(Action::OpenFileSearchHit(Box::new(hit), reply))
            .await?;
        result.await.map_err(|_| IpcError::ProjectUnavailable)
    }

    pub async fn file_tools(
        &self,
        request: FileToolsRequest,
        resolved: Option<PathBuf>,
    ) -> Result<FileToolsView, IpcError> {
        let (reply, result) = oneshot::channel();
        self.request(Action::FileTools(request, resolved, reply))
            .await?;
        result.await.map_err(|_| IpcError::ProjectUnavailable)
    }

    pub async fn read_file_tab(
        &self,
        request: FileTabRead,
        raster: bool,
    ) -> Result<Vec<u8>, IpcError> {
        let (reply, result) = oneshot::channel();
        self.request(Action::ReadFileTab(request, raster, reply))
            .await?;
        result.await.map_err(|_| IpcError::ProjectUnavailable)
    }

    pub async fn edit_file_tab(&self, request: FileTabEdit) -> Result<(), IpcError> {
        self.request(Action::EditFileTab(request)).await.map(|_| ())
    }
}

impl Navigation {
    pub(super) fn retire_file_search(&self) {
        self.model
            .lock()
            .expect("workspace state lock poisoned")
            .retire_file_search();
    }

    pub(super) fn open_file_match(
        &mut self,
        hit: PreparedFileHit,
    ) -> Result<OpenedFileSearchHit, IpcError> {
        let key = self.file_tools_key(hit.scope())?;
        if self.quit.is_some() || !hit.still_current() {
            return Err(IpcError::StaleSelection);
        }
        let found = &hit.file;
        let session = self.file_tools.sessions.entry(key).or_default();
        let existing = session
            .tabs
            .iter()
            .find(|tab| tab.relative == found.relative);
        if existing.is_some_and(|tab| {
            tab.is_dirty()
                || tab.kind != FileTabKind::Text
                || !tab
                    .files
                    .same_file(tab.link.id, &found.files, found.link.id)
        }) {
            return Err(IpcError::StaleSelection);
        }
        let current = found
            .files
            .read_limited(found.link.id, MAX_EDIT_BYTES)
            .map_err(|_| IpcError::StaleSelection)?;
        if current.revision != found.read.revision || !hit.still_current() {
            return Err(IpcError::StaleSelection);
        }
        let line = found.line;
        let id = if let Some(tab) = existing {
            let id = tab.id;
            session.keep(id);
            id
        } else {
            let text = std::str::from_utf8(&current.bytes).map_err(|_| IpcError::StaleSelection)?;
            let id = Uuid::new_v4();
            let file = hit.file;
            session.tabs.push(Document {
                id,
                relative: file.relative,
                files: file.files,
                link: file.link,
                kind: FileTabKind::Text,
                disk: Some(current.revision),
                crlf: preserves_crlf(text),
                edit: None,
                revision: 0,
            });
            id
        };
        session.selected = Some(id);
        session.open = true;
        Ok(OpenedFileSearchHit {
            view: session.view(None),
            line,
        })
    }

    fn file_tools_key(
        &self,
        scope: &DraftAttachmentScope,
    ) -> Result<(CheckoutIdentity, Uuid), IpcError> {
        self.require(scope.workspace_id)?;
        if self.view.selected_chat != scope.chat_id
            || self.view.draft.as_ref().map(|draft| &draft.id) != Some(&scope.draft_id)
        {
            return Err(IpcError::StaleSelection);
        }
        Ok((
            self.selection
                .as_ref()
                .ok_or(IpcError::RetiredWorkspace)?
                .checkout
                .clone(),
            Uuid::parse_str(&scope.draft_id).map_err(|_| IpcError::StaleSelection)?,
        ))
    }

    pub(super) fn change_file_tools(
        &mut self,
        request: FileToolsRequest,
        resolved: Option<PathBuf>,
    ) -> Result<FileToolsView, IpcError> {
        let key = self.file_tools_key(&request.scope)?;
        if matches!(request.change, FileToolsChange::Inspect) {
            return Ok(self.file_tools.sessions.get(&key).map_or_else(
                || FileSession::default().view(None),
                |session| session.view(None),
            ));
        }
        if self.quit.is_some() {
            return Err(IpcError::StaleSelection);
        }
        let checkout = key.0.clone();
        let session = self.file_tools.sessions.entry(key).or_default();
        let mut discard = None;
        match request.change {
            FileToolsChange::Inspect => unreachable!(),
            FileToolsChange::Show(value) => session.open = value,
            FileToolsChange::Widen(value) => session.wide = value,
            FileToolsChange::Open(open) => {
                session.open_file(
                    checkout,
                    resolved.ok_or(IpcError::StaleSelection)?,
                    open.keep,
                )?;
            }
            FileToolsChange::Select(id) => {
                session.document(id)?;
                session.selected = Some(id);
            }
            FileToolsChange::Keep(id) => {
                session.document(id)?;
                session.keep(id);
            }
            FileToolsChange::Move(movement) => {
                session.move_tab(movement.tab_id, movement.before)?
            }
            FileToolsChange::Close(id) => {
                let document = session.document_mut(id)?;
                if document.save(&checkout, &self.owners) {
                    session.remove(id);
                } else {
                    discard = Some(document.discard());
                }
            }
            FileToolsChange::Discard(target) => {
                if !session.matches_discard(target) {
                    return Err(IpcError::StaleSelection);
                }
                session.remove(target.tab_id);
            }
        }
        Ok(session.view(discard))
    }

    pub(super) fn read_file_tools(
        &mut self,
        request: FileTabRead,
        raster: bool,
    ) -> Result<Vec<u8>, IpcError> {
        let key = self.file_tools_key(&request.scope)?;
        let document = self
            .file_tools
            .sessions
            .get_mut(&key)
            .ok_or(IpcError::StaleSelection)?
            .document_mut(request.tab_id)?;
        if raster {
            document.raster()
        } else {
            document.text()
        }
    }

    pub(super) fn edit_file_tools(&mut self, request: FileTabEdit) -> Result<(), IpcError> {
        if self.draining_quit() {
            return Err(IpcError::StaleSelection);
        }
        // Session and tab IDs are minted together. Buffered typing may reach this
        // actor after the WebView selects another tab, chat or checkout.
        let (_, session) = self
            .file_tools
            .sessions
            .iter_mut()
            .find(|(_, session)| session.id == request.session_id)
            .ok_or(IpcError::StaleSelection)?;
        session.document_mut(request.tab_id)?.edit(request.text)?;
        session.keep(request.tab_id);
        Ok(())
    }
}

impl FileTools {
    pub(super) fn has_edits(&self, owner: Option<&CheckoutIdentity>) -> bool {
        self.sessions.iter().any(|((checkout, _), session)| {
            owner.is_none_or(|owner| owner == checkout)
                && session.tabs.iter().any(Document::is_dirty)
        })
    }

    pub(super) fn save_all(&mut self, owners: &RuntimeOwners) -> Vec<CapturedFileDiscard> {
        let mut failures = Vec::new();
        for ((checkout, _), session) in &mut self.sessions {
            for document in &mut session.tabs {
                if !document.save(checkout, owners) {
                    failures.push(CapturedFileDiscard {
                        session: session.id,
                        file: document.discard(),
                    });
                }
            }
        }
        failures
    }

    pub(super) fn discard_all(&mut self, captured: &[CapturedFileDiscard]) -> bool {
        let current = self.sessions.values().flat_map(|session| {
            session
                .tabs
                .iter()
                .filter(|document| document.is_dirty())
                .map(move |document| CapturedFileDiscard {
                    session: session.id,
                    file: document.discard(),
                })
        });
        let mut count = 0;
        for target in current {
            if !captured
                .iter()
                .any(|entry| entry.session == target.session && entry.file == target.file)
            {
                return false;
            }
            count += 1;
        }
        if count != captured.len() {
            return false;
        }
        for session in self.sessions.values_mut() {
            let session_id = session.id;
            for entry in captured.iter().filter(|entry| entry.session == session_id) {
                session.remove(entry.file.tab_id);
            }
        }
        true
    }
}

impl Default for FileSession {
    fn default() -> Self {
        Self {
            id: Uuid::new_v4(),
            open: false,
            wide: false,
            selected: None,
            preview: None,
            tabs: Vec::new(),
        }
    }
}

impl FileSession {
    fn view(&self, discard: Option<FileTabDiscard>) -> FileToolsView {
        FileToolsView {
            session_id: self.id,
            open: self.open,
            wide: self.wide,
            selected: self.selected,
            tabs: self
                .tabs
                .iter()
                .map(|document| FileTabView {
                    id: document.id,
                    path: document.link.display_path.clone(),
                    kind: document.kind,
                    preview: self.preview == Some(document.id),
                    dirty: document.is_dirty(),
                })
                .collect(),
            discard,
        }
    }

    fn open_file(
        &mut self,
        checkout: CheckoutIdentity,
        path: PathBuf,
        keep: bool,
    ) -> Result<(), IpcError> {
        if let Some(existing) = self.tabs.iter().find(|tab| tab.relative == path) {
            let id = existing.id;
            self.selected = Some(id);
            if keep {
                self.keep(id);
            }
        } else {
            let document = Document::open(checkout, path).map_err(file_error)?;
            let id = document.id;
            // Raster images have their own retained tabs. Only one clean file
            // follows browsing in the preview position.
            if !keep && document.kind != FileTabKind::Raster {
                if let Some(preview) = self.preview {
                    self.remove(preview);
                }
                self.preview = Some(id);
            }
            self.tabs.push(document);
            self.selected = Some(id);
        }
        self.open = true;
        Ok(())
    }

    fn index(&self, id: Uuid) -> Result<usize, IpcError> {
        self.tabs
            .iter()
            .position(|tab| tab.id == id)
            .ok_or(IpcError::StaleSelection)
    }

    fn document(&self, id: Uuid) -> Result<&Document, IpcError> {
        Ok(&self.tabs[self.index(id)?])
    }

    fn document_mut(&mut self, id: Uuid) -> Result<&mut Document, IpcError> {
        let index = self.index(id)?;
        Ok(&mut self.tabs[index])
    }

    fn keep(&mut self, id: Uuid) {
        if self.preview == Some(id) {
            self.preview = None;
        }
    }

    fn move_tab(&mut self, id: Uuid, before: Option<Uuid>) -> Result<(), IpcError> {
        let from = self.index(id)?;
        let to = before
            .map(|id| self.index(id))
            .transpose()?
            .unwrap_or(self.tabs.len());
        if from != to {
            let tab = self.tabs.remove(from);
            self.tabs.insert(if from < to { to - 1 } else { to }, tab);
        }
        Ok(())
    }

    fn matches_discard(&self, target: FileTabDiscard) -> bool {
        self.document(target.tab_id)
            .is_ok_and(|doc| doc.is_dirty() && doc.revision == target.revision)
    }

    fn remove(&mut self, id: Uuid) {
        let Ok(index) = self.index(id) else { return };
        self.tabs.remove(index);
        self.keep(id);
        if self.selected == Some(id) {
            self.selected = self
                .tabs
                .get(index)
                .or_else(|| self.tabs.last())
                .map(|tab| tab.id);
        }
    }
}

impl Document {
    fn open(checkout: CheckoutIdentity, relative: PathBuf) -> Result<Self, FileError> {
        let mut files = CheckoutFiles::new(checkout);
        let link = files.issue(&relative)?;
        let (kind, disk, crlf) = match files.read_limited(link.id, MAX_EDIT_BYTES) {
            Ok(read) if raster_type(&read.bytes).is_some() => (FileTabKind::Raster, None, false),
            Ok(read) if !read.bytes.contains(&0) => match std::str::from_utf8(&read.bytes) {
                Ok(text) => (FileTabKind::Text, Some(read.revision), preserves_crlf(text)),
                Err(_) => (FileTabKind::Other, None, false),
            },
            Ok(_) | Err(FileError::TooLarge) => (FileTabKind::Other, None, false),
            Err(error) => return Err(error),
        };
        Ok(Self {
            id: Uuid::new_v4(),
            relative,
            link,
            files,
            kind,
            disk,
            crlf,
            edit: None,
            revision: 0,
        })
    }

    fn text(&mut self) -> Result<Vec<u8>, IpcError> {
        if self.kind != FileTabKind::Text {
            return Err(IpcError::StaleSelection);
        }
        if let Some(text) = &self.edit {
            return Ok(text.as_bytes().to_vec());
        }
        let read = self
            .files
            .read_limited(self.link.id, MAX_EDIT_BYTES)
            .map_err(file_error)?;
        let text = std::str::from_utf8(&read.bytes).map_err(|_| IpcError::ProjectUnavailable)?;
        if text.contains('\0') {
            return Err(IpcError::ProjectUnavailable);
        }
        self.crlf = preserves_crlf(text);
        self.disk = Some(read.revision);
        Ok(read.bytes)
    }

    fn raster(&self) -> Result<Vec<u8>, IpcError> {
        if self.kind != FileTabKind::Raster {
            return Err(IpcError::StaleSelection);
        }
        let read = self
            .files
            .read_limited(self.link.id, MAX_EDIT_BYTES)
            .map_err(file_error)?;
        inline_raster_payload(read.bytes)
    }

    fn edit(&mut self, text: String) -> Result<(), IpcError> {
        if self.kind != FileTabKind::Text || text.contains('\0') {
            return Err(IpcError::StaleSelection);
        }
        let bytes = text.len()
            + if self.crlf {
                text.bytes().filter(|byte| *byte == b'\n').count()
            } else {
                0
            };
        if bytes as u64 > MAX_EDIT_BYTES {
            return Err(IpcError::ProjectUnavailable);
        }
        self.edit = Some(text);
        self.revision = self
            .revision
            .checked_add(1)
            .ok_or(IpcError::ProjectUnavailable)?;
        Ok(())
    }

    fn save(&mut self, checkout: &CheckoutIdentity, owners: &RuntimeOwners) -> bool {
        let Some(text) = &self.edit else { return true };
        let Some(disk) = &self.disk else { return false };
        let _lease = match owners.acquire_write(checkout) {
            Ok(lease) => lease,
            Err(error) => {
                eprintln!("{error}");
                return false;
            }
        };
        let encoded;
        let text = if self.crlf {
            encoded = text.replace("\r\n", "\n").replace('\n', "\r\n");
            encoded.as_str()
        } else {
            text.as_str()
        };
        match self.files.save_text(self.link.id, disk, text) {
            Ok(revision) => {
                self.disk = Some(revision);
                self.edit = None;
                true
            }
            Err(error) => {
                eprintln!("{error}");
                false
            }
        }
    }

    fn is_dirty(&self) -> bool {
        self.edit.is_some()
    }

    fn discard(&self) -> FileTabDiscard {
        FileTabDiscard {
            tab_id: self.id,
            revision: self.revision,
        }
    }
}

fn preserves_crlf(text: &str) -> bool {
    let mut lines = text
        .split_inclusive('\n')
        .filter(|line| line.ends_with('\n'))
        .peekable();
    lines.peek().is_some() && lines.all(|line| line.ends_with("\r\n"))
}

fn file_error(error: FileError) -> IpcError {
    match error {
        FileError::InvalidHandle | FileError::Changed | FileError::Replaced => {
            IpcError::StaleSelection
        }
        FileError::Checkout(_) => IpcError::RetiredWorkspace,
        _ => {
            eprintln!("{error}");
            IpcError::ProjectUnavailable
        }
    }
}
