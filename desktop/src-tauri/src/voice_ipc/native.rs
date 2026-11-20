use std::{
    sync::{
        Arc, OnceLock,
        atomic::{AtomicU64, Ordering},
    },
    time::Duration,
};

use gstreamer::{self as gst, prelude::*};
use gstreamer_sdp as sdp;
use gstreamer_webrtc as rtc;
use tauri::{AppHandle, Manager};

use super::{TIMEOUT, fixture_root, record_exchange};

type MediaResult<T> = Result<T, Box<dyn std::error::Error + Send + Sync>>;

pub(super) struct NativePeer {
    pipeline: gst::Pipeline,
    peer: gst::Element,
    microphone: gst::Element,
    speakers: gst::Element,
    received: Arc<AtomicU64>,
    fixture_partner: OnceLock<Arc<Self>>,
}

impl NativePeer {
    fn create(synthetic: bool) -> MediaResult<Arc<Self>> {
        gst::init()?;
        let (source, sink) = if synthetic {
            (
                "audiotestsrc is-live=true",
                "fakesink name=monitor sync=false async=false signal-handoffs=true",
            )
        } else {
            ("autoaudiosrc", "autoaudiosink sync=false")
        };
        let description = format!(
            "webrtcbin name=peer bundle-policy=max-bundle
             {source} ! audioconvert ! audioresample ! audio/x-raw,rate=48000,channels=1
             ! volume name=microphone ! opusenc ! rtpopuspay pt=111
             ! application/x-rtp,media=audio,encoding-name=OPUS,payload=111 ! peer.
             queue name=inbound ! rtpopusdepay ! opusdec ! audioconvert ! audioresample
             ! volume name=speakers ! {sink}"
        );
        let pipeline = gst::parse::launch(&description)?
            .downcast::<gst::Pipeline>()
            .map_err(|_| "The voice pipeline could not be assembled")?;
        let peer = pipeline.by_name("peer").ok_or("Missing WebRTC peer")?;
        let microphone = pipeline
            .by_name("microphone")
            .ok_or("Missing microphone volume")?;
        let speakers = pipeline
            .by_name("speakers")
            .ok_or("Missing playback volume")?;
        let inbound = pipeline
            .by_name("inbound")
            .and_then(|element| element.static_pad("sink"))
            .ok_or("Missing WebRTC audio input")?;
        peer.connect_pad_added(move |_, pad| {
            if pad.direction() == gst::PadDirection::Src
                && let Err(error) = pad.link(&inbound)
            {
                eprintln!("{error}");
            }
        });
        let received = Arc::new(AtomicU64::new(0));
        if let Some(monitor) = pipeline.by_name("monitor") {
            let received = received.clone();
            monitor.connect("handoff", false, move |_| {
                received.fetch_add(1, Ordering::Relaxed);
                None
            });
        }
        let connection = Arc::new(Self {
            pipeline,
            peer,
            microphone,
            speakers,
            received,
            fixture_partner: OnceLock::new(),
        });
        connection.pipeline.set_state(gst::State::Playing)?;
        Ok(connection)
    }

    pub(super) async fn offer(app: &AppHandle) -> MediaResult<(Arc<Self>, String)> {
        let root = app
            .get_webview_window("main")
            .and_then(|window| fixture_root(&window).ok());
        let connection = Self::create(root.is_some())?;
        connection
            .peer
            .emit_by_name::<Option<rtc::WebRTCDataChannel>>(
                "create-data-channel",
                &[&"oai-events", &None::<gst::Structure>],
            )
            .ok_or("The WebRTC data channel could not be created")?;
        let offer = connection.local_description("offer").await?;
        if let Some(root) = root {
            let partner = Self::create(true)?;
            partner
                .set_remote(rtc::WebRTCSDPType::Offer, &offer)
                .await?;
            let answer = partner.local_description("answer").await?;
            record_exchange(&root, &offer, &answer).map_err(|error| format!("{error:?}"))?;
            connection
                .fixture_partner
                .set(partner)
                .map_err(|_| "The fixture peer is already connected")?;
        }
        Ok((connection, offer))
    }

    async fn local_description(&self, kind: &str) -> MediaResult<String> {
        let (promise, reply) = gst::Promise::new_future();
        self.peer.emit_by_name::<()>(
            &format!("create-{kind}"),
            &[&None::<gst::Structure>, &promise],
        );
        let response = tokio::time::timeout(TIMEOUT, reply)
            .await?
            .map_err(|error| format!("WebRTC local description: {error:?}"))?
            .ok_or("WebRTC did not return a local description")?;
        let description = response.get::<rtc::WebRTCSessionDescription>(kind)?;
        self.set_description("set-local-description", &description)
            .await?;
        tokio::time::timeout(TIMEOUT, async {
            while self
                .peer
                .property::<rtc::WebRTCICEGatheringState>("ice-gathering-state")
                != rtc::WebRTCICEGatheringState::Complete
            {
                tokio::time::sleep(Duration::from_millis(25)).await;
            }
        })
        .await?;
        let description = self
            .peer
            .property::<Option<rtc::WebRTCSessionDescription>>("local-description")
            .ok_or("WebRTC did not retain the local description")?;
        Ok(description.sdp().as_text()?)
    }

    async fn set_description(
        &self,
        signal: &str,
        description: &rtc::WebRTCSessionDescription,
    ) -> MediaResult<()> {
        let (promise, reply) = gst::Promise::new_future();
        self.peer
            .emit_by_name::<()>(signal, &[description, &promise]);
        if let Some(response) = tokio::time::timeout(TIMEOUT, reply)
            .await?
            .map_err(|error| format!("WebRTC description: {error:?}"))?
            && let Ok(error) = response.get::<gst::glib::Error>("error")
        {
            return Err(error.into());
        }
        Ok(())
    }

    async fn set_remote(&self, kind: rtc::WebRTCSDPType, text: &str) -> MediaResult<()> {
        let description = rtc::WebRTCSessionDescription::new(
            kind,
            sdp::SDPMessage::parse_buffer(text.as_bytes())?,
        );
        self.set_description("set-remote-description", &description)
            .await
    }

    pub(super) async fn accept_answer(&self, answer: &str) -> MediaResult<()> {
        self.set_remote(rtc::WebRTCSDPType::Answer, answer).await?;
        tokio::time::timeout(TIMEOUT, async {
            loop {
                match self
                    .peer
                    .property::<rtc::WebRTCPeerConnectionState>("connection-state")
                {
                    rtc::WebRTCPeerConnectionState::Connected => return Ok(()),
                    rtc::WebRTCPeerConnectionState::Closed
                    | rtc::WebRTCPeerConnectionState::Failed => {
                        return Err("The WebRTC media connection closed".into());
                    }
                    _ => tokio::time::sleep(Duration::from_millis(25)).await,
                }
            }
        })
        .await?
    }

    pub(super) fn connected(&self) -> bool {
        self.pipeline.current_state() != gst::State::Null
            && !matches!(
                self.peer
                    .property::<rtc::WebRTCPeerConnectionState>("connection-state"),
                rtc::WebRTCPeerConnectionState::Closed | rtc::WebRTCPeerConnectionState::Failed
            )
    }

    pub(super) fn mute(&self, microphone: bool, muted: bool) {
        let volume = if microphone {
            &self.microphone
        } else {
            &self.speakers
        };
        volume.set_property("mute", muted);
    }

    pub(super) fn fixture_media(&self) -> serde_json::Value {
        serde_json::json!({
            "receiving": self.received.load(Ordering::Relaxed) > 0,
            "sending": self.fixture_partner.get().is_some_and(|peer| peer.received.load(Ordering::Relaxed) > 0),
            "microphoneMuted": self.microphone.property::<bool>("mute"),
            "speakerMuted": self.speakers.property::<bool>("mute"),
        })
    }

    pub(super) fn close(&self) {
        if let Err(error) = self.pipeline.set_state(gst::State::Null) {
            eprintln!("{error}");
        }
    }
}

impl Drop for NativePeer {
    fn drop(&mut self) {
        self.close();
    }
}
