use std::{collections::HashMap, time::Duration};

use indexmap::IndexMap;

use super::{
    SubmissionAcknowledgement, SubmissionError, WorkspaceEngine, WorkspaceError,
    submission::message_client_id,
};
use crate::{
    codex::{AppServerClient, BrowseError, CodexBrowser},
    identity::{ConnectionIdentity, OperationIdentity, RequestId, ThreadId, TurnId},
    storage::attachments::{AttachmentStore, JournalOutcome, JournalPhase},
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
                threads.entry(entry.thread).or_default().push(entry.id);
            }
        }

        let browser = CodexBrowser::new(client.clone());
        for (thread, requests) in threads {
            let mut evidence =
                match history_evidence(&browser, connection, &thread, &requests, timeout).await {
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
}

enum Evidence {
    Missing,
    Unique(TurnId),
    Conflicting,
}

async fn history_evidence(
    browser: &CodexBrowser,
    connection: &ConnectionIdentity,
    thread: &ThreadId,
    requests: &[RequestId],
    timeout: Duration,
) -> Result<HashMap<RequestId, Evidence>, BrowseError> {
    let chat = browser.thread_summary(thread, timeout).await?;
    let mut cursor = None;
    let mut wanted: HashMap<_, _> = requests.iter().map(|id| (*id, Evidence::Missing)).collect();
    for _ in 0..MAX_HISTORY_PAGES {
        let page = browser
            .history(&chat, cursor.as_ref(), timeout)
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
