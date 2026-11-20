use serde::{Deserialize, Serialize};
use ts_rs::TS;

use super::TranscriptRowRequest;

#[derive(Clone, Copy, Debug, Deserialize, Serialize, TS)]
#[serde(rename_all = "snake_case")]
pub enum FeedbackRating {
    GoodResult,
    BadResult,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct FeedbackRequest {
    pub row: TranscriptRowRequest,
    pub rating: FeedbackRating,
}

#[derive(Clone, Debug, Default, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct FeedbackView {
    pub available: bool,
    pub blocked_turns: Vec<String>,
}
