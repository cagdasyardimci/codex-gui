use codex_gui_core::{
    ipc::{ChatRow, PrepareVoiceCall, VoiceCallView},
    storage::drafts::DraftRevision,
};
use serde_json::json;
use tauri::Manager;

use crate::{
    project_ipc::ProjectIpc,
    voice_ipc::{ReserveVoice, VoiceIpc},
};

use super::*;

impl Navigation {
    pub(super) async fn reserve_voice_call(
        &mut self,
        request: PrepareVoiceCall,
    ) -> Result<VoiceCallView, IpcError> {
        self.require(request.workspace_id)?;
        self.sync_actions();
        let app = self.app.clone();
        let voice = app.state::<VoiceIpc>();
        if !voice.available()
            || !self.view.voice_available
            || self.view.selected_chat != request.chat_id
            || self
                .view
                .draft
                .as_ref()
                .is_none_or(|draft| draft.id != request.draft_id)
        {
            return Err(IpcError::StaleSelection);
        }
        let client = self
            .backend
            .as_ref()
            .ok_or(IpcError::StaleSelection)?
            .connection
            .client();
        let checkout = client
            .identity()
            .workspace
            .checkout
            .as_ref()
            .ok_or(IpcError::StaleSelection)?;
        let project = checkout.storage_key();
        let reconnect = request
            .reconnect
            .map(|id| voice.resume_target(id, &project, request.chat_id.as_deref()))
            .transpose()?;
        let browser = CodexBrowser::new(client.clone());
        let selected = browser
            .voice_selection(
                reconnect
                    .as_ref()
                    .and_then(|target| target.voice.as_deref()),
                RPC_TIMEOUT,
            )
            .await
            .map_err(|error| report(error.into()))?
            .ok_or(IpcError::StaleSelection)?;
        let thread = match request.chat_id {
            Some(chat) => ThreadId(chat),
            None => {
                let source = DraftId(
                    Uuid::parse_str(&request.draft_id).map_err(|_| IpcError::StaleSelection)?,
                );
                let preferences =
                    self.capture_run_settings(&self.project_context().map_err(report)?);
                let _lease = self
                    .owners
                    .acquire(client.identity())
                    .map_err(|error| report(error.into()))?;
                let created = browser
                    .create_voice_thread(&preferences, RPC_TIMEOUT)
                    .await
                    .map_err(|error| report(error.into()))?;
                let thread = created.id;
                self.store
                    .attach_source_draft_to_voice_thread(source, &thread)
                    .map_err(|error| report(error.into()))?;
                self.source_draft = self
                    .store
                    .desktop_selection()
                    .map_err(|error| report(error.into()))?
                    .source_draft;
                let name = "New Voice Chat";
                if let Err(error) = client
                    .request(
                        "thread/name/set",
                        json!({"threadId": thread.0, "name": name}),
                        RPC_TIMEOUT,
                    )
                    .await
                {
                    eprintln!("{error}");
                }
                let row = ChatRow {
                    id: thread.0.clone(),
                    title: name.into(),
                    preview: String::new(),
                };
                self.remember_sidebar_chat(&row, super::sidebar::sidebar_timestamp())
                    .map_err(report)?;
                self.view.chats.insert(0, row);
                self.focus(Some(thread.clone())).await.map_err(report)?;
                if self.view.write_access != WriteAccess::Ready
                    || self.view.selected_chat.as_deref() != Some(&thread.0)
                {
                    return Err(IpcError::StaleSelection);
                }
                thread
            }
        };
        voice.reserve(
            &app,
            ReserveVoice {
                client,
                thread,
                project,
                selection: selected,
                reconnect,
            },
        )
    }

    pub(super) fn try_voice_text(
        &self,
        chat: &str,
        draft: DraftId,
        revision: DraftRevision,
        text: &str,
    ) -> Result<bool, Failure> {
        let client = self
            .backend
            .as_ref()
            .ok_or("Codex is disconnected")?
            .connection
            .client();
        let Some(id) = self
            .app
            .state::<VoiceIpc>()
            .begin_text(client.identity(), chat)
            .map_err(|_| "The voice session cannot accept text at this time")?
        else {
            return Ok(false);
        };
        let app = self.app.clone();
        let store = self.store.clone();
        let text = text.to_owned();
        tauri::async_runtime::spawn(async move {
            let voice = app.state::<VoiceIpc>();
            let result = voice.append_text(id, &text).await;
            match result {
                Ok(()) => match store.clear_acknowledged_voice_text(draft, revision) {
                    Ok(true) => {
                        if let Some(navigation) = app.state::<ProjectIpc>().navigation.get()
                            && let Err(error) =
                                navigation.request(Action::VoiceTextSaved(draft)).await
                        {
                            eprintln!("{error:?}");
                        }
                    }
                    Ok(false) => {}
                    Err(error) => eprintln!("{error}"),
                },
                Err(error) => eprintln!("{error:?}"),
            }
            voice.finish_text(id);
        });
        Ok(true)
    }
}
