use codex_gui_core::{
    codex::{
        AppServerClient, AppServerConnection, ClientInfo, CodexBrowser, CodexExecutable,
        HistoryTurn,
    },
    identity::ThreadId,
    storage::attachments::ExitOwner,
    workspace::{OwnerError, RuntimeOwners},
};

use super::{Failure, Navigation, RPC_TIMEOUT};

const MAX_RECOVERY_PAGES: usize = 8;

impl Navigation {
    pub(super) fn recover_hidden_owners(&self, current: AppServerClient) {
        let owners = self.owners.clone();
        tauri::async_runtime::spawn(async move {
            let candidates = match owners.exit_owners() {
                Ok(candidates) => candidates,
                Err(error) => {
                    eprintln!("{error}");
                    return;
                }
            };
            for candidate in candidates {
                if let Err(error) = reconcile_hidden_owner(&owners, &current, candidate).await
                    && !matches!(
                        error.downcast_ref::<OwnerError>(),
                        Some(OwnerError::Retired)
                    )
                {
                    eprintln!("{error}");
                }
            }
        });
    }
}

async fn reconcile_hidden_owner(
    owners: &RuntimeOwners,
    current: &AppServerClient,
    candidate: ExitOwner,
) -> Result<(), Failure> {
    let Some(checkout) = candidate.restore() else {
        return Ok(());
    };
    if current.identity().workspace.checkout.as_ref() == Some(&checkout) {
        return reconcile_threads(current, candidate.threads, |thread, history| {
            owners.reconcile_history(current.identity(), thread, history)
        })
        .await;
    }
    let Some(recovery) = owners.begin_recovery(checkout)? else {
        return Ok(());
    };
    let executable = CodexExecutable::discover(None)?;
    let connection = AppServerConnection::connect(
        &executable,
        recovery.identity().clone(),
        ClientInfo {
            name: "codex_gui",
            title: "Codex GUI",
            version: env!("CARGO_PKG_VERSION"),
        },
        RPC_TIMEOUT,
    )
    .await?;
    let result = reconcile_threads(
        &connection.client(),
        candidate.threads,
        |thread, history| recovery.reconcile(thread, history),
    )
    .await;
    let shutdown = connection.disconnect().await;
    result?;
    shutdown?;
    Ok(())
}

async fn reconcile_threads(
    client: &AppServerClient,
    threads: Vec<ThreadId>,
    apply: impl Fn(&ThreadId, &[HistoryTurn]) -> Result<bool, OwnerError>,
) -> Result<(), Failure> {
    let browser = CodexBrowser::new(client.clone());
    for thread in threads {
        let result: Result<(), Failure> = async {
            let summary = browser.thread_summary(&thread, RPC_TIMEOUT).await?;
            let mut cursor = None;
            for _ in 0..MAX_RECOVERY_PAGES {
                let read = browser
                    .history(&summary, cursor.as_ref(), RPC_TIMEOUT)
                    .await?;
                let page = read.for_selection(client.identity(), &thread)?;
                if !apply(&thread, &page.data)? {
                    break;
                }
                cursor.clone_from(&page.next_cursor);
                if cursor.is_none() {
                    break;
                }
            }
            Ok(())
        }
        .await;
        if let Err(error) = result {
            if matches!(
                error.downcast_ref::<OwnerError>(),
                Some(OwnerError::Retired)
            ) {
                return Err(error);
            }
            eprintln!("{error}");
        }
    }
    Ok(())
}
