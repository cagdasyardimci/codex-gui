use std::{
    io,
    process::{ExitStatus, Stdio},
};

use tokio::process::{Child, ChildStderr, ChildStdin, ChildStdout};

use crate::identity::ConnectionIdentity;

use super::CodexExecutable;

pub struct AppServerProcess {
    connection: ConnectionIdentity,
    child: Child,
}

pub struct AppServerStdio {
    pub stdin: ChildStdin,
    pub stdout: ChildStdout,
    pub stderr: ChildStderr,
}

#[derive(Debug)]
pub struct AppServerExit {
    pub connection: ConnectionIdentity,
    pub status: ExitStatus,
}

impl AppServerProcess {
    pub fn spawn(executable: &CodexExecutable, connection: ConnectionIdentity) -> io::Result<Self> {
        let mut command = executable.command();
        command
            .args([
                "--enable",
                "default_mode_request_user_input",
                "app-server",
                "--stdio",
            ])
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        if let Some(checkout) = &connection.workspace.checkout {
            checkout.revalidate().map_err(io::Error::other)?;
            command.current_dir(checkout.canonical_path());
        }
        let child = command.spawn()?;
        Ok(Self { connection, child })
    }

    /// Transfers each pipe once. The process handle retains ownership of the child.
    pub fn take_stdio(&mut self) -> Option<AppServerStdio> {
        Some(AppServerStdio {
            stdin: self.child.stdin.take()?,
            stdout: self
                .child
                .stdout
                .take()
                .expect("app-server stdout is piped"),
            stderr: self
                .child
                .stderr
                .take()
                .expect("app-server stderr is piped"),
        })
    }

    pub async fn wait_for_exit(&mut self) -> io::Result<AppServerExit> {
        Ok(AppServerExit {
            connection: self.connection.clone(),
            status: self.child.wait().await?,
        })
    }

    pub async fn terminate(&mut self) -> io::Result<AppServerExit> {
        if self.child.try_wait()?.is_none()
            && let Err(error) = self.child.start_kill()
            && self.child.try_wait()?.is_none()
        {
            return Err(error);
        }
        self.wait_for_exit().await
    }
}

#[cfg(test)]
#[path = "process_tests.rs"]
mod tests;
