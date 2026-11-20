use std::path::Path;

use codex_gui_core::{
    files::CheckoutFiles,
    ipc::{DraftAttachmentRequest, DraftAttachmentScope, DraftAttachmentView},
    storage::attachments::{BlobLease, composer::ComposerAttachment},
};
use serde_json::{Value, json};

use super::*;

pub(crate) enum Mutation {
    Append(DraftAttachmentScope, Vec<ComposerAttachment>),
    Remove(DraftAttachmentRequest),
}

impl NavigationHandle {
    pub(crate) fn attachment_store(&self) -> &AttachmentStore {
        &self.1
    }

    pub(crate) async fn mutate_attachments(&self, mutation: Mutation) -> Result<(), IpcError> {
        self.request(Action::ComposerAttachment(mutation))
            .await
            .map(|_| ())
    }
}

impl Navigation {
    pub(super) fn update_composer_attachments(
        &mut self,
        mutation: Mutation,
    ) -> Result<(), IpcError> {
        let scope = match &mutation {
            Mutation::Append(scope, _) => scope,
            Mutation::Remove(request) => &request.scope,
        };
        self.require(scope.workspace_id)?;
        if self.quit.is_some() {
            return Err(IpcError::StaleSelection);
        }
        let draft =
            DraftId(Uuid::parse_str(&scope.draft_id).map_err(|_| IpcError::StaleSelection)?);
        if !self.editable.contains_key(&draft)
            || !self
                .store
                .owns_composer_draft(draft, scope.chat_id.as_deref())
                .map_err(|error| report(error.into()))?
        {
            return Err(IpcError::StaleSelection);
        }
        let selection = self.selection.as_ref().ok_or(IpcError::StaleSelection)?;
        let _write = self
            .owners
            .acquire_write(&selection.checkout)
            .map_err(|error| report(error.into()))?;
        match mutation {
            Mutation::Append(_, items) => self.store.append_composer_attachments(draft, &items),
            Mutation::Remove(request) => self
                .store
                .remove_composer_attachment(draft, &request.attachment_id),
        }
        .map_err(|error| report(error.into()))?;
        if let Some(visible) = self
            .view
            .draft
            .as_mut()
            .filter(|visible| visible.id == draft.0.to_string())
        {
            let saved = self
                .store
                .read_editor_draft(draft)
                .map_err(|error| report(error.into()))?;
            visible.attachments = views(&saved.context);
            self.publish_navigation();
        }
        self.store.collect().map_err(|error| report(error.into()))?;
        Ok(())
    }

    pub(super) fn capture_composer_context(
        &self,
        draft: DraftId,
        mut text: String,
        source: Vec<Value>,
    ) -> Result<(String, Vec<Value>, Vec<BlobLease>), Failure> {
        let selection = self
            .selection
            .as_ref()
            .ok_or("no checkout owns this draft")?;
        let mut attachments = Vec::new();
        let mut context = Vec::new();
        for item in source {
            match item["kind"].as_str() {
                Some("image") => {
                    let id = item["id"]
                        .as_str()
                        .ok_or("the image has no draft identity")?;
                    attachments.push(self.store.lease_composer_image(draft, id)?);
                }
                Some("fileReference") => {
                    let path = item["path"]
                        .as_str()
                        .ok_or("the file reference has no path")?;
                    let root = selection.checkout.canonical_path();
                    let relative = Path::new(path)
                        .strip_prefix(root)
                        .unwrap_or_else(|_| Path::new(path));
                    let mut files = CheckoutFiles::new(selection.checkout.clone());
                    files.issue(relative)?;
                    let path = root.join(relative);
                    let path = path.to_str().ok_or("file reference is not Unicode")?;
                    let label = item["recordedMentionName"]
                        .as_str()
                        .or_else(|| relative.file_name().and_then(|name| name.to_str()))
                        .ok_or("file reference has no name")?;
                    if item["recordedMentionName"].is_null() {
                        if !text.is_empty() {
                            text.push_str("\n\n");
                        }
                        text.push_str("File reference: ");
                        text.push_str(&relative.to_string_lossy());
                    }
                    context.push(json!({"type": "mention", "name": label, "path": path}));
                }
                _ => context.push(item),
            }
        }
        Ok((text, context, attachments))
    }
}

pub(super) fn views(context: &[Value]) -> Vec<DraftAttachmentView> {
    context
        .iter()
        .filter_map(|item| {
            let image = match item["kind"].as_str()? {
                "image" => true,
                "fileReference" => false,
                _ => return None,
            };
            Some(DraftAttachmentView {
                id: item["id"].as_str()?.into(),
                label: item["title"].as_str()?.into(),
                image,
            })
        })
        .collect()
}
