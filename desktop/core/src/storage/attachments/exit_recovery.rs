use std::{collections::BTreeMap, io, path::PathBuf};

use rusqlite::{Transaction, TransactionBehavior, params};

use crate::{
    checkout::CheckoutIdentity,
    codex::{HistoryTurn, TurnStatus},
    identity::ThreadId,
    workspace::{ExecutionSnapshot, ExecutionTarget},
};

use super::{AttachmentError, AttachmentStore};

pub struct ExitOwner {
    checkout_path: PathBuf,
    checkout_key: String,
    pub threads: Vec<ThreadId>,
}

impl ExitOwner {
    pub fn restore(&self) -> Option<CheckoutIdentity> {
        let checkout = CheckoutIdentity::capture(&self.checkout_path).ok()?;
        (checkout.storage_key() == self.checkout_key).then_some(checkout)
    }
}

impl AttachmentStore {
    pub fn preserve_exit_executions(
        &self,
        checkout: &CheckoutIdentity,
        execution: &ExecutionSnapshot,
    ) -> Result<(), AttachmentError> {
        if execution.active_turns.is_empty() && execution.unresolved_commands.is_empty() {
            return Ok(());
        }
        let key = checkout.storage_key();
        let mut state = self.inner.state();
        let transaction = state
            .database
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        remember_checkout(&transaction, checkout, &key)?;
        for target in &execution.active_turns {
            record(&transaction, &key, target, "")?;
        }
        for command in &execution.unresolved_commands {
            record(&transaction, &key, &command.target, &command.item)?;
        }
        transaction.commit()?;
        Ok(())
    }

    pub(crate) fn record_execution_transition(
        &self,
        checkout: &CheckoutIdentity,
        before: &ExecutionSnapshot,
        after: &ExecutionSnapshot,
    ) -> Result<(), AttachmentError> {
        if before == after {
            return Ok(());
        }
        let key = checkout.storage_key();
        let mut state = self.inner.state();
        let transaction = state
            .database
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        if !after.active_turns.is_empty() || !after.unresolved_commands.is_empty() {
            remember_checkout(&transaction, checkout, &key)?;
        }
        for target in &after.active_turns {
            record(&transaction, &key, target, "")?;
        }
        for command in &after.unresolved_commands {
            record(&transaction, &key, &command.target, &command.item)?;
        }
        for target in &before.active_turns {
            if !after.active_turns.contains(target) {
                clear(&transaction, &key, &target.thread, &target.turn.0, "")?;
            }
        }
        for command in &before.unresolved_commands {
            if !after.unresolved_commands.contains(command) {
                clear(
                    &transaction,
                    &key,
                    &command.target.thread,
                    &command.target.turn.0,
                    &command.item,
                )?;
            }
        }
        prune_checkout(&transaction, &key)?;
        transaction.commit()?;
        Ok(())
    }

    pub fn exit_owners(&self) -> Result<Vec<ExitOwner>, AttachmentError> {
        let state = self.inner.state();
        let mut query = state.database.prepare(
            "SELECT DISTINCT e.checkout_key, p.checkout_path, e.thread_id
             FROM exit_recovery e JOIN exit_checkout_paths p USING (checkout_key)
             ORDER BY e.checkout_key, e.thread_id",
        )?;
        let mut grouped = BTreeMap::new();
        let rows = query.query_map([], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
            ))
        })?;
        for row in rows {
            let (checkout_key, path, thread) = row?;
            let scope = grouped
                .entry(checkout_key.clone())
                .or_insert_with(|| ExitOwner {
                    checkout_path: PathBuf::from(path),
                    checkout_key,
                    threads: Vec::new(),
                });
            scope.threads.push(ThreadId(thread));
        }
        Ok(grouped.into_values().collect())
    }

    pub(crate) fn has_exit_evidence(
        &self,
        checkout: &CheckoutIdentity,
        thread: Option<&ThreadId>,
    ) -> Result<bool, AttachmentError> {
        let state = self.inner.state();
        Ok(state.database.query_row(
            "SELECT EXISTS (SELECT 1 FROM exit_recovery
             WHERE checkout_key = ?1 AND (?2 IS NULL OR thread_id = ?2))",
            params![checkout.storage_key(), thread.map(|thread| &thread.0)],
            |row| row.get(0),
        )?)
    }

    pub fn reconcile_exit_history(
        &self,
        checkout: &CheckoutIdentity,
        thread: &ThreadId,
        history: &[HistoryTurn],
    ) -> Result<(), AttachmentError> {
        checkout.revalidate().map_err(std::io::Error::other)?;
        let key = checkout.storage_key();
        let mut state = self.inner.state();
        let exists: bool = state.database.query_row(
            "SELECT EXISTS (SELECT 1 FROM exit_recovery WHERE checkout_key = ?1 AND thread_id = ?2)",
            params![key, thread.0],
            |row| row.get(0),
        )?;
        if !exists {
            return Ok(());
        }
        let transaction = state
            .database
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        for turn in history {
            let id = &turn.activity.id.0;
            if matches!(
                turn.activity.status,
                TurnStatus::Completed | TurnStatus::Interrupted | TurnStatus::Failed
            ) {
                clear(&transaction, &key, thread, id, "")?;
            }
            for item in &turn.items {
                if item["type"] == "commandExecution"
                    && matches!(
                        item["status"].as_str(),
                        Some("completed" | "failed" | "declined")
                    )
                    && let Some(item) = item["id"].as_str().filter(|item| !item.is_empty())
                {
                    clear(&transaction, &key, thread, id, item)?;
                }
            }
        }
        prune_checkout(&transaction, &key)?;
        transaction.commit()?;
        Ok(())
    }
}

fn remember_checkout(
    transaction: &Transaction<'_>,
    checkout: &CheckoutIdentity,
    key: &str,
) -> Result<(), AttachmentError> {
    let path = checkout
        .canonical_path()
        .to_str()
        .ok_or_else(|| io::Error::from(io::ErrorKind::InvalidInput))?;
    transaction.execute(
        "INSERT INTO exit_checkout_paths (checkout_key, checkout_path) VALUES (?1, ?2)
         ON CONFLICT (checkout_key) DO UPDATE SET checkout_path = excluded.checkout_path",
        params![key, path],
    )?;
    Ok(())
}

fn prune_checkout(transaction: &Transaction<'_>, key: &str) -> rusqlite::Result<()> {
    transaction.execute(
        "DELETE FROM exit_checkout_paths WHERE checkout_key = ?1
         AND NOT EXISTS (SELECT 1 FROM exit_recovery WHERE checkout_key = ?1)",
        [key],
    )?;
    Ok(())
}

fn record(
    transaction: &Transaction<'_>,
    key: &str,
    target: &ExecutionTarget,
    item: &str,
) -> rusqlite::Result<()> {
    transaction.execute(
        "INSERT OR IGNORE INTO exit_recovery (checkout_key, thread_id, turn_id, item_id) VALUES (?1, ?2, ?3, ?4)",
        params![key, target.thread.0, target.turn.0, item],
    )?;
    Ok(())
}

fn clear(
    transaction: &Transaction<'_>,
    key: &str,
    thread: &ThreadId,
    turn: &str,
    item: &str,
) -> rusqlite::Result<()> {
    transaction.execute(
        "DELETE FROM exit_recovery WHERE checkout_key = ?1 AND thread_id = ?2 AND turn_id = ?3 AND item_id = ?4",
        params![key, thread.0, turn, item],
    )?;
    Ok(())
}

pub(in crate::storage) fn migrate(transaction: &Transaction<'_>) -> rusqlite::Result<()> {
    transaction.execute_batch(
        "CREATE TABLE exit_recovery (
            checkout_key TEXT NOT NULL,
            thread_id TEXT NOT NULL,
            turn_id TEXT NOT NULL,
            item_id TEXT NOT NULL,
            PRIMARY KEY (checkout_key, thread_id, turn_id, item_id)
        ) STRICT, WITHOUT ROWID;",
    )
}

pub(in crate::storage) fn migrate_checkout_paths(
    transaction: &Transaction<'_>,
) -> rusqlite::Result<()> {
    transaction.execute_batch(
        "CREATE TABLE exit_checkout_paths (
            checkout_key TEXT PRIMARY KEY,
            checkout_path TEXT NOT NULL
        ) STRICT, WITHOUT ROWID;
        INSERT INTO exit_checkout_paths (checkout_key, checkout_path)
        SELECT project_key, project_path FROM desktop_selection d
        WHERE EXISTS (SELECT 1 FROM exit_recovery e WHERE e.checkout_key = d.project_key);",
    )
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use crate::{identity::TurnId, workspace::CommandExecution};

    use super::*;

    #[test]
    fn turn_completion_clears_only_its_turn_evidence_until_the_command_exit_is_reported() {
        let scratch = tempfile::tempdir().unwrap();
        let checkout = CheckoutIdentity::capture(scratch.path()).unwrap();
        let store = AttachmentStore::open(&scratch.path().join("workspace.sqlite3")).unwrap();
        let target = ExecutionTarget {
            thread: ThreadId("thread".into()),
            turn: TurnId("turn".into()),
        };
        store
            .preserve_exit_executions(
                &checkout,
                &ExecutionSnapshot {
                    active_turns: vec![target.clone()],
                    unresolved_commands: vec![CommandExecution {
                        target: target.clone(),
                        item: "command".into(),
                    }],
                },
            )
            .unwrap();
        let count = || {
            store
                .inner
                .state()
                .database
                .query_row("SELECT COUNT(*) FROM exit_recovery", [], |row| {
                    row.get::<_, u32>(0)
                })
                .unwrap()
        };
        let turns = |items| {
            serde_json::from_value::<Vec<HistoryTurn>>(
                json!([{"id": "turn", "status": "interrupted", "items": items}]),
            )
            .unwrap()
        };
        store
            .reconcile_exit_history(&checkout, &ThreadId("other".into()), &turns(json!([])))
            .unwrap();
        assert_eq!(count(), 2);
        store
            .reconcile_exit_history(&checkout, &target.thread, &turns(json!([])))
            .unwrap();
        assert_eq!(count(), 1);
        store
            .reconcile_exit_history(
                &checkout,
                &target.thread,
                &turns(json!([
                    {"type": "commandExecution", "id": "command", "status": "completed"}
                ])),
            )
            .unwrap();
        assert_eq!(count(), 0);
    }
}
