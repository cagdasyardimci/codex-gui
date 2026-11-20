use codex_gui_core::{
    ipc::{ProjectContextChange, ProjectContextRequest, ResponseBookmarkRequest},
    storage::{
        attachments::AttachmentError,
        project_context::{
            ConversationBookmark, ConversationBookmarkKind, ProjectContext, ProjectContextError,
            ProjectContextItem, ProjectSkillSelection, SavedPrompt, put_project_entry,
            remove_project_entry,
        },
    },
};

use super::*;

const MAX_TITLE_BYTES: usize = 1024;
const MAX_CONTENT_BYTES: usize = 64 * 1024;

impl Navigation {
    pub(super) fn project_context(&self) -> Result<ProjectContext, Failure> {
        match &self.selection {
            Some(selection) => Ok(self
                .store
                .project_context_view(&selection.checkout)?
                .context),
            None => Ok(ProjectContext::default()),
        }
    }

    pub(super) fn project_context_changed(&mut self, context: &ProjectContext) {
        self.view.project_has_input = context.has_submission_context();
        self.view.bookmarked_responses = context
            .bookmarks
            .iter()
            .filter(|bookmark| {
                self.view.selected_chat.as_ref() == Some(&bookmark.thread_id)
                    && bookmark.file_path.is_none()
            })
            .filter_map(|bookmark| {
                bookmark
                    .item_id
                    .as_deref()
                    .map(|item| transcript_id(&bookmark.turn_id, item))
            })
            .collect();
    }

    pub(super) fn set_response_bookmark(
        &mut self,
        request: ResponseBookmarkRequest,
    ) -> Result<(), IpcError> {
        let row = request.row;
        let (turn, label) = self.finished_response(&row)?;
        let item = row
            .item_id
            .strip_prefix(&format!("{turn}/"))
            .filter(|id| !id.is_empty())
            .ok_or(IpcError::StaleSelection)?;
        let checkout = &self
            .selection
            .as_ref()
            .ok_or(IpcError::RetiredWorkspace)?
            .checkout;
        let _write = self
            .owners
            .acquire_write(checkout)
            .map_err(|error| report(error.into()))?;
        let view = self
            .store
            .project_context_view(checkout)
            .map_err(project_error)?;
        let current = view.context.bookmarks.iter().find(|bookmark| {
            bookmark.thread_id == row.chat_id
                && bookmark.turn_id == turn
                && bookmark.item_id.as_deref() == Some(item)
                && bookmark.file_path.is_none()
        });
        if current.is_some() == request.bookmarked {
            return Ok(());
        }
        let existing = current.map(|bookmark| bookmark.id.clone());
        self.store
            .edit_project_context(checkout, view.revision, |context| {
                if let Some(id) = existing {
                    remove_project_entry(&mut context.bookmarks, &id, |bookmark| &bookmark.id)?;
                } else {
                    context.bookmarks.push(ConversationBookmark {
                        id: Uuid::new_v4().to_string(),
                        thread_id: row.chat_id,
                        turn_id: turn,
                        item_id: Some(item.to_owned()),
                        kind: ConversationBookmarkKind::Answer,
                        label,
                        file_path: None,
                    });
                }
                Ok(())
            })
            .map_err(project_error)?;
        let context = self.project_context().map_err(report)?;
        self.project_context_changed(&context);
        self.publish_navigation();
        Ok(())
    }

    pub(super) fn finished_response(
        &self,
        row: &codex_gui_core::ipc::TranscriptRowRequest,
    ) -> Result<(String, String), IpcError> {
        self.require(row.workspace_id)?;
        let (turn, response) = self
            .model
            .lock()
            .expect("workspace state lock poisoned")
            .projection
            .finished_response(row)?;
        if self.view.turn_rail.as_ref().is_none_or(|rail| {
            !rail
                .turns
                .iter()
                .any(|entry| entry.id == turn && entry.finished)
        }) {
            return Err(IpcError::StaleSelection);
        }
        Ok((turn, response))
    }

    pub(super) async fn edit_project_context(
        &mut self,
        request: ProjectContextRequest,
    ) -> Result<(), IpcError> {
        let ProjectContextRequest {
            scope,
            revision,
            change,
        } = request;
        self.require(scope.workspace_id)?;
        if self.view.selected_chat != scope.chat_id
            || self.view.draft.as_ref().map(|draft| &draft.id) != Some(&scope.draft_id)
        {
            return Err(IpcError::StaleSelection);
        }
        let checkout = &self
            .selection
            .as_ref()
            .ok_or(IpcError::RetiredWorkspace)?
            .checkout;
        match change {
            ProjectContextChange::InsertPrompt(input) => {
                if self
                    .view
                    .queue
                    .as_ref()
                    .and_then(|queue| queue.editing.as_ref())
                    .is_some()
                {
                    return Err(IpcError::StaleSelection);
                }
                let _write = self
                    .owners
                    .acquire_write(checkout)
                    .map_err(|error| report(error.into()))?;
                let view = self
                    .store
                    .project_context_view(checkout)
                    .map_err(project_error)?;
                let prompt = view
                    .context
                    .saved_prompts
                    .iter()
                    .find(|prompt| view.revision == revision && prompt.id == input.id)
                    .ok_or(IpcError::StaleSelection)?;
                let draft = self.editor_id().ok_or(IpcError::StaleSelection)?;
                let text = if input.expected_text.trim().is_empty() {
                    prompt.instructions.clone()
                } else {
                    format!("{}\n\n{}", input.expected_text, prompt.instructions)
                };
                self.store
                    .replace_editor_text(draft, Some(&input.expected_text), text)
                    .map_err(|error| match error {
                        AttachmentError::StaleComposerText => IpcError::StaleSelection,
                        error => report(error.into()),
                    })?;
                self.set_editor(draft).map_err(report)?;
                self.publish_navigation();
            }
            ProjectContextChange::OpenBookmark(id) => {
                let view = self
                    .store
                    .project_context_view(checkout)
                    .map_err(project_error)?;
                let bookmark = view
                    .context
                    .bookmarks
                    .into_iter()
                    .find(|bookmark| view.revision == revision && bookmark.id == id)
                    .ok_or(IpcError::StaleSelection)?;
                let thread = ThreadId(bookmark.thread_id);
                if self.view.selected_chat.as_deref() != Some(&thread.0) {
                    let backend = self.backend.as_ref().ok_or(IpcError::StaleSelection)?;
                    CodexBrowser::new(backend.connection.client())
                        .thread_summary(&thread, RPC_TIMEOUT)
                        .await
                        .map_err(|error| report(error.into()))?;
                    self.focus(Some(thread)).await.map_err(report)?;
                }
                let item = bookmark
                    .item_id
                    .map(|id| transcript_id(&bookmark.turn_id, &id));
                self.jump_to_history_item(scope.workspace_id, bookmark.turn_id, item)?;
            }
            change => {
                let skill = match &change {
                    ProjectContextChange::SetSkill(Some(id)) => {
                        let client = self
                            .backend
                            .as_ref()
                            .map(|backend| backend.connection.client());
                        let model = self.model.lock().expect("workspace state lock poisoned");
                        Some(
                            model
                                .composer_catalog
                                .as_ref()
                                .and_then(|catalog| {
                                    catalog.skill(
                                        &scope,
                                        client.as_ref().map(AppServerClient::identity),
                                        *id,
                                    )
                                })
                                .ok_or(IpcError::StaleSelection)?,
                        )
                    }
                    _ => None,
                };
                if let ProjectContextChange::SetModel(Some(preference)) = &change {
                    self.validate_project_model(preference)?;
                }
                let changes_model = matches!(change, ProjectContextChange::SetModel(_));
                let _write = self
                    .owners
                    .acquire_write(checkout)
                    .map_err(|error| report(error.into()))?;
                self.store
                    .edit_project_context(checkout, revision, |context| {
                        apply_edit(context, change, skill)
                    })
                    .map_err(project_error)?;
                let context = self.project_context().map_err(report)?;
                self.project_context_changed(&context);
                if changes_model {
                    self.reconcile_composer_models();
                    if let Some(settings) = self.view.composer_settings.as_mut() {
                        settings.revision = Uuid::new_v4();
                    }
                }
                self.publish_navigation();
            }
        }
        Ok(())
    }
}

fn project_error(error: ProjectContextError) -> IpcError {
    match error {
        ProjectContextError::StaleRevision | ProjectContextError::InvalidEdit => {
            IpcError::StaleSelection
        }
        error => report(error.into()),
    }
}

fn apply_edit(
    context: &mut ProjectContext,
    change: ProjectContextChange,
    skill: Option<ProjectSkillSelection>,
) -> Result<(), ProjectContextError> {
    match change {
        ProjectContextChange::SaveItem(edit) => {
            let title = checked_title(edit.title)?;
            if edit.body.len() > MAX_CONTENT_BYTES
                || edit
                    .reference_path
                    .as_ref()
                    .is_some_and(|path| path.len() > MAX_TITLE_BYTES)
            {
                return Err(ProjectContextError::InvalidEdit);
            }
            put_project_entry(
                &mut context.items,
                edit.id,
                |item| &item.id,
                |id| ProjectContextItem {
                    id,
                    kind: edit.kind,
                    title,
                    body: edit.body,
                    reference_path: edit.reference_path,
                    is_included: edit.is_included,
                },
            )?;
        }
        ProjectContextChange::RemoveItem(id) => {
            remove_project_entry(&mut context.items, &id, |item| &item.id)?
        }
        ProjectContextChange::IncludeItem(edit) => {
            let item = context
                .items
                .iter_mut()
                .find(|item| item.id == edit.id)
                .ok_or(ProjectContextError::StaleRevision)?;
            item.is_included = edit.is_included;
        }
        ProjectContextChange::SavePrompt(edit) => {
            let title = checked_title(edit.title)?;
            if edit.instructions.trim().is_empty() || edit.instructions.len() > MAX_CONTENT_BYTES {
                return Err(ProjectContextError::InvalidEdit);
            }
            put_project_entry(
                &mut context.saved_prompts,
                edit.id,
                |prompt| &prompt.id,
                |id| SavedPrompt {
                    id,
                    title,
                    instructions: edit.instructions,
                },
            )?;
        }
        ProjectContextChange::RemovePrompt(id) => {
            remove_project_entry(&mut context.saved_prompts, &id, |prompt| &prompt.id)?;
            if context.selected_prompt_id.as_ref() == Some(&id) {
                context.selected_prompt_id = None;
            }
        }
        ProjectContextChange::SetSkill(_) => context.selected_skill = skill,
        ProjectContextChange::SetModel(preference) => context.model_preference = preference,
        ProjectContextChange::RemoveBookmark(id) => {
            remove_project_entry(&mut context.bookmarks, &id, |bookmark| &bookmark.id)?
        }
        _ => return Err(ProjectContextError::InvalidEdit),
    }
    Ok(())
}

fn checked_title(title: String) -> Result<String, ProjectContextError> {
    let title = title.trim();
    if title.is_empty() || title.len() > MAX_TITLE_BYTES {
        return Err(ProjectContextError::InvalidEdit);
    }
    Ok(title.into())
}
