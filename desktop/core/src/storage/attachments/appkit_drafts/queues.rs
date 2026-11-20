use super::*;
use base64::{Engine, engine::general_purpose::STANDARD};
use serde_json::json;

#[derive(Debug, Default, Eq, PartialEq)]
pub struct AppKitQueueImport {
    pub paused_entries: usize,
    pub server_receipts: usize,
    pub preserved_entries: usize,
    pub preferences: usize,
}

#[derive(Deserialize)]
#[serde(untagged)]
enum SourceQueue {
    Current {
        messages: Vec<Value>,
        edit: Option<SourceEdit>,
    },
    Legacy(Vec<Value>),
}

#[derive(Deserialize)]
struct SourceEdit {
    message: Value,
    position: usize,
}

struct StagedQueueEntry {
    thread: ThreadId,
    client: Uuid,
    request: Value,
    source: Value,
    server_id: Option<String>,
    server_receipt: bool,
    attachments: Vec<BlobLease>,
}

impl AttachmentStore {
    pub fn import_appkit_queues(
        &self,
        source: AppKitDraftCopy<'_>,
        checkout: &CheckoutIdentity,
    ) -> Result<AppKitQueueImport, AppKitDraftError> {
        checkout.revalidate()?;
        let project = unicode_path(checkout.canonical_path())?;
        let scope = checkout.storage_key();
        if !fs::symlink_metadata(source.preferences)?.is_file() {
            return Err(AppKitDraftError::InvalidSource);
        }
        let preferences = PlistValue::from_file(source.preferences)?
            .into_dictionary()
            .ok_or(AppKitDraftError::InvalidSource)?;
        let mut report = AppKitQueueImport::default();
        let mut entries = Vec::new();
        if let Some(records) =
            project_queue_preferences(&preferences, project, "CodexGUI.queuedMessages")?
        {
            for (bucket, item) in records {
                let thread = queue_bucket(bucket)?;
                let queue: SourceQueue =
                    serde_json::from_slice(item.as_data().ok_or(AppKitDraftError::InvalidSource)?)?;
                let messages = match queue {
                    SourceQueue::Legacy(messages) => messages,
                    SourceQueue::Current { mut messages, edit } => {
                        if let Some(edit) = edit {
                            messages.insert(edit.position.min(messages.len()), edit.message);
                        }
                        messages
                    }
                };
                for message in messages {
                    let raw_id = nonempty(&message["id"])?;
                    let id =
                        Uuid::parse_str(raw_id).map_err(|_| AppKitDraftError::InvalidSource)?;
                    if imported_entry(&self.inner.state().database, &scope, &thread, id)? {
                        report.preserved_entries += 1;
                        continue;
                    }
                    entries.push(self.stage_queue_entry(
                        source,
                        checkout,
                        thread.clone(),
                        id,
                        message,
                    )?);
                }
            }
        }
        let flags = project_queue_preferences(&preferences, project, "CodexGUI.queueingEnabled")?;
        let mut state = self.inner.state();
        let tx = state
            .database
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        checkout.revalidate()?;
        if let Some(flags) = flags {
            for (bucket, value) in flags {
                let thread = queue_bucket(bucket)?;
                let enabled = value.as_boolean().ok_or(AppKitDraftError::InvalidSource)?;
                report.preferences += tx.execute(
                    "INSERT INTO queue_preferences (checkout_key, thread_id, enabled) VALUES (?1, ?2, ?3)
                     ON CONFLICT DO NOTHING",
                    params![scope, thread.0, enabled],
                )?;
            }
        }
        for entry in &entries {
            let key = entry.client.as_bytes().as_slice();
            // Imported receipts are independent of the destination’s editable draft.
            let inserted = tx.execute(
                "INSERT INTO submissions (id, thread_id, draft_id, draft_revision, request, phase, checkout_key)
                 VALUES (?1, ?2, ?3, 0, ?4, ?5, ?6) ON CONFLICT DO NOTHING",
                params![
                    key, entry.thread.0, Uuid::new_v4().as_bytes().as_slice(),
                    serde_json::to_string(&entry.request)?,
                    if entry.server_receipt { "dispatching" } else { "reserved" }, scope,
                ],
            )?;
            if inserted == 0 {
                report.preserved_entries += 1;
                continue;
            }
            tx.execute(
                "INSERT INTO appkit_queue_origins (checkout_key, thread_id, id, source) VALUES (?1, ?2, ?3, ?4)",
                params![scope, entry.thread.0, key, serde_json::to_string(&entry.source)?],
            )?;
            if entry.server_receipt {
                tx.execute(
                    "INSERT INTO queue_receipts (id, queued_id) VALUES (?1, ?2)",
                    params![key, entry.server_id],
                )?;
                report.server_receipts += 1;
            } else {
                tx.execute(
                    "INSERT INTO legacy_queue (id, session_id, generation, paused)
                     VALUES (?1, zeroblob(16), zeroblob(8), TRUE)",
                    [key],
                )?;
                report.paused_entries += 1;
            }
            let owned: BTreeSet<_> = entry.attachments.iter().map(BlobLease::id).collect();
            for image in owned {
                verify_saved_file(&tx, &self.inner.blobs, image)?;
                tx.execute(
                    "INSERT INTO submission_attachments (submission_id, blob_id) VALUES (?1, ?2)",
                    params![key, image.0.as_slice()],
                )?;
            }
        }
        tx.commit()?;
        Ok(report)
    }

    fn stage_queue_entry(
        &self,
        source: AppKitDraftCopy<'_>,
        checkout: &CheckoutIdentity,
        thread: ThreadId,
        client: Uuid,
        message: Value,
    ) -> Result<StagedQueueEntry, AppKitDraftError> {
        let encoded_context = message["context"]
            .as_array()
            .ok_or(AppKitDraftError::InvalidSource)?;
        let context = encoded_context
            .iter()
            .cloned()
            .map(|item| self.stage_appkit_item(source, item))
            .collect::<Result<Vec<_>, _>>()?;
        let phase = message["steeringPhase"].as_str();
        let saved_server = message["serverID"].as_str().filter(|id| !id.is_empty());
        let server_receipt = thread.0 != NEW_CHAT
            && phase != Some("ready")
            && (saved_server.is_some()
                || message["enqueueUncertain"] == true
                || matches!(phase, Some("deleting" | "sending")));
        let input = if phase == Some("ready")
            && let Some(encoded) = message["steeringInputJSON"].as_str()
        {
            let bytes = STANDARD
                .decode(encoded)
                .map_err(|_| AppKitDraftError::InvalidSource)?;
            let mut input: Vec<Value> = serde_json::from_slice(&bytes)?;
            for item in &mut input {
                if item["type"] == "localImage"
                    && let Some((_, copied)) = context
                        .iter()
                        .filter_map(|item| item.image.as_ref())
                        .find(|(original, _)| item["path"].as_str() == Some(original))
                {
                    item["path"] = json!(unicode_path(&copied.path())?);
                }
            }
            input
        } else {
            encode_queue_input(&message, &context, checkout)?
        };
        if input.is_empty() {
            return Err(AppKitDraftError::InvalidSource);
        }
        let request = queue_request(&thread, checkout, &message, &input)?;
        let attachments = context
            .into_iter()
            .filter_map(|item| item.image.map(|(_, lease)| lease))
            .collect();
        Ok(StagedQueueEntry {
            thread,
            client,
            request,
            server_id: saved_server.map(str::to_owned),
            server_receipt,
            source: message,
            attachments,
        })
    }
}

fn project_queue_preferences<'a>(
    preferences: &'a plist::Dictionary,
    project: &str,
    key: &str,
) -> Result<Option<&'a plist::Dictionary>, AppKitDraftError> {
    preferences
        .get(key)
        .map(|value| {
            let projects = value
                .as_dictionary()
                .ok_or(AppKitDraftError::InvalidSource)?;
            projects
                .get(project)
                .map(|value| value.as_dictionary().ok_or(AppKitDraftError::InvalidSource))
                .transpose()
        })
        .transpose()
        .map(Option::flatten)
}

fn queue_bucket(bucket: &str) -> Result<ThreadId, AppKitDraftError> {
    Ok(thread_from_bucket(bucket)?.unwrap_or_else(|| ThreadId(NEW_CHAT.into())))
}

fn imported_entry(
    database: &Connection,
    scope: &str,
    thread: &ThreadId,
    id: Uuid,
) -> rusqlite::Result<bool> {
    database.query_row(
        "SELECT EXISTS (SELECT 1 FROM appkit_queue_origins WHERE checkout_key = ?1 AND thread_id = ?2 AND id = ?3)",
        params![scope, thread.0, id.as_bytes().as_slice()],
        |row| row.get(0),
    )
}

fn nonempty(value: &Value) -> Result<&str, AppKitDraftError> {
    value
        .as_str()
        .filter(|text| !text.is_empty())
        .ok_or(AppKitDraftError::InvalidSource)
}

fn encode_queue_input(
    message: &Value,
    context: &[StagedItem],
    checkout: &CheckoutIdentity,
) -> Result<Vec<Value>, AppKitDraftError> {
    let original = message["text"]
        .as_str()
        .ok_or(AppKitDraftError::InvalidSource)?
        .trim();
    let body = if message["collaborationMode"]["mode"] == "plan" {
        original
            .strip_prefix("/plan ")
            .map(str::trim)
            .unwrap_or(original)
    } else {
        original
    };
    let mut text = Vec::new();
    if !body.is_empty() {
        text.push(body.to_owned());
    }
    let mut input = Vec::new();
    let mut images = 0;
    for staged in context {
        let context = &staged.item;
        match context["kind"].as_str() {
            Some("image") => {
                images += 1;
                let path = nonempty(&context["path"])?;
                if path.starts_with("data:image/") {
                    input.push(json!({"type":"image","url":path}));
                } else if Path::new(path).is_absolute() && !path.contains('\0') {
                    input.push(json!({"type":"localImage","path":path}));
                } else {
                    return Err(AppKitDraftError::InvalidSource);
                }
                if let Some(annotations) = context["imageAnnotations"].as_array() {
                    let descriptions: Vec<_> = annotations
                        .iter()
                        .filter_map(annotation_description)
                        .collect();
                    if !descriptions.is_empty() {
                        let mut section = vec![format!("Image {images}:")];
                        section.extend(
                            descriptions
                                .into_iter()
                                .enumerate()
                                .map(|(index, description)| {
                                    format!("{}. {description}", index + 1)
                                }),
                        );
                        text.push(section.join("\n"));
                    }
                }
            }
            Some("fileReference") => {
                let file = Path::new(nonempty(&context["path"])?);
                let file = checkout.canonical_path().join(file).canonicalize()?;
                let relative = file
                    .strip_prefix(checkout.canonical_path())
                    .ok()
                    .filter(|path| !path.as_os_str().is_empty())
                    .ok_or(AppKitDraftError::InvalidSource)?;
                let name = context["recordedMentionName"].as_str();
                if name.is_none() {
                    text.push(format!("File reference: {}", unicode_path(relative)?));
                }
                let name = name
                    .or_else(|| file.file_name().and_then(|name| name.to_str()))
                    .ok_or(AppKitDraftError::InvalidSource)?;
                input.push(json!({"type":"mention","name":name,"path":unicode_path(&file)?}));
            }
            Some("textExcerpt") => {
                let path = nonempty(&context["path"])?;
                let excerpt = context["excerpt"]
                    .as_str()
                    .ok_or(AppKitDraftError::InvalidSource)?;
                let first = context["firstLine"].as_u64().unwrap_or(1);
                let lines: Vec<_> = excerpt
                    .split('\n')
                    .enumerate()
                    .map(|(index, line)| {
                        format!(
                            "{}: {}",
                            first.saturating_add(index as u64),
                            line.strip_suffix('\r').unwrap_or(line)
                        )
                    })
                    .collect();
                let last = context["lastLine"]
                    .as_u64()
                    .unwrap_or_else(|| first.saturating_add(lines.len().saturating_sub(1) as u64));
                text.push(format!(
                    "Selected code from {path}, lines {first}–{last}:\n{}",
                    lines.join("\n")
                ));
            }
            _ => return Err(AppKitDraftError::InvalidSource),
        }
    }
    if !text.is_empty() {
        input.insert(0, json!({"type":"text","text":text.join("\n\n")}));
    }
    if let Some(skills) = message["skills"].as_array() {
        for skill in skills {
            input.push(json!({"type":"skill","name":nonempty(&skill["name"])?, "path":nonempty(&skill["path"])?}));
        }
    }
    Ok(input)
}

fn annotation_description(annotation: &Value) -> Option<String> {
    let x = annotation["x"]
        .as_f64()
        .filter(|value| (0.0..=1.0).contains(value))?;
    let y = annotation["y"]
        .as_f64()
        .filter(|value| (0.0..=1.0).contains(value))?;
    let text = annotation["text"]
        .as_str()
        .filter(|text| !text.trim().is_empty())?;
    Some(format!(
        "(x: {}%, y: {}%) {text}",
        (x * 1000.0).round() / 10.0,
        (y * 1000.0).round() / 10.0
    ))
}

fn queue_request(
    thread: &ThreadId,
    checkout: &CheckoutIdentity,
    message: &Value,
    input: &[Value],
) -> Result<Value, AppKitDraftError> {
    let preferences = &message["preferences"];
    let configuration = &preferences["configurationDefaults"];
    let full = preferences["approvalMode"] == "fullAccess";
    let policy = configuration["approvalPolicy"].as_str().unwrap_or(if full {
        "never"
    } else {
        "on-request"
    });
    let reviewer = if configuration["approvalPolicy"].is_null()
        && preferences["approvalMode"] == "approveForMe"
    {
        "auto_review"
    } else {
        "user"
    };
    let sandbox = match configuration["sandboxMode"].as_str() {
        Some("read-only") => json!({"type":"readOnly"}),
        Some("danger-full-access") => json!({"type":"dangerFullAccess"}),
        None if full => json!({"type":"dangerFullAccess"}),
        _ => {
            json!({"type":"workspaceWrite","networkAccess":configuration["networkAccess"].as_bool().unwrap_or(false)})
        }
    };
    let tier = message["serviceTier"]
        .as_str()
        .or_else(|| preferences["composerServiceTier"].as_str())
        .or_else(|| configuration["serviceTier"].as_str())
        .unwrap_or(if preferences["fastMode"] == true {
            "priority"
        } else {
            "default"
        });
    let collaboration = &message["collaborationMode"];
    let mode = if collaboration.is_null() {
        Value::Null
    } else {
        json!({
            "mode":nonempty(&collaboration["mode"])?,
            "settings":{
                "model":nonempty(&collaboration["model"])?,
                "reasoning_effort":collaboration["reasoningEffort"],
                "developer_instructions":null,
            }
        })
    };
    Ok(json!({
        "threadId":thread.0,
        "cwd":unicode_path(checkout.canonical_path())?,
        "clientUserMessageId":nonempty(&message["id"])?,
        "input":input,
        "model":message["modelID"],
        "effort":message["effort"],
        "serviceTierForTurn":tier,
        "approvalPolicy":policy,
        "approvalsReviewer":reviewer,
        "sandboxPolicy":sandbox,
        "collaborationMode":mode,
    }))
}

pub(in crate::storage) fn migrate(tx: &Transaction<'_>) -> rusqlite::Result<()> {
    tx.execute_batch(
        "CREATE TABLE appkit_queue_origins (
            checkout_key TEXT NOT NULL,
            thread_id TEXT NOT NULL,
            id BLOB NOT NULL CHECK (length(id) = 16),
            source TEXT NOT NULL CHECK (json_valid(source) AND json_type(source) = 'object'),
            PRIMARY KEY (checkout_key, thread_id, id)
         ) STRICT, WITHOUT ROWID;",
    )
}
