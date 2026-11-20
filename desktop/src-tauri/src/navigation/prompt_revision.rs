use std::{borrow::Cow, path::PathBuf, sync::Arc};

use base64::{Engine, engine::general_purpose::STANDARD};
use codex_gui_core::{
    codex::{
        BrowseError, ChatRead, ChatSummary, CliQualification, ForkBoundary, ThreadActivity,
        ThreadSummary, TurnItemRead,
    },
    files::{CheckoutFiles, read_local_file},
    identity::TurnId,
    ipc::{
        ComposerSelection, ReviseSentPrompt, SendRequest, SentPromptEdit, TranscriptRowRequest,
        present_question_reply,
    },
    storage::attachments::{
        composer::MAX_COMPOSER_ATTACHMENTS, fork_revisions::RecordedAttachment,
    },
    storage::drafts::DraftRevision,
};
use serde_json::Value;

use super::*;
use crate::transcript_ipc::{MAX_INLINE_BYTES, raster_type, relative_image};

const MAX_PROMPT_BYTES: usize = 1024 * 1024;

pub(super) struct PromptRevisions {
    editor: Option<PromptEditor>,
    pub(super) sender: mpsc::Sender<Box<ForkCompletion>>,
    pub(super) completed: mpsc::Receiver<Box<ForkCompletion>>,
    pub(super) active_forks: std::collections::HashSet<Uuid>,
}

impl Default for PromptRevisions {
    fn default() -> Self {
        let (sender, completed) = mpsc::channel(4);
        Self {
            editor: None,
            sender,
            completed,
            active_forks: Default::default(),
        }
    }
}

impl PromptRevisions {
    pub(super) fn retire_editor(&mut self) {
        self.editor = None;
    }

    pub(super) fn cancel(&mut self, ticket: Uuid) {
        if self
            .editor
            .as_ref()
            .is_some_and(|editor| editor.ticket == ticket)
        {
            self.retire_editor();
        }
    }
}

struct PromptEditor {
    ticket: Uuid,
    row: TranscriptRowRequest,
    rail: Uuid,
    thread: ThreadId,
    turn: TurnId,
    client: AppServerClient,
    checkout: CheckoutIdentity,
    summary: Arc<ChatRead<ChatSummary>>,
    text: String,
    attachments: Vec<RecordedAttachment>,
}

pub(super) enum ForkCompletion {
    Revision(RevisionForkCompletion),
    Conversation(super::conversation_fork::ConversationForkCompletion),
}

pub(super) struct RevisionForkCompletion {
    row: TranscriptRowRequest,
    rail: Uuid,
    connection: ConnectionIdentity,
    checkout: CheckoutIdentity,
    turn: TurnId,
    draft: DraftId,
    source_draft: (DraftId, DraftRevision),
    choice: Option<ComposerSelection>,
    result: Result<ThreadSummary, BrowseError>,
    _lease: RuntimeUse,
}

impl NavigationHandle {
    pub(crate) async fn open_sent_prompt(
        &self,
        request: TranscriptRowRequest,
    ) -> Result<SentPromptEdit, IpcError> {
        let (reply, result) = oneshot::channel();
        self.request(Action::OpenSentPrompt(request, reply)).await?;
        result.await.map_err(|_| IpcError::ProjectUnavailable)
    }
}

impl Navigation {
    pub(super) fn sync_prompt_revision(&mut self) {
        self.view.literal_fork_revision = self
            .editor_id()
            .is_some_and(|draft| self.is_literal_revision(draft).unwrap_or(false));
    }

    pub(super) fn is_literal_revision(&self, draft: DraftId) -> Result<bool, Failure> {
        match self
            .selection
            .as_ref()
            .zip(self.view.selected_chat.as_deref())
        {
            Some((selection, chat)) => {
                Ok(self
                    .store
                    .is_literal_fork_revision(&selection.checkout, chat, draft)?)
            }
            None => Ok(false),
        }
    }

    pub(super) fn prompt_fork_scope(
        &self,
    ) -> Result<(&Selection, &Backend, &codex_gui_core::ipc::TurnRailView), IpcError> {
        let selection = self.selection.as_ref().ok_or(IpcError::RetiredWorkspace)?;
        let backend = self.backend.as_ref().ok_or(IpcError::StaleSelection)?;
        let rail = self
            .view
            .turn_rail
            .as_ref()
            .ok_or(IpcError::StaleSelection)?;
        if self.quit.is_some()
            || self.view.actions.stop.is_some()
            || self.view.actions.recover
            || self.view.slash_commands.recover_plan
            || self
                .view
                .queue
                .as_ref()
                .is_some_and(|queue| queue.editing.is_some())
            || !self.view.account.permits_turns
            || backend.connection.compatibility().qualification() == CliQualification::Unverified
        {
            return Err(IpcError::StaleSelection);
        }
        Ok((selection, backend, rail))
    }

    pub(super) async fn inspect_sent_prompt(
        &mut self,
        request: TranscriptRowRequest,
    ) -> Result<SentPromptEdit, IpcError> {
        self.require(request.workspace_id)?;
        self.sync_actions();
        if !self.view.can_edit_sent_prompt {
            return Err(IpcError::StaleSelection);
        }
        let turn = self
            .model
            .lock()
            .expect("workspace state lock poisoned")
            .projection
            .sent_prompt_turn(&request)?;
        let (selection, backend, rail) = self.prompt_fork_scope()?;
        let closed = rail
            .turns
            .iter()
            .any(|entry| entry.id == turn && entry.finished);
        let thread = selection
            .thread
            .as_ref()
            .filter(|thread| thread.0 == request.chat_id)
            .cloned()
            .filter(|_| closed)
            .ok_or(IpcError::StaleSelection)?;
        let turn = TurnId(turn);
        let rail = rail.id;
        let checkout = selection.checkout.clone();
        let client = backend.connection.client();
        let browser = CodexBrowser::new(client.clone());
        let summary = browser
            .thread_summary(&thread, RPC_TIMEOUT)
            .await
            .map_err(|error| report(error.into()))?;
        let selected = summary
            .for_selection(client.identity(), &thread)
            .map_err(|error| report(error.into()))?;
        if !matches!(
            selected.activity,
            ThreadActivity::Idle | ThreadActivity::NotLoaded
        ) {
            return Err(IpcError::StaleSelection);
        }
        let items = browser
            .turn_items(&summary, &turn, TurnItemRead::Complete, RPC_TIMEOUT)
            .await
            .map_err(|error| report(error.into()))?;
        let items = items
            .for_selection(client.identity(), &thread)
            .map_err(|error| report(error.into()))?;
        let user = items
            .items
            .iter()
            .find(|value| value["type"] == "userMessage")
            .and_then(|value| value["id"].as_str().map(|id| (id, value)))
            .filter(|(id, _)| items.id == turn && transcript_id(&turn.0, id) == request.item_id)
            .and_then(|(_, item)| {
                recorded_prompt(item).map(|prompt| (prompt.text.to_owned(), item.clone()))
            })
            .ok_or(IpcError::StaleSelection)?;
        let (text, raw) = user;
        let store = self.store.clone();
        let source = checkout.clone();
        let thread_id = thread.clone();
        let turn_id = turn.clone();
        let attachments = tauri::async_runtime::spawn_blocking(move || {
            let prompt =
                recorded_prompt(&raw).ok_or("the recorded prompt is no longer available")?;
            capture_attachments(&store, &source, &thread_id, &turn_id, &prompt.attachments)
        })
        .await
        .map_err(|error| report(error.into()))?
        .map_err(report)?;
        let ticket = Uuid::new_v4();
        let labels = attachments
            .iter()
            .map(|entry| match entry {
                RecordedAttachment::Image { title, .. } => title.clone(),
                RecordedAttachment::Mention { name, .. } => name.clone(),
            })
            .collect();
        self.prompt_revisions.editor = Some(PromptEditor {
            ticket,
            row: request,
            rail,
            thread,
            turn,
            client,
            checkout,
            summary: Arc::new(summary),
            text: text.clone(),
            attachments,
        });
        Ok(SentPromptEdit {
            ticket,
            text,
            attachments: labels,
        })
    }

    pub(super) fn revise_sent_prompt(
        &mut self,
        revision: ReviseSentPrompt,
    ) -> Result<(), IpcError> {
        let editor = self
            .prompt_revisions
            .editor
            .as_ref()
            .filter(|editor| editor.ticket == revision.ticket)
            .ok_or(IpcError::StaleSelection)?;
        self.require(editor.row.workspace_id)?;
        let (selection, backend, rail) = self.prompt_fork_scope()?;
        if selection.checkout != editor.checkout
            || selection.thread.as_ref() != Some(&editor.thread)
            || backend.connection.client().identity() != editor.client.identity()
            || rail.id != editor.rail
            || revision.text == editor.text
            || revision.text.len() > MAX_PROMPT_BYTES
            || revision.text.trim().is_empty() && editor.attachments.is_empty()
        {
            return Err(IpcError::StaleSelection);
        }
        self.model
            .lock()
            .expect("workspace state lock poisoned")
            .projection
            .sent_prompt_turn(&editor.row)?;
        let lease = self
            .owners
            .acquire(editor.client.identity())
            .map_err(|error| report(error.into()))?;
        let source = self.editor_id().ok_or(IpcError::StaleSelection)?;
        let source_draft = (
            source,
            self.store
                .read_editor_draft(source)
                .map_err(|error| report(error.into()))?
                .revision,
        );
        let draft = self
            .store
            .stage_fork_revision(
                &editor.checkout,
                &editor.thread,
                &editor.turn,
                &revision.text,
                &editor.attachments,
            )
            .map_err(|error| report(error.into()))?;
        let editor = self
            .prompt_revisions
            .editor
            .take()
            .expect("captured prompt");
        let choice = self
            .view
            .composer_settings
            .as_ref()
            .map(|view| view.selection.clone());
        let complete = self.prompt_revisions.sender.clone();
        tauri::async_runtime::spawn(async move {
            let browser = CodexBrowser::new(editor.client.clone());
            let result = browser
                .fork_chat(
                    &editor.summary,
                    &ForkBoundary::Before(editor.turn.clone()),
                    RPC_TIMEOUT,
                )
                .await;
            let _ = complete
                .send(Box::new(ForkCompletion::Revision(RevisionForkCompletion {
                    row: editor.row,
                    rail: editor.rail,
                    connection: editor.client.identity().clone(),
                    checkout: editor.checkout,
                    turn: editor.turn,
                    draft,
                    source_draft,
                    choice,
                    result,
                    _lease: lease,
                })))
                .await;
        });
        self.sync_actions();
        Ok(())
    }

    pub(super) async fn complete_prompt_fork(
        &mut self,
        completion: ForkCompletion,
    ) -> Result<(), Failure> {
        match completion {
            ForkCompletion::Revision(revision) => self.complete_revision_fork(revision).await,
            ForkCompletion::Conversation(fork) => self.complete_conversation_fork(fork).await,
        }
    }

    async fn complete_revision_fork(
        &mut self,
        completion: RevisionForkCompletion,
    ) -> Result<(), Failure> {
        let RevisionForkCompletion {
            row,
            rail,
            connection,
            checkout,
            turn,
            draft,
            source_draft,
            choice,
            result,
            _lease,
        } = completion;
        self.sync_actions();
        let fork = result?;
        let bound = self.store.bind_fork_revision(&checkout, draft, &fork.id)?;
        if bound && let Some(choice) = choice {
            self.store
                .save_composer_selection(&checkout, Some(&fork.id.0), &choice)?;
        }
        let Some(selection) = self
            .selection
            .as_ref()
            .filter(|selection| selection.checkout == checkout)
        else {
            return Ok(());
        };
        let still_selected = bound
            && selection.id == row.workspace_id
            && selection
                .thread
                .as_ref()
                .is_some_and(|thread| thread.0 == row.chat_id)
            && self
                .view
                .turn_rail
                .as_ref()
                .is_some_and(|view| view.id == rail)
            && self
                .backend
                .as_ref()
                .is_some_and(|backend| backend.connection.client().identity() == &connection)
            && self.quit.is_none()
            && self.view.actions.stop.is_none()
            && self.editor_id() == Some(source_draft.0)
            && self
                .store
                .read_editor_draft(source_draft.0)
                .is_ok_and(|saved| saved.revision == source_draft.1);
        let thread = self.remember_fork(fork);
        self.sync_actions();
        if !still_selected {
            return Ok(());
        }
        self.focus(Some(thread.clone())).await?;
        if self.view.retryable
            || !self.view.actions.send
            || self.editor_id() != Some(draft)
            || self
                .view
                .turn_rail
                .as_ref()
                .is_none_or(|rail| rail.turns.iter().any(|entry| entry.id == turn.0))
        {
            return Ok(());
        }
        let saved = self.store.read_editor_draft(draft)?;
        let request = SendRequest {
            workspace_id: row.workspace_id,
            chat_id: Some(thread.0),
            draft_id: draft.0.to_string(),
            text: saved.text,
            attachment_ids: super::composer_attachments::views(&saved.context)
                .into_iter()
                .map(|item| item.id)
                .collect(),
            composer_revision: self
                .view
                .composer_settings
                .as_ref()
                .map(|view| view.revision),
            expected_turn: None,
        };
        self.send_visible(request)
            .await
            .map_err(|error| format!("could not submit the edited prompt: {error:?}").into())
    }
}

struct RecordedPrompt<'a> {
    text: &'a str,
    attachments: Vec<RecordedInput<'a>>,
}

enum RecordedInput<'a> {
    Mention { name: &'a str, path: &'a str },
    LocalImage(&'a str),
    InlineImage(&'a str),
}

pub(super) fn is_editable_prompt(item: &Value) -> bool {
    recorded_prompt(item).is_some()
}

fn recorded_prompt(item: &Value) -> Option<RecordedPrompt<'_>> {
    let items = item["content"].as_array()?;
    let mut text = "";
    let mut attachments = Vec::new();
    for (index, input) in items.iter().enumerate() {
        match input["type"].as_str()? {
            "text" if index == 0 => {
                if ["text_elements", "textElements"].iter().any(|key| {
                    input[*key]
                        .as_array()
                        .is_some_and(|elements| !elements.is_empty())
                }) {
                    return None;
                }
                text = input["text"].as_str()?;
            }
            "mention" => attachments.push(RecordedInput::Mention {
                name: input["name"].as_str().filter(|name| !name.is_empty())?,
                path: input["path"]
                    .as_str()
                    .filter(|path| !path.is_empty() && !path.contains('\0'))?,
            }),
            "localImage" => attachments.push(RecordedInput::LocalImage(
                input["path"]
                    .as_str()
                    .filter(|path| !path.is_empty() && !path.contains('\0'))?,
            )),
            "image" => attachments.push(RecordedInput::InlineImage(
                input["url"]
                    .as_str()
                    .or_else(|| input["image_url"].as_str())
                    .filter(|url| image_data(url).is_some())?,
            )),
            _ => return None,
        }
    }
    if attachments.len() > MAX_COMPOSER_ATTACHMENTS
        || text.trim().is_empty() && attachments.is_empty()
        || text.len() > MAX_PROMPT_BYTES
        || matches!(present_question_reply(text), Cow::Owned(_))
    {
        return None;
    }
    Some(RecordedPrompt { text, attachments })
}

fn image_data(source: &str) -> Option<&str> {
    let (media, payload) = source.strip_prefix("data:")?.split_once(";base64,")?;
    (matches!(
        media,
        "image/png" | "image/jpeg" | "image/gif" | "image/webp"
    ) && payload.len() <= (MAX_INLINE_BYTES as usize).div_ceil(3) * 4)
        .then_some(payload)
}

fn capture_attachments(
    store: &AttachmentStore,
    checkout: &CheckoutIdentity,
    thread: &ThreadId,
    turn: &TurnId,
    inputs: &[RecordedInput<'_>],
) -> Result<Vec<RecordedAttachment>, Failure> {
    inputs
        .iter()
        .map(|input| match input {
            RecordedInput::Mention { name, path } => {
                let relative = relative_image(checkout, Path::new(path))
                    .ok_or("recorded mention is outside the captured checkout")?;
                CheckoutFiles::new(checkout.clone()).issue(Path::new(&relative))?;
                Ok(RecordedAttachment::Mention {
                    name: (*name).into(),
                    relative,
                })
            }
            RecordedInput::LocalImage(path) => {
                let resolved = if path.starts_with("file:") {
                    tauri::Url::parse(path)?
                        .to_file_path()
                        .map_err(|_| "invalid recorded local image URL")?
                } else {
                    PathBuf::from(path)
                };
                let title = resolved
                    .file_name()
                    .and_then(|name| name.to_str())
                    .unwrap_or("Image");
                if let Some(relative) = relative_image(checkout, &resolved) {
                    let bytes =
                        read_local_file(checkout, Path::new(&relative), MAX_INLINE_BYTES)?.bytes;
                    Ok(RecordedAttachment::Image {
                        title: title.into(),
                        lease: stage_image(store, &bytes)?,
                    })
                } else {
                    let lease = store.lease_sent_image(checkout, &thread.0, &turn.0, &resolved)?;
                    let bytes = lease.read_preview(MAX_INLINE_BYTES)?;
                    if raster_type(&bytes).is_none() {
                        return Err("recorded image has unsupported bytes".into());
                    }
                    Ok(RecordedAttachment::Image {
                        title: "Image".into(),
                        lease,
                    })
                }
            }
            RecordedInput::InlineImage(url) => {
                let bytes =
                    STANDARD.decode(image_data(url).ok_or("recorded image data is invalid")?)?;
                Ok(RecordedAttachment::Image {
                    title: "Image".into(),
                    lease: stage_image(store, &bytes)?,
                })
            }
        })
        .collect()
}

fn stage_image(
    store: &AttachmentStore,
    bytes: &[u8],
) -> Result<codex_gui_core::storage::attachments::BlobLease, Failure> {
    if bytes.len() > MAX_INLINE_BYTES as usize || raster_type(bytes).is_none() {
        return Err("recorded image has unsupported bytes".into());
    }
    Ok(store.stage(bytes)?)
}
