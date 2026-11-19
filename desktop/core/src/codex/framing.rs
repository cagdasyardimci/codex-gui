use std::{
    collections::VecDeque,
    io, mem,
    sync::{Arc, Mutex},
};

use thiserror::Error;
use tokio::io::{AsyncBufReadExt, AsyncRead, AsyncReadExt, BufReader};

#[derive(Debug, Error)]
pub enum JsonlReadError {
    #[error("could not read app-server stdout: {0}")]
    Io(#[from] io::Error),
    #[error("app-server frame exceeded {limit} bytes")]
    Oversized { limit: usize },
    #[error("app-server stdout closed inside a frame")]
    Truncated,
}

pub struct JsonlReader<R> {
    input: BufReader<R>,
    partial: Vec<u8>,
    limit: usize,
}

impl<R: AsyncRead + Unpin> JsonlReader<R> {
    pub fn new(input: R, limit: usize) -> Self {
        Self {
            input: BufReader::new(input),
            partial: Vec::new(),
            limit,
        }
    }

    pub async fn next_frame(&mut self) -> Result<Option<Vec<u8>>, JsonlReadError> {
        loop {
            let chunk = self.input.fill_buf().await?;
            if chunk.is_empty() {
                return if self.partial.is_empty() {
                    Ok(None)
                } else {
                    Err(JsonlReadError::Truncated)
                };
            }

            let lf = chunk.iter().position(|byte| *byte == b'\n');
            let end = lf.unwrap_or(chunk.len());
            if end > self.limit - self.partial.len() {
                return Err(JsonlReadError::Oversized { limit: self.limit });
            }
            self.partial.extend_from_slice(&chunk[..end]);
            self.input.consume(end + usize::from(lf.is_some()));

            if lf.is_some() {
                if self.partial.last() == Some(&b'\r') {
                    self.partial.pop();
                }
                if !self.partial.is_empty() {
                    return Ok(Some(mem::take(&mut self.partial)));
                }
            }
        }
    }
}

#[derive(Clone)]
pub struct StderrTail {
    bytes: Arc<Mutex<VecDeque<u8>>>,
    capacity: usize,
}

impl StderrTail {
    pub fn new(capacity: usize) -> Self {
        Self {
            bytes: Arc::new(Mutex::new(VecDeque::with_capacity(capacity))),
            capacity,
        }
    }

    pub async fn drain(&self, mut stderr: impl AsyncRead + Unpin) -> io::Result<()> {
        let mut buffer = [0; 4096];
        loop {
            let count = stderr.read(&mut buffer).await?;
            if count == 0 {
                return Ok(());
            }
            let recent = &buffer[count.saturating_sub(self.capacity)..count];
            let mut bytes = self.bytes.lock().expect("stderr buffer lock poisoned");
            let overflow = (bytes.len() + recent.len()).saturating_sub(self.capacity);
            bytes.drain(..overflow);
            bytes.extend(recent);
        }
    }

    /// Returns raw diagnostics. Redact sensitive values before presentation or export.
    pub fn snapshot(&self) -> Vec<u8> {
        self.bytes
            .lock()
            .expect("stderr buffer lock poisoned")
            .iter()
            .copied()
            .collect()
    }
}

#[cfg(test)]
mod tests;
