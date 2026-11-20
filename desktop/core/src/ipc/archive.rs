use serde::{Deserialize, Serialize};
use ts_rs::TS;
use uuid::Uuid;

use super::WorkspaceId;

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ArchiveScope {
    pub workspace_id: Option<WorkspaceId>,
}

#[derive(Debug, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct ArchivedChat {
    pub id: String,
    pub title: String,
    pub preview: String,
    pub project: String,
    pub path: String,
    #[ts(type = "number")]
    pub created_at: i64,
    #[ts(type = "number")]
    pub updated_at: i64,
}

#[derive(Debug, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct ArchiveCatalog {
    pub revision: Uuid,
    pub chats: Vec<ArchivedChat>,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct RestoreArchive {
    pub revision: Uuid,
    pub target: ArchiveTarget,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
pub enum ArchiveTarget {
    Chat(String),
    Project(String),
}
