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
    pub web_rtc: bool,
    pub web_socket: bool,
}

pub fn realtime_enabled(config: &Value) -> bool {
    config.is_object() && config["features"]["realtime_conversation"] != false
}

pub fn has_speech_credentials(config: &Value, account: Option<&Account>) -> bool {
    speech_credentials(config, account, |key| {
        !key.is_empty()
            && !key.contains(['=', '\0'])
            && std::env::var(key).is_ok_and(|value| !value.trim().is_empty())
    })
}

fn speech_credentials(
    config: &Value,
    account: Option<&Account>,
    env_present: impl Fn(&str) -> bool,
) -> bool {
    let provider_id = config["model_provider"].as_str().unwrap_or("openai");
    let provider = &config["model_providers"][provider_id];
    if let Some(key) = provider["env_key"].as_str() {
        return env_present(key);
    }
    provider["experimental_bearer_token"]
        .as_str()
        .is_some_and(|key| !key.trim().is_empty())
        || ((provider_id == "openai" || provider["name"] == "OpenAI")
            && env_present("OPENAI_API_KEY"))
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

    pub async fn voice_selection(
        &self,
        requested: Option<&str>,
        timeout: Duration,
    ) -> Result<Option<RealtimeVoiceSelection>, BrowseError> {
        let (account, config) =
            tokio::try_join!(self.account(timeout), self.realtime_configuration(timeout))?;
        if !realtime_enabled(&config) {
            return Ok(None);
        }
        let web_rtc = matches!(account.account, Some(Account::Chatgpt { .. }))
            && (config["model_provider"].is_null() || config["model_provider"] == "openai");
        let catalog = self
            .realtime_voice_catalog(timeout)
            .await
            .unwrap_or_default();
        let voice = catalog.resolve(requested.or_else(|| config["realtime"]["voice"].as_str()));
        if requested.is_some() && voice.is_none() {
            return Ok(None);
        }
        let web_socket =
            voice.is_some() && has_speech_credentials(&config, account.account.as_ref());
        Ok((web_rtc || web_socket).then_some(RealtimeVoiceSelection {
            voice,
            web_rtc,
            web_socket,
        }))
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
        settings: &crate::workspace::SendSettings,
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
        let sandbox =
            settings
                .sandbox_policy
                .as_ref()
                .and_then(|policy| match policy["type"].as_str() {
                    Some("readOnly") => Some("read-only"),
                    Some("workspaceWrite") => Some("workspace-write"),
                    Some("dangerFullAccess") => Some("danger-full-access"),
                    _ => None,
                });
        let mut config = json!({"realtime.type": "conversational"});
        if let Some(effort) = settings.reasoning_effort.as_ref() {
            config["model_reasoning_effort"] = json!(effort);
        }
        if sandbox == Some("workspace-write")
            && let Some(access) = settings
                .sandbox_policy
                .as_ref()
                .and_then(|policy| policy["networkAccess"].as_bool())
        {
            config["sandbox_workspace_write.network_access"] = json!(access);
        }
        let result: Started = self.read("thread/start", json!({
            "cwd": cwd, "historyMode": "paginated", "config": config, "model": settings.model,
            "approvalPolicy": settings.approval_policy, "approvalsReviewer": settings.approvals_reviewer,
            "serviceTier": settings.service_tier.as_deref().filter(|tier| *tier != "default"),
            "sandbox": sandbox,
        }), timeout).await?;
        checkout.validate_reported(&result.cwd)?;
        checkout.validate_reported(&result.thread.cwd)?;
        Ok(result.thread)
    }

    pub async fn start_voice_call(
        &self,
        thread: &ThreadId,
        session: uuid::Uuid,
        offer: Option<&str>,
        voice: Option<&str>,
        timeout: Duration,
    ) -> Result<(), BrowseError> {
        let transport = offer.map_or_else(
            || json!({"type": "websocket"}),
            |sdp| json!({"type": "webrtc", "sdp": sdp}),
        );
        let mut params = json!({
            "threadId": thread.0, "realtimeSessionId": session, "outputModality": "audio",
            "version": "v3", "transport": transport,
            "flushTranscriptTailOnSessionEnd": true, "codexResponseHandoffMode": "bemTags",
            "clientManagedHandoffs": false,
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

    pub async fn append_voice_audio(
        &self,
        thread: &ThreadId,
        audio: &crate::ipc::SpeechAudio,
        timeout: Duration,
    ) -> Result<(), BrowseError> {
        self.read::<BTreeMap<String, Value>>(
            "thread/realtime/appendAudio",
            json!({
                "threadId": thread.0, "audio": audio,
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
    fn speech_requires_the_effective_providers_configured_key() {
        let service = json!({
            "model_provider": "fixture",
            "model_providers": {"fixture": {"env_key": "FIXTURE_KEY", "experimental_bearer_token": "example"}},
        });
        assert!(!speech_credentials(
            &service,
            Some(&Account::ApiKey),
            |_| false
        ));
        assert!(speech_credentials(&service, None, |key| key == "FIXTURE_KEY"));

        let built_in = json!({});
        assert!(!speech_credentials(&built_in, None, |_| false));
        assert!(speech_credentials(&built_in, None, |key| key == "OPENAI_API_KEY"));
        assert!(speech_credentials(
            &built_in,
            Some(&Account::ApiKey),
            |_| false
        ));
        let configured = json!({"model_provider": "fixture", "model_providers": {
            "fixture": {"experimental_bearer_token": "example"}
        }});
        assert!(speech_credentials(&configured, None, |_| false));
    }

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
