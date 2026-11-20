use serde::{Deserialize, Serialize};
use ts_rs::TS;
use uuid::Uuid;

use super::SidebarChatKey;

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
pub enum DeleteChatSource {
    Sidebar(SidebarDeleteSource),
    Archive(ArchiveDeleteSource),
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SidebarDeleteSource {
    pub revision: Uuid,
    pub key: SidebarChatKey,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ArchiveDeleteSource {
    pub revision: Uuid,
    pub chat_id: String,
}

#[derive(Debug, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct ConfirmDeleteChat {
    pub ticket: Uuid,
    pub title: String,
}
