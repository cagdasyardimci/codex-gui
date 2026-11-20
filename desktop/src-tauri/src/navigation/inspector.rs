use codex_gui_core::{
    codex::HistoryTurn,
    ipc::{InspectorAgent, InspectorSource, InspectorSourceRequest, InspectorView},
};
use serde_json::Value;
use tauri::Url;
use tokio::time::Instant;

use super::*;

mod child;
pub(super) use child::{ChildFinished, ChildRead};

const MAX_SOURCES: usize = 64;
const MAX_AGENTS: usize = 64;
const MAX_LABEL_CHARS: usize = 240;
const MAX_DETAIL_CHARS: usize = 8_192;
const CHILD_REFRESH_DELAY: Duration = Duration::from_millis(120);

#[derive(Default)]
pub(super) struct Inspector {
    sources: Vec<Source>,
    agents: Vec<InspectorAgent>,
    selected_child: Option<String>,
    child: Option<child::ChildState>,
    child_revision: u32,
    refresh_at: Option<Instant>,
}

struct Source {
    view: InspectorSource,
    url: Option<Url>,
    detail: Option<String>,
}

impl Inspector {
    pub(super) fn view(&self) -> InspectorView {
        InspectorView {
            sources: self
                .sources
                .iter()
                .map(|source| source.view.clone())
                .collect(),
            agents: self.agents.clone(),
            child_revision: self.child_revision,
        }
    }

    pub(super) fn history(&mut self, parent: &ThreadId, turns: &[HistoryTurn]) {
        for turn in turns.iter().rev() {
            for item in &turn.items {
                self.item(parent, &turn.activity.id.0, item);
            }
        }
    }

    pub(super) fn event(&mut self, parent: &ThreadId, event: &ServerEvent) -> bool {
        let ServerEvent::Notification { method, params } = event else {
            return false;
        };
        let thread = params["threadId"].as_str();
        if thread.is_some()
            && thread == self.selected_child.as_deref()
            && matches!(
                method.as_str(),
                "turn/started"
                    | "turn/completed"
                    | "item/started"
                    | "item/completed"
                    | "item/agentMessage/delta"
            )
        {
            self.refresh_at
                .get_or_insert_with(|| Instant::now() + CHILD_REFRESH_DELAY);
        }
        if thread != Some(parent.0.as_str())
            || !matches!(method.as_str(), "item/started" | "item/completed")
        {
            return false;
        }
        params["turnId"]
            .as_str()
            .is_some_and(|turn| self.item(parent, turn, &params["item"]))
    }

    pub(super) fn flush_child(&mut self) -> bool {
        if self.refresh_at.is_none_or(|ready| Instant::now() < ready) {
            return false;
        }
        self.refresh_at = None;
        self.child_revision = self.child_revision.wrapping_add(1);
        true
    }

    fn item(&mut self, parent: &ThreadId, turn: &str, item: &Value) -> bool {
        let Some(kind) = item["type"].as_str() else {
            return false;
        };
        match kind {
            "subAgentActivity" => item["agentThreadId"]
                .as_str()
                .is_some_and(|id| self.agent(parent, id, item["agentPath"].as_str())),
            "collabAgentToolCall"
                if item["tool"] == "spawnAgent" && item["senderThreadId"] == parent.0 =>
            {
                let mut changed = false;
                if let Some(receivers) = item["receiverThreadIds"].as_array() {
                    for id in receivers.iter().filter_map(Value::as_str) {
                        changed |= self.agent(parent, id, None);
                    }
                }
                changed
            }
            "webSearch" | "mcpToolCall" | "dynamicToolCall" => {
                source(turn, item, kind).is_some_and(|source| self.record_source(source))
            }
            _ => false,
        }
    }

    fn agent(&mut self, parent: &ThreadId, id: &str, path: Option<&str>) -> bool {
        if id.is_empty() || id.len() > MAX_LABEL_CHARS || id == parent.0 {
            return false;
        }
        let label = path
            .and_then(|path| path.rsplit('/').find(|segment| !segment.is_empty()))
            .map(|segment| segment.replace('_', " "));
        if let Some(agent) = self.agents.iter_mut().find(|agent| agent.id == id) {
            if let Some(label) = label
                && agent.label != label
            {
                agent.label = label.chars().take(MAX_LABEL_CHARS).collect();
                return true;
            }
            return false;
        }
        if self.agents.len() >= MAX_AGENTS {
            return false;
        }
        self.agents.push(InspectorAgent {
            id: id.to_owned(),
            label: label
                .unwrap_or_else(|| "Subagent".into())
                .chars()
                .take(MAX_LABEL_CHARS)
                .collect(),
        });
        true
    }

    fn record_source(&mut self, source: Source) -> bool {
        if let Some(prior) = self
            .sources
            .iter_mut()
            .find(|record| record.view.id == source.view.id)
        {
            if prior.view.label == source.view.label
                && prior.view.category == source.view.category
                && prior.url == source.url
                && prior.detail == source.detail
            {
                return false;
            }
            *prior = source;
        } else {
            if self.sources.len() >= MAX_SOURCES {
                self.sources.remove(0);
            }
            self.sources.push(source);
        }
        true
    }
}

fn source(turn: &str, item: &Value, kind: &str) -> Option<Source> {
    let raw_id = item["id"].as_str().filter(|value| !value.is_empty())?;
    let id = transcript_id(turn, raw_id);
    let (label, category, url, detail) = if kind == "webSearch" {
        let url = item["action"]["url"].as_str().and_then(safe_url);
        let label = url
            .as_ref()
            .map(Url::as_str)
            .or_else(|| item["query"].as_str())
            .filter(|label| !label.is_empty())?;
        (label.to_owned(), "Web Search", url, None)
    } else {
        let tool = item["tool"].as_str().filter(|tool| !tool.is_empty())?;
        let label = match item["server"].as_str().filter(|server| !server.is_empty()) {
            Some(server) => format!("{server} · {tool}"),
            None => tool.to_owned(),
        };
        let detail = item
            .get("result")
            .filter(|result| !result.is_null())
            .and_then(|result| serde_json::to_string_pretty(result).ok())
            .map(|text| text.chars().take(MAX_DETAIL_CHARS).collect());
        (label, "Tools", None, detail)
    };
    let view = InspectorSource {
        id,
        revision: Uuid::new_v4(),
        label: label.chars().take(MAX_LABEL_CHARS).collect(),
        category: category.to_owned(),
        has_detail: detail.is_some(),
        can_open: url.is_some(),
    };
    Some(Source { view, url, detail })
}

fn safe_url(text: &str) -> Option<Url> {
    let url = Url::parse(text).ok()?;
    (url.scheme() == "https"
        && url.host_str().is_some()
        && url.username().is_empty()
        && url.password().is_none())
    .then_some(url)
}

impl NavigationHandle {
    pub(crate) async fn inspector_source(
        &self,
        source: InspectorSourceRequest,
    ) -> Result<Url, IpcError> {
        let (reply, result) = oneshot::channel();
        self.request(Action::InspectorSource(source, reply)).await?;
        result.await.map_err(|_| IpcError::ProjectUnavailable)
    }

    pub(crate) async fn inspector_source_detail(
        &self,
        source: InspectorSourceRequest,
    ) -> Result<String, IpcError> {
        let (reply, result) = oneshot::channel();
        self.request(Action::InspectorSourceDetail(source, reply))
            .await?;
        result.await.map_err(|_| IpcError::ProjectUnavailable)
    }
}

impl Navigation {
    pub(super) fn inspector_scope(
        &self,
        scope: &codex_gui_core::ipc::ChatRequest,
    ) -> Result<(), IpcError> {
        self.require(scope.workspace_id)?;
        if self.quit.is_some() || self.view.selected_chat.as_deref() != Some(scope.chat_id.as_str())
        {
            return Err(IpcError::StaleSelection);
        }
        Ok(())
    }

    fn inspector_source_record(&self, source: InspectorSourceRequest) -> Result<&Source, IpcError> {
        self.inspector_scope(&source.scope)?;
        self.inspector
            .sources
            .iter()
            .find(|entry| {
                entry.view.id == source.source_id && entry.view.revision == source.revision
            })
            .ok_or(IpcError::StaleSelection)
    }

    pub(super) fn inspector_source_url(
        &self,
        source: InspectorSourceRequest,
    ) -> Result<Url, IpcError> {
        self.inspector_source_record(source)?
            .url
            .clone()
            .ok_or(IpcError::StaleSelection)
    }

    pub(super) fn inspector_detail(
        &self,
        source: InspectorSourceRequest,
    ) -> Result<String, IpcError> {
        self.inspector_source_record(source)?
            .detail
            .clone()
            .ok_or(IpcError::StaleSelection)
    }
}
