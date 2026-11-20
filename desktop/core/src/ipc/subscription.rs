use std::sync::{Arc, Weak};
use std::time::Duration;

use serde::{Deserialize, Serialize};
use tokio::{sync::watch, time::timeout};
use ts_rs::TS;
use uuid::Uuid;

use super::WorkspaceView;

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize, TS)]
pub struct SubscriptionId(Uuid);

#[derive(Clone, Debug, Default, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct WorkspaceSnapshot {
    pub revision: u32,
    pub workspace: Option<WorkspaceView>,
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
pub enum WorkspaceUpdate {
    Changed(WorkspaceSnapshot),
    Resync,
    Retired,
    Idle,
}

#[derive(Default)]
struct Publication {
    subscriber: Option<SubscriptionId>,
    snapshot: WorkspaceSnapshot,
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
            publication.snapshot.revision = publication
                .snapshot
                .revision
                .checked_add(1)
                .expect("workspace projection exhausted its revision range");
            publication.snapshot.workspace = workspace;
            true
        });
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
                        WorkspaceUpdate::Changed(current.snapshot.clone())
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
    use crate::ipc::WorkspaceId;

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
                workspace: None
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
                workspace: Some(view)
            }
        );
        assert_eq!(waiting.wait(Duration::ZERO).await, WorkspaceUpdate::Retired);
        assert!(projection.poll(request(&first, 5)).is_none());
        let idle = projection.poll(request(&fresh, 5)).unwrap();
        assert_eq!(idle.wait(Duration::ZERO).await, WorkspaceUpdate::Idle);
        assert!(projection.poll(request(&fresh, 5)).is_some());
    }
}
