use std::time::Duration;

use serde::{Deserialize, Serialize};
use serde_json::json;
use thiserror::Error;
use tokio::sync::watch;
use ts_rs::TS;

use super::{AppServerClient, HistoryTurn, RequestError, TurnStatus};
use crate::identity::ThreadId;

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize, TS)]
#[serde(tag = "type", rename_all = "camelCase")]
pub enum ReviewTarget {
    UncommittedChanges,
    BaseBranch { branch: String },
    Commit { sha: String },
    Custom { instructions: String },
}

impl ReviewTarget {
    pub fn from_argument(argument: &str) -> Option<Self> {
        if argument == "uncommitted" {
            return Some(Self::UncommittedChanges);
        }
        let (kind, argument) = argument.split_once(char::is_whitespace)?;
        let value = argument.trim().to_owned();
        let target = match kind {
            "base" => Self::BaseBranch { branch: value },
            "commit" => Self::Commit { sha: value },
            "custom" => Self::Custom {
                instructions: value,
            },
            _ => return None,
        };
        target.valid().then_some(target)
    }

    pub fn valid(&self) -> bool {
        match self {
            Self::UncommittedChanges => true,
            Self::BaseBranch { branch } => {
                !branch.is_empty()
                    && branch.len() <= 512
                    && !branch
                        .chars()
                        .any(|ch| ch.is_whitespace() || ch.is_control())
            }
            Self::Commit { sha } => {
                (7..=64).contains(&sha.len()) && sha.bytes().all(|byte| byte.is_ascii_hexdigit())
            }
            Self::Custom { instructions } => {
                instructions.len() <= 8192
                    && !instructions.trim().is_empty()
                    && !instructions.contains('\0')
            }
        }
    }
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub enum ReviewDelivery {
    Inline,
    Detached,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewStarted {
    pub review_thread_id: ThreadId,
    pub turn: HistoryTurn,
}

#[derive(Debug, Error)]
pub enum ReviewError {
    #[error(transparent)]
    Request(#[from] RequestError),
    #[error("the review target is invalid")]
    InvalidTarget,
    #[error("the review has no checkout owner")]
    MissingCheckout,
    #[error("the review acknowledgement changed the captured owner")]
    InvalidReply,
}

impl AppServerClient {
    pub async fn start_review(
        &self,
        thread: &ThreadId,
        target: &ReviewTarget,
        delivery: ReviewDelivery,
        timeout: Duration,
    ) -> Result<ReviewStarted, ReviewError> {
        if !target.valid() || thread.0.is_empty() {
            return Err(ReviewError::InvalidTarget);
        }
        let checkout = self
            .identity()
            .workspace
            .checkout
            .clone()
            .ok_or(ReviewError::MissingCheckout)?;
        let (_keep, stopped) = watch::channel(false);
        let reply = self
            .request_scoped(
                "review/start",
                json!({"threadId": thread.0, "target": target, "delivery": delivery}),
                timeout,
                checkout,
                stopped,
            )
            .await?;
        let started: ReviewStarted =
            serde_json::from_value(reply).map_err(|_| ReviewError::InvalidReply)?;
        if started.review_thread_id.0.is_empty()
            || started.turn.activity.id.0.is_empty()
            || started.turn.activity.status == TurnStatus::Unknown
            || (&started.review_thread_id == thread) != (delivery == ReviewDelivery::Inline)
        {
            return Err(ReviewError::InvalidReply);
        }
        Ok(started)
    }
}
