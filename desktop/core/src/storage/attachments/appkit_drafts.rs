use std::{collections::BTreeMap, io::Cursor, path::Component};

use plist::Value as PlistValue;
use serde::Deserialize;
use uuid::Uuid;

use super::*;
use crate::checkout::{CheckoutError, CheckoutIdentity};

const MAX_APPKIT_IMAGE_BYTES: u64 = 20 * 1024 * 1024;
const NEW_CHAT: &str = "new-chat";

pub mod queues;

#[derive(Clone, Copy)]
pub struct AppKitDraftCopy<'a> {
    pub preferences: &'a Path,
    pub original_images: &'a Path,
    pub copied_images: &'a Path,
}

#[derive(Debug, Default, Eq, PartialEq)]
pub struct AppKitDraftImport {
    pub imported_drafts: usize,
    pub preserved_drafts: usize,
    pub imported_sent_references: usize,
}

#[derive(Debug, PartialEq)]
pub struct ImportedDraft {
    pub id: DraftId,
    pub thread: Option<ThreadId>,
}

#[derive(Debug, PartialEq)]
pub struct ImportedSentReference {
    pub thread: ThreadId,
    pub item: Value,
    pub original_image_path: Option<PathBuf>,
}

#[derive(Debug, Error)]
pub enum AppKitDraftError {
    #[error(transparent)]
    Checkout(#[from] CheckoutError),
    #[error(transparent)]
    Database(#[from] rusqlite::Error),
    #[error(transparent)]
    Draft(#[from] DraftStoreError),
    #[error(transparent)]
    Attachment(#[from] AttachmentError),
    #[error(transparent)]
    Disk(#[from] io::Error),
    #[error(transparent)]
    Plist(#[from] plist::Error),
    #[error(transparent)]
    Json(#[from] serde_json::Error),
    #[error("the copied AppKit preference or context has an invalid shape")]
    InvalidSource,
    #[error("the checkout or attachment path cannot be represented in the AppKit format")]
    NonUnicodePath,
    #[error("the copied image is not a supported AppKit PNG: {0}")]
    InvalidImage(PathBuf),
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct StoredSent {
    project_path: String,
    #[serde(rename = "threadID")]
    thread_id: String,
    item: Value,
}

type ProjectRecords<T> = BTreeMap<String, BTreeMap<String, T>>;

#[derive(Default)]
struct DraftInput {
    text: String,
    context: Vec<Value>,
}

struct StagedItem {
    item: Value,
    image: Option<(String, BlobLease)>,
}

impl AttachmentStore {
    pub fn import_appkit_drafts(
        &self,
        source: AppKitDraftCopy<'_>,
        checkout: &CheckoutIdentity,
    ) -> Result<AppKitDraftImport, AppKitDraftError> {
        checkout.revalidate()?;
        let path = unicode_path(checkout.canonical_path())?;
        let key = checkout.storage_key();
        if !fs::symlink_metadata(source.preferences)?.is_file() {
            return Err(AppKitDraftError::InvalidSource);
        }
        let preferences = PlistValue::from_file(source.preferences)?
            .into_dictionary()
            .ok_or(AppKitDraftError::InvalidSource)?;
        let records = draft_inputs(&preferences, path, checkout)?;
        let references = sent_inputs(&preferences, path)?;
        let mut report = AppKitDraftImport::default();

        // Stage bytes before taking the database lock. Leases keep them alive through the transaction.
        let mut drafts = Vec::new();
        for (bucket, draft) in records {
            let thread = thread_from_bucket(&bucket)?;
            if draft_already_present(
                &self.inner.state().database,
                path,
                &key,
                &bucket,
                thread.as_ref(),
            )? {
                report.preserved_drafts += 1;
                continue;
            }
            let items = draft
                .context
                .into_iter()
                .map(|item| self.stage_appkit_item(source, item))
                .collect::<Result<Vec<_>, _>>()?;
            drafts.push((bucket, thread, draft.text, items));
        }
        let mut sent = Vec::new();
        for (ordinal, (thread, item)) in references.into_iter().enumerate() {
            let identity = hex::encode(Sha256::digest(serde_json::to_vec(&item)?));
            let present: bool = self.inner.state().database.query_row(
                "SELECT EXISTS (SELECT 1 FROM appkit_sent_references
                 WHERE checkout_path = ?1 AND checkout_key = ?2 AND thread_id = ?3 AND identity = ?4)",
                params![path, key, thread.0, identity], |row| row.get(0),
            )?;
            if present {
                continue;
            }
            let item = self.stage_appkit_item(source, item)?;
            let ordinal = i64::try_from(ordinal).map_err(|_| AppKitDraftError::InvalidSource)?;
            sent.push((ordinal, thread, identity, item));
        }

        let mut state = self.inner.state();
        let transaction = state
            .database
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        checkout.revalidate()?;
        for (bucket, thread, text, items) in &drafts {
            if draft_already_present(&transaction, path, &key, bucket, thread.as_ref())? {
                report.preserved_drafts += 1;
                continue;
            }
            let draft = DraftId(Uuid::new_v4());
            let context: Vec<_> = items.iter().map(|item| item.item.clone()).collect();
            save_in_transaction(
                &transaction,
                draft,
                None,
                DraftRevision::INITIAL,
                Some(text),
                Some(&context),
            )?;
            let draft_id = draft.0.as_bytes().as_slice();
            replace_references(
                &transaction,
                &self.inner.blobs,
                draft_id,
                items
                    .iter()
                    .filter_map(|item| item.image.as_ref().map(|(_, lease)| lease.id())),
            )?;
            if let Some(thread) = thread {
                transaction.execute(
                    "INSERT INTO thread_drafts (thread_id, draft_id) VALUES (?1, ?2)",
                    params![thread.0, draft_id],
                )?;
            }
            transaction.execute(
                "INSERT INTO appkit_draft_origins (checkout_path, checkout_key, source_bucket, thread_id, draft_id)
                 VALUES (?1, ?2, ?3, ?4, ?5)",
                params![path, key, bucket, thread.as_ref().map(|thread| &thread.0), draft_id],
            )?;
            report.imported_drafts += 1;
        }
        for (ordinal, thread, identity, item) in &sent {
            let original = item.image.as_ref().map(|(path, _)| path);
            let blob = item.image.as_ref().map(|(_, lease)| lease.id().0);
            report.imported_sent_references += transaction.execute(
                "INSERT INTO appkit_sent_references (checkout_path, checkout_key, thread_id, identity, ordinal, item, original_image_path, blob_id)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8) ON CONFLICT DO NOTHING",
                params![path, key, thread.0, identity, ordinal, serde_json::to_string(&item.item)?, original, blob.as_ref().map(|id| id.as_slice())],
            )?;
        }
        transaction.commit()?;
        Ok(report)
    }

    pub fn imported_appkit_drafts(
        &self,
        checkout: &CheckoutIdentity,
    ) -> Result<Vec<ImportedDraft>, AppKitDraftError> {
        checkout.revalidate()?;
        let state = self.inner.state();
        let mut select = state.database.prepare(
            "SELECT draft_id, thread_id FROM appkit_draft_origins
             WHERE checkout_path = ?1 AND checkout_key = ?2 AND draft_id IS NOT NULL ORDER BY source_bucket",
        )?;
        let mapped = select.query_map(
            params![
                unicode_path(checkout.canonical_path())?,
                checkout.storage_key()
            ],
            |row| {
                Ok(ImportedDraft {
                    id: DraftId(Uuid::from_bytes(row.get(0)?)),
                    thread: row.get::<_, Option<String>>(1)?.map(ThreadId),
                })
            },
        )?;
        Ok(mapped.collect::<rusqlite::Result<_>>()?)
    }

    pub fn imported_appkit_sent_references(
        &self,
        checkout: &CheckoutIdentity,
        thread: &ThreadId,
    ) -> Result<Vec<ImportedSentReference>, AppKitDraftError> {
        checkout.revalidate()?;
        let state = self.inner.state();
        let mut select = state.database.prepare(
            "SELECT item, original_image_path FROM appkit_sent_references
             WHERE checkout_path = ?1 AND checkout_key = ?2 AND thread_id = ?3 ORDER BY ordinal, identity",
        )?;
        let mapped = select.query_map(
            params![
                unicode_path(checkout.canonical_path())?,
                checkout.storage_key(),
                thread.0
            ],
            |row| Ok((row.get::<_, String>(0)?, row.get::<_, Option<String>>(1)?)),
        )?;
        mapped
            .map(|row| {
                let (item, original) = row?;
                Ok(ImportedSentReference {
                    thread: thread.clone(),
                    item: serde_json::from_str(&item)?,
                    original_image_path: original.map(PathBuf::from),
                })
            })
            .collect()
    }

    fn stage_appkit_item(
        &self,
        source: AppKitDraftCopy<'_>,
        mut item: Value,
    ) -> Result<StagedItem, AppKitDraftError> {
        if item["id"].as_str().is_none()
            || item["kind"].as_str().is_none()
            || item["title"].as_str().is_none()
        {
            return Err(AppKitDraftError::InvalidSource);
        }
        let owned = item["path"]
            .as_str()
            .filter(|_| item["kind"] == "image")
            .and_then(|path| copied_image_path(source, path).map(|copy| (path.to_owned(), copy)));
        let image = if let Some((original, copy)) = owned {
            let info = fs::symlink_metadata(&copy)?;
            if !info.is_file() || info.len() > MAX_APPKIT_IMAGE_BYTES {
                return Err(AppKitDraftError::InvalidImage(copy));
            }
            let mut bytes = Vec::new();
            File::open(&copy)?
                .take(MAX_APPKIT_IMAGE_BYTES + 1)
                .read_to_end(&mut bytes)?;
            if !bytes.starts_with(b"\x89PNG\r\n\x1a\n")
                || bytes.len() as u64 > MAX_APPKIT_IMAGE_BYTES
            {
                return Err(AppKitDraftError::InvalidImage(copy));
            }
            let lease = self.stage(Cursor::new(bytes))?;
            item["path"] = Value::String(unicode_path(&lease.path())?.into());
            Some((original, lease))
        } else {
            None
        };
        Ok(StagedItem { item, image })
    }
}

fn unicode_path(path: &Path) -> Result<&str, AppKitDraftError> {
    path.to_str().ok_or(AppKitDraftError::NonUnicodePath)
}

fn thread_from_bucket(bucket: &str) -> Result<Option<ThreadId>, AppKitDraftError> {
    if bucket == NEW_CHAT {
        return Ok(None);
    }
    bucket
        .strip_prefix("thread:")
        .filter(|thread| !thread.is_empty())
        .map(|thread| Some(ThreadId(thread.into())))
        .ok_or(AppKitDraftError::InvalidSource)
}

fn draft_already_present(
    database: &Connection,
    path: &str,
    key: &str,
    bucket: &str,
    thread: Option<&ThreadId>,
) -> rusqlite::Result<bool> {
    database.query_row(
        "SELECT EXISTS (SELECT 1 FROM appkit_draft_origins WHERE checkout_path = ?1 AND checkout_key = ?2 AND source_bucket = ?3)
         OR EXISTS (SELECT 1 FROM thread_drafts WHERE thread_id = ?4)",
        params![path, key, bucket, thread.map(|thread| &thread.0)], |row| row.get(0),
    )
}

fn copied_image_path(source: AppKitDraftCopy<'_>, path: &str) -> Option<PathBuf> {
    let relative = Path::new(path).strip_prefix(source.original_images).ok()?;
    let mut components = relative.components();
    let Component::Normal(file) = components.next()? else {
        return None;
    };
    if components.next().is_some() {
        return None;
    }
    let file = Path::new(file);
    if !file.extension()?.to_str()?.eq_ignore_ascii_case("png") {
        return None;
    }
    Uuid::parse_str(file.file_stem()?.to_str()?).ok()?;
    Some(source.copied_images.join(file))
}

fn data_field<'a>(
    preferences: &'a plist::Dictionary,
    key: &str,
) -> Result<Option<&'a [u8]>, AppKitDraftError> {
    preferences
        .get(key)
        .map(|value| value.as_data().ok_or(AppKitDraftError::InvalidSource))
        .transpose()
}

fn draft_inputs(
    preferences: &plist::Dictionary,
    project: &str,
    checkout: &CheckoutIdentity,
) -> Result<BTreeMap<String, DraftInput>, AppKitDraftError> {
    let mut text = preferences
        .get("CodexGUI.drafts")
        .map(plist::from_value::<ProjectRecords<String>>)
        .transpose()?
        .unwrap_or_default();
    let mut drafts: BTreeMap<_, _> = text
        .remove(project)
        .unwrap_or_default()
        .into_iter()
        .map(|(key, text)| {
            (
                key,
                DraftInput {
                    text,
                    context: Vec::new(),
                },
            )
        })
        .collect();
    if let (Some(legacy_project), Some(legacy_draft)) = (
        preferences
            .get("recentProject")
            .and_then(PlistValue::as_string),
        preferences.get("draft").and_then(PlistValue::as_string),
    ) && checkout
        .validate_reported(Path::new(legacy_project))
        .is_ok()
    {
        drafts.entry(NEW_CHAT.into()).or_insert_with(|| DraftInput {
            text: legacy_draft.into(),
            context: Vec::new(),
        });
    }
    if let Some(encoded) = data_field(preferences, "CodexGUI.draftContext")? {
        let mut context: ProjectRecords<Vec<Value>> = serde_json::from_slice(encoded)?;
        for (bucket, items) in context.remove(project).unwrap_or_default() {
            drafts.entry(bucket).or_default().context = items;
        }
    }
    Ok(drafts)
}

fn sent_inputs(
    preferences: &plist::Dictionary,
    project: &str,
) -> Result<Vec<(ThreadId, Value)>, AppKitDraftError> {
    let Some(data) = data_field(preferences, "CodexGUI.sentReferences")? else {
        return Ok(Vec::new());
    };
    if let Ok(current) = serde_json::from_slice::<Vec<StoredSent>>(data) {
        return current
            .into_iter()
            .filter(|record| record.project_path == project)
            .map(|record| {
                if record.thread_id.is_empty() {
                    return Err(AppKitDraftError::InvalidSource);
                }
                Ok((ThreadId(record.thread_id), record.item))
            })
            .collect();
    }
    let mut legacy: ProjectRecords<Vec<Value>> = serde_json::from_slice(data)?;
    let mut items = Vec::new();
    for (bucket, values) in legacy.remove(project).unwrap_or_default() {
        if let Some(thread) = thread_from_bucket(&bucket)? {
            items.extend(values.into_iter().map(|item| (thread.clone(), item)));
        }
    }
    Ok(items)
}

pub(in crate::storage) fn migrate(transaction: &Transaction<'_>) -> rusqlite::Result<()> {
    transaction.execute_batch(
        "CREATE TABLE appkit_draft_origins (
            checkout_path TEXT NOT NULL,
            checkout_key TEXT NOT NULL,
            source_bucket TEXT NOT NULL,
            thread_id TEXT,
            draft_id BLOB REFERENCES drafts (id) ON DELETE SET NULL,
            PRIMARY KEY (checkout_path, checkout_key, source_bucket)
        ) STRICT, WITHOUT ROWID;
        CREATE TABLE appkit_sent_references (
            checkout_path TEXT NOT NULL,
            checkout_key TEXT NOT NULL,
            thread_id TEXT NOT NULL,
            identity TEXT NOT NULL,
            ordinal INTEGER NOT NULL,
            item TEXT NOT NULL CHECK (json_valid(item) AND json_type(item) = 'object'),
            original_image_path TEXT,
            blob_id BLOB REFERENCES attachment_blobs (id) ON DELETE RESTRICT,
            PRIMARY KEY (checkout_path, checkout_key, thread_id, identity)
        ) STRICT, WITHOUT ROWID;
        CREATE INDEX appkit_sent_references_blob ON appkit_sent_references (blob_id);",
    )
}

#[cfg(test)]
mod tests;
