use std::collections::{HashMap, VecDeque};

use indexmap::IndexMap;

use crate::{
    codex::{HistoryTurn, ServerEvent, TurnStatus},
    identity::{ConnectionIdentity, ThreadId},
};

use super::*;

const MAX_RESIDENT_REPORTS: usize = 12;
const MAX_REPORT_ITEMS: usize = 128;

pub struct TurnEditReports {
    owner: ConnectionIdentity,
    chats: HashMap<ThreadId, ChatReports>,
    residents: VecDeque<ThreadId>,
}

#[derive(Default)]
struct ChatReports {
    active: Option<TurnMark>,
    latest: Option<LatestReport>,
}

#[derive(Clone)]
struct TurnMark {
    id: TurnId,
    started_at: Option<i64>,
}

struct LatestReport {
    turn: TurnMark,
    body: Option<ReportBody>,
}

struct ReportBody {
    items: IndexMap<String, ReportItem>,
    incomplete: bool,
    result: Arc<TurnEdits>,
}

impl TurnEditReports {
    pub fn new(owner: ConnectionIdentity) -> Self {
        Self {
            owner,
            chats: HashMap::new(),
            residents: VecDeque::new(),
        }
    }

    pub fn current(&self, thread: &ThreadId) -> Option<Arc<TurnEdits>> {
        let latest = self.chats.get(thread)?.latest.as_ref()?;
        Some(latest.body.as_ref()?.result.clone())
    }

    pub fn view(&self, thread: &ThreadId) -> Option<LastTurnView> {
        let latest = self.chats.get(thread)?.latest.as_ref()?;
        Some(latest.body.as_ref().map_or_else(
            || LastTurnView {
                turn_id: latest.turn.id.0.clone(),
                revision: None,
                quality: TurnEditQuality::Missing,
                totals: None,
            },
            |body| body.result.view().clone(),
        ))
    }

    /// The app-server returns this newest-first page from a scoped latest history read.
    pub fn apply_latest_history(
        &mut self,
        owner: &ConnectionIdentity,
        thread: &ThreadId,
        turns: &[HistoryTurn],
    ) {
        if owner != &self.owner {
            return;
        }
        let Some(checkout) = &owner.workspace.checkout else {
            return;
        };
        if checkout.revalidate().is_err() {
            return;
        }
        let candidate = turns.iter().enumerate().find_map(|(index, turn)| {
            let items = file_change_items(checkout, turn);
            (!items.0.is_empty() || items.1).then_some((index, turn, items))
        });
        let chat = self.chats.entry(thread.clone()).or_default();
        if let Some(active) = turns
            .iter()
            .find(|turn| turn.activity.status == TurnStatus::InProgress)
        {
            chat.active = Some(mark(active));
        }
        let Some((position, turn, (mut items, incomplete))) = candidate else {
            return;
        };
        let next = mark(turn);
        if let Some(latest) = &chat.latest
            && latest.turn.id != next.id
        {
            let ordered = turns
                .iter()
                .position(|turn| turn.activity.id == latest.turn.id)
                .map_or_else(
                    || {
                        next.started_at
                            .zip(latest.turn.started_at)
                            .is_some_and(|(new, prior)| new > prior)
                    },
                    |prior| position < prior,
                );
            if !ordered {
                return;
            }
        }
        if let Some(prior) = &chat.latest
            && prior.turn.id == next.id
            && let Some(body) = &prior.body
        {
            for (id, incoming) in &mut items {
                if !incoming.terminal
                    && let Some(completed) = body.items.get(id).filter(|item| item.terminal)
                {
                    incoming.clone_from(completed);
                }
            }
        }
        let stable = chat.latest.as_ref().is_some_and(|prior| {
            prior.turn.id == next.id
                && prior
                    .body
                    .as_ref()
                    .is_some_and(|body| body.items == items && body.incomplete == incomplete)
        });
        if !stable {
            chat.latest = Some(LatestReport {
                body: Some(ReportBody::new(&next.id, items, incomplete)),
                turn: next,
            });
        }
        self.touch(thread);
    }

    pub fn observe(&mut self, owner: &ConnectionIdentity, event: &ServerEvent) {
        if owner != &self.owner {
            return;
        }
        let Some(checkout) = &owner.workspace.checkout else {
            return;
        };
        let ServerEvent::Notification { method, params } = event else {
            return;
        };
        let turn_started = method == "turn/started";
        let turn_finished = method == "turn/completed";
        let live_patch = method == "item/fileChange/patchUpdated";
        let result_item = matches!(method.as_str(), "item/started" | "item/completed")
            && params["item"]["type"] == "fileChange";
        if !(turn_started || turn_finished || live_patch || result_item) {
            return;
        }
        if checkout.revalidate().is_err() {
            return;
        }
        let Some(thread) = value_id(&params["threadId"]).map(ThreadId) else {
            return;
        };
        let turn = if turn_started || turn_finished {
            &params["turn"]["id"]
        } else {
            &params["turnId"]
        };
        let Some(turn) = value_id(turn).map(TurnId) else {
            return;
        };
        let chat = self.chats.entry(thread.clone()).or_default();
        if turn_started {
            chat.active = Some(TurnMark {
                id: turn,
                started_at: params["turn"]["startedAt"].as_i64(),
            });
            return;
        }
        if turn_finished {
            if chat.active.as_ref().is_some_and(|active| active.id == turn) {
                chat.active = None;
            }
            return;
        }
        let item = if live_patch {
            &params["itemId"]
        } else {
            &params["item"]["id"]
        };
        let Some(item) = value_id(item) else { return };
        let active = chat
            .active
            .as_ref()
            .filter(|active| active.id == turn)
            .cloned();
        let same_turn = chat
            .latest
            .as_ref()
            .is_some_and(|latest| latest.turn.id == turn);
        if !same_turn {
            let Some(active) = active else { return };
            chat.latest = Some(LatestReport {
                turn: active,
                body: None,
            });
        }
        let changes = if live_patch {
            &params["changes"]
        } else {
            &params["item"]["changes"]
        };
        let terminal = method == "item/completed";
        let report = ReportItem::read(
            checkout,
            changes,
            terminal,
            !terminal || params["item"]["status"] != "completed",
        );
        let latest = chat.latest.as_mut().expect("known reported turn");
        if let Some(body) = &mut latest.body {
            if body
                .items
                .get(&item)
                .is_some_and(|prior| prior == &report || (prior.terminal && !terminal))
            {
                return;
            }
            admit_item(&mut body.items, &mut body.incomplete, item, report);
            body.result = TurnEdits::build(&turn, body.items.values(), body.incomplete);
        } else {
            let items = IndexMap::from([(item, report)]);
            latest.body = Some(ReportBody::new(&turn, items, same_turn));
        }
        self.touch(&thread);
    }

    fn touch(&mut self, thread: &ThreadId) {
        self.residents.retain(|current| current != thread);
        self.residents.push_back(thread.clone());
        if self.residents.len() > MAX_RESIDENT_REPORTS
            && let Some(evicted) = self.residents.pop_front()
            && let Some(report) = self
                .chats
                .get_mut(&evicted)
                .and_then(|chat| chat.latest.as_mut())
        {
            report.body = None;
        }
    }
}

impl ReportBody {
    fn new(turn: &TurnId, items: IndexMap<String, ReportItem>, incomplete: bool) -> Self {
        let result = TurnEdits::build(turn, items.values(), incomplete);
        Self {
            items,
            incomplete,
            result,
        }
    }
}

fn mark(turn: &HistoryTurn) -> TurnMark {
    TurnMark {
        id: turn.activity.id.clone(),
        started_at: turn.started_at,
    }
}

fn value_id(value: &Value) -> Option<String> {
    value
        .as_str()
        .filter(|id| !id.is_empty())
        .map(str::to_owned)
}

fn file_change_items(
    checkout: &CheckoutIdentity,
    turn: &HistoryTurn,
) -> (IndexMap<String, ReportItem>, bool) {
    let mut items = IndexMap::new();
    let mut incomplete = false;
    for item in turn
        .items
        .iter()
        .filter(|item| item["type"] == "fileChange")
    {
        let Some(id) = value_id(&item["id"]) else {
            incomplete = true;
            continue;
        };
        let status = item["status"].as_str();
        let terminal = matches!(status, Some("completed" | "failed" | "declined"));
        let report = ReportItem::read(
            checkout,
            &item["changes"],
            terminal,
            status != Some("completed"),
        );
        admit_item(&mut items, &mut incomplete, id, report);
    }
    (items, incomplete)
}

fn admit_item(
    items: &mut IndexMap<String, ReportItem>,
    incomplete: &mut bool,
    id: String,
    report: ReportItem,
) {
    let replaced = items.get(&id);
    let bytes = items.values().map(ReportItem::bytes).sum::<usize>();
    if (replaced.is_none() && items.len() == MAX_REPORT_ITEMS)
        || bytes - replaced.map_or(0, ReportItem::bytes) + report.bytes() > MAX_REPORT_BYTES
    {
        *incomplete = true;
        return;
    }
    items.insert(id, report);
}
