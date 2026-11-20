use super::*;

#[derive(Clone, Debug, Eq, PartialEq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum SpeechRole {
    User,
    Assistant,
}

#[derive(Clone, Debug, Eq, PartialEq, Deserialize)]
pub struct VoiceSegment {
    pub id: String,
    pub role: SpeechRole,
    pub text: String,
}

impl VoiceSegment {
    pub fn from_item(item: &Value) -> Option<Self> {
        if item["type"] != "transcriptSegment" {
            return None;
        }
        let spoken: Self = serde_json::from_value(item.clone()).ok()?;
        (!spoken.id.is_empty() && !spoken.text.trim().is_empty()).then_some(spoken)
    }
}

#[derive(Clone, Debug)]
pub enum TimelineEntry {
    Turn { id: String, started: bool },
    VoiceStarted,
    VoiceClosed,
    Speech(VoiceSegment),
}

#[derive(Clone, Debug, Eq, PartialEq, Hash)]
pub struct TimelineCursor {
    owner: ConnectionIdentity,
    thread: ThreadId,
    token: String,
}

#[derive(Clone, Debug)]
pub struct VoiceTimelinePage {
    pub entries: Vec<TimelineEntry>,
    pub active_at_start: Option<bool>,
    pub next: Option<TimelineCursor>,
}

impl CodexBrowser {
    pub async fn voice_timeline(
        &self,
        chat: &ChatRead<ChatSummary>,
        cursor: Option<&TimelineCursor>,
        timeout: Duration,
    ) -> Result<ChatRead<VoiceTimelinePage>, BrowseError> {
        self.validate_chat(chat)?;
        let scope = &chat.scope;
        let token = match cursor {
            Some(cursor) if cursor.owner == scope.connection && cursor.thread == scope.thread => {
                Some(&cursor.token)
            }
            Some(_) => return Err(BrowseError::CursorScope),
            None => None,
        };
        #[derive(Deserialize)]
        #[serde(rename_all = "camelCase")]
        struct Response {
            data: Vec<Value>,
            next_cursor: Option<String>,
        }
        let method = "thread/timeline/list";
        let raw: Value = self
            .read(
                method,
                json!({"threadId": scope.thread.0, "cursor": token, "limit": 100}),
                timeout,
            )
            .await?;
        self.validate_chat(chat)?;
        let active_at_start = raw
            .get("activeRealtimeSessionAtPageStart")
            .map(Value::is_string);
        let response: Response = serde_json::from_value(raw)
            .map_err(|source| BrowseError::Response { method, source })?;
        let entries = response
            .data
            .into_iter()
            .filter_map(|entry| match entry["type"].as_str()? {
                "turnStarted" | "turnCompleted" => Some(TimelineEntry::Turn {
                    id: entry["turnId"].as_str()?.to_owned(),
                    started: entry["type"] == "turnStarted",
                }),
                "realtime" => match entry["item"]["type"].as_str()? {
                    "realtimeSessionStarted" => Some(TimelineEntry::VoiceStarted),
                    "realtimeSessionClosed" => Some(TimelineEntry::VoiceClosed),
                    _ => VoiceSegment::from_item(&entry["item"]).map(TimelineEntry::Speech),
                },
                _ => None,
            })
            .collect();
        let next = response
            .next_cursor
            .filter(|value| !value.is_empty())
            .map(|token| TimelineCursor {
                owner: scope.connection.clone(),
                thread: scope.thread.clone(),
                token,
            });
        Ok(ChatRead {
            scope: scope.clone(),
            data: VoiceTimelinePage {
                entries,
                active_at_start,
                next,
            },
        })
    }
}
