mod browse;
mod compatibility;
mod executable;
mod framing;
mod process;
mod protocol;
mod session;

#[cfg(test)]
mod fixtures;

pub use browse::{
    Account, AccountSnapshot, BrowseError, BrowserLogin, ChatRead, ChatSummary, CodexBrowser,
    HistoryTurn, LoginCancellation, LoginCompletion, ModelOption, Page, ProjectChatCursor,
    QueueSnapshot, QueuedSubmission, ThreadActivity, ThreadSummary, TurnActivity, TurnCursor,
    TurnStatus,
};
pub use compatibility::{CliCompatibility, CliQualification, CompatibilityError};
pub use executable::{CodexExecutable, DiscoveryError, VersionProbeError};
pub use framing::{JsonlReadError, JsonlReader, StderrTail};
pub use process::{AppServerExit, AppServerProcess, AppServerStdio};
pub use protocol::{
    ClientInfo, InitializeError, ProtocolReadError, RpcError, RpcId, ServerEvent, ServerMessage,
    initialize, read_message,
};
pub use session::{AppServerClient, AppServerConnection, ConnectError, Delivery, RequestError};
