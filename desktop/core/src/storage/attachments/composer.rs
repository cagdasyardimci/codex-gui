use std::{collections::HashSet, io, path::Path};

use rusqlite::TransactionBehavior;
use serde_json::{Value, json};

use crate::{
    checkout::CheckoutIdentity,
    files::read_local_file,
    ipc::{DraftImageAnnotations, ImageAnnotation},
    storage::project_context::{self, ProjectContext, ProjectContextError, ProjectContextView},
};

use super::{
    AttachmentError, AttachmentStore, BlobId, BlobLease, DraftId, read_draft, replace_references,
    save_in_transaction, verify_saved_file,
};

pub const MAX_COMPOSER_ATTACHMENTS: usize = 8;
const MAX_IMAGE_ANNOTATIONS: usize = 32;

pub struct ComposerAttachment {
    pub id: String,
    pub title: String,
    pub kind: ComposerAttachmentKind,
}

pub enum ComposerAttachmentKind {
    Image(BlobLease),
    File(String),
}

impl AttachmentStore {
    pub fn composer_project_context(
        &self,
        checkout: &CheckoutIdentity,
    ) -> Result<Option<ProjectContext>, ProjectContextError> {
        let state = self.inner.state();
        project_context::read_project_context(&state.database, checkout)
    }

    pub fn project_context_view(
        &self,
        checkout: &CheckoutIdentity,
    ) -> Result<ProjectContextView, ProjectContextError> {
        let state = self.inner.state();
        Ok(project_context::project_context_view(&state.database, checkout)?.unwrap_or_default())
    }

    pub fn edit_project_context(
        &self,
        checkout: &CheckoutIdentity,
        revision: u32,
        edit: impl FnOnce(&mut ProjectContext) -> Result<(), ProjectContextError>,
    ) -> Result<(), ProjectContextError> {
        let mut state = self.inner.state();
        project_context::edit_project_context(&mut state.database, checkout, revision, edit)
            .map(|_| ())
    }

    pub fn initialize_composer_project_context(
        &self,
        checkout: &CheckoutIdentity,
        context: &ProjectContext,
    ) -> Result<bool, ProjectContextError> {
        let mut state = self.inner.state();
        project_context::initialize_project_context(&mut state.database, checkout, context)
    }

    pub fn add_composer_context(
        &self,
        draft: DraftId,
        expected: &str,
        text: &str,
        context: Value,
    ) -> Result<(), AttachmentError> {
        let mut state = self.inner.state();
        let transaction = state
            .database
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        let mut saved = read_draft(&transaction, draft)?.ok_or(AttachmentError::MissingDraft)?;
        if saved.text != expected {
            return Err(AttachmentError::StaleComposerText);
        }
        if saved
            .context
            .iter()
            .filter(|item| is_composer_attachment(item))
            .count()
            >= MAX_COMPOSER_ATTACHMENTS
        {
            return Err(io::Error::other("too many composer attachments").into());
        }
        saved.context.push(context);
        let revision = saved
            .revision
            .next()
            .ok_or_else(|| io::Error::other("draft revision exhausted"))?;
        save_in_transaction(
            &transaction,
            draft,
            Some(saved.revision),
            revision,
            Some(text),
            Some(&saved.context),
        )?;
        transaction.commit()?;
        Ok(())
    }
    pub fn composer_image_annotations(
        &self,
        draft: DraftId,
        id: &str,
    ) -> Result<DraftImageAnnotations, AttachmentError> {
        let state = self.inner.state();
        let saved = read_draft(&state.database, draft)?.ok_or(AttachmentError::MissingDraft)?;
        let image = image_context(&saved.context, id).ok_or(AttachmentError::StaleAnnotations)?;
        let blob = image["path"]
            .as_str()
            .and_then(|path| self.composer_blob_id(Path::new(path)))
            .ok_or(AttachmentError::StaleAnnotations)?;
        verify_saved_file(&state.database, &self.inner.blobs, blob)?;
        Ok(DraftImageAnnotations {
            digest: hex::encode(blob.0),
            annotations: image_annotations(image),
        })
    }

    pub fn save_composer_image_annotations(
        &self,
        draft: DraftId,
        id: &str,
        digest: &str,
        original: &[ImageAnnotation],
        annotations: &[ImageAnnotation],
        maximum_bytes: u64,
    ) -> Result<(), AttachmentError> {
        let mut ids = HashSet::new();
        if annotations.len() > MAX_IMAGE_ANNOTATIONS.max(original.len())
            || annotations
                .iter()
                .any(|annotation| !annotation.is_valid() || !ids.insert(&annotation.id))
        {
            return Err(io::Error::other("invalid image annotations").into());
        }
        let lease = self.lease_composer_image(draft, id)?;
        if hex::encode(lease.id.0) != digest {
            return Err(AttachmentError::StaleAnnotations);
        }
        lease.read_preview(maximum_bytes)?;
        self.update_composer_attachments(draft, |context| {
            let image = context
                .iter_mut()
                .find(|item| item["kind"] == "image" && item["id"] == id)
                .ok_or(AttachmentError::StaleAnnotations)?;
            let current = image["path"]
                .as_str()
                .and_then(|path| self.composer_blob_id(Path::new(path)));
            if current != Some(lease.id) || image_annotations(image) != original {
                return Err(AttachmentError::StaleAnnotations);
            }
            image["imageAnnotations"] = json!(annotations);
            Ok(())
        })
    }
    pub fn owns_composer_draft(
        &self,
        draft: DraftId,
        thread: Option<&str>,
    ) -> Result<bool, AttachmentError> {
        let state = self.inner.state();
        let id = draft.0.as_bytes().as_slice();
        let owned = match thread {
            Some(thread) => state.database.query_row(
                "SELECT EXISTS (SELECT 1 FROM thread_drafts WHERE thread_id = ?1 AND draft_id = ?2)",
                rusqlite::params![thread, id], |row| row.get(0),
            )?,
            None => state.database.query_row(
                "SELECT EXISTS (SELECT 1 FROM desktop_selection WHERE slot = 1 AND source_draft = ?1)",
                [id], |row| row.get(0),
            )?,
        };
        Ok(owned)
    }

    pub fn append_composer_attachments(
        &self,
        draft: DraftId,
        added: &[ComposerAttachment],
    ) -> Result<(), AttachmentError> {
        self.update_composer_attachments(draft, |context| {
            let mut occupied = context.iter().filter_map(|item| item["id"].as_str().map(str::to_owned)).collect::<HashSet<_>>();
            if context.iter().filter(|item| is_composer_attachment(item)).count() + added.len() > MAX_COMPOSER_ATTACHMENTS {
                return Err(io::Error::other("too many composer attachments").into());
            }
            for attachment in added {
                if !occupied.insert(attachment.id.clone()) {
                    return Err(io::Error::other("duplicate composer attachment identity").into());
                }
                let (kind, path) = match &attachment.kind {
                    ComposerAttachmentKind::Image(lease) => {
                        if !std::sync::Arc::ptr_eq(&self.inner, &lease.store) {
                            return Err(AttachmentError::ForeignLease);
                        }
                        ("image", lease.path().into_os_string().into_string()
                            .map_err(|_| io::Error::other("attachment path is not Unicode"))?)
                    }
                    ComposerAttachmentKind::File(path) => ("fileReference", path.clone()),
                };
                context.push(json!({"id": attachment.id, "kind": kind, "title": attachment.title, "path": path}));
            }
            Ok(())
        })
    }

    pub fn remove_composer_attachment(
        &self,
        draft: DraftId,
        attachment: &str,
    ) -> Result<(), AttachmentError> {
        self.update_composer_attachments(draft, |context| {
            let at = context
                .iter()
                .position(|item| is_composer_attachment(item) && item["id"] == attachment)
                .ok_or_else(|| io::Error::other("retired composer attachment"))?;
            context.remove(at);
            Ok(())
        })
    }

    fn update_composer_attachments(
        &self,
        draft: DraftId,
        apply: impl FnOnce(&mut Vec<Value>) -> Result<(), AttachmentError>,
    ) -> Result<(), AttachmentError> {
        let mut state = self.inner.state();
        let transaction = state
            .database
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        let mut saved = read_draft(&transaction, draft)?.ok_or(AttachmentError::MissingDraft)?;
        apply(&mut saved.context)?;
        let revision = saved
            .revision
            .next()
            .ok_or_else(|| io::Error::other("draft revision exhausted"))?;
        save_in_transaction(
            &transaction,
            draft,
            Some(saved.revision),
            revision,
            None,
            Some(&saved.context),
        )?;
        let removed = replace_references(
            &transaction,
            &self.inner.blobs,
            draft.0.as_bytes(),
            saved
                .context
                .iter()
                .filter(|item| item["kind"] == "image")
                .filter_map(|item| {
                    item["path"]
                        .as_str()
                        .and_then(|path| self.composer_blob_id(Path::new(path)))
                }),
        )?;
        transaction.commit()?;
        state.candidates.extend(removed);
        Ok(())
    }

    pub fn lease_composer_image(
        &self,
        draft: DraftId,
        id: &str,
    ) -> Result<BlobLease, AttachmentError> {
        let mut state = self.inner.state();
        let saved = read_draft(&state.database, draft)?.ok_or(AttachmentError::MissingDraft)?;
        let blob = saved
            .context
            .iter()
            .find(|item| item["id"] == id && item["kind"] == "image")
            .and_then(|item| item["path"].as_str())
            .and_then(|path| self.composer_blob_id(Path::new(path)))
            .ok_or_else(|| io::Error::other("retired composer image"))?;
        verify_saved_file(&state.database, &self.inner.blobs, blob)?;
        Ok(self.retain(&mut state, blob))
    }

    pub fn lease_sent_image(
        &self,
        checkout: &CheckoutIdentity,
        thread: &str,
        turn: &str,
        path: &Path,
    ) -> Result<BlobLease, AttachmentError> {
        let blob = self
            .composer_blob_id(path)
            .ok_or_else(|| io::Error::other("invalid sent attachment"))?;
        let mut state = self.inner.state();
        let has_owner: bool = state.database.query_row(
            "SELECT EXISTS (SELECT 1 FROM sent_submission_attachments AS a
             JOIN submissions AS s ON s.id = a.submission_id JOIN submission_outcomes AS o ON o.id = s.id
             WHERE s.checkout_key = ?1 AND s.thread_id = ?2 AND o.turn_id = ?3 AND a.blob_id = ?4)",
            rusqlite::params![checkout.storage_key(), thread, turn, blob.0.as_slice()], |row| row.get(0),
        )?;
        if !has_owner {
            return Err(AttachmentError::Missing(blob));
        }
        verify_saved_file(&state.database, &self.inner.blobs, blob)?;
        Ok(self.retain(&mut state, blob))
    }

    fn composer_blob_id(&self, path: &Path) -> Option<BlobId> {
        if path.parent()? != self.inner.blobs {
            return None;
        }
        let mut bytes = [0; 32];
        hex::decode_to_slice(path.file_name()?.to_str()?, &mut bytes).ok()?;
        let id = BlobId(bytes);
        (id.path(&self.inner.blobs) == path).then_some(id)
    }
}

fn image_context<'a>(context: &'a [Value], id: &str) -> Option<&'a Value> {
    context
        .iter()
        .find(|item| item["kind"] == "image" && item["id"] == id)
}

pub fn image_annotations(context: &Value) -> Vec<ImageAnnotation> {
    context["imageAnnotations"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|value| serde_json::from_value::<ImageAnnotation>(value.clone()).ok())
        .filter(ImageAnnotation::is_valid)
        .collect()
}

impl BlobLease {
    pub fn read_preview(&self, limit: u64) -> Result<Vec<u8>, AttachmentError> {
        let root = CheckoutIdentity::capture(&self.store.blobs).map_err(io::Error::other)?;
        let name = hex::encode(self.id.0);
        let read = read_local_file(&root, Path::new(&name), limit).map_err(io::Error::other)?;
        if read.revision.digest != name {
            return Err(AttachmentError::InvalidFile(self.id));
        }
        Ok(read.bytes)
    }
}

fn is_composer_attachment(item: &Value) -> bool {
    matches!(
        item["kind"].as_str(),
        Some("image" | "fileReference" | "textExcerpt" | "skill" | "projectContext")
    )
}
