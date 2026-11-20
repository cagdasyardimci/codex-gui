use codex_gui_core::ipc::FileSaveView;

use super::*;

struct SaveTarget {
    key: (CheckoutIdentity, Uuid),
    scope: DraftAttachmentScope,
    tab: Uuid,
    job: Uuid,
    edit_revision: u32,
}

pub(in crate::navigation) struct FileSaveCompletion {
    target: SaveTarget,
    result: Result<(CheckoutFiles, FileRevision), FileError>,
    reply: oneshot::Sender<FileSaveView>,
    _lease: RuntimeUse,
}

impl Default for FileTools {
    fn default() -> Self {
        let (saves, completed) = mpsc::channel(16);
        Self {
            sessions: HashMap::new(),
            saves,
            completed,
        }
    }
}

impl FileTools {
    pub(in crate::navigation) fn is_saving(&self) -> bool {
        self.sessions
            .values()
            .any(|session| session.tabs.iter().any(|tab| tab.saving.is_some()))
    }
}

impl NavigationHandle {
    pub async fn save_file_tab(&self, request: FileTabRead) -> Result<FileSaveView, IpcError> {
        let (reply, result) = oneshot::channel();
        self.request(Action::SaveFileTab(request, reply)).await?;
        result.await.map_err(|_| IpcError::ProjectUnavailable)
    }
}

impl Navigation {
    pub(in crate::navigation) fn start_file_save(
        &mut self,
        request: FileTabRead,
        reply: oneshot::Sender<FileSaveView>,
    ) -> Result<(), IpcError> {
        let key = self.file_tools_key(&request.scope)?;
        if self.quit.is_some() {
            return Err(IpcError::StaleSelection);
        }
        let session = self
            .file_tools
            .sessions
            .get_mut(&key)
            .ok_or(IpcError::StaleSelection)?;
        let document = session.document_mut(request.tab_id)?;
        if document.saving.is_some() || document.kind != FileTabKind::Text {
            return Err(IpcError::StaleSelection);
        }
        let Some(text) = &document.edit else {
            let _ = reply.send(FileSaveView {
                view: Some(session.view(None)),
                saved: true,
            });
            return Ok(());
        };
        let mut files = document
            .files
            .duplicate(document.link.id)
            .map_err(file_error)?;
        let disk = document.disk.clone().ok_or(IpcError::StaleSelection)?;
        let lease = self
            .owners
            .acquire_write(&key.0)
            .map_err(|error| report(error.into()))?;
        let handle = document.link.id;
        let text = document.encode_edit(text).into_owned();
        let target = SaveTarget {
            key,
            scope: request.scope,
            tab: document.id,
            job: Uuid::new_v4(),
            edit_revision: document.revision,
        };
        document.saving = Some(target.job);
        self.file_save_changed();
        let completed = self.file_tools.saves.clone();
        let gate = self
            .model
            .lock()
            .expect("workspace state lock poisoned")
            .file_save_fixture_gate
            .clone();
        tauri::async_runtime::spawn(async move {
            if let Some(gate) = gate {
                let _permit = gate.acquire().await;
            }
            let result = tauri::async_runtime::spawn_blocking(move || {
                let saved = files.save_text(handle, &disk, &text)?;
                Ok((files, saved))
            })
            .await
            .unwrap_or_else(|error| Err(FileError::Io(std::io::Error::other(error))));
            let _ = completed
                .send(Box::new(FileSaveCompletion {
                    target,
                    result,
                    reply,
                    _lease: lease,
                }))
                .await;
        });
        Ok(())
    }

    pub(in crate::navigation) fn finish_file_save(&mut self, completed: FileSaveCompletion) {
        let FileSaveCompletion {
            target,
            result,
            reply,
            _lease,
        } = completed;
        let visible = self
            .file_tools_key(&target.scope)
            .is_ok_and(|key| key == target.key);
        let Some(session) = self.file_tools.sessions.get_mut(&target.key) else {
            return;
        };
        let Ok(document) = session.document_mut(target.tab) else {
            return;
        };
        if document.saving != Some(target.job) {
            return;
        }
        document.saving = None;
        let saved = match result {
            Ok((files, revision)) => {
                document.files = files;
                document.disk = Some(revision);
                if document.revision == target.edit_revision {
                    document.edit = None;
                }
                true
            }
            Err(error) => {
                eprintln!("{error}");
                false
            }
        };
        let view = visible.then(|| session.view(None));
        self.file_save_changed();
        let _ = reply.send(FileSaveView { view, saved });
    }

    fn file_save_changed(&mut self) {
        self.view.file_revision = self.view.file_revision.wrapping_add(1);
        self.view.saving_files = self.file_tools.is_saving();
        self.publish_navigation();
    }
}
