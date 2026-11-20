use serde::Deserialize;
use ts_rs::TS;

use super::SendRequest;
use crate::codex::{ReviewDelivery, ReviewTarget};

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StartReviewRequest {
    pub draft: SendRequest,
    pub delivery: ReviewDelivery,
    pub target: ReviewTarget,
}
