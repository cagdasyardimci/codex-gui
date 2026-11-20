use std::{collections::HashMap, sync::Arc};

use codex_gui_core::{
    identity::ThreadId,
    ipc::{
        ApprovalChoice, ApprovalView, DictationTarget, InteractionAnswer, InteractionContent,
        InteractionView, IpcError, PermissionChoice, PermissionView, QuestionAnswer, QuestionView,
        RespondRequest, WriteAccess,
    },
    workspace::{InteractionKind, InteractionResponse, PendingInteraction, PermissionScope},
};
use serde_json::{Value, json};
use uuid::Uuid;

use super::{Navigation, RPC_TIMEOUT, report};

#[derive(Default)]
pub(super) struct InteractionProjection {
    tickets: HashMap<String, Arc<PendingInteraction>>,
}

impl InteractionProjection {
    pub fn project(
        &mut self,
        requests: Vec<Arc<PendingInteraction>>,
        selected: Option<&ThreadId>,
    ) -> Vec<InteractionView> {
        self.tickets.retain(|_, stored| {
            requests
                .iter()
                .any(|request| request.identity == stored.identity)
        });
        requests
            .into_iter()
            .filter(|request| Some(&request.identity.thread) == selected)
            .filter_map(|request| {
                let content = present(&request)?;
                let id = self
                    .tickets
                    .iter()
                    .find(|(_, stored)| stored.identity == request.identity)
                    .map(|(ticket, _)| ticket.clone())
                    .unwrap_or_else(|| {
                        let ticket = Uuid::new_v4().to_string();
                        self.tickets.insert(ticket.clone(), request);
                        ticket
                    });
                Some(InteractionView { id, content })
            })
            .collect()
    }
}

impl Navigation {
    pub(super) fn can_dictate(&self, target: &DictationTarget) -> bool {
        self.quit.is_none() && self.view.write_access == WriteAccess::Ready
            && self.selection.as_ref().is_some_and(|selection| selection.id == target.workspace_id)
            && self.view.actions.interactions.iter().any(|request| {
                request.id == target.interaction_id && matches!(
                    &request.content,
                    InteractionContent::Questions(questions) if questions.iter().any(|question| {
                        question.id == target.question_id && question.accepts_text && !question.secret
                    })
                )
            })
    }

    pub(super) async fn respond(&mut self, request: RespondRequest) -> Result<(), IpcError> {
        self.require(request.workspace_id)?;
        if self.view.write_access != WriteAccess::Ready {
            return Err(IpcError::StaleSelection);
        }
        let pending = self
            .interactions
            .tickets
            .get(&request.interaction_id)
            .ok_or(IpcError::StaleSelection)?;
        let backend = self.backend.as_ref().ok_or(IpcError::RetiredWorkspace)?;
        let client = backend.connection.client();
        let response = wire_response(pending, request.response).ok_or(IpcError::StaleSelection)?;
        let result = backend
            .engine
            .respond_interaction(&client, pending.identity.clone(), response, RPC_TIMEOUT)
            .await
            .map_err(|error| report(error.into()));
        self.sync_actions();
        result
    }
}

fn present(request: &PendingInteraction) -> Option<InteractionContent> {
    let params = &request.parameters;
    Some(match request.kind {
        InteractionKind::Question => InteractionContent::Questions(questions(params)?),
        InteractionKind::Permission => {
            let permissions = params["permissions"]
                .as_object()?
                .iter()
                .map(|(key, value)| PermissionChoice {
                    key: key.clone(),
                    label: match key.as_str() {
                        "fileSystem" => "File access".into(),
                        "network" => "Network access".into(),
                        _ => key.clone(),
                    },
                    detail: describe_permission(value),
                })
                .collect();
            InteractionContent::Permissions(PermissionView {
                request: params["reason"].as_str().map(str::to_owned),
                permissions,
            })
        }
        InteractionKind::Command | InteractionKind::FileChange => {
            let description = params["command"]
                .as_str()
                .or(params["reason"].as_str())
                .unwrap_or(if request.kind == InteractionKind::FileChange {
                    "Apply file changes"
                } else {
                    "Run command"
                });
            let choices = decisions(request)
                .iter()
                .enumerate()
                .filter_map(|(index, value)| {
                    Some(ApprovalChoice {
                        index: u32::try_from(index).ok()?,
                        label: decision_label(value)?.into(),
                    })
                })
                .collect();
            InteractionContent::Approval(ApprovalView {
                request: description.into(),
                choices,
            })
        }
    })
}

fn describe_permission(value: &Value) -> String {
    match value {
        Value::String(value) => value.clone(),
        Value::Object(fields) => fields
            .iter()
            .filter_map(|(key, value)| {
                let detail = describe_permission(value);
                (!detail.is_empty()).then(|| format!("{key} · {detail}"))
            })
            .collect::<Vec<_>>()
            .join("\n"),
        Value::Array(items) => items
            .iter()
            .map(describe_permission)
            .collect::<Vec<_>>()
            .join("\n"),
        _ => String::new(),
    }
}

fn questions(params: &Value) -> Option<Vec<QuestionView>> {
    params["questions"]
        .as_array()?
        .iter()
        .map(|question| {
            let options: Vec<String> = question["options"]
                .as_array()
                .into_iter()
                .flatten()
                .filter_map(|option| option["label"].as_str().map(str::to_owned))
                .collect();
            Some(QuestionView {
                id: question["id"].as_str()?.into(),
                prompt: question["question"].as_str()?.into(),
                accepts_text: question["isOther"].as_bool().unwrap_or(false) || options.is_empty(),
                secret: question["isSecret"].as_bool().unwrap_or(false),
                options,
            })
        })
        .collect()
}

fn decisions(request: &PendingInteraction) -> Vec<Value> {
    let params = &request.parameters;
    if let Some(offered) = params["availableDecisions"].as_array() {
        return offered.clone();
    }
    let mut offered = vec![
        json!("accept"),
        json!("acceptForSession"),
        json!("decline"),
        json!("cancel"),
    ];
    if request.kind == InteractionKind::Command {
        if let Some(amendment) = params["proposedExecpolicyAmendment"].as_array() {
            offered.push(
                json!({"acceptWithExecpolicyAmendment": {"execpolicy_amendment": amendment}}),
            );
        }
        for amendment in params["proposedNetworkPolicyAmendments"]
            .as_array()
            .into_iter()
            .flatten()
        {
            offered.push(
                json!({"applyNetworkPolicyAmendment": {"network_policy_amendment": amendment}}),
            );
        }
    }
    offered
}

fn decision_label(value: &Value) -> Option<&'static str> {
    Some(match value.as_str() {
        Some("accept") => "Approve",
        Some("acceptForSession") => "Approve for Session",
        Some("decline") => "Decline",
        Some("cancel") => "Cancel",
        _ if value.get("acceptWithExecpolicyAmendment").is_some() => "Approve Command Rule",
        _ if value.get("applyNetworkPolicyAmendment").is_some() => "Apply Network Rule",
        _ => return None,
    })
}

fn wire_response(
    request: &PendingInteraction,
    answer: InteractionAnswer,
) -> Option<InteractionResponse> {
    match (request.kind, answer) {
        (
            InteractionKind::Command | InteractionKind::FileChange,
            InteractionAnswer::Decision(index),
        ) => {
            let decision = decisions(request).get(index as usize)?.clone();
            decision_label(&decision)?;
            Some(InteractionResponse::Decision(decision))
        }
        (InteractionKind::Permission, InteractionAnswer::Permissions(answer)) => {
            let requested = request.parameters["permissions"].as_object()?;
            let granted = answer
                .keys
                .into_iter()
                .map(|key| Some((key.clone(), requested.get(&key)?.clone())))
                .collect::<Option<_>>()?;
            let scope = if answer.for_session {
                PermissionScope::Session
            } else {
                PermissionScope::Turn
            };
            Some(InteractionResponse::Permissions { granted, scope })
        }
        (InteractionKind::Question, InteractionAnswer::Answers(answers)) => {
            let questions = questions(&request.parameters)?;
            if questions.len() != answers.len() {
                return None;
            }
            let by_id = questions
                .iter()
                .map(|question| {
                    let QuestionAnswer { values, .. } =
                        answers.iter().find(|answer| answer.id == question.id)?;
                    if values.is_empty()
                        || values.iter().any(|value| {
                            value.trim().is_empty()
                                || (!question.accepts_text && !question.options.contains(value))
                        })
                    {
                        return None;
                    }
                    Some((question.id.clone(), values.clone()))
                })
                .collect::<Option<_>>()?;
            Some(InteractionResponse::Answers(by_id))
        }
        _ => None,
    }
}
