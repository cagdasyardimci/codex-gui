use codex_gui_core::{
    codex::{CliQualification, RequestError, ThreadActivity},
    identity::TurnId,
    ipc::{
        ComposerPermissions, ComposerSettingsRequest, ContextUsage, DraftAttachmentScope,
        ExecuteSlashCommand, SendRequest, SlashCommandOutcome,
    },
    slash_commands::{COMMANDS, Command, ComposerInput, parse},
    storage::attachments::{
        AttachmentError,
        composer_plan::{ComposerPlan, PlanUpdate},
    },
    workspace::SendSettings,
};
use serde_json::{Value, json};

use super::*;

#[derive(Default)]
pub(super) struct CommandRuntime {
    plans: bool,
    compact_unsupported: bool,
    usage: HashMap<ThreadId, ContextUsage>,
    compactions: HashMap<ThreadId, Compaction>,
}

struct Compaction {
    source: String,
    draft: DraftId,
    turn: Option<TurnId>,
    previous_turns: std::collections::HashSet<String>,
    _lease: RuntimeUse,
}

impl NavigationHandle {
    pub(crate) async fn execute_slash_command(
        &self,
        request: ExecuteSlashCommand,
    ) -> Result<SlashCommandOutcome, IpcError> {
        let (reply, result) = oneshot::channel();
        self.request(Action::SlashCommand(request, reply)).await?;
        result.await.map_err(|_| IpcError::ProjectUnavailable)
    }
}

impl Navigation {
    pub(super) async fn load_command_capabilities(&mut self, client: &AppServerClient) {
        let plans = client
            .request("collaborationMode/list", json!({}), RPC_TIMEOUT)
            .await
            .ok()
            .and_then(|value| {
                value["data"]
                    .as_array()
                    .map(|presets| presets.iter().any(|preset| preset["mode"] == "plan"))
            })
            .unwrap_or(false);
        if let Some(backend) = self.backend.as_mut() {
            backend.commands.plans = plans;
        }
    }

    pub(super) fn read_plan(&self) -> Result<ComposerPlan, Failure> {
        match self.selection.as_ref() {
            Some(selection) => Ok(self
                .store
                .composer_plan(&selection.checkout, self.view.selected_chat.as_deref())?),
            None => Ok(ComposerPlan::default()),
        }
    }

    pub(super) fn sync_slash_commands(&mut self) {
        let mut view = codex_gui_core::ipc::SlashCommandView::default();
        if let (Some(selection), Some(backend)) = (&self.selection, &self.backend)
            && self.quit.is_none()
            && self
                .view
                .queue
                .as_ref()
                .is_none_or(|queue| queue.editing.is_none())
        {
            let saved = self.read_plan().unwrap_or_default();
            view.plan = saved.enabled;
            view.recover_plan = saved.pending.is_some();
            let thread = selection.thread.as_ref();
            view.context = thread
                .and_then(|id| backend.commands.usage.get(id))
                .cloned();
            if view.recover_plan
                || thread.is_some_and(|id| backend.commands.compactions.contains_key(id))
            {
                self.view.actions.send = false;
            }
            let has_model = self.effective_command_model().is_some();
            let idle = self.view.actions.send && self.view.actions.stop.is_none();
            let compact_supported = !backend.commands.compact_unsupported
                && backend.connection.compatibility().qualification()
                    != CliQualification::Unverified;
            view.available = COMMANDS
                .iter()
                .map(|spec| spec.command)
                .filter(|command| match command {
                    Command::New
                    | Command::Resume
                    | Command::Status
                    | Command::Mention
                    | Command::Skills => true,
                    Command::Copy | Command::Diff => thread.is_some(),
                    Command::Model | Command::Reasoning => has_model,
                    Command::Fast => self.fast_tier().is_some(),
                    Command::Permissions => self.view.composer_settings.is_some(),
                    Command::Plan => {
                        has_model && backend.commands.plans && (idle || view.recover_plan)
                    }
                    Command::Compact => compact_supported && idle && thread.is_some(),
                    Command::Fork
                    | Command::Rename
                    | Command::Archive
                    | Command::Delete
                    | Command::Review => false,
                })
                .collect();
        }
        self.view.slash_commands = view;
    }

    pub(super) async fn execute_slash(
        &mut self,
        request: ExecuteSlashCommand,
    ) -> Result<SlashCommandOutcome, IpcError> {
        let ExecuteSlashCommand {
            draft,
            choice,
            confirmed,
        } = request;
        self.require(draft.workspace_id)?;
        self.validate_send_selection(&draft)?;
        let draft_id = self.editor_id().ok_or(IpcError::StaleSelection)?;
        let saved = self
            .store
            .read_editor_draft(draft_id)
            .map_err(|error| report(error.into()))?;
        if self.quit.is_some()
            || saved.text != draft.text
            || super::composer_attachments::views(&saved.context)
                .iter()
                .map(|entry| &entry.id)
                .ne(draft.attachment_ids.iter())
        {
            return Err(IpcError::StaleSelection);
        }
        if self.is_literal_revision(draft_id).map_err(report)? {
            return Ok(SlashCommandOutcome::Send);
        }
        let (command, original) = match parse(&draft.text) {
            ComposerInput::Text | ComposerInput::Literal(_) if choice.is_none() && !confirmed => {
                return Ok(SlashCommandOutcome::Send);
            }
            ComposerInput::Command { command, arguments } => (command, arguments.trim()),
            _ => return Err(IpcError::StaleSelection),
        };
        self.sync_actions();
        if !self.view.slash_commands.available.contains(&command) {
            return Err(IpcError::StaleSelection);
        }
        let argument = match choice.as_deref() {
            None => original,
            Some(choice) if original.is_empty() => choice.trim(),
            _ => return Err(IpcError::StaleSelection),
        };
        let visible = SlashCommandOutcome::Present(command);
        match command {
            Command::New => {
                self.consume_command(draft_id, &draft.text)?;
                self.focus(None).await.map_err(report)?;
                return Ok(SlashCommandOutcome::Applied);
            }
            Command::Resume if !argument.is_empty() => {
                let thread = ThreadId(argument.to_owned());
                let client = self
                    .backend
                    .as_ref()
                    .ok_or(IpcError::StaleSelection)?
                    .connection
                    .client();
                CodexBrowser::new(client)
                    .thread_summary(&thread, RPC_TIMEOUT)
                    .await
                    .map_err(|error| report(error.into()))?;
                self.consume_command(draft_id, &draft.text)?;
                self.focus(Some(thread)).await.map_err(report)?;
                return Ok(SlashCommandOutcome::Applied);
            }
            Command::Model | Command::Reasoning | Command::Fast | Command::Permissions => {
                if matches!(
                    command,
                    Command::Model | Command::Reasoning | Command::Permissions
                ) && argument.is_empty()
                    || command == Command::Permissions && argument == "full" && !confirmed
                {
                    return Ok(visible);
                }
                self.apply_slash_preference(command, argument, confirmed, &draft)?;
            }
            Command::Plan => {
                let previous = self.read_plan().map_err(report)?;
                if previous.pending.is_some() && choice.is_none() {
                    return Ok(visible);
                }
                if choice.is_none() && !original.is_empty() {
                    return Ok(SlashCommandOutcome::Send);
                }
                let enabled = match choice.as_deref() {
                    Some("plan") if previous.pending.is_some() && confirmed => true,
                    Some("default") if previous.pending.is_some() && confirmed => false,
                    None => !previous.enabled,
                    _ => return Err(IpcError::StaleSelection),
                };
                self.update_plan(draft, enabled, previous).await?;
                return Ok(SlashCommandOutcome::Applied);
            }
            Command::Compact => {
                self.start_compaction(draft_id, draft).await?;
                return Ok(SlashCommandOutcome::Applied);
            }
            Command::Diff | Command::Status => {
                self.consume_command(draft_id, &draft.text)?;
                return Ok(visible);
            }
            Command::Copy if confirmed => {}
            Command::Resume | Command::Skills | Command::Mention | Command::Copy => {
                return Ok(visible);
            }
            Command::Fork
            | Command::Rename
            | Command::Archive
            | Command::Delete
            | Command::Review => {
                return Err(IpcError::StaleSelection);
            }
        }
        self.consume_command(draft_id, &draft.text)?;
        Ok(SlashCommandOutcome::Applied)
    }

    fn effective_command_model(&self) -> Option<&codex_gui_core::ipc::AccountModel> {
        let id = self
            .view
            .composer_settings
            .as_ref()?
            .effective_model_id
            .as_deref()?;
        self.view.account.models.iter().find(|model| model.id == id)
    }

    fn fast_tier(&self) -> Option<&str> {
        let tiers = &self.effective_command_model()?.service_tiers;
        tiers
            .iter()
            .find(|tier| tier.id == "priority")
            .or_else(|| {
                tiers.iter().find(|tier| {
                    tier.id.eq_ignore_ascii_case("fast") || tier.name.eq_ignore_ascii_case("fast")
                })
            })
            .map(|tier| tier.id.as_str())
    }

    fn apply_slash_preference(
        &mut self,
        command: Command,
        argument: &str,
        confirmed: bool,
        draft: &SendRequest,
    ) -> Result<(), IpcError> {
        let settings = self
            .view
            .composer_settings
            .as_ref()
            .ok_or(IpcError::StaleSelection)?;
        let mut selection = settings.selection.clone();
        match command {
            Command::Model => {
                let model = self
                    .view
                    .account
                    .models
                    .iter()
                    .find(|model| model.id == argument)
                    .ok_or(IpcError::StaleSelection)?;
                selection.model_id = Some(model.id.clone());
                selection.effort = selection.effort.filter(|effort| {
                    model
                        .efforts
                        .iter()
                        .any(|option| &option.reasoning_effort == effort)
                });
                selection.service_tier = selection.service_tier.filter(|tier| {
                    tier == "default" || model.service_tiers.iter().any(|option| &option.id == tier)
                });
            }
            Command::Reasoning => selection.effort = Some(argument.to_owned()),
            Command::Fast => {
                let tier = self.fast_tier().ok_or(IpcError::StaleSelection)?;
                let enabled = match argument {
                    "" => selection.service_tier.as_deref() != Some(tier),
                    "on" => true,
                    "off" => false,
                    _ => return Err(IpcError::StaleSelection),
                };
                selection.service_tier = Some(if enabled { tier } else { "default" }.to_owned());
            }
            Command::Permissions => {
                selection.permissions = match argument {
                    "ask" => ComposerPermissions::AskForApproval,
                    "auto" => ComposerPermissions::ApproveForMe,
                    "full" if confirmed => ComposerPermissions::FullAccess,
                    _ => return Err(IpcError::StaleSelection),
                }
            }
            _ => return Err(IpcError::StaleSelection),
        };
        self.change_composer_settings(ComposerSettingsRequest {
            scope: DraftAttachmentScope {
                workspace_id: draft.workspace_id,
                chat_id: draft.chat_id.clone(),
                draft_id: draft.draft_id.clone(),
            },
            revision: settings.revision,
            selection,
            confirm_full_access: confirmed,
        })
    }

    fn consume_command(&mut self, draft: DraftId, source: &str) -> Result<(), IpcError> {
        let checkout = &self
            .selection
            .as_ref()
            .ok_or(IpcError::RetiredWorkspace)?
            .checkout;
        let _write = self
            .owners
            .acquire_write(checkout)
            .map_err(|error| report(error.into()))?;
        self.store
            .replace_editor_text(draft, Some(source), String::new())
            .map_err(command_store_error)?;
        self.set_editor(draft).map_err(report)?;
        self.publish_navigation();
        Ok(())
    }

    async fn update_plan(
        &mut self,
        draft: SendRequest,
        enabled: bool,
        mut plan: ComposerPlan,
    ) -> Result<(), IpcError> {
        if self.view.actions.stop.is_some() {
            return Err(IpcError::StaleSelection);
        }
        let checkout = self
            .selection
            .as_ref()
            .ok_or(IpcError::RetiredWorkspace)?
            .checkout
            .clone();
        let _write = self
            .owners
            .acquire_write(&checkout)
            .map_err(|error| report(error.into()))?;
        let Some(thread) = draft.chat_id.as_deref() else {
            self.store
                .settle_composer_plan(
                    &checkout,
                    None,
                    enabled,
                    Some((&draft.draft_id, &draft.text)),
                )
                .map_err(command_store_error)?;
            self.set_editor(self.editor_id().ok_or(IpcError::StaleSelection)?)
                .map_err(report)?;
            self.sync_actions();
            return Ok(());
        };
        let client = self
            .backend
            .as_ref()
            .ok_or(IpcError::StaleSelection)?
            .connection
            .client();
        let settings = self.capture_run_settings(&self.project_context().map_err(report)?);
        let mode = collaboration_mode(&settings, enabled).ok_or(IpcError::StaleSelection)?;
        let old_pending = plan.pending.take();
        plan.pending = Some(PlanUpdate {
            draft_id: draft.draft_id.clone(),
            source: draft.text,
            mode: mode.clone(),
        });
        self.store
            .save_composer_plan(&checkout, Some(thread), &plan)
            .map_err(command_store_error)?;
        let applied = client
            .request(
                "thread/settings/update",
                json!({
                    "threadId": thread, "collaborationMode": mode,
                }),
                RPC_TIMEOUT,
            )
            .await;
        let outcome = match applied {
            Ok(_) => settle_plan(&self.store, &checkout, thread, plan, enabled),
            Err(error) if error.is_unsent() || matches!(error, RequestError::Remote(_)) => {
                plan.pending = old_pending;
                self.store
                    .save_composer_plan(&checkout, Some(thread), &plan)
                    .map_err(command_store_error)?;
                Err(error.into())
            }
            Err(error) => Err(error.into()),
        };
        if let Some(draft) = self.editor_id() {
            self.set_editor(draft).map_err(report)?;
        }
        self.sync_actions();
        outcome.map_err(report)
    }

    async fn start_compaction(&mut self, id: DraftId, draft: SendRequest) -> Result<(), IpcError> {
        let backend = self.backend.as_mut().ok_or(IpcError::StaleSelection)?;
        let client = backend.connection.client();
        let thread = ThreadId(draft.chat_id.ok_or(IpcError::StaleSelection)?);
        let summary = CodexBrowser::new(client.clone())
            .thread_summary(&thread, RPC_TIMEOUT)
            .await
            .map_err(|error| report(error.into()))?;
        let summary = summary
            .for_selection(client.identity(), &thread)
            .map_err(|error| report(error.into()))?;
        if !matches!(
            summary.activity,
            ThreadActivity::Idle | ThreadActivity::NotLoaded
        ) {
            return Err(IpcError::StaleSelection);
        }
        let previous_turns = self
            .view
            .turn_rail
            .as_ref()
            .into_iter()
            .flat_map(|rail| &rail.turns)
            .map(|turn| turn.id.clone())
            .collect();
        let _lease = self
            .owners
            .acquire(client.identity())
            .map_err(|error| report(error.into()))?;
        backend.commands.compactions.insert(
            thread.clone(),
            Compaction {
                source: draft.text,
                draft: id,
                turn: None,
                previous_turns,
                _lease,
            },
        );
        let result = client
            .request(
                "thread/compact/start",
                json!({"threadId": thread.0}),
                RPC_TIMEOUT,
            )
            .await;
        if let Err(error) = result {
            if error.is_unsent() || matches!(error, RequestError::Remote(_)) {
                backend.commands.compactions.remove(&thread);
            }
            if matches!(&error, RequestError::Remote(remote) if remote.code == -32601) {
                backend.commands.compact_unsupported = true;
            }
            self.sync_actions();
            return Err(report(error.into()));
        }
        self.sync_actions();
        Ok(())
    }
}

impl Backend {
    pub(super) fn observe_slash_event(
        &mut self,
        event: &ServerEvent,
        store: &AttachmentStore,
    ) -> Result<bool, Failure> {
        let ServerEvent::Notification { method, params } = event else {
            return Ok(false);
        };
        let Some(id) = params["threadId"].as_str().filter(|id| !id.is_empty()) else {
            return Ok(false);
        };
        let thread = ThreadId(id.to_owned());
        let client = self.connection.client();
        let owner = client.identity();
        if !self.engine.snapshot().writable_threads.contains(&thread) {
            return Ok(false);
        }
        let Some(checkout) = owner.workspace.checkout.as_ref() else {
            return Ok(false);
        };
        if method == "thread/tokenUsage/updated" {
            let usage = &params["tokenUsage"];
            let tokens = usage["last"]["totalTokens"]
                .as_u64()
                .and_then(|tokens| u32::try_from(tokens).ok());
            let window = usage["modelContextWindow"]
                .as_u64()
                .and_then(|window| u32::try_from(window).ok())
                .filter(|window| *window > 0);
            if let Some(tokens) = tokens {
                self.commands
                    .usage
                    .insert(thread, ContextUsage { tokens, window });
                return Ok(true);
            }
        } else if method == "thread/settings/updated" {
            let settings = &params["threadSettings"];
            let mode = &settings["collaborationMode"];
            if let Some(cwd) = settings["cwd"].as_str()
                && checkout.validate_reported(Path::new(cwd)).is_ok()
                && let Some(enabled) = mode["mode"].as_str().and_then(|mode| match mode {
                    "plan" => Some(true),
                    "default" => Some(false),
                    _ => None,
                })
            {
                let mut plan = store.composer_plan(checkout, Some(id))?;
                if plan
                    .pending
                    .as_ref()
                    .is_some_and(|pending| same_mode(&pending.mode, mode))
                {
                    settle_plan(store, checkout, id, plan, enabled)?;
                } else if plan.enabled != enabled {
                    plan.enabled = enabled;
                    store.save_composer_plan(checkout, Some(id), &plan)?;
                }
                return Ok(true);
            }
        } else if let Some(compaction) = self.commands.compactions.get_mut(&thread) {
            let turn = params["turnId"]
                .as_str()
                .or_else(|| params["turn"]["id"].as_str());
            let marker = method == "thread/compacted"
                || method == "item/completed" && params["item"]["type"] == "contextCompaction";
            if let Some(turn) = turn
                && (marker || matches!(method.as_str(), "turn/started" | "turn/completed"))
                && !compaction.previous_turns.contains(turn)
                && compaction
                    .turn
                    .as_ref()
                    .is_none_or(|current| current.0 == turn)
            {
                compaction
                    .turn
                    .get_or_insert_with(|| TurnId(turn.to_owned()));
                if marker {
                    let finished = self
                        .commands
                        .compactions
                        .remove(&thread)
                        .expect("captured compaction");
                    consume_saved_command(store, finished.draft, &finished.source)?;
                    return Ok(true);
                }
                if method == "turn/completed" && params["turn"]["status"] != "completed" {
                    self.commands.compactions.remove(&thread);
                    return Ok(true);
                }
            }
        }
        Ok(false)
    }
}

fn same_mode(expected: &Value, actual: &Value) -> bool {
    expected["mode"] == actual["mode"]
        && expected["settings"]["model"] == actual["settings"]["model"]
        && expected["settings"]["reasoning_effort"] == actual["settings"]["reasoning_effort"]
        && expected["settings"]["developer_instructions"]
            == actual["settings"]["developer_instructions"]
}

pub(super) fn collaboration_mode(settings: &SendSettings, enabled: bool) -> Option<Value> {
    Some(json!({
        "mode": if enabled { "plan" } else { "default" },
        "settings": { "model": settings.model.as_ref()?, "reasoning_effort": settings.reasoning_effort,
                      "developer_instructions": null },
    }))
}

fn command_store_error(error: AttachmentError) -> IpcError {
    match error {
        AttachmentError::StaleComposerText => IpcError::StaleSelection,
        error => report(error.into()),
    }
}

fn settle_plan(
    store: &AttachmentStore,
    checkout: &CheckoutIdentity,
    thread: &str,
    plan: ComposerPlan,
    enabled: bool,
) -> Result<(), Failure> {
    let command = plan
        .pending
        .as_ref()
        .map(|pending| (pending.draft_id.as_str(), pending.source.as_str()));
    store
        .settle_composer_plan(checkout, Some(thread), enabled, command)
        .map_err(Into::into)
}

fn consume_saved_command(
    store: &AttachmentStore,
    draft: DraftId,
    source: &str,
) -> Result<(), AttachmentError> {
    match store.replace_editor_text(draft, Some(source), String::new()) {
        Err(AttachmentError::StaleComposerText | AttachmentError::MissingDraft) => Ok(()),
        result => result,
    }
}
