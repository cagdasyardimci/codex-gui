mod executable;
mod framing;
mod process;

#[cfg(test)]
mod fixtures;

pub use executable::{CodexExecutable, DiscoveryError, VersionProbeError};
pub use framing::{JsonlReadError, JsonlReader, StderrTail};
pub use process::{AppServerExit, AppServerProcess, AppServerStdio};
