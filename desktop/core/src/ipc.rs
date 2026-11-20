use std::path::Path;

use serde::{Deserialize, Serialize};
use ts_rs::TS;
use uuid::Uuid;

use crate::checkout::CheckoutIdentity;
use crate::files::{
    FileRevision,
    index::{ProjectPathId, ProjectPathMatch},
};
use crate::git::turn_edits::{EditTotals, LastTurnView, TurnEditQuality};

mod actions;
mod archive;
mod chat_deletion;
mod composer_settings;
mod context;
mod git;
mod markdown;
mod media;
mod message_search;
mod navigation;
mod project_context;
mod prompt_revision;
mod question_reply;
mod queue;
mod sidebar;
mod slash_commands;
mod stream;
mod subscription;
pub use actions::{
    ApprovalChoice, ApprovalView, ConversationActions, GrantedPermissions, InteractionAnswer,
    InteractionContent, InteractionView, PermissionChoice, PermissionView, QuestionAnswer,
    QuestionView, RecoverSendRequest, RespondRequest, SendRequest, StopRequest, StopTarget,
    TurnTarget,
};
pub use archive::{ArchiveCatalog, ArchiveScope, ArchiveTarget, ArchivedChat, RestoreArchive};
pub use chat_deletion::{
    ArchiveDeleteSource, ConfirmDeleteChat, DeleteChatSource, SidebarDeleteSource,
};
pub use composer_settings::{
    ComposerPermissions, ComposerSelection, ComposerSelectionView, ComposerSettingsRequest,
    ModelEffort, ModelServiceTier,
};
pub use context::{
    ComposerChoice, ComposerChoiceKind, ComposerContextSelection, ComposerContextTarget,
    ComposerFileContext, ComposerSourceLines, ComposerTokenRange,
};
pub use git::{DiffFileView, DiffPatchRequest, DiffPatchView};
pub use markdown::{MarkdownKind, MarkdownNode, MarkdownTargetRequest};
pub use media::{
    DraftAttachmentRequest, DraftAttachmentScope, DraftAttachmentView, DraftImageAnnotations,
    ImageAnnotation, ReuseAttachmentRequest, SaveImageAnnotations, TranscriptAttachment,
    TranscriptAttachmentLocation, TranscriptMediaRequest,
};
pub use message_search::{MessageSearchHitRequest, MessageSearchPage, MessageSearchPageRequest};
pub use navigation::{
    AccountModel, AccountView, ChatRequest, ChatRow, DraftEdit, EditorDraft, LoginScope,
    LoginTicket, NavigationIntent, NavigationView, OlderHistoryRequest, OlderHistoryView,
    QuitDecision, QuitView, TranscriptViewportRequest, TurnJump, TurnPreview, TurnRailRequest,
    TurnRailTicketRequest, TurnRailView, TurnReferenceView, WriteAccess,
};
pub use project_context::{
    InsertProjectPrompt, ProjectContextChange, ProjectContextRequest, ProjectItemEdit,
    ProjectItemInclusion, ProjectPromptEdit, ResponseBookmarkRequest,
};
pub use prompt_revision::{RecoverFork, ReviseSentPrompt, SentPromptEdit};
pub use question_reply::present_question_reply;
pub use queue::{
    QueueCommand, QueueEditView, QueueEntryView, QueueRequest, QueueSteerTarget, QueueView,
};
pub use sidebar::{
    SidebarChange, SidebarChat, SidebarChatFlag, SidebarChatKey, SidebarChatName,
    SidebarChatUnread, SidebarGroup, SidebarMove, SidebarProject, SidebarProjectName,
    SidebarProjectPin, SidebarProjectRequest, SidebarRequest, SidebarSort, SidebarView,
};
pub use slash_commands::{
    ContextUsage, ExecuteSlashCommand, SlashCommandOutcome, SlashCommandView,
};
pub use stream::{
    CommandUpdate, StreamChange, TextBatch, TextBatcher, TranscriptCommand, TranscriptItem,
    TranscriptRole, TranscriptView,
};
pub use subscription::{
    HistoryInsertion, RevisionedHistory, RevisionedNavigation, RevisionedStream, SubscriptionId,
    WorkspaceProjection, WorkspaceSnapshot, WorkspaceSubscription, WorkspaceUpdate,
    WorkspaceUpdateRequest,
};

pub const WORKSPACE_WINDOW: &str = "main";

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize, TS)]
pub struct WorkspaceId(Uuid);

#[derive(Debug, Deserialize, Serialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct WorkspaceRequest {
    pub workspace_id: WorkspaceId,
}

#[derive(Debug, Deserialize, Serialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ProjectPathRequest {
    pub workspace_id: WorkspaceId,
    pub query: String,
}

#[derive(Debug, Deserialize, Serialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TranscriptRowRequest {
    pub workspace_id: WorkspaceId,
    pub chat_id: String,
    pub item_id: String,
    pub generation: u32,
    pub revision: u32,
}

#[derive(Debug, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct TranscriptImageDependency {
    pub path: String,
    pub revision: Option<FileRevision>,
}

#[derive(Clone, Debug, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct WorkspaceView {
    pub workspace_id: WorkspaceId,
    pub project_path: String,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub enum IpcError {
    UnauthorizedWindow,
    PickerBusy,
    InvalidCheckout,
    RetiredWorkspace,
    ProjectUnavailable,
    StaleSelection,
}

#[derive(Default)]
pub struct WorkspaceGrants {
    selected: Option<Grant>,
}

struct Grant {
    id: WorkspaceId,
    display_path: String,
    checkout: CheckoutIdentity,
}

impl WorkspaceGrants {
    pub fn select_folder(
        &mut self,
        window: &str,
        selected: &Path,
    ) -> Result<WorkspaceId, IpcError> {
        authorize_window(window)?;
        let checkout =
            CheckoutIdentity::capture(selected).map_err(|_| IpcError::InvalidCheckout)?;
        Ok(self.select_checkout(selected, checkout))
    }

    pub fn select_checkout(&mut self, selected: &Path, checkout: CheckoutIdentity) -> WorkspaceId {
        let id = WorkspaceId(Uuid::new_v4());
        self.selected = Some(Grant {
            id,
            display_path: selected.display().to_string(),
            checkout,
        });
        id
    }

    pub fn clear(&mut self) {
        self.selected = None;
    }

    pub fn snapshot(
        &self,
        window: &str,
        request: WorkspaceRequest,
    ) -> Result<WorkspaceView, IpcError> {
        Ok(self.authorized_grant(window, request.workspace_id)?.view())
    }

    pub fn checkout(&self, window: &str, id: WorkspaceId) -> Result<CheckoutIdentity, IpcError> {
        Ok(self.authorized_grant(window, id)?.checkout.clone())
    }

    fn authorized_grant(&self, window: &str, id: WorkspaceId) -> Result<&Grant, IpcError> {
        authorize_window(window)?;
        let grant = self
            .selected
            .as_ref()
            .filter(|grant| grant.id == id)
            .ok_or(IpcError::RetiredWorkspace)?;
        grant
            .checkout
            .revalidate()
            .map_err(|_| IpcError::RetiredWorkspace)?;
        Ok(grant)
    }

    pub fn current_view(&self) -> Option<WorkspaceView> {
        let grant = self.selected.as_ref()?;
        grant.checkout.revalidate().ok()?;
        Some(grant.view())
    }
}

impl Grant {
    fn view(&self) -> WorkspaceView {
        WorkspaceView {
            workspace_id: self.id,
            project_path: self.display_path.clone(),
        }
    }
}

pub fn authorize_window(window: &str) -> Result<(), IpcError> {
    if window != WORKSPACE_WINDOW {
        return Err(IpcError::UnauthorizedWindow);
    }
    Ok(())
}

pub fn workspace_typescript() -> String {
    let mut output = String::from(
        "// Generated by cargo run -p codex-gui-core --example export_workspace_ipc.\n\n",
    );
    for declaration in [
        WorkspaceId::decl(),
        WorkspaceRequest::decl(),
        ProjectPathRequest::decl(),
        ProjectPathId::decl(),
        ProjectPathMatch::decl(),
        WorkspaceView::decl(),
        IpcError::decl(),
        SubscriptionId::decl(),
        WorkspaceSnapshot::decl(),
        WorkspaceSubscription::decl(),
        WorkspaceUpdateRequest::decl(),
        WorkspaceUpdate::decl(),
        RevisionedStream::decl(),
        RevisionedHistory::decl(),
        HistoryInsertion::decl(),
        TextBatch::decl(),
        StreamChange::decl(),
        TranscriptItem::decl(),
        TranscriptCommand::decl(),
        TranscriptRowRequest::decl(),
        MarkdownKind::decl(),
        MarkdownNode::decl(),
        MarkdownTargetRequest::decl(),
        FileRevision::decl(),
        TranscriptImageDependency::decl(),
        TranscriptAttachment::decl(),
        TranscriptMediaRequest::decl(),
        DraftAttachmentView::decl(),
        DraftAttachmentScope::decl(),
        DraftAttachmentRequest::decl(),
        ComposerChoice::decl(),
        ComposerChoiceKind::decl(),
        ComposerContextSelection::decl(),
        ComposerContextTarget::decl(),
        ComposerFileContext::decl(),
        ComposerSourceLines::decl(),
        ComposerTokenRange::decl(),
        ProjectContextRequest::decl(),
        ProjectContextChange::decl(),
        ProjectItemEdit::decl(),
        ProjectItemInclusion::decl(),
        ProjectPromptEdit::decl(),
        InsertProjectPrompt::decl(),
        ResponseBookmarkRequest::decl(),
        crate::storage::project_context::ProjectContextView::decl(),
        crate::storage::project_context::ProjectContext::decl(),
        crate::storage::project_context::ProjectContextItem::decl(),
        crate::storage::project_context::ProjectContextItemKind::decl(),
        crate::storage::project_context::SavedPrompt::decl(),
        crate::storage::project_context::ProjectSkillSelection::decl(),
        crate::storage::project_context::ProjectModelPreference::decl(),
        crate::storage::project_context::ConversationBookmark::decl(),
        crate::storage::project_context::ConversationBookmarkKind::decl(),
        ImageAnnotation::decl(),
        DraftImageAnnotations::decl(),
        SaveImageAnnotations::decl(),
        ReuseAttachmentRequest::decl(),
        TranscriptView::decl(),
        ReviseSentPrompt::decl(),
        RecoverFork::decl(),
        SentPromptEdit::decl(),
        TranscriptRole::decl(),
        NavigationView::decl(),
        crate::slash_commands::Command::decl(),
        SlashCommandView::decl(),
        ContextUsage::decl(),
        ExecuteSlashCommand::decl(),
        SlashCommandOutcome::decl(),
        SidebarView::decl(),
        SidebarGroup::decl(),
        SidebarSort::decl(),
        SidebarChatKey::decl(),
        SidebarChat::decl(),
        SidebarProject::decl(),
        SidebarRequest::decl(),
        SidebarChange::decl(),
        SidebarProjectName::decl(),
        SidebarChatName::decl(),
        SidebarProjectPin::decl(),
        SidebarChatFlag::decl(),
        SidebarChatUnread::decl(),
        SidebarMove::decl(),
        SidebarProjectRequest::decl(),
        ArchiveScope::decl(),
        ArchiveCatalog::decl(),
        ArchivedChat::decl(),
        RestoreArchive::decl(),
        ArchiveTarget::decl(),
        ArchiveDeleteSource::decl(),
        ConfirmDeleteChat::decl(),
        DeleteChatSource::decl(),
        SidebarDeleteSource::decl(),
        MessageSearchPage::decl(),
        MessageSearchPageRequest::decl(),
        MessageSearchHitRequest::decl(),
        ChatRow::decl(),
        EditorDraft::decl(),
        ChatRequest::decl(),
        OlderHistoryRequest::decl(),
        OlderHistoryView::decl(),
        TranscriptViewportRequest::decl(),
        TurnRailView::decl(),
        TurnReferenceView::decl(),
        TurnPreview::decl(),
        TurnJump::decl(),
        TurnRailRequest::decl(),
        TurnRailTicketRequest::decl(),
        DraftEdit::decl(),
        NavigationIntent::decl(),
        QueueRequest::decl(),
        QueueCommand::decl(),
        QueueSteerTarget::decl(),
        QueueView::decl(),
        QueueEntryView::decl(),
        QueueEditView::decl(),
        RevisionedNavigation::decl(),
        AccountView::decl(),
        AccountModel::decl(),
        ModelEffort::decl(),
        ModelServiceTier::decl(),
        ComposerPermissions::decl(),
        ComposerSelection::decl(),
        ComposerSelectionView::decl(),
        ComposerSettingsRequest::decl(),
        LoginScope::decl(),
        LoginTicket::decl(),
        WriteAccess::decl(),
        ConversationActions::decl(),
        StopTarget::decl(),
        TurnTarget::decl(),
        StopRequest::decl(),
        SendRequest::decl(),
        RecoverSendRequest::decl(),
        InteractionView::decl(),
        InteractionContent::decl(),
        ApprovalView::decl(),
        ApprovalChoice::decl(),
        PermissionView::decl(),
        PermissionChoice::decl(),
        QuestionView::decl(),
        QuestionAnswer::decl(),
        GrantedPermissions::decl(),
        InteractionAnswer::decl(),
        RespondRequest::decl(),
        DiffFileView::decl(),
        DiffPatchRequest::decl(),
        DiffPatchView::decl(),
        LastTurnView::decl(),
        EditTotals::decl(),
        TurnEditQuality::decl(),
        QuitView::decl(),
        QuitDecision::decl(),
    ] {
        output.push_str("export ");
        output.push_str(&declaration);
        output.push('\n');
    }
    output
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn checked_in_typescript_matches_the_rust_ipc_contract() {
        let generated = include_str!("../../frontend/src/generated/workspace.ts");
        assert_eq!(generated.replace("\r\n", "\n"), workspace_typescript());
    }

    #[test]
    fn workspace_reads_require_the_current_grant_and_main_window() {
        let root = tempfile::tempdir().unwrap();
        let mut grants = WorkspaceGrants::default();
        assert_eq!(
            grants.select_folder("other", root.path()),
            Err(IpcError::UnauthorizedWindow)
        );
        let first = grants.select_folder(WORKSPACE_WINDOW, root.path()).unwrap();
        let request = || WorkspaceRequest {
            workspace_id: first,
        };
        assert_eq!(
            serde_json::to_value(request()).unwrap()["workspaceId"],
            first.0.to_string()
        );
        assert_eq!(
            grants.snapshot("other", request()),
            Err(IpcError::UnauthorizedWindow)
        );
        assert_eq!(
            grants
                .snapshot(WORKSPACE_WINDOW, request())
                .unwrap()
                .workspace_id,
            first
        );
        let second = grants.select_folder(WORKSPACE_WINDOW, root.path()).unwrap();
        assert_ne!(first, second);
        assert_eq!(
            grants.snapshot(WORKSPACE_WINDOW, request()),
            Err(IpcError::RetiredWorkspace)
        );
    }
}
