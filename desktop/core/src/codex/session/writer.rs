use std::{
    future::poll_fn,
    io,
    pin::Pin,
    sync::{Arc, Mutex},
    task::Poll,
};

use tokio::{
    io::{AsyncWrite, AsyncWriteExt},
    sync::{Notify, mpsc, oneshot, watch},
    time::{self, Instant},
};

use super::Shared;
use crate::checkout::CheckoutIdentity;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Delivery {
    Unsent,
    PossiblySent,
}

#[derive(Default)]
struct Progress {
    accepted: usize,
    cancelled: bool,
    complete: bool,
}

#[derive(Default)]
pub(super) struct WriteTicket {
    progress: Mutex<Progress>,
    cancelled: Notify,
}

impl WriteTicket {
    pub(super) fn cancel(&self) -> Delivery {
        let mut progress = self.progress.lock().expect("write ticket lock poisoned");
        progress.cancelled = true;
        let delivery = if progress.accepted == 0 {
            Delivery::Unsent
        } else {
            Delivery::PossiblySent
        };
        drop(progress);
        self.cancelled.notify_one();
        delivery
    }

    pub(super) fn can_receive_reply(&self) -> bool {
        let progress = self.progress.lock().expect("write ticket lock poisoned");
        progress.complete && !progress.cancelled
    }
}

pub(super) struct Outbound {
    pub bytes: Vec<u8>,
    pub deadline: Instant,
    pub ticket: Arc<WriteTicket>,
    pub written: Option<oneshot::Sender<()>>,
    pub scope: Option<OutboundScope>,
}

pub(super) struct OutboundScope {
    pub checkout: Option<CheckoutIdentity>,
    pub stopped: watch::Receiver<bool>,
}

pub(super) async fn run<W: AsyncWrite + Unpin>(
    mut output: W,
    mut frames: mpsc::Receiver<Outbound>,
    shared: &Shared,
) {
    while let Some(frame) = frames.recv().await {
        let result = time::timeout_at(frame.deadline, async {
            tokio::select! {
                biased;
                _ = frame.ticket.cancelled.notified() => Ok(false),
                written = write_frame(&mut output, &frame, shared) => written,
            }
        })
        .await;

        match result {
            Ok(Ok(true)) => {
                if let Some(written) = frame.written {
                    let _ = written.send(());
                }
            }
            Ok(Ok(false)) | Err(_) if frame.ticket.cancel() == Delivery::Unsent => {}
            // Closing stdin prevents another frame from following an incomplete line.
            _ => break,
        }
    }
}

async fn write_frame<W: AsyncWrite + Unpin>(
    output: &mut W,
    frame: &Outbound,
    shared: &Shared,
) -> io::Result<bool> {
    let mut offset = 0;
    while offset < frame.bytes.len() {
        let count = poll_fn(|cx| {
            if let Some(checkout) = frame
                .scope
                .as_ref()
                .and_then(|scope| scope.checkout.as_ref())
            {
                // Check the captured directory again when the queued frame becomes writable.
                checkout.revalidate().map_err(io::Error::other)?;
            }
            // Hold the read guard through the poll to order writes with Stop.
            let stopped = frame.scope.as_ref().map(|scope| scope.stopped.borrow());
            // Hold admission through this nonblocking poll to order retirement with writes.
            let connection = shared.state.lock().expect("pending request lock poisoned");
            let mut progress = frame
                .ticket
                .progress
                .lock()
                .expect("write ticket lock poisoned");
            if connection.retired
                || progress.cancelled
                || stopped.is_some_and(|stopped| *stopped)
                || Instant::now() >= frame.deadline
            {
                return Poll::Ready(Ok(None));
            }
            let write =
                std::task::ready!(Pin::new(&mut *output).poll_write(cx, &frame.bytes[offset..]));
            match write {
                Ok(0) => Poll::Ready(Err(io::ErrorKind::WriteZero.into())),
                Ok(count) => {
                    progress.accepted += count;
                    progress.complete = progress.accepted == frame.bytes.len();
                    Poll::Ready(Ok(Some(count)))
                }
                Err(error) => Poll::Ready(Err(error)),
            }
        })
        .await?;
        let Some(count) = count else {
            return Ok(false);
        };
        offset += count;
    }
    output.flush().await?;
    Ok(true)
}
