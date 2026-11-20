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

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct RemoteDeviceScope {
    pub session: Uuid,
    pub surface: Uuid,
}

#[derive(Clone, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct RemotePairingView {
    pub id: Uuid,
    #[ts(type = "number")]
    pub expires_at: i64,
    pub manual_code: String,
    pub width: usize,
    pub cells: Vec<bool>,
}

#[derive(Clone, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct RemoteDeviceView {
    pub id: Uuid,
    pub name: String,
}

#[derive(Default, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct RemoteDevicesView {
    pub connected: bool,
    pub environment: Option<Uuid>,
    pub pairing: Option<RemotePairingView>,
    pub devices: Vec<RemoteDeviceView>,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
pub enum RemoteDeviceCommand {
    Refresh,
    BeginPairing,
    CheckPairing(Uuid),
    ClosePairing,
    Revoke(Uuid),
}
