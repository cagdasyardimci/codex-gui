use serde::{Deserialize, Serialize};
use ts_rs::TS;
use uuid::Uuid;

#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub enum SidebarGroup {
    #[default]
    ByProject,
    OneList,
}

#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub enum SidebarSort {
    #[default]
    LastUpdated,
    Manual,
}

#[derive(Clone, Debug, Deserialize, Eq, Hash, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SidebarChatKey {
    pub project_id: String,
    pub chat_id: String,
}

#[derive(Clone, Debug, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct SidebarChat {
    pub key: SidebarChatKey,
    pub title: String,
    pub preview: String,
    pub pinned: bool,
    pub unread: bool,
}

#[derive(Clone, Debug, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct SidebarProject {
    pub id: String,
    pub title: String,
    pub path: String,
    pub pinned: bool,
}

#[derive(Clone, Debug, Default, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct SidebarView {
    pub revision: Option<Uuid>,
    pub active_project: Option<String>,
    pub projects: Vec<SidebarProject>,
    pub chats: Vec<SidebarChat>,
    pub group: SidebarGroup,
    pub sort: SidebarSort,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SidebarRequest {
    pub revision: Uuid,
    pub change: SidebarChange,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
pub enum SidebarChange {
    OpenProject(String),
    OpenChat(SidebarChatKey),
    ArchiveChat(SidebarChatKey),
    ArchiveProject(String),
    RenameProject(SidebarProjectName),
    RenameChat(SidebarChatName),
    PinProject(SidebarProjectPin),
    PinChat(SidebarChatFlag),
    MarkUnread(SidebarChatUnread),
    Group(SidebarGroup),
    Sort(SidebarSort),
    MoveChat(SidebarMove),
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SidebarProjectName {
    pub project_id: String,
    pub title: String,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SidebarChatName {
    pub key: SidebarChatKey,
    pub title: String,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SidebarProjectPin {
    pub project_id: String,
    pub pinned: bool,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SidebarChatFlag {
    pub key: SidebarChatKey,
    pub pinned: bool,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SidebarChatUnread {
    pub key: SidebarChatKey,
    pub unread: bool,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SidebarMove {
    pub source: SidebarChatKey,
    pub target: SidebarChatKey,
    pub after: bool,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SidebarProjectRequest {
    pub revision: Uuid,
    pub project_id: String,
}
