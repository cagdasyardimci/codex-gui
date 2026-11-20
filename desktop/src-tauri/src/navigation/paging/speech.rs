use std::collections::HashSet;

use codex_gui_core::{
    codex::{
        ChatRead, CodexBrowser, SpeechRole, TimelineCursor, TimelineEntry, VoiceSegment,
        VoiceTimelinePage,
    },
    identity::TurnId,
    ipc::{TranscriptItem, TranscriptRole, TranscriptView},
};

use super::*;

pub(super) type SpeechPage = ChatRead<VoiceTimelinePage>;

#[derive(Default)]
pub(super) struct SpeechHistory {
    pages: Vec<VoiceTimelinePage>,
    seen: HashSet<TimelineCursor>,
    covered: HashSet<String>,
}

impl SpeechHistory {
    pub(super) fn has_more(&self) -> bool {
        self.pages.last().is_none_or(|page| page.next.is_some())
    }

    fn covers(&self, turn: Option<&str>) -> bool {
        !self.pages.is_empty()
            && turn.is_none_or(|id| self.covered.contains(id) || !self.has_more())
    }

    fn append(&mut self, mut page: VoiceTimelinePage) {
        for entry in &page.entries {
            if let TimelineEntry::Turn { id, started: true } = entry {
                self.covered.insert(id.clone());
            }
        }
        page.next = page.next.filter(|cursor| self.seen.insert(cursor.clone()));
        self.pages.push(page);
    }

    fn rows(&self, loaded: &HashSet<TurnId>) -> (TranscriptView, Vec<String>, HashSet<String>) {
        let mut view = TranscriptView::default();
        let mut order = Vec::new();
        let mut turns = HashSet::new();
        let mut preceding = None;
        let mut seen_speech = HashSet::new();
        let mut voice_turns = HashSet::new();
        let mut voice_active = false;
        for page in self.pages.iter().rev() {
            if let Some(active) = page.active_at_start {
                voice_active = active;
            }
            for entry in &page.entries {
                match entry {
                    TimelineEntry::Turn { id, .. } => {
                        preceding = Some(id.as_str());
                        if voice_active {
                            voice_turns.insert(id.clone());
                        }
                        if turns.insert(id) {
                            order.push(id.clone());
                        }
                    }
                    TimelineEntry::VoiceStarted => voice_active = true,
                    TimelineEntry::VoiceClosed => voice_active = false,
                    TimelineEntry::Speech(speech) if seen_speech.insert(&speech.id) => {
                        let anchor = match preceding {
                            Some(turn) if loaded.contains(&TurnId(turn.into())) => turn.to_owned(),
                            None if loaded.is_empty() || !self.has_more() => {
                                let anchor = format!("speech/{}", speech.id);
                                order.push(anchor.clone());
                                anchor
                            }
                            _ => continue,
                        };
                        view.push_message(speech_item(speech, anchor));
                    }
                    _ => {}
                }
            }
        }
        (view, order, voice_turns)
    }
}

pub(in crate::navigation) fn speech_item(speech: &VoiceSegment, turn_id: String) -> TranscriptItem {
    let role = match speech.role {
        SpeechRole::User => TranscriptRole::User,
        SpeechRole::Assistant => TranscriptRole::Assistant,
    };
    let mut item = TranscriptItem::message(
        format!("speech/{}", speech.id),
        turn_id,
        speech.text.clone(),
        true,
        role,
    );
    item.spoken = true;
    item
}

impl Navigation {
    pub(in crate::navigation) fn remember_voice_turn(&mut self, chat: &str, turn: &str) {
        if let Some(owner) = self
            .pages
            .owner
            .as_mut()
            .filter(|owner| owner.thread.0 == chat)
        {
            owner.voice_turns.insert(turn.into());
        }
    }

    pub(in crate::navigation) fn voice_turn(&self, chat: &str, turn: &str) -> bool {
        self.pages
            .owner
            .as_ref()
            .is_some_and(|owner| owner.thread.0 == chat && owner.voice_turns.contains(turn))
    }

    pub(in crate::navigation) fn present_speech(&mut self, chat: &str, speech: VoiceSegment) {
        let Some(owner) = self
            .pages
            .owner
            .as_ref()
            .filter(|owner| owner.thread.0 == chat)
        else {
            return;
        };
        let anchor = owner
            .rail
            .order()
            .into_iter()
            .last()
            .unwrap_or_else(|| format!("speech/{}", speech.id));
        self.publish_stream(
            owner.workspace,
            codex_gui_core::ipc::StreamChange::FinalItem(speech_item(&speech, anchor)),
        );
    }

    pub(in crate::navigation) fn start_speech_history(
        &mut self,
        explicit: bool,
    ) -> Result<(), IpcError> {
        let Some(owner) = self.pages.owner.as_mut() else {
            return Ok(());
        };
        let Some(speech) = owner.speech.as_ref() else {
            return Ok(());
        };
        if owner.pending.is_some() || !speech.has_more() {
            return Ok(());
        }
        let target = owner
            .rail
            .order()
            .into_iter()
            .find(|id| owner.loaded.contains(&TurnId(id.clone())));
        if !explicit && speech.covers(target.as_deref()) {
            return Ok(());
        }
        let summary = owner.summary.clone().ok_or(IpcError::StaleSelection)?;
        let client = self
            .backend
            .as_ref()
            .ok_or(IpcError::StaleSelection)?
            .connection
            .client();
        if client.identity() != &owner.connection {
            return Err(IpcError::StaleSelection);
        }
        let cursor = speech.pages.last().and_then(|page| page.next.clone());
        let ticket = owner.ticket;
        let complete = self.pages.sender.clone();
        owner.pending = Some(tauri::async_runtime::spawn(async move {
            let result = CodexBrowser::new(client)
                .voice_timeline(&summary, cursor.as_ref(), RPC_TIMEOUT)
                .await;
            let _ = complete
                .send(Box::new(HistoryCompletion {
                    ticket,
                    result: HistoryResult::Speech(result),
                }))
                .await;
        }));
        self.view.older_history = self.pages.view();
        self.publish_navigation();
        Ok(())
    }

    pub(super) fn complete_speech(
        &mut self,
        ticket: Uuid,
        result: Result<SpeechPage, BrowseError>,
    ) {
        let Some(owner) = self
            .pages
            .owner
            .as_mut()
            .filter(|owner| owner.ticket == ticket)
        else {
            return;
        };
        owner.pending = None;
        let Some(selection) = self.selection.as_ref().filter(|selection| {
            selection.id == owner.workspace && selection.thread.as_ref() == Some(&owner.thread)
        }) else {
            return;
        };
        let Some(client) = self
            .backend
            .as_ref()
            .map(|backend| backend.connection.client())
        else {
            return;
        };
        if &owner.connection != client.identity() || selection.checkout.revalidate().is_err() {
            self.retire_history_pages();
            self.publish_navigation();
            return;
        }
        let page = match result.and_then(|result| {
            result
                .for_selection(client.identity(), &owner.thread)
                .cloned()
        }) {
            Ok(page) => page,
            Err(error) => {
                eprintln!("{error}");
                self.view.older_history = self.pages.view();
                self.publish_navigation();
                return;
            }
        };
        let Some(speech) = owner.speech.as_mut() else {
            return;
        };
        speech.append(page);
        let (history, order, voice_turns) = speech.rows(&owner.loaded);
        owner.voice_turns.extend(voice_turns);
        let voice_turns = owner.voice_turns.clone();
        owner.ticket = Uuid::new_v4();
        let workspace = owner.workspace;
        self.view.older_history = self.pages.view();
        {
            let mut state = self.model.lock().expect("workspace state lock poisoned");
            state.publish();
            state.projection.merge_voice_history(
                workspace,
                self.view.clone(),
                history,
                &order,
                &voice_turns,
            );
        }
        if let Err(error) = self.start_speech_history(false) {
            eprintln!("{error:?}");
        }
    }
}
