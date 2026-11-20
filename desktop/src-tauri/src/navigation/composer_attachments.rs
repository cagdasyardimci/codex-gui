use std::path::Path;

use codex_gui_core::{
    files::CheckoutFiles,
    ipc::{
        DraftAttachmentRequest, DraftAttachmentScope, DraftAttachmentView, SaveImageAnnotations,
    },
    storage::attachments::{
        AttachmentError, BlobLease,
        composer::{ComposerAttachment, image_annotations},
    },
    storage::project_context::ProjectContext,
};
use serde_json::{Value, json};

use super::*;

pub(crate) enum Mutation {
    Append(DraftAttachmentScope, Vec<ComposerAttachment>),
    Remove(DraftAttachmentRequest),
    Annotate(SaveImageAnnotations),
    Context {
        scope: DraftAttachmentScope,
        expected: String,
        text: String,
        item: Value,
    },
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

    pub(crate) async fn composer_context_client(
        &self,
        scope: DraftAttachmentScope,
    ) -> Result<Option<AppServerClient>, IpcError> {
        let (reply, result) = oneshot::channel();
        self.request(Action::ComposerContextClient(scope, reply))
            .await?;
        result.await.map_err(|_| IpcError::ProjectUnavailable)
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
            Mutation::Annotate(request) => &request.attachment.scope,
            Mutation::Context { scope, .. } => scope,
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
        if matches!(&mutation, Mutation::Context { .. })
            && (self.view.selected_chat != scope.chat_id
                || self.view.draft.as_ref().map(|draft| &draft.id) != Some(&scope.draft_id))
        {
            return Err(IpcError::StaleSelection);
        }
        let _write = self
            .owners
            .acquire_write(&selection.checkout)
            .map_err(|error| report(error.into()))?;
        match mutation {
            Mutation::Append(_, items) => self.store.append_composer_attachments(draft, &items),
            Mutation::Remove(request) => self
                .store
                .remove_composer_attachment(draft, &request.attachment_id),
            Mutation::Annotate(request) => self.store.save_composer_image_annotations(
                draft,
                &request.attachment.attachment_id,
                &request.digest,
                &request.original,
                &request.annotations,
                crate::transcript_ipc::MAX_INLINE_BYTES,
            ),
            Mutation::Context {
                expected,
                text,
                item,
                ..
            } => self
                .store
                .add_composer_context(draft, &expected, &text, item),
        }
        .map_err(|error| match error {
            AttachmentError::StaleAnnotations | AttachmentError::StaleComposerText => {
                IpcError::StaleSelection
            }
            error => report(error.into()),
        })?;
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
            visible.text = saved.text;
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
        project: ProjectContext,
        default_skill: Option<Value>,
    ) -> Result<(String, Vec<Value>, Vec<BlobLease>), Failure> {
        let selection = self
            .selection
            .as_ref()
            .ok_or("no checkout owns this draft")?;
        let mut attachments = Vec::new();
        let mut context = Vec::new();
        let mut comments = Vec::new();
        let mut explicit_items = std::collections::HashSet::new();
        for item in source {
            match item["kind"].as_str() {
                Some("image") => {
                    let id = item["id"]
                        .as_str()
                        .ok_or("the image has no draft identity")?;
                    attachments.push(self.store.lease_composer_image(draft, id)?);
                    let annotations = image_annotations(&item);
                    if !annotations.is_empty() {
                        let mut group = format!("Image {}:", attachments.len());
                        for (index, annotation) in annotations.into_iter().enumerate() {
                            use std::fmt::Write;
                            write!(
                                group,
                                "\n{}. (x: {}%, y: {}%) {}",
                                index + 1,
                                percentage(annotation.x),
                                percentage(annotation.y),
                                annotation.text
                            )?;
                        }
                        comments.push(group);
                    }
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
                Some("textExcerpt") => {
                    let path = item["path"].as_str().ok_or("the excerpt has no path")?;
                    let excerpt = item["excerpt"]
                        .as_str()
                        .ok_or("the excerpt has no source text")?;
                    let first = item["firstLine"].as_u64().unwrap_or(1);
                    let last = item["lastLine"].as_u64().unwrap_or_else(|| {
                        first.saturating_add(excerpt.lines().count().saturating_sub(1) as u64)
                    });
                    let mut description =
                        format!("Selected code from {path}, lines {first}–{last}:");
                    for (offset, line) in excerpt.lines().enumerate() {
                        use std::fmt::Write;
                        write!(
                            description,
                            "\n{}: {line}",
                            first.saturating_add(offset as u64)
                        )?;
                    }
                    append_text(&mut text, &description);
                }
                Some("skill") => {
                    let path = item["path"].as_str().ok_or("the skill has no path")?;
                    let name = item["title"].as_str().ok_or("the skill has no name")?;
                    context.push(json!({"type": "skill", "name": name, "path": path}));
                }
                Some("projectContext") => {
                    if let Some(id) = item["projectItemId"].as_str() {
                        explicit_items.insert(id.to_owned());
                    }
                    let body = item["body"]
                        .as_str()
                        .ok_or("the project item has no text")?;
                    let title = item["title"]
                        .as_str()
                        .ok_or("the project item has no title")?;
                    append_text(&mut text, &format!("{title}\n{body}"));
                }
                _ => context.push(item),
            }
        }
        let project_text = project
            .items
            .iter()
            .filter(|item| item.is_included && !explicit_items.contains(&item.id))
            .map(|item| item.request_text())
            .collect::<Vec<_>>()
            .join("\n");
        if !project_text.is_empty() {
            append_text(
                &mut text,
                &format!("Project context selected for this request:\n{project_text}"),
            );
        }
        if let Some(skill) = default_skill.filter(|skill| !context.contains(skill)) {
            context.push(skill);
        }
        for group in comments {
            append_text(&mut text, &group);
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
                "fileReference" | "textExcerpt" | "skill" | "projectContext" => false,
                _ => return None,
            };
            Some(DraftAttachmentView {
                id: item["id"].as_str()?.into(),
                label: item["title"].as_str()?.into(),
                image,
                annotation_count: image_annotations(item).len(),
            })
        })
        .collect()
}

fn append_text(text: &mut String, part: &str) {
    if !text.is_empty() {
        text.push_str("\n\n");
    }
    text.push_str(part);
}

fn percentage(coordinate: f64) -> String {
    let tenths = (coordinate * 1000.0).round() as u32;
    let whole = tenths / 10;
    let fraction = tenths % 10;
    if fraction == 0 {
        whole.to_string()
    } else {
        format!("{whole}.{fraction}")
    }
}
