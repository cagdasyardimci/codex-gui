use std::io;

use rusqlite::{Connection, OptionalExtension, Transaction, TransactionBehavior, params};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use uuid::Uuid;

use crate::checkout::CheckoutIdentity;

use super::{AttachmentError, AttachmentStore, DraftId, read_draft, save_in_transaction};

#[derive(Debug, Default, Deserialize, Serialize)]
pub struct ComposerPlan {
    pub enabled: bool,
    pub pending: Option<PlanUpdate>,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct PlanUpdate {
    pub draft_id: String,
    pub source: String,
    pub mode: Value,
}

impl AttachmentStore {
    pub fn composer_plan(
        &self,
        checkout: &CheckoutIdentity,
        thread: Option<&str>,
    ) -> Result<ComposerPlan, AttachmentError> {
        checkout.revalidate().map_err(io::Error::other)?;
        let state = self.inner.state();
        let content: Option<String> = state
            .database
            .query_row(
                "SELECT state FROM composer_plan_modes WHERE checkout_key = ?1 AND thread_id = ?2",
                params![checkout.storage_key(), thread.unwrap_or_default()],
                |row| row.get(0),
            )
            .optional()?;
        match content {
            Some(content) => Ok(serde_json::from_str(&content).map_err(io::Error::other)?),
            None => Ok(ComposerPlan::default()),
        }
    }

    pub fn save_composer_plan(
        &self,
        checkout: &CheckoutIdentity,
        thread: Option<&str>,
        plan: &ComposerPlan,
    ) -> Result<(), AttachmentError> {
        checkout.revalidate().map_err(io::Error::other)?;
        let state = self.inner.state();
        save_plan(&state.database, checkout, thread, plan)
    }

    pub fn settle_composer_plan(
        &self,
        checkout: &CheckoutIdentity,
        thread: Option<&str>,
        enabled: bool,
        command: Option<(&str, &str)>,
    ) -> Result<(), AttachmentError> {
        checkout.revalidate().map_err(io::Error::other)?;
        let mut state = self.inner.state();
        let transaction = state
            .database
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        save_plan(
            &transaction,
            checkout,
            thread,
            &ComposerPlan {
                enabled,
                pending: None,
            },
        )?;
        if let Some((id, source)) = command {
            let draft = DraftId(Uuid::parse_str(id).map_err(io::Error::other)?);
            if let Some(saved) =
                read_draft(&transaction, draft)?.filter(|draft| draft.text == source)
            {
                let revision = saved
                    .revision
                    .next()
                    .ok_or_else(|| io::Error::other("draft revision exhausted"))?;
                save_in_transaction(
                    &transaction,
                    draft,
                    Some(saved.revision),
                    revision,
                    Some(""),
                    None,
                )?;
            }
        }
        transaction.commit()?;
        Ok(())
    }
}

fn save_plan(
    database: &Connection,
    checkout: &CheckoutIdentity,
    thread: Option<&str>,
    plan: &ComposerPlan,
) -> Result<(), AttachmentError> {
    let content = serde_json::to_string(plan).map_err(io::Error::other)?;
    database.execute(
        "INSERT INTO composer_plan_modes (checkout_key, thread_id, state) VALUES (?1, ?2, ?3)
         ON CONFLICT (checkout_key, thread_id) DO UPDATE SET state = excluded.state",
        params![checkout.storage_key(), thread.unwrap_or_default(), content],
    )?;
    Ok(())
}

pub(in crate::storage) fn migrate(transaction: &Transaction<'_>) -> rusqlite::Result<()> {
    transaction.execute_batch(
        "CREATE TABLE composer_plan_modes (
        checkout_key TEXT NOT NULL, thread_id TEXT NOT NULL,
        state TEXT NOT NULL CHECK (json_valid(state) AND json_type(state) = 'object'),
        PRIMARY KEY (checkout_key, thread_id)
    ) STRICT, WITHOUT ROWID;",
    )
}
