use super::*;

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub enum RemoteHostPhase {
    #[default]
    Disabled,
    Connecting,
    Connected,
    Duplicate,
    Disconnected,
}

#[derive(Clone, Debug, Default, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct RemoteHostView {
    pub enabled: bool,
    pub keep_awake: bool,
    pub phase: RemoteHostPhase,
    pub available: bool,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
pub enum RemoteHostCommand {
    Enabled(bool),
    KeepAwake(bool),
    Refresh,
}
