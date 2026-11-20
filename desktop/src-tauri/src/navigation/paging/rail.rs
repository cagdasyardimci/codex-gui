use codex_gui_core::{
    checkout::CheckoutIdentity,
    codex::{AppServerClient, TurnActivity, TurnItemRead, TurnItems, TurnStatus},
    ipc::{
        TranscriptItem, TranscriptRole, TurnJump, TurnPreview, TurnRailRequest,
        TurnRailTicketRequest, TurnRailView, TurnReferenceView, present_question_reply,
    },
};
use serde_json::Value;

use super::*;
use crate::navigation::transcript::append_turn_items;

type ReferencePage = ChatRead<Page<TurnActivity, TurnCursor>>;

pub(super) struct ReferenceRead {
    summary: Arc<ChatRead<ChatSummary>>,
    page: ReferencePage,
}

pub(super) enum RailCompletion {
    References {
        cursor: Option<TurnCursor>,
        result: Box<Result<ReferenceRead, BrowseError>>,
    },
    Items {
        mode: TurnItemRead,
        turn: TurnActivity,
        result: Result<ChatRead<TurnItems>, BrowseError>,
    },
}

struct ReadJob {
    ticket: Uuid,
    turn: Option<TurnId>,
    task: JoinHandle<()>,
}

impl Drop for ReadJob {
    fn drop(&mut self) {
        self.task.abort();
    }
}

struct Reference {
    activity: TurnActivity,
    title: Option<String>,
}

pub(super) struct TurnRail {
    id: Uuid,
    references: Vec<Reference>,
    seen: HashSet<TurnId>,
    cursor: Option<(TurnCursor, Uuid)>,
    loading_references: Option<ReadJob>,
    hovering: Option<ReadJob>,
    jumping: Option<ReadJob>,
    preview: Option<TurnPreview>,
    jump: Option<TurnJump>,
}

impl TurnRail {
    pub(super) fn new(history: &[HistoryTurn]) -> Self {
        let mut rail = Self {
            id: Uuid::new_v4(),
            references: Vec::new(),
            seen: HashSet::new(),
            cursor: None,
            loading_references: None,
            hovering: None,
            jumping: None,
            preview: None,
            jump: None,
        };
        rail.include_history(history);
        rail
    }

    pub(super) fn include_history(&mut self, history: &[HistoryTurn]) {
        self.merge(
            history.iter().map(|turn| Reference {
                activity: turn.activity.clone(),
                title: first_prompt(&turn.items).map(|title| excerpt(&title, 72)),
            }),
            false,
        );
    }

    fn merge(&mut self, newest_first: impl Iterator<Item = Reference>, newest_page: bool) {
        let mut before = if newest_page {
            self.references.len()
        } else {
            0
        };
        for reference in newest_first {
            if self.seen.insert(reference.activity.id.clone()) {
                self.references.insert(before, reference);
            } else if let Some(index) = self
                .references
                .iter()
                .position(|old| old.activity.id == reference.activity.id)
            {
                let old = &mut self.references[index];
                if reference.title.is_some() {
                    old.title = reference.title;
                }
                if old.activity.status == TurnStatus::InProgress
                    || reference.activity.status != TurnStatus::InProgress
                {
                    old.activity.status = reference.activity.status;
                }
                before = index;
            }
        }
    }

    pub(super) fn order(&self) -> Vec<String> {
        self.references
            .iter()
            .map(|reference| reference.activity.id.0.clone())
            .collect()
    }

    pub(super) fn scope_id(&self) -> Uuid {
        self.id
    }

    pub(super) fn view(&self) -> TurnRailView {
        TurnRailView {
            id: self.id,
            turns: self
                .references
                .iter()
                .map(|reference| TurnReferenceView {
                    id: reference.activity.id.0.clone(),
                    title: reference.title.clone(),
                })
                .collect(),
            earlier: self.cursor.as_ref().map(|(_, ticket)| *ticket),
            preview: self.preview.clone(),
            jump: self.jump.clone(),
            pending_jump: self.jumping.as_ref().and_then(|job| {
                job.turn.as_ref().map(|turn| TurnJump {
                    ticket: job.ticket,
                    turn_id: turn.0.clone(),
                })
            }),
        }
    }

    fn cancel_preview(&mut self) {
        self.hovering = None;
        self.preview = None;
    }
}

impl Navigation {
    pub(in crate::navigation) fn start_new_chat_rail(&mut self, client: AppServerClient) {
        let Some(selection) = &self.selection else {
            return;
        };
        let Some(thread) = selection.thread.clone() else {
            return;
        };
        self.pages.install(
            selection.id,
            thread,
            client.identity(),
            None,
            &Page {
                data: Vec::new(),
                next_cursor: None,
            },
        );
        self.start_turn_rail(client);
    }

    pub(in crate::navigation) fn start_turn_rail(&mut self, client: AppServerClient) {
        let Some(owner) = self.pages.owner.as_mut() else {
            return;
        };
        owner.read_references(client, None, self.pages.sender.clone());
        self.view.turn_rail = Some(owner.rail.view());
    }

    pub(in crate::navigation) fn load_turn_references(
        &mut self,
        request: TurnRailTicketRequest,
    ) -> Result<(), IpcError> {
        let client = self.rail_client(request.workspace_id)?;
        let sender = self.pages.sender.clone();
        let owner = self.pages.rail_owner(
            request.workspace_id,
            &request.chat_id,
            request.rail_id,
            &client,
        )?;
        let (cursor, _) = owner
            .rail
            .cursor
            .as_ref()
            .filter(|(_, ticket)| *ticket == request.ticket)
            .ok_or(IpcError::StaleSelection)?;
        owner.read_references(client, Some(cursor.clone()), sender);
        Ok(())
    }

    pub(in crate::navigation) fn observe_rail_turn(&mut self, thread: &ThreadId, id: &str) {
        let Some(owner) = self
            .pages
            .owner
            .as_mut()
            .filter(|owner| &owner.thread == thread)
        else {
            return;
        };
        let turn = TurnId(id.to_owned());
        if owner.rail.seen.insert(turn.clone()) {
            owner.rail.references.push(Reference {
                activity: TurnActivity {
                    id: turn,
                    status: TurnStatus::InProgress,
                },
                title: None,
            });
            self.view.turn_rail = Some(owner.rail.view());
            self.publish_navigation();
        }
    }

    pub(in crate::navigation) fn preview_turn(
        &mut self,
        request: TurnRailRequest,
    ) -> Result<(), IpcError> {
        self.read_rail_turn(request, TurnItemRead::Preview)
    }

    pub(in crate::navigation) fn jump_to_turn(
        &mut self,
        request: TurnRailRequest,
    ) -> Result<(), IpcError> {
        self.read_rail_turn(request, TurnItemRead::Complete)
    }

    pub(in crate::navigation) fn cancel_turn_preview(
        &mut self,
        request: TurnRailRequest,
    ) -> Result<(), IpcError> {
        let client = self.rail_client(request.workspace_id)?;
        let owner = self.pages.rail_owner(
            request.workspace_id,
            &request.chat_id,
            request.rail_id,
            &client,
        )?;
        if owner
            .rail
            .hovering
            .as_ref()
            .and_then(|job| job.turn.as_ref())
            .is_some_and(|turn| turn.0 == request.turn_id)
            || owner
                .rail
                .preview
                .as_ref()
                .is_some_and(|preview| preview.turn_id == request.turn_id)
        {
            owner.rail.cancel_preview();
            self.view.turn_rail = Some(owner.rail.view());
            self.publish_navigation();
        }
        Ok(())
    }

    fn read_rail_turn(
        &mut self,
        request: TurnRailRequest,
        mode: TurnItemRead,
    ) -> Result<(), IpcError> {
        let client = self.rail_client(request.workspace_id)?;
        let sender = self.pages.sender.clone();
        let owner = self.pages.rail_owner(
            request.workspace_id,
            &request.chat_id,
            request.rail_id,
            &client,
        )?;
        let turn = owner
            .rail
            .references
            .iter()
            .find(|reference| reference.activity.id.0 == request.turn_id)
            .ok_or(IpcError::StaleSelection)?
            .activity
            .clone();
        if mode == TurnItemRead::Preview && owner.rail.jumping.is_some() {
            return Ok(());
        }
        owner.rail.cancel_preview();
        let resident = self
            .model
            .lock()
            .expect("workspace state lock poisoned")
            .projection
            .read_conversation(request.workspace_id, &request.chat_id, |rows| {
                resident_excerpt(rows, &turn.id)
            })?;
        match (mode, resident) {
            (TurnItemRead::Preview, Some(preview)) => owner.rail.preview = preview,
            (TurnItemRead::Complete, Some(_)) => {
                owner.rail.jumping = None;
                owner.rail.jump = Some(TurnJump {
                    ticket: Uuid::new_v4(),
                    turn_id: turn.id.0,
                });
            }
            _ => owner.read_items(client, turn, mode, sender),
        }
        self.view.turn_rail = Some(owner.rail.view());
        self.publish_navigation();
        Ok(())
    }

    pub(in crate::navigation) fn cancel_turn_jump(
        &mut self,
        request: TurnRailTicketRequest,
    ) -> Result<(), IpcError> {
        let client = self.rail_client(request.workspace_id)?;
        let owner = self.pages.rail_owner(
            request.workspace_id,
            &request.chat_id,
            request.rail_id,
            &client,
        )?;
        if owner
            .rail
            .jumping
            .as_ref()
            .is_some_and(|job| job.ticket == request.ticket)
        {
            owner.rail.jumping = None;
            self.view.turn_rail = Some(owner.rail.view());
            self.publish_navigation();
        }
        Ok(())
    }

    fn rail_client(&self, workspace: WorkspaceId) -> Result<AppServerClient, IpcError> {
        self.require(workspace)?;
        self.backend
            .as_ref()
            .map(|backend| backend.connection.client())
            .ok_or(IpcError::StaleSelection)
    }

    pub(super) fn complete_rail(&mut self, ticket: Uuid, completion: RailCompletion) {
        let Some(selection) = self.selection.as_ref() else {
            return;
        };
        let Some(client) = self
            .backend
            .as_ref()
            .map(|backend| backend.connection.client())
        else {
            return;
        };
        let Some(owner) = self.pages.owner.as_mut().filter(|owner| {
            owner.workspace == selection.id
                && selection.thread.as_ref() == Some(&owner.thread)
                && &owner.connection == client.identity()
        }) else {
            return;
        };
        if selection.checkout.revalidate().is_err() {
            self.retire_history_pages();
            self.publish_navigation();
            return;
        }
        let mut added = None;
        match completion {
            RailCompletion::References { cursor, result } => {
                if !take_job(&mut owner.rail.loading_references, ticket) {
                    return;
                }
                let read = result
                    .as_ref()
                    .as_ref()
                    .map_err(|error| error.to_string())
                    .and_then(|read| {
                        read.page
                            .for_selection(&owner.connection, &owner.thread)
                            .map(|page| (read, page))
                            .map_err(|error| error.to_string())
                    });
                if let Ok((read, page)) = read {
                    owner.summary = Some(read.summary.clone());
                    owner.rail.merge(
                        page.data.iter().cloned().map(|activity| Reference {
                            activity,
                            title: None,
                        }),
                        cursor.is_none(),
                    );
                    owner.rail.cursor = page
                        .next_cursor
                        .clone()
                        .filter(|next| Some(next) != cursor.as_ref())
                        .map(|next| (next, Uuid::new_v4()));
                } else if let Err(error) = read {
                    eprintln!("{error}");
                }
            }
            RailCompletion::Items { mode, turn, result } => {
                let job = match mode {
                    TurnItemRead::Preview => &mut owner.rail.hovering,
                    TurnItemRead::Complete => &mut owner.rail.jumping,
                };
                if !take_job(job, ticket) {
                    return;
                }
                if let Some(items) = checked_read(&result, &owner.connection, &owner.thread)
                    .filter(|items| items.id == turn.id)
                {
                    if mode == TurnItemRead::Preview {
                        owner.rail.preview = preview_from_items(items);
                    } else if let Some(view) = turn_body(&selection.checkout, turn, items) {
                        owner.loaded.insert(items.id.clone());
                        owner.rail.jump = Some(TurnJump {
                            ticket,
                            turn_id: items.id.0.clone(),
                        });
                        added = Some((view, owner.rail.order()));
                    }
                }
            }
        }
        self.view.turn_rail = Some(owner.rail.view());
        if let Some((view, order)) = added {
            let mut state = self.model.lock().expect("workspace state lock poisoned");
            state.publish();
            state
                .projection
                .merge_history(selection.id, self.view.clone(), view, &order);
        } else {
            self.publish_navigation();
        }
    }
}

impl HistoryPaging {
    fn rail_owner(
        &mut self,
        workspace: WorkspaceId,
        chat: &str,
        rail: Uuid,
        client: &AppServerClient,
    ) -> Result<&mut HistoryOwner, IpcError> {
        self.owner
            .as_mut()
            .filter(|owner| {
                owner.workspace == workspace
                    && owner.thread.0 == chat
                    && owner.rail.id == rail
                    && &owner.connection == client.identity()
            })
            .ok_or(IpcError::StaleSelection)
    }
}

impl HistoryOwner {
    fn read_references(
        &mut self,
        client: AppServerClient,
        cursor: Option<TurnCursor>,
        sender: mpsc::Sender<Box<HistoryCompletion>>,
    ) {
        if self.rail.loading_references.is_some() {
            return;
        }
        let summary = self.summary.clone();
        let chat = self.thread.clone();
        let ticket = Uuid::new_v4();
        let task = tauri::async_runtime::spawn(async move {
            let browser = CodexBrowser::new(client);
            let result = async {
                let summary = get_summary(&browser, &chat, summary).await?;
                let page = browser
                    .turn_statuses(&summary, cursor.as_ref(), RPC_TIMEOUT)
                    .await?;
                Ok(ReferenceRead { summary, page })
            }
            .await;
            send_result(
                sender,
                ticket,
                RailCompletion::References {
                    cursor,
                    result: Box::new(result),
                },
            )
            .await;
        });
        self.rail.loading_references = Some(ReadJob {
            ticket,
            turn: None,
            task,
        });
    }

    fn read_items(
        &mut self,
        client: AppServerClient,
        turn: TurnActivity,
        mode: TurnItemRead,
        sender: mpsc::Sender<Box<HistoryCompletion>>,
    ) {
        let id = turn.id.clone();
        let summary = self.summary.clone();
        let chat = self.thread.clone();
        let ticket = Uuid::new_v4();
        let task = tauri::async_runtime::spawn(async move {
            let browser = CodexBrowser::new(client);
            let result = async {
                let summary = get_summary(&browser, &chat, summary).await?;
                browser
                    .turn_items(&summary, &turn.id, mode, RPC_TIMEOUT)
                    .await
            }
            .await;
            send_result(sender, ticket, RailCompletion::Items { mode, turn, result }).await;
        });
        let job = ReadJob {
            ticket,
            turn: Some(id),
            task,
        };
        match mode {
            TurnItemRead::Preview => self.rail.hovering = Some(job),
            TurnItemRead::Complete => self.rail.jumping = Some(job),
        }
    }
}

async fn get_summary(
    browser: &CodexBrowser,
    chat: &ThreadId,
    summary: Option<Arc<ChatRead<ChatSummary>>>,
) -> Result<Arc<ChatRead<ChatSummary>>, BrowseError> {
    if let Some(summary) = summary {
        return Ok(summary);
    }
    browser
        .thread_summary(chat, RPC_TIMEOUT)
        .await
        .map(Arc::new)
}

async fn send_result(
    sender: mpsc::Sender<Box<HistoryCompletion>>,
    ticket: Uuid,
    completion: RailCompletion,
) {
    let _ = sender
        .send(Box::new(HistoryCompletion {
            ticket,
            result: HistoryResult::Rail(completion),
        }))
        .await;
}

fn take_job(job: &mut Option<ReadJob>, ticket: Uuid) -> bool {
    if job.as_ref().is_none_or(|job| job.ticket != ticket) {
        return false;
    }
    *job = None;
    true
}

fn checked_read<'a, T>(
    result: &'a Result<ChatRead<T>, BrowseError>,
    connection: &ConnectionIdentity,
    thread: &ThreadId,
) -> Option<&'a T> {
    match result
        .as_ref()
        .map_err(|error| error.to_string())
        .and_then(|page| {
            page.for_selection(connection, thread)
                .map_err(|error| error.to_string())
        }) {
        Ok(page) => Some(page),
        Err(error) => {
            eprintln!("{error}");
            None
        }
    }
}

fn resident_excerpt(rows: &[TranscriptItem], turn: &TurnId) -> Option<Option<TurnPreview>> {
    let mut selected = rows.iter().filter(|row| row.turn_id == turn.0).peekable();
    selected.peek()?;
    let prompt = selected
        .clone()
        .find(|row| row.role == TranscriptRole::User && !row.text.trim().is_empty())
        .map(|row| excerpt(&row.text, 400));
    let response = selected
        .rev()
        .find(|row| row.role == TranscriptRole::Assistant && !row.text.trim().is_empty())
        .map(|row| excerpt(&row.text, 800));
    Some(build_preview(turn, prompt, response))
}

fn preview_from_items(result: &TurnItems) -> Option<TurnPreview> {
    let prompt = first_prompt(&result.items).map(|prompt| excerpt(&prompt, 400));
    let response = result
        .items
        .iter()
        .rev()
        .filter(|item| item["type"] == "agentMessage")
        .filter_map(|item| item["text"].as_str())
        .find(|text| !text.trim().is_empty())
        .map(|text| excerpt(text, 800));
    build_preview(&result.id, prompt, response)
}

fn build_preview(
    turn: &TurnId,
    prompt: Option<String>,
    response: Option<String>,
) -> Option<TurnPreview> {
    (prompt.is_some() || response.is_some()).then(|| TurnPreview {
        turn_id: turn.0.clone(),
        prompt,
        response,
    })
}

fn first_prompt(items: &[Value]) -> Option<String> {
    items
        .iter()
        .filter(|item| item["type"] == "userMessage")
        .filter_map(|item| item["content"].as_array())
        .flatten()
        .filter(|part| part["type"] == "text")
        .filter_map(|part| part["text"].as_str())
        .find(|text| !text.trim().is_empty())
        .map(|text| present_question_reply(text).into_owned())
}

fn excerpt(text: &str, limit: usize) -> String {
    text.trim().chars().take(limit).collect()
}

fn turn_body(
    checkout: &CheckoutIdentity,
    activity: TurnActivity,
    source: &TurnItems,
) -> Option<TranscriptView> {
    let mut view = TranscriptView::default();
    append_turn_items(
        &mut view,
        checkout,
        &activity,
        &source.items,
        &mut Vec::new(),
    );
    (!view.items.is_empty()).then_some(view)
}
