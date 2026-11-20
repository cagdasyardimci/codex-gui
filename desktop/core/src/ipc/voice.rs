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
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PrepareVoiceCall {
    pub workspace_id: WorkspaceId,
    pub chat_id: Option<String>,
    pub draft_id: String,
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
