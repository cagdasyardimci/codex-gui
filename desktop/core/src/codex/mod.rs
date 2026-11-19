mod executable;
mod framing;
mod process;
mod protocol;

#[cfg(test)]
mod fixtures;

pub use executable::{CodexExecutable, DiscoveryError, VersionProbeError};
pub use framing::{JsonlReadError, JsonlReader, StderrTail};
pub use process::{AppServerExit, AppServerProcess, AppServerStdio};
pub use protocol::{
    ClientInfo, InitializeError, ProtocolReadError, RpcError, RpcId, ServerEvent, ServerMessage,
    initialize, read_message,
};
