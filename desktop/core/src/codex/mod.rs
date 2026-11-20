mod browse;
mod compatibility;
mod executable;
mod framing;
mod process;
mod protocol;
mod review;
mod session;

#[cfg(test)]
mod fixtures;

pub use browse::{
    Account, AccountSnapshot, BrowseError, BrowserLogin, ChatRead, ChatSummary, CodexBrowser,
    EffectiveConfiguration, ForkBoundary, HistoryTurn, IntegrationCatalogs, LoginCancellation,
    LoginCompletion, ModelOption, Page, ProjectChatCursor, QueueSnapshot, QueuedSubmission,
    RealtimeVoiceCatalog, RealtimeVoiceSelection, RelayPhase, RelayStatus, ResetCandidate,
    SettingsRateLimits, SpeechRole, ThreadActivity, ThreadSummary, TimelineCursor, TimelineEntry,
    TurnActivity, TurnCursor, TurnItemRead, TurnItems, TurnStatus, UsageResetOutcome, VoiceSegment,
    VoiceTimelinePage, WindowsSandboxReadiness, WindowsSandboxSetupCompleted,
    WindowsSandboxSetupMode, has_speech_credentials, realtime_enabled, validate_voice_sdp,
    voice_sample,
};
pub use compatibility::{CliCompatibility, CliQualification, CompatibilityError};
pub(crate) use executable::is_executable;
pub use executable::{CodexExecutable, DiscoveryError, VersionProbeError};
pub use framing::{JsonlReadError, JsonlReader, StderrTail};
pub use process::{AppServerExit, AppServerProcess, AppServerStdio};
pub use protocol::{
    ClientInfo, InitializeError, ProtocolReadError, RpcError, RpcId, ServerEvent, ServerMessage,
    initialize, read_message,
};
pub use review::{ReviewDelivery, ReviewError, ReviewStarted, ReviewTarget};
pub use session::{AppServerClient, AppServerConnection, ConnectError, Delivery, RequestError};
