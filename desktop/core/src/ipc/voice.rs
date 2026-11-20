use super::*;

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub enum VoicePhase {
    Preparing,
    Connecting,
    Active,
    Ending,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub enum VoiceMediaHost {
    Webview,
    Native,
    Pcm,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct VoiceCallView {
    pub id: Uuid,
    pub project_id: String,
    pub chat_id: String,
    pub media: VoiceMediaHost,
    pub phase: VoicePhase,
    pub microphone_muted: bool,
    pub speaker_muted: bool,
}

#[derive(Clone, Debug, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct VoiceCallUpdate {
    pub call: Option<VoiceCallView>,
    pub answer: Option<String>,
    pub reconnect: Option<VoiceReconnect>,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct VoiceReconnect {
    pub id: Uuid,
    pub project_id: String,
    pub chat_id: String,
}

#[derive(Clone, Debug, Deserialize, Serialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct VoiceAudioUpdate {
    pub id: Uuid,
    pub audio: SpeechAudio,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PrepareVoiceCall {
    pub workspace_id: WorkspaceId,
    pub chat_id: Option<String>,
    pub draft_id: String,
    pub reconnect: Option<Uuid>,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StartVoiceCall {
    pub id: Uuid,
    pub offer: Option<String>,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct VoiceMute {
    pub id: Uuid,
    pub microphone: bool,
    pub muted: bool,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct VoiceSettingsView {
    pub voices: Vec<VoiceChoice>,
    pub selected: String,
    pub default_voice: Option<String>,
    pub managed: bool,
    pub preview: bool,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct VoiceChoice {
    pub id: String,
    pub label: String,
    pub language: Option<String>,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PreviewVoice {
    pub selection: super::SettingsSelection,
    pub workspace_id: Option<WorkspaceId>,
    pub id: Uuid,
    pub voice: String,
}

#[derive(Clone, Debug, Deserialize, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct SpeechAudio {
    pub data: String,
    pub sample_rate: u32,
    pub num_channels: u8,
    pub samples_per_channel: Option<u32>,
}

#[derive(Debug, Serialize, TS)]
#[serde(tag = "type", rename_all = "camelCase")]
pub enum SpeechEvent {
    Audio { audio: SpeechAudio },
    Finished,
    Retired,
}

impl SpeechAudio {
    pub fn valid(&self) -> bool {
        use base64::{Engine, engine::general_purpose::STANDARD};

        if self.data.is_empty()
            || self.data.len() > 512 * 1024
            || !(8_000..=192_000).contains(&self.sample_rate)
            || !(1..=8).contains(&self.num_channels)
        {
            return false;
        }
        let bytes_per_frame = usize::from(self.num_channels) * 2;
        STANDARD.decode(&self.data).is_ok_and(|data| {
            !data.is_empty()
                && data.len() % bytes_per_frame == 0
                && self
                    .samples_per_channel
                    .is_none_or(|samples| data.len() / bytes_per_frame == samples as usize)
        })
    }
}
