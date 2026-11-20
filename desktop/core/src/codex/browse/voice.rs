use std::collections::BTreeMap;

use super::*;

mod locale;
pub use locale::voice_sample;

const MAX_SDP_BYTES: usize = 256 * 1024;

pub fn validate_voice_sdp(sdp: &str) -> bool {
    sdp.len() <= MAX_SDP_BYTES
        && sdp.starts_with("v=0")
        && !sdp.contains('\0')
        && sdp.lines().any(|line| line.starts_with("m=audio "))
}

#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct RealtimeVoiceCatalog {
    #[serde(default)]
    v3: Vec<String>,
    default_v3: Option<String>,
    default_v1: Option<String>,
}

impl RealtimeVoiceCatalog {
    pub(crate) fn settings_choices(self) -> Vec<crate::ipc::VoiceChoice> {
        self.v3.into_iter().map(locale::choice).collect()
    }

    pub fn contains(&self, voice: &str) -> bool {
        self.v3.iter().any(|known| known == voice)
    }

    pub(crate) fn resolve(&self, configured: Option<&str>) -> Option<String> {
        let voice = configured
            .or(self.default_v3.as_deref())
            .or(self.default_v1.as_deref())?;
        self.contains(voice).then(|| voice.to_owned())
    }
}

pub struct RealtimeVoiceSelection {
    pub voice: Option<String>,
}

pub(crate) fn realtime_enabled(config: &Value) -> bool {
    config.is_object() && config["features"]["realtime_conversation"] != false
}

pub(crate) fn has_speech_credentials(config: &Value, account: Option<&Account>) -> bool {
    let provider_id = config["model_provider"].as_str().unwrap_or("openai");
    let provider = &config["model_providers"][provider_id];
    let configured_env = |key: &str| {
        !key.is_empty()
            && !key.contains(['=', '\0'])
            && std::env::var(key).is_ok_and(|value| !value.trim().is_empty())
    };
    if let Some(key) = provider["env_key"].as_str() {
        return configured_env(key);
    }
    provider["experimental_bearer_token"]
        .as_str()
        .is_some_and(|key| !key.trim().is_empty())
        || ((provider_id == "openai" || provider["name"] == "OpenAI")
            && configured_env("OPENAI_API_KEY"))
        || matches!(account, Some(Account::ApiKey))
}

impl CodexBrowser {
    pub async fn realtime_voice_catalog(
        &self,
        timeout: Duration,
    ) -> Result<RealtimeVoiceCatalog, BrowseError> {
        #[derive(Deserialize)]
        struct Response {
            voices: RealtimeVoiceCatalog,
        }
        let mut received: Response = self
            .read("thread/realtime/listVoices", json!({}), timeout)
            .await?;
        let mut unique = std::collections::HashSet::new();
        received.voices.v3.retain(|name| {
            !name.is_empty()
                && name.len() <= 64
                && name
                    .bytes()
                    .all(|byte| byte.is_ascii_alphanumeric() || byte == b'-')
                && unique.insert(name.clone())
        });
        received.voices.v3.truncate(128);
        Ok(received.voices)
    }

    async fn realtime_configuration(&self, timeout: Duration) -> Result<Value, BrowseError> {
        let checkout = self.checkout()?;
        checkout.revalidate()?;
        let cwd = checkout
            .canonical_path()
            .to_str()
            .ok_or(BrowseError::NonUnicodeCheckout)?;
        let mut response: Value = self
            .read(
                "config/read",
                json!({"cwd": cwd, "includeLayers": false}),
                timeout,
            )
            .await?;
        checkout.revalidate()?;
        Ok(response["config"].take())
    }

    pub async fn web_voice_selection(
        &self,
        timeout: Duration,
    ) -> Result<Option<RealtimeVoiceSelection>, BrowseError> {
        let (account, config) =
            tokio::try_join!(self.account(timeout), self.realtime_configuration(timeout))?;
        if !matches!(account.account, Some(Account::Chatgpt { .. }))
            || !realtime_enabled(&config)
            || !(config["model_provider"].is_null() || config["model_provider"] == "openai")
        {
            return Ok(None);
        }
        let catalog = self
            .realtime_voice_catalog(timeout)
            .await
            .unwrap_or_default();
        let voice = catalog.resolve(config["realtime"]["voice"].as_str());
        Ok(Some(RealtimeVoiceSelection { voice }))
    }

    pub async fn speech_voice_available(
        &self,
        voice: &str,
        timeout: Duration,
    ) -> Result<bool, BrowseError> {
        let (account, config, catalog) = tokio::try_join!(
            self.account(timeout),
            self.realtime_configuration(timeout),
            self.realtime_voice_catalog(timeout),
        )?;
        Ok(realtime_enabled(&config)
            && has_speech_credentials(&config, account.account.as_ref())
            && catalog.contains(voice))
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
        voice: Option<&str>,
        timeout: Duration,
    ) -> Result<(), BrowseError> {
        let mut params = json!({
            "threadId": thread.0, "realtimeSessionId": session, "outputModality": "audio",
            "version": "v3", "transport": {"type": "webrtc", "sdp": offer},
            "flushTranscriptTailOnSessionEnd": true, "codexResponseHandoffMode": "bemTags",
        });
        if let Some(voice) = voice {
            params["voice"] = json!(voice);
        }
        self.read::<BTreeMap<String, Value>>("thread/realtime/start", params, timeout)
            .await?;
        Ok(())
    }

    pub async fn create_speech_thread(&self, timeout: Duration) -> Result<ThreadId, BrowseError> {
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
            "cwd": cwd, "ephemeral": true, "approvalPolicy": "never", "sandbox": "read-only",
        }), timeout).await?;
        checkout.validate_reported(&result.cwd)?;
        checkout.validate_reported(&result.thread.cwd)?;
        Ok(result.thread.id)
    }

    pub async fn start_speech(
        &self,
        thread: &ThreadId,
        session: uuid::Uuid,
        voice: &str,
        timeout: Duration,
    ) -> Result<(), BrowseError> {
        self.read::<BTreeMap<String, Value>>(
            "thread/realtime/start",
            json!({
                "threadId": thread.0, "realtimeSessionId": session, "voice": voice, "version": "v3",
                "outputModality": "audio", "includeStartupContext": false,
                "clientManagedHandoffs": true, "flushTranscriptTailOnSessionEnd": false,
                "transport": {"type": "websocket"},
            }),
            timeout,
        )
        .await?;
        Ok(())
    }

    pub async fn append_speech(
        &self,
        thread: &ThreadId,
        text: &str,
        timeout: Duration,
    ) -> Result<(), BrowseError> {
        self.read::<BTreeMap<String, Value>>(
            "thread/realtime/appendSpeech",
            json!({
                "threadId": thread.0, "text": text,
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn keeps_legacy_voice_catalogs_out_of_v3_settings() {
        let baseline: RealtimeVoiceCatalog = serde_json::from_value(json!({
            "v1": ["marin"], "v2": ["cedar"], "defaultV1": "marin", "defaultV2": "cedar",
        }))
        .unwrap();
        assert_eq!(baseline.resolve(None), None);
        assert!(baseline.settings_choices().is_empty());

        let modern: RealtimeVoiceCatalog = serde_json::from_value(json!({
            "v3": ["marin", "cedar"], "defaultV1": "marin",
        }))
        .unwrap();
        assert_eq!(modern.resolve(None).as_deref(), Some("marin"));
        assert_eq!(modern.resolve(Some("cedar")).as_deref(), Some("cedar"));
        assert_eq!(modern.resolve(Some("unavailable")), None);
    }
}
