use std::time::Duration;

use tokio::{
    io::{AsyncWriteExt, duplex},
    time::timeout,
};

use super::*;

#[tokio::test]
async fn only_lf_delimits_json_even_when_unicode_spans_pipe_reads() {
    let json = "{\"message\":\"Türkçe 🧭\u{2028}inside the same frame\"}";
    let wire = format!("\r\n{json}\r\n{{}}\n");
    let (mut writer, pipe) = duplex(1);
    let mut reader = JsonlReader::new(pipe, 1024);

    timeout(Duration::from_secs(5), async {
        tokio::join!(
            async {
                writer.write_all(wire.as_bytes()).await.unwrap();
                writer.shutdown().await.unwrap();
            },
            async {
                assert_eq!(reader.next_frame().await.unwrap().unwrap(), json.as_bytes());
                assert_eq!(reader.next_frame().await.unwrap().unwrap(), b"{}");
                assert!(reader.next_frame().await.unwrap().is_none());
            }
        );
    })
    .await
    .unwrap();
}

#[tokio::test]
async fn accepts_the_exact_limit_and_rejects_an_oversized_partial_frame() {
    let data = b"1234\n123456789";
    let mut reader = JsonlReader::new(data.as_slice(), 4);
    assert_eq!(reader.next_frame().await.unwrap().unwrap(), b"1234");
    assert!(matches!(
        reader.next_frame().await,
        Err(JsonlReadError::Oversized { limit: 4 })
    ));
}

#[tokio::test]
async fn reports_eof_during_a_frame_without_delivering_it() {
    let mut reader = JsonlReader::new(b"{\"result\":".as_slice(), 64);
    assert!(matches!(
        reader.next_frame().await,
        Err(JsonlReadError::Truncated)
    ));
}

#[tokio::test]
async fn noisy_stderr_retains_only_the_exact_tail_across_reads() {
    let mut output = vec![b'x'; 4090];
    output.extend(b"0123456789abcdefghij");
    let diagnostics = StderrTail::new(16);
    let retained = diagnostics.clone();
    diagnostics.drain(output.as_slice()).await.unwrap();
    assert_eq!(retained.snapshot(), b"456789abcdefghij");
}
