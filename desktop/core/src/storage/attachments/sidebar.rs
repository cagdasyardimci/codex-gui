use std::{collections::HashMap, io, path::Path};

use rusqlite::{OptionalExtension, Row, Transaction, TransactionBehavior, params};
use serde::{Deserialize, Serialize};

use crate::{
    checkout::CheckoutIdentity,
    ipc::{
        ChatRow, SidebarChat, SidebarChatKey, SidebarGroup, SidebarProject, SidebarSort,
        SidebarView,
    },
};

use super::{AttachmentError, AttachmentStore};

#[derive(Debug, Default, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SidebarPreferences {
    pub group: SidebarGroup,
    pub sort: SidebarSort,
    pub order: Vec<SidebarChatKey>,
}

impl AttachmentStore {
    pub fn remember_sidebar_project(
        &self,
        checkout: &CheckoutIdentity,
    ) -> Result<(), AttachmentError> {
        checkout.revalidate().map_err(io::Error::other)?;
        let path = checkout
            .canonical_path()
            .to_str()
            .ok_or_else(|| io::Error::other("project path is not Unicode"))?;
        let state = self.inner.state();
        state.database.execute(
            "INSERT INTO desktop_projects (id, path, last_opened)
             VALUES (?1, ?2, (SELECT coalesce(max(last_opened), 0) + 1 FROM desktop_projects))
             ON CONFLICT(id) DO UPDATE SET path = excluded.path, last_opened = excluded.last_opened",
            params![checkout.storage_key(), path],
        )?;
        Ok(())
    }

    pub fn sidebar_project(&self, id: &str) -> Result<Option<SidebarProject>, AttachmentError> {
        let state = self.inner.state();
        Ok(state
            .database
            .query_row(
                "SELECT id, path, title, pinned FROM desktop_projects WHERE id = ?1",
                [id],
                row_project,
            )
            .optional()?)
    }

    pub fn rename_sidebar_project(&self, id: &str, title: &str) -> Result<bool, AttachmentError> {
        let state = self.inner.state();
        Ok(state.database.execute(
            "UPDATE desktop_projects SET title = ?2 WHERE id = ?1",
            params![id, title],
        )? == 1)
    }

    pub fn remove_sidebar_project(&self, id: &str) -> Result<(), AttachmentError> {
        let state = self.inner.state();
        state
            .database
            .execute("DELETE FROM desktop_projects WHERE id = ?1", [id])?;
        Ok(())
    }

    pub fn pin_sidebar_project(&self, id: &str, pinned: bool) -> Result<bool, AttachmentError> {
        let state = self.inner.state();
        Ok(state.database.execute(
            "UPDATE desktop_projects SET pinned = ?2 WHERE id = ?1",
            params![id, pinned],
        )? == 1)
    }

    pub fn remember_sidebar_chats(
        &self,
        checkout: &CheckoutIdentity,
        rows: impl IntoIterator<Item = (ChatRow, i64)>,
    ) -> Result<(), AttachmentError> {
        checkout.revalidate().map_err(io::Error::other)?;
        let project = checkout.storage_key();
        let mut state = self.inner.state();
        let transaction = state
            .database
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        {
            let mut upsert = transaction.prepare(
                "INSERT INTO desktop_sidebar_chats (project_id, thread_id, title, preview, updated_at, position)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6)
                 ON CONFLICT(project_id, thread_id) DO UPDATE SET title = excluded.title,
                   preview = excluded.preview, updated_at = excluded.updated_at, position = excluded.position,
                   archived = 0",
            )?;
            for (index, (row, updated_at)) in rows.into_iter().enumerate() {
                upsert.execute(params![
                    project,
                    row.id,
                    row.title,
                    row.preview,
                    updated_at,
                    i64::try_from(index).map_err(io::Error::other)?
                ])?;
            }
        }
        transaction.commit()?;
        Ok(())
    }

    pub fn set_sidebar_archived(
        &self,
        checkout: &CheckoutIdentity,
        row: &ChatRow,
        updated_at: i64,
        archived: bool,
    ) -> Result<(), AttachmentError> {
        checkout.revalidate().map_err(io::Error::other)?;
        let state = self.inner.state();
        state.database.execute(
            "INSERT INTO desktop_sidebar_chats (project_id, thread_id, title, preview, updated_at, position, archived)
             VALUES (?1, ?2, ?3, ?4, ?5, 0, ?6)
             ON CONFLICT(project_id, thread_id) DO UPDATE SET title = excluded.title, preview = excluded.preview,
               updated_at = excluded.updated_at, archived = excluded.archived,
               pinned = CASE WHEN excluded.archived THEN 0 ELSE desktop_sidebar_chats.pinned END",
            params![checkout.storage_key(), row.id, row.title, row.preview, updated_at, archived],
        )?;
        Ok(())
    }

    pub fn rename_sidebar_chat(
        &self,
        key: &SidebarChatKey,
        title: &str,
    ) -> Result<bool, AttachmentError> {
        let state = self.inner.state();
        Ok(state.database.execute(
            "UPDATE desktop_sidebar_chats SET title = ?3 WHERE project_id = ?1 AND thread_id = ?2",
            params![key.project_id, key.chat_id, title],
        )? == 1)
    }

    pub fn pin_sidebar_chat(
        &self,
        key: &SidebarChatKey,
        pinned: bool,
    ) -> Result<bool, AttachmentError> {
        let state = self.inner.state();
        Ok(state.database.execute(
            "UPDATE desktop_sidebar_chats SET pinned = ?3 WHERE project_id = ?1 AND thread_id = ?2",
            params![key.project_id, key.chat_id, pinned],
        )? == 1)
    }

    pub fn mark_sidebar_chat(
        &self,
        key: &SidebarChatKey,
        unread: bool,
    ) -> Result<bool, AttachmentError> {
        let state = self.inner.state();
        Ok(state.database.execute(
            "UPDATE desktop_sidebar_chats SET unread = ?3 WHERE project_id = ?1 AND thread_id = ?2",
            params![key.project_id, key.chat_id, unread],
        )? == 1)
    }

    pub fn sidebar_chat_finished(
        &self,
        key: &SidebarChatKey,
        unread: bool,
    ) -> Result<(), AttachmentError> {
        let state = self.inner.state();
        state.database.execute(
            "UPDATE desktop_sidebar_chats SET updated_at = unixepoch(), unread = (?3 OR unread)
             WHERE project_id = ?1 AND thread_id = ?2",
            params![key.project_id, key.chat_id, unread],
        )?;
        Ok(())
    }

    pub fn sidebar_preferences(&self) -> Result<SidebarPreferences, AttachmentError> {
        let state = self.inner.state();
        let content: Option<String> = state
            .database
            .query_row(
                "SELECT content FROM desktop_sidebar_preferences WHERE slot = 1",
                [],
                |row| row.get(0),
            )
            .optional()?;
        content.map_or_else(
            || Ok(SidebarPreferences::default()),
            |content| {
                serde_json::from_str(&content)
                    .map_err(io::Error::other)
                    .map_err(Into::into)
            },
        )
    }

    pub fn save_sidebar_preferences(
        &self,
        preferences: &SidebarPreferences,
    ) -> Result<(), AttachmentError> {
        let content = serde_json::to_string(preferences).map_err(io::Error::other)?;
        let state = self.inner.state();
        state.database.execute(
            "INSERT INTO desktop_sidebar_preferences (slot, content) VALUES (1, ?1)
             ON CONFLICT(slot) DO UPDATE SET content = excluded.content",
            [content],
        )?;
        Ok(())
    }

    pub fn sidebar_view(&self, active: Option<String>) -> Result<SidebarView, AttachmentError> {
        let preferences = self.sidebar_preferences()?;
        let state = self.inner.state();
        let mut projects = state.database.prepare(
            "SELECT id, path, title, pinned FROM desktop_projects ORDER BY pinned DESC, last_opened DESC, id",
        )?;
        let projects = projects
            .query_map([], row_project)?
            .collect::<Result<Vec<_>, _>>()?;
        let mut chats = state.database.prepare(
            "SELECT project_id, thread_id, title, preview, pinned, unread FROM desktop_sidebar_chats
             WHERE archived = 0
             ORDER BY pinned DESC, updated_at DESC, position, project_id, thread_id",
        )?;
        let mut chats = chats
            .query_map([], |row| {
                Ok(SidebarChat {
                    key: SidebarChatKey {
                        project_id: row.get(0)?,
                        chat_id: row.get(1)?,
                    },
                    title: row.get(2)?,
                    preview: row.get(3)?,
                    pinned: row.get(4)?,
                    unread: row.get(5)?,
                })
            })?
            .collect::<Result<Vec<_>, _>>()?;
        if preferences.sort == SidebarSort::Manual {
            let ranks: HashMap<_, _> = preferences
                .order
                .iter()
                .enumerate()
                .map(|(at, key)| (key, at))
                .collect();
            chats.sort_by_key(|chat| {
                (
                    !chat.pinned,
                    ranks.get(&chat.key).copied().unwrap_or(usize::MAX),
                )
            });
        }
        Ok(SidebarView {
            active_project: active,
            projects,
            chats,
            group: preferences.group,
            sort: preferences.sort,
            ..SidebarView::default()
        })
    }
}

fn row_project(row: &Row<'_>) -> rusqlite::Result<SidebarProject> {
    let path: String = row.get(1)?;
    let title: Option<String> = row.get(2)?;
    let title = title.unwrap_or_else(|| {
        Path::new(&path)
            .file_name()
            .and_then(|name| name.to_str())
            .unwrap_or(&path)
            .to_owned()
    });
    Ok(SidebarProject {
        id: row.get(0)?,
        title,
        path,
        pinned: row.get(3)?,
    })
}

pub(in crate::storage) fn migrate(transaction: &Transaction<'_>) -> rusqlite::Result<()> {
    transaction.execute_batch(
        "CREATE TABLE desktop_projects (
            id TEXT NOT NULL PRIMARY KEY, path TEXT NOT NULL, title TEXT,
            pinned INTEGER NOT NULL DEFAULT 0 CHECK (pinned IN (0, 1)),
            last_opened INTEGER NOT NULL
        ) STRICT, WITHOUT ROWID;
        CREATE TABLE desktop_sidebar_chats (
            project_id TEXT NOT NULL REFERENCES desktop_projects (id) ON DELETE CASCADE,
            thread_id TEXT NOT NULL, title TEXT NOT NULL, preview TEXT NOT NULL,
            updated_at INTEGER NOT NULL, position INTEGER NOT NULL,
            pinned INTEGER NOT NULL DEFAULT 0 CHECK (pinned IN (0, 1)),
            unread INTEGER NOT NULL DEFAULT 0 CHECK (unread IN (0, 1)),
            PRIMARY KEY (project_id, thread_id)
        ) STRICT, WITHOUT ROWID;
        CREATE TABLE desktop_sidebar_preferences (
            slot INTEGER PRIMARY KEY CHECK (slot = 1),
            content TEXT NOT NULL CHECK (json_valid(content) AND json_type(content) = 'object')
        ) STRICT;",
    )
}

pub(in crate::storage) fn migrate_archive(transaction: &Transaction<'_>) -> rusqlite::Result<()> {
    transaction.execute_batch(
        "ALTER TABLE desktop_sidebar_chats
         ADD COLUMN archived INTEGER NOT NULL DEFAULT 0 CHECK (archived IN (0, 1));",
    )
}
