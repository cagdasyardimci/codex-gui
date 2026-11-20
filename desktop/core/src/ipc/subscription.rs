use std::sync::{Arc, Weak};
use std::time::Duration;

use serde::{Deserialize, Serialize};
use tokio::{sync::watch, time::timeout};
use ts_rs::TS;
use uuid::Uuid;

use super::{
    IpcError, NavigationView, TranscriptRowRequest, WorkspaceId, WorkspaceView,
    stream::{CommandUpdate, StreamChange, TranscriptItem, TranscriptRole, TranscriptView},
};

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize, TS)]
pub struct SubscriptionId(Uuid);

#[derive(Clone, Debug, Default, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct WorkspaceSnapshot {
    pub revision: u32,
    pub workspace: Option<WorkspaceView>,
    pub transcript: TranscriptView,
    pub navigation: NavigationView,
}

#[derive(Debug, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct WorkspaceSubscription {
    pub subscription_id: SubscriptionId,
    pub snapshot: WorkspaceSnapshot,
}

#[derive(Clone, Copy, Debug, Deserialize, Serialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct WorkspaceUpdateRequest {
    pub subscription_id: SubscriptionId,
    pub after_revision: u32,
}

#[derive(Debug, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct RevisionedStream {
    pub revision: u32,
    pub change: StreamChange,
}

#[derive(Debug, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct RevisionedNavigation {
    pub revision: u32,
    pub navigation: NavigationView,
}

#[derive(Debug, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct RevisionedHistory {
    pub revision: u32,
    pub insertions: Vec<HistoryInsertion>,
    pub navigation: NavigationView,
}

#[derive(Clone, Debug, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct HistoryInsertion {
    pub position: u32,
    pub rows: Vec<TranscriptItem>,
}

#[derive(Debug, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub enum WorkspaceUpdate {
    Changed(WorkspaceSnapshot),
    Stream(RevisionedStream),
    Navigation(RevisionedNavigation),
    History(RevisionedHistory),
    Resync,
    Retired,
    Idle,
}

#[derive(Default)]
struct Publication {
    subscriber: Option<SubscriptionId>,
    snapshot: WorkspaceSnapshot,
    change: Change,
}

#[derive(Default)]
enum Change {
    #[default]
    Snapshot,
    Stream(StreamChange),
    Navigation,
    History(Vec<HistoryInsertion>),
}

impl Publication {
    fn owns_workspace(&self, workspace: WorkspaceId) -> bool {
        self.snapshot
            .workspace
            .as_ref()
            .map(|view| view.workspace_id)
            == Some(workspace)
    }

    fn advance(&mut self, change: Change) {
        self.snapshot.revision = self
            .snapshot
            .revision
            .checked_add(1)
            .expect("workspace projection exhausted its revision range");
        self.change = change;
    }

    fn adjacent_update(&self) -> WorkspaceUpdate {
        match &self.change {
            Change::Stream(change) => WorkspaceUpdate::Stream(RevisionedStream {
                revision: self.snapshot.revision,
                change: change.clone(),
            }),
            Change::Navigation => WorkspaceUpdate::Navigation(RevisionedNavigation {
                revision: self.snapshot.revision,
                navigation: self.snapshot.navigation.clone(),
            }),
            Change::History(insertions) => WorkspaceUpdate::History(RevisionedHistory {
                revision: self.snapshot.revision,
                insertions: insertions.clone(),
                navigation: self.snapshot.navigation.clone(),
            }),
            Change::Snapshot => WorkspaceUpdate::Changed(self.snapshot.clone()),
        }
    }
}

pub struct WorkspaceProjection {
    publication: watch::Sender<Publication>,
    pending_poll: Weak<()>,
}

impl Default for WorkspaceProjection {
    fn default() -> Self {
        let (publication, _) = watch::channel(Publication::default());
        Self {
            publication,
            pending_poll: Weak::new(),
        }
    }
}

impl WorkspaceProjection {
    pub fn publish(&mut self, workspace: Option<WorkspaceView>) {
        self.publication.send_if_modified(|publication| {
            if publication.snapshot.workspace == workspace {
                return false;
            }
            publication.snapshot.workspace = workspace;
            publication.snapshot.transcript = TranscriptView::default();
            publication.snapshot.navigation = NavigationView::default();
            publication.advance(Change::Snapshot);
            true
        });
    }

    pub fn replace_history(
        &mut self,
        workspace: Option<WorkspaceView>,
        navigation: NavigationView,
        mut transcript: TranscriptView,
    ) {
        self.publication.send_modify(|publication| {
            publication.snapshot.workspace = workspace;
            publication.snapshot.navigation = navigation;
            publication.advance(Change::Snapshot);
            transcript.generation = publication.snapshot.revision;
            publication.snapshot.transcript = transcript;
        });
    }

    pub fn update_navigation(&mut self, navigation: NavigationView) {
        self.publication.send_if_modified(|publication| {
            if publication.snapshot.navigation == navigation {
                return false;
            }
            publication.snapshot.navigation = navigation;
            publication.advance(Change::Navigation);
            true
        });
    }

    pub fn prepend_history(
        &mut self,
        workspace: WorkspaceId,
        navigation: NavigationView,
        earlier: TranscriptView,
    ) -> bool {
        self.change_history(workspace, navigation, |view| {
            let rows = view.insert(0, earlier);
            if rows.is_empty() {
                Vec::new()
            } else {
                vec![HistoryInsertion { position: 0, rows }]
            }
        })
    }

    pub fn merge_history(
        &mut self,
        workspace: WorkspaceId,
        navigation: NavigationView,
        added: TranscriptView,
        order: &[String],
    ) -> bool {
        self.change_history(workspace, navigation, |view| view.merge(added, order))
    }

    fn change_history(
        &mut self,
        workspace: WorkspaceId,
        navigation: NavigationView,
        update: impl FnOnce(&mut TranscriptView) -> Vec<HistoryInsertion>,
    ) -> bool {
        self.publication.send_if_modified(|publication| {
            if !publication.owns_workspace(workspace)
                || publication.snapshot.navigation.selected_chat != navigation.selected_chat
            {
                return false;
            }
            let insertions = update(&mut publication.snapshot.transcript);
            if insertions.is_empty() && publication.snapshot.navigation == navigation {
                return false;
            }
            publication.snapshot.navigation = navigation;
            publication.advance(Change::History(insertions));
            true
        })
    }

    pub fn read_conversation<T>(
        &self,
        workspace: WorkspaceId,
        chat: &str,
        read: impl FnOnce(&[TranscriptItem]) -> T,
    ) -> Result<T, IpcError> {
        let current = self.publication.borrow();
        if !current.owns_workspace(workspace) {
            return Err(IpcError::RetiredWorkspace);
        }
        if current.snapshot.navigation.selected_chat.as_deref() != Some(chat) {
            return Err(IpcError::StaleSelection);
        }
        Ok(read(&current.snapshot.transcript.items))
    }

    pub fn publish_stream(&mut self, workspace: WorkspaceId, mut change: StreamChange) -> bool {
        self.publication.send_if_modified(|publication| {
            if !publication.owns_workspace(workspace)
                || !publication.snapshot.transcript.apply(&mut change)
            {
                return false;
            }
            publication.advance(Change::Stream(change));
            true
        })
    }

    pub fn publish_command(&mut self, workspace: WorkspaceId, change: CommandUpdate) -> bool {
        self.publication.send_if_modified(|publication| {
            if !publication.owns_workspace(workspace) {
                return false;
            }
            let Some(row) = publication
                .snapshot
                .transcript
                .apply_command(change)
                .cloned()
            else {
                return false;
            };
            publication.advance(Change::Stream(StreamChange::FinalItem(row)));
            true
        })
    }

    pub fn copy_transcript_source(
        &self,
        request: &TranscriptRowRequest,
    ) -> Result<String, IpcError> {
        self.read_transcript_row(request, |row| {
            (row.role == TranscriptRole::Assistant && row.completed && !row.text.is_empty())
                .then(|| row.text.clone())
        })
    }

    pub fn transcript_images(
        &self,
        request: &TranscriptRowRequest,
    ) -> Result<Vec<String>, IpcError> {
        self.read_transcript_row(request, |row| {
            row.completed.then(|| row.local_images.clone())
        })
    }

    fn read_transcript_row<T>(
        &self,
        request: &TranscriptRowRequest,
        read: impl FnOnce(&TranscriptItem) -> Option<T>,
    ) -> Result<T, IpcError> {
        let publication = self.publication.borrow();
        if !publication.owns_workspace(request.workspace_id) {
            return Err(IpcError::RetiredWorkspace);
        }
        if publication.snapshot.navigation.selected_chat.as_ref() != Some(&request.chat_id)
            || publication.snapshot.transcript.generation != request.generation
        {
            return Err(IpcError::StaleSelection);
        }
        publication
            .snapshot
            .transcript
            .matching_row(&request.item_id, request.revision)
            .and_then(read)
            .ok_or(IpcError::StaleSelection)
    }

    pub fn subscribe(&mut self) -> WorkspaceSubscription {
        let subscription_id = SubscriptionId(Uuid::new_v4());
        self.pending_poll = Weak::new();
        self.publication
            .send_modify(|publication| publication.subscriber = Some(subscription_id));
        WorkspaceSubscription {
            subscription_id,
            snapshot: self.publication.borrow().snapshot.clone(),
        }
    }

    pub fn poll(&mut self, request: WorkspaceUpdateRequest) -> Option<WorkspacePoll> {
        if self.publication.borrow().subscriber != Some(request.subscription_id)
            || self.pending_poll.strong_count() != 0
        {
            return None;
        }
        let permit = Arc::new(());
        self.pending_poll = Arc::downgrade(&permit);
        Some(WorkspacePoll {
            request,
            receiver: self.publication.subscribe(),
            _permit: permit,
        })
    }
}

pub struct WorkspacePoll {
    request: WorkspaceUpdateRequest,
    receiver: watch::Receiver<Publication>,
    _permit: Arc<()>,
}

impl WorkspacePoll {
    pub async fn wait(mut self, max_wait: Duration) -> WorkspaceUpdate {
        timeout(max_wait, self.next())
            .await
            .unwrap_or(WorkspaceUpdate::Idle)
    }

    async fn next(&mut self) -> WorkspaceUpdate {
        loop {
            {
                let current = self.receiver.borrow_and_update();
                if current.subscriber != Some(self.request.subscription_id) {
                    return WorkspaceUpdate::Retired;
                }
                let revision = current.snapshot.revision;
                if revision != self.request.after_revision {
                    return if self.request.after_revision.checked_add(1) == Some(revision) {
                        current.adjacent_update()
                    } else {
                        WorkspaceUpdate::Resync
                    };
                }
            }
            if self.receiver.changed().await.is_err() {
                return WorkspaceUpdate::Retired;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ipc::{TextBatcher, TranscriptCommand};

    #[tokio::test]
    async fn prepends_only_new_rows_and_retains_the_current_history_generation() {
        let mut projection = WorkspaceProjection::default();
        let workspace_id = WorkspaceId(Uuid::new_v4());
        let workspace = WorkspaceView {
            workspace_id,
            project_path: "project".into(),
        };
        let navigation = NavigationView {
            selected_chat: Some("chat".into()),
            ..NavigationView::default()
        };
        let message = |id: &str, text: &str| {
            TranscriptItem::message(
                id.into(),
                "turn".into(),
                text.into(),
                false,
                TranscriptRole::Assistant,
            )
        };
        let mut current = TranscriptView::default();
        current.push_message(message("visible", "current content"));
        projection.replace_history(Some(workspace), navigation.clone(), current);
        let initial = projection.subscribe();
        let mut earlier = TranscriptView::default();
        earlier.push_message(message("oldest", "earlier content"));
        earlier.push_message(message("visible", "stale overlapping content"));
        assert!(projection.prepend_history(workspace_id, navigation.clone(), earlier));
        let request = WorkspaceUpdateRequest {
            subscription_id: initial.subscription_id,
            after_revision: initial.snapshot.revision,
        };
        let WorkspaceUpdate::History(update) =
            projection.poll(request).unwrap().wait(Duration::ZERO).await
        else {
            panic!("expected an adjacent history insertion");
        };
        assert_eq!(update.insertions.len(), 1);
        assert_eq!(update.insertions[0].position, 0);
        assert_eq!(update.insertions[0].rows.len(), 1);
        assert_eq!(update.insertions[0].rows[0].item_id, "oldest");
        let after = projection.subscribe().snapshot.transcript;
        assert_eq!(after.generation, initial.snapshot.transcript.generation);
        assert_eq!(after.items[1], initial.snapshot.transcript.items[0]);
        let mut batcher = TextBatcher::default();
        batcher.append("visible".into(), " continues".into());
        assert!(projection.publish_stream(workspace_id, batcher.flush().unwrap()));
        let continued = projection.subscribe().snapshot.transcript;
        assert_eq!(continued.items[0], after.items[0]);
        assert_eq!(continued.items[1].text, "current content continues");
        let other = NavigationView {
            selected_chat: Some("other".into()),
            ..navigation
        };
        assert!(!projection.prepend_history(workspace_id, other, TranscriptView::default()));
    }

    #[test]
    fn updates_only_the_target_row_and_keeps_finished_copy_scoped_to_the_original_source() {
        let mut projection = WorkspaceProjection::default();
        let workspace_id = WorkspaceId(Uuid::new_v4());
        let workspace = WorkspaceView {
            workspace_id,
            project_path: "project".into(),
        };
        let navigation = NavigationView {
            selected_chat: Some("chat".into()),
            ..NavigationView::default()
        };
        let exact = "  First \n\n```txt\n日本語 👩🏽‍💻\n```\n";
        let mut history = TranscriptView::default();
        history.push_message(TranscriptItem::message(
            "turn/finished".into(),
            "turn".into(),
            exact.into(),
            true,
            TranscriptRole::Assistant,
        ));
        projection.replace_history(Some(workspace.clone()), navigation.clone(), history.clone());
        let initial = projection.subscribe().snapshot;
        let old = initial.transcript.items[0].clone();
        let mut request = TranscriptRowRequest {
            workspace_id,
            chat_id: "chat".into(),
            generation: initial.transcript.generation,
            item_id: old.item_id.clone(),
            revision: old.revision,
        };
        let mut batch = TextBatcher::default();
        batch.append("newer/fresh".into(), "new reply".into());
        assert!(projection.publish_stream(workspace_id, batch.flush().unwrap()));
        let current = projection.subscribe().snapshot;
        assert_eq!(current.transcript.items[0], old);
        assert_eq!(projection.copy_transcript_source(&request).unwrap(), exact);
        request.item_id = "newer/fresh".into();
        assert_eq!(
            projection.copy_transcript_source(&request),
            Err(IpcError::StaleSelection)
        );
        request.item_id = old.item_id;
        projection.replace_history(Some(workspace), navigation, history);
        assert_eq!(
            projection.copy_transcript_source(&request),
            Err(IpcError::StaleSelection)
        );
    }

    #[test]
    fn appends_command_groups_and_changes_only_the_group_that_owns_the_update() {
        let mut view = TranscriptView::default();
        let command = |id: &str, completed, body: Option<&str>| CommandUpdate::Item {
            turn_id: "turn".into(),
            command: TranscriptCommand {
                id: id.into(),
                command: format!("command {id}"),
                output: body.map(str::to_owned),
                completed,
                exit_code: completed.then_some(0),
            },
        };
        let first = view
            .apply_command(command("turn/a", false, None))
            .unwrap()
            .item_id
            .clone();
        let group = view.apply_command(command("turn/b", false, None)).unwrap();
        assert_eq!(group.item_id, first);
        assert_eq!(group.commands.len(), 2);
        view.push_message(TranscriptItem::message(
            "turn/message".into(),
            "turn".into(),
            "reply".into(),
            true,
            TranscriptRole::Assistant,
        ));
        let untouched = view
            .apply_command(command("turn/c", true, Some("new group")))
            .unwrap()
            .clone();
        let first_revision = view.items[0].revision;
        let changed = view
            .apply_command(CommandUpdate::Output {
                item_id: "turn/a".into(),
                delta: "local output\n".into(),
            })
            .unwrap();
        assert_eq!(changed.item_id, first);
        assert_eq!(changed.revision, first_revision + 1);
        assert!(changed.commands[1].output.is_none());
        assert_eq!(view.items[2], untouched);
        let completed = view.apply_command(command("turn/a", true, None)).unwrap();
        assert_eq!(
            completed.commands[0].output.as_deref(),
            Some("local output\n")
        );
        assert!(
            view.apply_command(CommandUpdate::Output {
                item_id: "turn/a".into(),
                delta: "late".into()
            })
            .is_none()
        );
    }

    #[tokio::test]
    async fn bounded_subscription_catches_adjacent_updates_and_resyncs_after_replacement_or_lag() {
        let mut projection = WorkspaceProjection::default();
        let view = WorkspaceView {
            workspace_id: WorkspaceId(Uuid::new_v4()),
            project_path: "first".into(),
        };
        projection.publish(Some(view.clone()));
        let first = projection.subscribe();
        assert_eq!(first.snapshot.workspace, Some(view.clone()));
        let request =
            |subscription: &WorkspaceSubscription, after_revision| WorkspaceUpdateRequest {
                subscription_id: subscription.subscription_id,
                after_revision,
            };
        let waiting = projection.poll(request(&first, 1)).unwrap();
        assert!(projection.poll(request(&first, 1)).is_none());
        let publish = async {
            tokio::task::yield_now().await;
            projection.publish(None);
        };
        let (update, ()) = tokio::join!(biased; waiting.wait(Duration::from_secs(1)), publish);
        assert_eq!(
            update,
            WorkspaceUpdate::Changed(WorkspaceSnapshot {
                revision: 2,
                ..WorkspaceSnapshot::default()
            })
        );
        let lagging = projection.poll(request(&first, 2)).unwrap();
        projection.publish(Some(view.clone()));
        projection.publish(None);
        projection.publish(Some(view.clone()));
        assert_eq!(lagging.wait(Duration::ZERO).await, WorkspaceUpdate::Resync);

        let waiting = projection.poll(request(&first, 5)).unwrap();
        let fresh = projection.subscribe();
        assert_eq!(
            fresh.snapshot,
            WorkspaceSnapshot {
                revision: 5,
                workspace: Some(view),
                ..WorkspaceSnapshot::default()
            }
        );
        assert_eq!(waiting.wait(Duration::ZERO).await, WorkspaceUpdate::Retired);
        assert!(projection.poll(request(&first, 5)).is_none());
        let idle = projection.poll(request(&fresh, 5)).unwrap();
        assert_eq!(idle.wait(Duration::ZERO).await, WorkspaceUpdate::Idle);
        assert!(projection.poll(request(&fresh, 5)).is_some());
    }

    #[tokio::test]
    async fn transcript_batches_flush_before_terminals_and_reconnect_to_the_same_text() {
        let mut projection = WorkspaceProjection::default();
        let workspace_id = WorkspaceId(Uuid::new_v4());
        projection.publish(Some(WorkspaceView {
            workspace_id,
            project_path: "first".into(),
        }));
        let initial = projection.subscribe();
        let mut batcher = TextBatcher::default();
        assert!(batcher.append("first".into(), "café ".into()).is_none());
        assert!(batcher.append("second".into(), "日本語".into()).is_none());
        assert!(batcher.append("first".into(), "👩🏽‍💻".into()).is_none());
        let mut finishing = batcher.finish(StreamChange::ItemCompleted("first".into()));
        let text = finishing.next().unwrap();
        let terminal = finishing.next().unwrap();
        assert!(finishing.next().is_none());
        assert!(projection.publish_stream(workspace_id, text.clone()));
        let request = WorkspaceUpdateRequest {
            subscription_id: initial.subscription_id,
            after_revision: initial.snapshot.revision,
        };
        assert_eq!(
            projection.poll(request).unwrap().wait(Duration::ZERO).await,
            WorkspaceUpdate::Stream(RevisionedStream {
                change: text,
                revision: 2
            }),
        );
        let reconnect = projection.subscribe();
        assert_eq!(reconnect.snapshot.transcript.items[0].text, "café 👩🏽‍💻");
        assert_eq!(reconnect.snapshot.transcript.items[1].text, "日本語");
        assert!(!reconnect.snapshot.transcript.items[0].completed);
        assert!(projection.publish_stream(workspace_id, terminal));
        assert!(batcher.append("first".into(), "late".into()).is_none());
        assert!(!projection.publish_stream(workspace_id, batcher.flush().unwrap()));
        assert!(projection.publish_stream(workspace_id, StreamChange::Completed));
        let complete = projection.subscribe();
        assert!(complete.snapshot.transcript.completed);
        assert_eq!(complete.snapshot.transcript.items[0].text, "café 👩🏽‍💻");
        projection.publish(None);
        assert!(!projection.publish_stream(workspace_id, StreamChange::Completed));
        assert!(projection.subscribe().snapshot.transcript.items.is_empty());
    }
}
