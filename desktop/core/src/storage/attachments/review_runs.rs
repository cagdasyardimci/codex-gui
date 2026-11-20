use rusqlite::{Transaction, TransactionBehavior, params};
use uuid::Uuid;

use crate::{
    checkout::CheckoutIdentity,
    identity::ThreadId,
    storage::drafts::{DraftId, DraftRevision, DraftSave, read_draft, save_in_transaction},
};

use super::{AttachmentError, AttachmentStore};

#[derive(Clone, Copy)]
pub struct ReviewReservation {
    pub request: Uuid,
    pub draft: DraftId,
    pub revision: DraftRevision,
}

pub(crate) fn migrate(transaction: &Transaction<'_>) -> rusqlite::Result<()> {
    transaction.execute_batch(
        "CREATE TABLE desktop_review_reservations (
            checkout TEXT NOT NULL,
            source TEXT NOT NULL,
            request BLOB NOT NULL,
            PRIMARY KEY (checkout, source)
        ) WITHOUT ROWID;",
    )
}

impl AttachmentStore {
    pub fn has_review_reservation(
        &self,
        checkout: &CheckoutIdentity,
        source: &ThreadId,
    ) -> Result<bool, AttachmentError> {
        let state = self.inner.state();
        Ok(state.database.query_row(
            "SELECT EXISTS (SELECT 1 FROM desktop_review_reservations WHERE checkout = ?1 AND source = ?2)",
            params![checkout.storage_key(), source.0],
            |row| row.get(0),
        )?)
    }

    pub fn reserve_review(
        &self,
        checkout: &CheckoutIdentity,
        source: &ThreadId,
        request: Uuid,
    ) -> Result<bool, AttachmentError> {
        let state = self.inner.state();
        Ok(state.database.execute(
            "INSERT OR IGNORE INTO desktop_review_reservations VALUES (?1, ?2, ?3)",
            params![
                checkout.storage_key(),
                source.0,
                request.as_bytes().as_slice()
            ],
        )? == 1)
    }

    pub fn settle_review(
        &self,
        checkout: &CheckoutIdentity,
        source: &ThreadId,
        reservation: ReviewReservation,
        accepted: bool,
    ) -> Result<bool, AttachmentError> {
        let mut state = self.inner.state();
        let tx = state
            .database
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        let removed = tx.execute(
            "DELETE FROM desktop_review_reservations WHERE checkout = ?1 AND source = ?2 AND request = ?3",
            params![checkout.storage_key(), source.0, reservation.request.as_bytes().as_slice()],
        )?;
        let consumed = if removed != 0
            && accepted
            && let Some(current) = read_draft(&tx, reservation.draft)?
            && current.revision == reservation.revision
        {
            let revision = current
                .revision
                .next()
                .ok_or_else(|| std::io::Error::other("draft revision exhausted"))?;
            save_in_transaction(
                &tx,
                reservation.draft,
                Some(current.revision),
                revision,
                Some(""),
                None,
            )? == DraftSave::Applied
        } else {
            false
        };
        tx.commit()?;
        Ok(consumed)
    }
}
