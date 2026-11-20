use std::{collections::HashMap, time::Duration};

use indexmap::IndexMap;

use super::{
    SubmissionAcknowledgement, SubmissionError, WorkspaceEngine, WorkspaceError,
    submission::message_client_id,
};
use crate::{
    codex::{AppServerClient, BrowseError, ChatRead, ChatSummary, CodexBrowser, QueueSnapshot},
    identity::{ConnectionIdentity, OperationIdentity, RequestId, ThreadId, TurnId},
    storage::attachments::{AttachmentStore, JournalOutcome, JournalPhase, PendingSubmission},
};

const MAX_HISTORY_PAGES: usize = 25;

#[derive(Debug, Default)]
pub struct SubmissionRecovery {
    pub unsent: Vec<RequestId>,
    pub acknowledged: Vec<RequestId>,
    pub unresolved: Vec<RequestId>,
    pub read_failures: Vec<(ThreadId, BrowseError)>,
}

impl WorkspaceEngine {
    pub async fn recover_submissions(
        &self,
        client: &AppServerClient,
        store: &AttachmentStore,
        timeout: Duration,
    ) -> Result<SubmissionRecovery, SubmissionError> {
        let connection = client.identity();
        if connection != &self.snapshot().connection {
            return Err(WorkspaceError::Retired.into());
        }
        let checkout = connection
            .workspace
            .checkout
            .clone()
            .ok_or(WorkspaceError::MissingCheckout)?;
        let journal = store.clone();
        let captured = checkout.clone();
        let pending = tokio::task::spawn_blocking(move || {
            captured.revalidate()?;
            Ok::<_, SubmissionError>(journal.pending_submissions(&captured)?)
        })
        .await??;
        let mut result = SubmissionRecovery::default();
        let mut threads = IndexMap::<_, Vec<_>>::new();
        for entry in pending {
            if !entry.matches_checkout {
                result.unresolved.push(entry.id);
            } else if entry.reserved {
                let commit = self.preparation_commit.clone().lock_owned().await;
                if connection != &self.snapshot().connection {
                    return Err(WorkspaceError::Retired.into());
                }
                let captured = checkout.clone();
                let journal = store.clone();
                tokio::task::spawn_blocking(move || {
                    let _commit = commit;
                    captured.revalidate()?;
                    Ok::<_, SubmissionError>(
                        journal.set_submission_phase(entry.id, JournalPhase::Unsent)?,
                    )
                })
                .await??;
                result.unsent.push(entry.id);
            } else {
                threads.entry(entry.thread.clone()).or_default().push(entry);
            }
        }

        let browser = CodexBrowser::new(client.clone());
        for (thread, entries) in threads {
            let any_queue_add = entries.iter().any(|entry| entry.queue_add);
            let summary = match browser.thread_summary(&thread, timeout).await {
                Ok(summary) => summary,
                Err(error) => {
                    result
                        .unresolved
                        .extend(entries.iter().map(|entry| entry.id));
                    result.read_failures.push((thread, error));
                    continue;
                }
            };
            let mut requests = entries.iter().map(|entry| entry.id).collect::<Vec<_>>();
            if any_queue_add {
                let queue = browser
                    .queue_snapshot(&summary, timeout)
                    .await
                    .and_then(|snapshot| snapshot.into_for_selection(connection, &thread));
                match queue {
                    Ok(QueueSnapshot::Available(queued)) => {
                        let mut queue_evidence = HashMap::new();
                        for item in queued {
                            if let Ok(client) = uuid::Uuid::parse_str(&item.client_user_message_id)
                            {
                                queue_evidence
                                    .entry(RequestId(client))
                                    .and_modify(|receipt| *receipt = None)
                                    .or_insert(Some(item.id));
                            }
                        }
                        requests.clear();
                        for entry in entries {
                            match (entry.queue_add, queue_evidence.remove(&entry.id)) {
                                (true, Some(Some(queued_id))) => {
                                    self.recover_queue_receipt(
                                        connection,
                                        &entry,
                                        queued_id,
                                        store,
                                        &mut result,
                                    )
                                    .await?;
                                }
                                (true, Some(None)) => result.unresolved.push(entry.id),
                                _ => requests.push(entry.id),
                            }
                        }
                    }
                    Ok(QueueSnapshot::Unsupported) => {}
                    Err(error) => result.read_failures.push((thread.clone(), error)),
                }
            }
            if requests.is_empty() {
                continue;
            }
            let mut evidence =
                match history_evidence(&browser, &summary, connection, &thread, &requests, timeout)
                    .await
                {
                    Ok(evidence) => evidence,
                    Err(error) => {
                        result.unresolved.extend(requests);
                        result.read_failures.push((thread, error));
                        continue;
                    }
                };
            for request in requests {
                if let Some(Evidence::Unique(turn)) = evidence.remove(&request) {
                    let operation = OperationIdentity {
                        connection: connection.clone(),
                        request,
                    };
                    let acknowledgement = self
                        .acknowledge(&operation, &thread, JournalOutcome::Accepted(turn), store)
                        .await?;
                    if matches!(
                        acknowledgement,
                        SubmissionAcknowledgement::Accepted { .. }
                            | SubmissionAcknowledgement::Duplicate
                    ) {
                        result.acknowledged.push(request);
                        continue;
                    }
                }
                result.unresolved.push(request);
            }
        }
        Ok(result)
    }

    async fn recover_queue_receipt(
        &self,
        connection: &ConnectionIdentity,
        entry: &PendingSubmission,
        queued_id: String,
        store: &AttachmentStore,
        result: &mut SubmissionRecovery,
    ) -> Result<(), SubmissionError> {
        if let Some(known) = &entry.queued_id {
            if known != &queued_id {
                result.unresolved.push(entry.id);
            }
            return Ok(());
        }
        let operation = OperationIdentity {
            connection: connection.clone(),
            request: entry.id,
        };
        let acknowledgement = self
            .acknowledge(
                &operation,
                &entry.thread,
                JournalOutcome::Queued(queued_id),
                store,
            )
            .await?;
        if matches!(
            acknowledgement,
            SubmissionAcknowledgement::Queued { .. } | SubmissionAcknowledgement::Duplicate
        ) {
            result.acknowledged.push(entry.id);
        } else {
            result.unresolved.push(entry.id);
        }
        Ok(())
    }
}

enum Evidence {
    Missing,
    Unique(TurnId),
    Conflicting,
}

async fn history_evidence(
    browser: &CodexBrowser,
    chat: &ChatRead<ChatSummary>,
    connection: &ConnectionIdentity,
    thread: &ThreadId,
    requests: &[RequestId],
    timeout: Duration,
) -> Result<HashMap<RequestId, Evidence>, BrowseError> {
    let mut cursor = None;
    let mut wanted: HashMap<_, _> = requests.iter().map(|id| (*id, Evidence::Missing)).collect();
    for _ in 0..MAX_HISTORY_PAGES {
        let page = browser
            .history(chat, cursor.as_ref(), timeout)
            .await?
            .into_for_selection(connection, thread)?;
        for turn in &page.data {
            if turn.activity.id.0.is_empty() {
                continue;
            }
            for client in turn.items.iter().filter_map(message_client_id) {
                if let Some(evidence) = wanted.get_mut(&client) {
                    match evidence {
                        Evidence::Missing => *evidence = Evidence::Unique(turn.activity.id.clone()),
                        Evidence::Unique(id) if id != &turn.activity.id => {
                            *evidence = Evidence::Conflicting
                        }
                        _ => {}
                    }
                }
            }
        }
        cursor = page.next_cursor;
        if cursor.is_none() {
            return Ok(wanted);
        }
    }
    // Incomplete history cannot rule out conflicting matches on unread pages.
    Ok(HashMap::new())
}
