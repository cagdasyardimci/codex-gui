use std::{
    collections::{BTreeMap, HashSet},
    fs, io,
    path::{Path, PathBuf},
};

use plist::{Dictionary, Value as Plist};
use rusqlite::{Transaction, TransactionBehavior, params};
use serde::{Deserialize, Serialize};
use thiserror::Error;

use crate::{
    checkout::CheckoutIdentity,
    ipc::{ComposerPermissions, ComposerSelection, SidebarGroup, SidebarSort},
    storage::project_context::{
        ProjectContextError, ProjectContextImport, import_appkit_project_context,
    },
};

use super::{
    AttachmentError, AttachmentStore,
    appkit_drafts::{AppKitDraftCopy, AppKitDraftError},
    sidebar::SidebarPreferences,
};

mod presentation;
pub use presentation::{AppKitDesktopPresentation, AppKitPaneLayout};

const PREFERENCES: &str = "preferences.plist";
const MAX_PREFERENCES_BYTES: u64 = 32 * 1024 * 1024;

#[derive(Debug, Error)]
pub enum AppKitPreferenceError {
    #[error(transparent)]
    Io(#[from] io::Error),
    #[error(transparent)]
    Plist(#[from] plist::Error),
    #[error(transparent)]
    Json(#[from] serde_json::Error),
    #[error(transparent)]
    Database(#[from] rusqlite::Error),
    #[error(transparent)]
    Attachments(#[from] AttachmentError),
    #[error(transparent)]
    Drafts(#[from] AppKitDraftError),
    #[error(transparent)]
    ProjectContext(#[from] ProjectContextError),
    #[error("the staged AppKit data has an invalid or unavailable source")]
    InvalidSource,
}

pub struct AppKitPreferences {
    root: CheckoutIdentity,
    preferences: PathBuf,
    originals: PathBuf,
    values: Dictionary,
    remote_enabled: Option<bool>,
}

#[derive(Debug, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AppKitPreferenceImport {
    pub projects: usize,
    pub pinned_chats: usize,
    pub contexts: usize,
    pub drafts: usize,
    pub sent_references: usize,
    pub paused_entries: usize,
    pub queue_receipts: usize,
    pub unresolved_commands: usize,
    pub active_threads: usize,
    pub review_markers: usize,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct PinnedChat {
    id: String,
    cwd: String,
    name: Option<String>,
    preview: Option<String>,
    updated_at: Option<f64>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct SentProject {
    project_path: String,
}

#[derive(Deserialize)]
#[serde(untagged)]
enum SentProjects {
    Current(Vec<SentProject>),
    Legacy(BTreeMap<String, serde_json::Value>),
}

#[derive(Deserialize)]
struct PendingCommand {
    #[serde(rename = "threadID")]
    thread: String,
    #[serde(rename = "turnID")]
    turn: String,
    #[serde(rename = "itemID")]
    item: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct RunPreferences {
    approval_mode: Option<ComposerPermissions>,
    fast_mode: Option<bool>,
    composer_service_tier: Option<String>,
    configuration_defaults: Option<serde_json::Value>,
}

impl AppKitPreferences {
    pub fn open(root: &Path, original_images: &Path) -> Result<Self, AppKitPreferenceError> {
        if !original_images.is_absolute() || !fs::symlink_metadata(root)?.is_dir() {
            return Err(AppKitPreferenceError::InvalidSource);
        }
        let root = CheckoutIdentity::capture(root).map_err(io::Error::other)?;
        let preferences = root.canonical_path().join(PREFERENCES);
        for folder in ["project-context", "draft-images", "notification-sounds"] {
            match fs::symlink_metadata(root.canonical_path().join(folder)) {
                Ok(found) if !found.is_dir() => return Err(AppKitPreferenceError::InvalidSource),
                Ok(_) => {}
                Err(error) if error.kind() == io::ErrorKind::NotFound => {}
                Err(error) => return Err(error.into()),
            }
        }
        let values = read_preferences(&preferences)?;
        let key = "CodexGUI.remoteAccessEnabled";
        let remote_path = root.canonical_path().join("remote-preferences.plist");
        let remote_enabled = match read_preferences(&remote_path) {
            Ok(remote) => remote.get(key).and_then(Plist::as_boolean),
            Err(AppKitPreferenceError::Io(error)) if error.kind() == io::ErrorKind::NotFound => {
                None
            }
            Err(error) => return Err(error),
        }
        .or_else(|| values.get(key).and_then(Plist::as_boolean));
        Ok(Self {
            root,
            preferences,
            originals: original_images.into(),
            values,
            remote_enabled,
        })
    }

    pub fn root(&self) -> &Path {
        self.root.canonical_path()
    }

    pub fn remote_host_enabled(&self) -> Option<bool> {
        self.remote_enabled
    }

    pub fn source_checkout(&self) -> Option<CheckoutIdentity> {
        self.visible_projects().into_iter().next()
    }

    fn visible_projects(&self) -> Vec<CheckoutIdentity> {
        let removed = strings(self.values.get("CodexGUI.removedProjects"));
        let modern = strings(self.values.get("CodexGUI.recentProjects"));
        let legacy = text(self.values.get("recentProject"));
        let pinned = strings(self.values.get("CodexGUI.pinnedProjects"));
        let mut seen = HashSet::new();
        legacy
            .into_iter()
            .chain(modern)
            .chain(pinned)
            .filter(|path| !removed.contains(path))
            .filter_map(|path| CheckoutIdentity::capture(Path::new(path)).ok())
            .filter(|checkout| seen.insert(checkout.storage_key()))
            .collect()
    }

    fn copied_projects(
        &self,
        visible: &[CheckoutIdentity],
        pinned: &[PinnedChat],
    ) -> Result<Vec<CheckoutIdentity>, AppKitPreferenceError> {
        let mut seen = HashSet::new();
        let mut recorded = Vec::new();
        for key in [
            "CodexGUI.selectedThreads",
            "CodexGUI.drafts",
            "CodexGUI.queuedMessages",
            "CodexGUI.pendingCommands",
            "CodexGUI.activeExecutionThreads",
        ] {
            recorded.extend(
                self.dictionary(key)
                    .into_iter()
                    .flat_map(Dictionary::keys)
                    .cloned(),
            );
        }
        recorded.extend(pinned.iter().map(|chat| chat.cwd.clone()));
        if let Some(drafts) =
            self.encoded::<BTreeMap<String, serde_json::Value>>("CodexGUI.draftContext")?
        {
            recorded.extend(drafts.into_keys());
        }
        match self.encoded("CodexGUI.sentReferences")? {
            Some(SentProjects::Current(sent)) => {
                recorded.extend(sent.into_iter().map(|sent| sent.project_path))
            }
            Some(SentProjects::Legacy(sent)) => recorded.extend(sent.into_keys()),
            None => {}
        }
        recorded.extend(crate::storage::project_context::staged_appkit_projects(
            &self.root().join("project-context"),
        )?);
        recorded.extend(
            self.dictionary("reviewedChangeFingerprints.v1")
                .into_iter()
                .flat_map(Dictionary::keys)
                .filter_map(|origin| {
                    origin
                        .split_once('\0')
                        .map(|(project, _)| project.to_owned())
                }),
        );
        Ok(visible
            .iter()
            .cloned()
            .chain(
                recorded
                    .iter()
                    .filter_map(|path| CheckoutIdentity::capture(Path::new(path)).ok()),
            )
            .filter(|checkout| seen.insert(checkout.storage_key()))
            .collect())
    }

    fn dictionary(&self, key: &str) -> Option<&Dictionary> {
        self.values.get(key).and_then(Plist::as_dictionary)
    }

    fn encoded<T: serde::de::DeserializeOwned>(
        &self,
        key: &str,
    ) -> Result<Option<T>, AppKitPreferenceError> {
        self.values.get(key).map(|value| decode(value)).transpose()
    }

    fn composer(&self) -> Result<Option<ComposerSelection>, AppKitPreferenceError> {
        let model = self.dictionary("CodexGUI.modelPreference");
        let run: Option<RunPreferences> = self.encoded("CodexGUI.runPreferences")?;
        if model.is_none() && run.is_none() {
            return Ok(None);
        }
        let mut composer = ComposerSelection {
            model_id: model
                .and_then(|model| text(model.get("model")))
                .map(str::to_owned),
            effort: model
                .and_then(|model| text(model.get("effort")))
                .map(str::to_owned),
            ..ComposerSelection::default()
        };
        if let Some(run) = run {
            composer.service_tier = run
                .composer_service_tier
                .filter(|value| !value.trim().is_empty())
                .or_else(|| {
                    run.configuration_defaults.is_none().then(|| {
                        if run.fast_mode.unwrap_or(false) {
                            "priority"
                        } else {
                            "default"
                        }
                        .into()
                    })
                });
            if run.configuration_defaults.is_none() {
                composer.permissions = run.approval_mode.unwrap_or_default();
            }
        }
        Ok(Some(composer))
    }

    pub fn import(
        &self,
        store: &AttachmentStore,
    ) -> Result<AppKitPreferenceImport, AppKitPreferenceError> {
        self.root.revalidate().map_err(io::Error::other)?;
        let mut report = AppKitPreferenceImport::default();
        let visible = self.visible_projects();
        let pinned: Vec<PinnedChat> = self.encoded("CodexGUI.pinnedTasks")?.unwrap_or_default();
        let candidates = self.copied_projects(&visible, &pinned)?;
        let source = AppKitDraftCopy {
            preferences: &self.preferences,
            original_images: &self.originals,
            copied_images: &self.root().join("draft-images"),
        };
        let context = self.root().join("project-context");
        let composer = self
            .composer()?
            .map(|composer| serde_json::to_string(&composer))
            .transpose()?;
        for checkout in &candidates {
            let drafts = store.import_appkit_drafts(source, checkout)?;
            report.drafts += drafts.imported_drafts;
            report.sent_references += drafts.imported_sent_references;
            let queued = store.import_appkit_queues(source, checkout)?;
            report.paused_entries += queued.paused_entries;
            report.queue_receipts += queued.server_receipts;
            if import_appkit_project_context(&mut store.inner.state().database, &context, checkout)?
                == ProjectContextImport::Imported
            {
                report.contexts += 1;
            }
        }

        let mut state = store.inner.state();
        let transaction = state
            .database
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        let selected = self.dictionary("CodexGUI.selectedThreads");
        let names = self.dictionary("CodexGUI.projectDisplayNames");
        let pins = strings(self.values.get("CodexGUI.pinnedProjects"));
        for checkout in visible.iter().rev() {
            let path = checkout_text(checkout)?;
            if admitted(&transaction, &format!("sidebar/{}", checkout.storage_key()))? {
                report.projects += transaction.execute(
                    "INSERT OR IGNORE INTO desktop_projects (id, path, title, pinned, last_opened) VALUES
                     (?1, ?2, ?3, ?4, (SELECT coalesce(max(last_opened), 0) + 1 FROM desktop_projects))",
                    params![checkout.storage_key(), path, names.and_then(|names| text(names.get(path))), pins.contains(&path)],
                )?;
                for chat in pinned
                    .iter()
                    .filter(|chat| chat.cwd == path && !chat.id.trim().is_empty())
                {
                    report.pinned_chats += transaction.execute(
                        "INSERT OR IGNORE INTO desktop_sidebar_chats
                         (project_id, thread_id, title, preview, updated_at, position, pinned)
                         VALUES (?1, ?2, ?3, ?4, ?5, 0, 1)",
                        params![
                            checkout.storage_key(),
                            chat.id,
                            chat.name
                                .as_deref()
                                .filter(|name| !name.is_empty())
                                .or(chat.preview.as_deref())
                                .unwrap_or(&chat.id),
                            chat.preview.as_deref().unwrap_or_default(),
                            foundation_seconds(chat.updated_at)
                        ],
                    )?;
                }
            }
        }
        for checkout in &candidates {
            let path = checkout_text(checkout)?;
            let key = checkout.storage_key();
            if admitted(&transaction, &format!("project/{key}"))? {
                if let Some(thread) = selected.and_then(|fields| text(fields.get(path))) {
                    transaction.execute(
                        "INSERT OR IGNORE INTO desktop_project_selections VALUES (?1, ?2)",
                        params![key, thread],
                    )?;
                }
                if let Some(composer) = &composer {
                    transaction.execute(
                        "INSERT OR IGNORE INTO appkit_composer_preferences VALUES (?1, ?2)",
                        params![key, composer],
                    )?;
                }
                self.import_execution(&transaction, checkout, &mut report)?;
                self.import_markers(&transaction, checkout, &mut report)?;
            }
        }
        if admitted(&transaction, "desktop")? {
            self.import_desktop(&transaction, visible.first(), selected)?;
        }
        transaction.commit()?;
        self.root.revalidate().map_err(io::Error::other)?;
        Ok(report)
    }

    fn import_desktop(
        &self,
        transaction: &Transaction<'_>,
        source: Option<&CheckoutIdentity>,
        selected: Option<&Dictionary>,
    ) -> Result<(), AppKitPreferenceError> {
        let has_selection: bool = transaction.query_row(
            "SELECT EXISTS(SELECT 1 FROM desktop_selection WHERE slot = 1)",
            [],
            |row| row.get(0),
        )?;
        if !has_selection && let Some(checkout) = source {
            let path = checkout_text(checkout)?;
            let draft = super::navigation::source_draft_for(transaction, &checkout.storage_key())?;
            transaction.execute("INSERT INTO desktop_selection (slot, project_path, project_key, thread_id, source_draft) VALUES (1, ?1, ?2, ?3, ?4)",
                params![path, checkout.storage_key(), selected.and_then(|fields| text(fields.get(path))), draft.0.as_bytes().as_slice()])?;
        }
        let group = match text(self.values.get("sidebar.organization")) {
            Some("oneList") => SidebarGroup::OneList,
            _ => SidebarGroup::ByProject,
        };
        let sort = match text(self.values.get("sidebar.sortOrder")) {
            Some("manual") => SidebarSort::Manual,
            _ => SidebarSort::LastUpdated,
        };
        let preferences = serde_json::to_string(&SidebarPreferences {
            group,
            sort,
            order: Vec::new(),
        })?;
        let inserted = transaction.execute(
            "INSERT OR IGNORE INTO desktop_sidebar_preferences VALUES (1, ?1)",
            [preferences],
        )?;
        if inserted == 1 {
            for (index, id) in strings(self.values.get("sidebar.manualThreadIDs"))
                .into_iter()
                .enumerate()
            {
                transaction.execute(
                    "INSERT OR IGNORE INTO appkit_sidebar_order VALUES (?1, ?2)",
                    params![id, index as i64],
                )?;
            }
        }
        let destination_visibility: bool = transaction.query_row(
            "SELECT EXISTS(SELECT 1 FROM desktop_hidden_reasoning_efforts)",
            [],
            |row| row.get(0),
        )?;
        if !destination_visibility {
            for effort in strings(self.values.get("settings.hiddenReasoningEfforts")) {
                if !super::reasoning_visibility::REQUIRED_EFFORTS.contains(&effort) {
                    transaction.execute(
                        "INSERT OR IGNORE INTO desktop_hidden_reasoning_efforts VALUES (?1)",
                        [effort],
                    )?;
                }
            }
        }
        Ok(())
    }

    fn import_execution(
        &self,
        transaction: &Transaction<'_>,
        checkout: &CheckoutIdentity,
        report: &mut AppKitPreferenceImport,
    ) -> Result<(), AppKitPreferenceError> {
        let path = checkout_text(checkout)?;
        let key = checkout.storage_key();
        if let Some(data) = self
            .dictionary("CodexGUI.pendingCommands")
            .and_then(|entries| entries.get(path))
        {
            let commands: Vec<PendingCommand> = decode(data)?;
            for command in commands.into_iter().filter(|entry| {
                [&entry.thread, &entry.turn, &entry.item]
                    .iter()
                    .all(|id| !id.trim().is_empty())
            }) {
                report.unresolved_commands += transaction.execute(
                    "INSERT OR IGNORE INTO appkit_unresolved_commands VALUES (?1, ?2, ?3, ?4, ?5)",
                    params![key, path, command.thread, command.turn, command.item],
                )?;
            }
        }
        for thread in strings(
            self.dictionary("CodexGUI.activeExecutionThreads")
                .and_then(|entries| entries.get(path)),
        ) {
            report.active_threads += transaction.execute(
                "INSERT OR IGNORE INTO appkit_active_threads VALUES (?1, ?2, ?3)",
                params![key, path, thread],
            )?;
        }
        Ok(())
    }

    fn import_markers(
        &self,
        transaction: &Transaction<'_>,
        checkout: &CheckoutIdentity,
        report: &mut AppKitPreferenceImport,
    ) -> Result<(), AppKitPreferenceError> {
        let path = checkout_text(checkout)?;
        let key = checkout.storage_key();
        for (origin, digest) in self
            .dictionary("reviewedChangeFingerprints.v1")
            .into_iter()
            .flatten()
        {
            let fields: Vec<_> = origin.split('\0').collect();
            let [project, thread, turn, file, hunk] = fields.as_slice() else {
                continue;
            };
            let Some(digest) = text(Some(digest)).filter(|digest| {
                digest.len() <= 16 && digest.bytes().all(|byte| byte.is_ascii_hexdigit())
            }) else {
                continue;
            };
            if *project == path && !thread.is_empty() && !turn.is_empty() && !file.is_empty() {
                report.review_markers += transaction.execute(
                    "INSERT OR IGNORE INTO appkit_review_markers VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                    params![key, thread, turn, file, hunk, digest],
                )?;
            }
        }
        Ok(())
    }
}

fn read_preferences(path: &Path) -> Result<Dictionary, AppKitPreferenceError> {
    let metadata = fs::symlink_metadata(path)?;
    if !metadata.is_file() || metadata.len() > MAX_PREFERENCES_BYTES {
        return Err(AppKitPreferenceError::InvalidSource);
    }
    Plist::from_file(path)?
        .into_dictionary()
        .ok_or(AppKitPreferenceError::InvalidSource)
}

fn checkout_text(checkout: &CheckoutIdentity) -> Result<&str, AppKitPreferenceError> {
    checkout
        .canonical_path()
        .to_str()
        .ok_or(AppKitPreferenceError::InvalidSource)
}

fn admitted(transaction: &Transaction<'_>, scope: &str) -> rusqlite::Result<bool> {
    Ok(transaction.execute(
        "INSERT OR IGNORE INTO appkit_imported_preferences VALUES (?1)",
        [scope],
    )? == 1)
}

fn foundation_seconds(value: Option<f64>) -> i64 {
    value
        .filter(|value| value.is_finite())
        .map_or(0, |value| (value + 978_307_200.0) as i64)
}

fn text(value: Option<&Plist>) -> Option<&str> {
    value
        .and_then(Plist::as_string)
        .filter(|text| !text.trim().is_empty())
}

fn strings(value: Option<&Plist>) -> Vec<&str> {
    value
        .and_then(Plist::as_array)
        .into_iter()
        .flatten()
        .filter_map(|value| text(Some(value)))
        .collect()
}

fn decode<T: serde::de::DeserializeOwned>(value: &Plist) -> Result<T, AppKitPreferenceError> {
    if let Some(bytes) = value.as_data() {
        Ok(serde_json::from_slice(bytes)?)
    } else {
        Ok(plist::from_value(value)?)
    }
}

pub(crate) fn migrate(transaction: &Transaction<'_>) -> rusqlite::Result<()> {
    transaction.execute_batch("CREATE TABLE appkit_imported_preferences (scope TEXT PRIMARY KEY) WITHOUT ROWID;
        CREATE TABLE desktop_source_drafts (project_id TEXT PRIMARY KEY, draft_id BLOB NOT NULL REFERENCES drafts (id)) WITHOUT ROWID;
        INSERT INTO desktop_source_drafts SELECT coalesce(project_key, ''), source_draft FROM desktop_selection;
        CREATE TABLE desktop_project_selections (project_id TEXT PRIMARY KEY, thread_id TEXT) WITHOUT ROWID;
        INSERT INTO desktop_project_selections (project_id, thread_id) SELECT project_key, thread_id FROM desktop_selection WHERE project_key IS NOT NULL;
        CREATE TABLE appkit_composer_preferences (checkout_key TEXT PRIMARY KEY, selection TEXT NOT NULL) WITHOUT ROWID;
        CREATE TABLE appkit_sidebar_order (thread_id TEXT PRIMARY KEY, position INTEGER NOT NULL) WITHOUT ROWID;
        CREATE TABLE appkit_unresolved_commands (checkout_key TEXT NOT NULL, checkout_path TEXT NOT NULL,
            thread_id TEXT NOT NULL, turn_id TEXT NOT NULL, item_id TEXT NOT NULL,
            PRIMARY KEY (checkout_key, thread_id, turn_id, item_id)) WITHOUT ROWID;
        CREATE TABLE appkit_active_threads (checkout_key TEXT NOT NULL, checkout_path TEXT NOT NULL, thread_id TEXT NOT NULL,
            PRIMARY KEY (checkout_key, thread_id)) WITHOUT ROWID;
        CREATE TABLE appkit_review_decisions (origin TEXT NOT NULL, hunk INTEGER NOT NULL, PRIMARY KEY (origin, hunk)) WITHOUT ROWID;
        CREATE TABLE appkit_review_markers (checkout_key TEXT NOT NULL, thread_id TEXT NOT NULL, turn_id TEXT NOT NULL,
            path TEXT NOT NULL, hunk TEXT NOT NULL, fingerprint TEXT NOT NULL,
            PRIMARY KEY (checkout_key, thread_id, turn_id, path, hunk)) WITHOUT ROWID;")
}
