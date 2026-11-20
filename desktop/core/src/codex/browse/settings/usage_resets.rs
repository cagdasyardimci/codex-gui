use std::time::{SystemTime, UNIX_EPOCH};

use uuid::Uuid;

use super::*;
use crate::{files::FileRevision, ipc::UsageResetOffer};

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct CreditList {
    available_count: u32,
    credits: Option<Vec<Credit>>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Credit {
    id: String,
    title: Option<String>,
    status: String,
    reset_type: String,
    expires_at: Option<i64>,
}

#[derive(Clone)]
pub struct ResetCandidate {
    pub offer: UsageResetOffer,
    pub key: String,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq)]
#[serde(rename_all = "camelCase")]
pub enum UsageResetOutcome {
    Reset,
    AlreadyRedeemed,
    NothingToReset,
    NoCredit,
}

impl SettingsRateLimits {
    pub fn reset_balance(&self) -> Option<u32> {
        self.rate_limit_reset_credits
            .as_ref()
            .map(|credits| credits.available_count)
    }

    pub fn reset_candidates(&self) -> Vec<ResetCandidate> {
        let Some(credits) = &self.rate_limit_reset_credits else {
            return Vec::new();
        };
        if credits.available_count == 0 || self.account_id.as_deref().is_none_or(str::is_empty) {
            return Vec::new();
        }
        let windows = self.windows();
        if !windows.iter().any(|window| {
            window
                .remaining_percent
                .is_some_and(|remaining| remaining <= 10.0)
        }) {
            return Vec::new();
        }
        let Ok(now) = SystemTime::now().duration_since(UNIX_EPOCH) else {
            return Vec::new();
        };
        let Ok(now) = i64::try_from(now.as_secs()) else {
            return Vec::new();
        };
        if let Some(available) = &credits.credits {
            let mut seen = HashSet::new();
            return available
                .iter()
                .filter(|credit| {
                    credit.status == "available"
                        && credit.reset_type == "codexRateLimits"
                        && !credit.id.is_empty()
                        && credit.id.len() <= 512
                        && credit.expires_at.is_none_or(|expires| expires > now)
                        && seen.insert(&credit.id)
                })
                .take(40)
                .map(|credit| ResetCandidate {
                    key: format!("named:{}", credit.id),
                    offer: UsageResetOffer {
                        id: Some(credit.id.clone()),
                        title: credit
                            .title
                            .as_ref()
                            .filter(|title| !title.trim().is_empty())
                            .cloned()
                            .unwrap_or_else(|| "Full Reset".into()),
                        expires_at: credit.expires_at,
                    },
                })
                .collect();
        }

        let windows = windows
            .iter()
            .map(|window| (&window.name, window.minutes, window.resets_at))
            .collect::<Vec<_>>();
        let fingerprint = json!([credits.available_count, windows]).to_string();
        vec![ResetCandidate {
            key: format!(
                "next:{}",
                FileRevision::from_bytes(fingerprint.as_bytes()).digest
            ),
            offer: UsageResetOffer {
                id: None,
                title: "Usage Reset".into(),
                expires_at: None,
            },
        }]
    }
}

impl CodexBrowser {
    pub async fn redeem_usage_reset(
        &self,
        credit_id: Option<&str>,
        attempt: Uuid,
        timeout: Duration,
    ) -> Result<UsageResetOutcome, BrowseError> {
        #[derive(Deserialize)]
        struct Receipt {
            outcome: UsageResetOutcome,
        }
        let mut request = json!({"idempotencyKey": attempt});
        if let Some(credit_id) = credit_id {
            request["creditId"] = json!(credit_id);
        }
        let receipt: Receipt = self
            .read("account/rateLimitResetCredit/consume", request, timeout)
            .await?;
        Ok(receipt.outcome)
    }
}
