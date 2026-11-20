use std::collections::BTreeMap;

use super::*;

const MAX_SDP_BYTES: usize = 256 * 1024;

pub fn validate_voice_sdp(sdp: &str) -> bool {
    sdp.len() <= MAX_SDP_BYTES
        && sdp.starts_with("v=0")
        && !sdp.contains('\0')
        && sdp.lines().any(|line| line.starts_with("m=audio "))
}

impl CodexBrowser {
    pub async fn web_voice_available(&self, timeout: Duration) -> Result<bool, BrowseError> {
        let checkout = self.checkout()?;
        checkout.revalidate()?;
        let cwd = checkout
            .canonical_path()
            .to_str()
            .ok_or(BrowseError::NonUnicodeCheckout)?;
        let (account, config) = tokio::try_join!(
            self.account(timeout),
            self.read::<Value>(
                "config/read",
                json!({"cwd": cwd, "includeLayers": false}),
                timeout
            ),
        )?;
        checkout.revalidate()?;
        Ok(matches!(account.account, Some(Account::Chatgpt { .. }))
            && config.get("config").is_some_and(|settings| {
                settings.is_object()
                    && (settings["model_provider"].is_null()
                        || settings["model_provider"] == "openai")
            }))
    }

    pub async fn create_voice_thread(
        &self,
        timeout: Duration,
    ) -> Result<ThreadSummary, BrowseError> {
        #[derive(Deserialize)]
        struct Started {
            thread: ThreadSummary,
            cwd: PathBuf,
        }
        let checkout = self.checkout()?;
        checkout.revalidate()?;
        let cwd = checkout
            .canonical_path()
            .to_str()
            .ok_or(BrowseError::NonUnicodeCheckout)?;
        let result: Started = self.read("thread/start", json!({
            "cwd": cwd, "historyMode": "paginated", "config": {"realtime.type": "conversational"},
        }), timeout).await?;
        checkout.validate_reported(&result.cwd)?;
        checkout.validate_reported(&result.thread.cwd)?;
        Ok(result.thread)
    }

    pub async fn start_voice_call(
        &self,
        thread: &ThreadId,
        session: uuid::Uuid,
        offer: &str,
        timeout: Duration,
    ) -> Result<(), BrowseError> {
        self.read::<BTreeMap<String, Value>>(
            "thread/realtime/start",
            json!({
                "threadId": thread.0, "realtimeSessionId": session, "outputModality": "audio",
                "version": "v3", "transport": {"type": "webrtc", "sdp": offer},
                "flushTranscriptTailOnSessionEnd": true, "codexResponseHandoffMode": "bemTags",
            }),
            timeout,
        )
        .await?;
        Ok(())
    }

    pub async fn append_voice_text(
        &self,
        thread: &ThreadId,
        text: &str,
        timeout: Duration,
    ) -> Result<(), BrowseError> {
        self.read::<BTreeMap<String, Value>>(
            "thread/realtime/appendText",
            json!({"threadId": thread.0, "text": text, "role": "user"}),
            timeout,
        )
        .await?;
        Ok(())
    }

    pub async fn stop_voice_call(
        &self,
        thread: &ThreadId,
        timeout: Duration,
    ) -> Result<(), BrowseError> {
        self.read::<BTreeMap<String, Value>>(
            "thread/realtime/stop",
            json!({"threadId": thread.0}),
            timeout,
        )
        .await?;
        Ok(())
    }
}
