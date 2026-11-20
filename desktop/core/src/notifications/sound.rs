use std::{
    fs::File,
    io::{self, Cursor, Read},
    path::Path,
};

use symphonia::core::{
    formats::{FormatOptions, TrackType, probe::Hint},
    io::MediaSourceStream,
    meta::MetadataOptions,
};
use thiserror::Error;

const MAX_BYTES: u64 = 32 * 1024 * 1024;
const MAX_SECONDS: usize = 30;

pub struct AlertAudio {
    pub channels: u16,
    pub sample_rate: u32,
    pub samples: Vec<i16>,
}

#[derive(Debug, Error)]
pub enum AlertAudioError {
    #[error("could not read alert sound: {0}")]
    Io(#[from] io::Error),
    #[error("the selected sound is not a supported WAV, AIFF or CAF file")]
    Format,
    #[error("the selected sound is empty or longer than 30 seconds")]
    Duration,
    #[error("alert audio decode failed: {0}")]
    Decode(#[from] symphonia::core::errors::Error),
}

impl AlertAudio {
    pub fn read(path: &Path) -> Result<Self, AlertAudioError> {
        let file = File::open(path)?;
        let metadata = file.metadata()?;
        if !metadata.is_file() || metadata.len() > MAX_BYTES {
            return Err(AlertAudioError::Format);
        }
        let mut bytes = Vec::with_capacity(metadata.len() as usize);
        file.take(MAX_BYTES + 1).read_to_end(&mut bytes)?;
        if bytes.len() as u64 > MAX_BYTES || !is_alert_container(&bytes) {
            return Err(AlertAudioError::Format);
        }
        Self::decode(bytes)
    }

    fn decode(bytes: Vec<u8>) -> Result<Self, AlertAudioError> {
        let source = MediaSourceStream::new(Box::new(Cursor::new(bytes)), Default::default());
        let mut container = symphonia::default::get_probe().probe(
            &Hint::new(),
            source,
            FormatOptions::default(),
            MetadataOptions::default(),
        )?;
        let track = container
            .default_track(TrackType::Audio)
            .ok_or(AlertAudioError::Format)?;
        let track_id = track.id;
        let codec = track
            .codec_params
            .as_ref()
            .and_then(|params| params.audio())
            .ok_or(AlertAudioError::Format)?;
        let mut decoder =
            symphonia::default::get_codecs().make_audio_decoder(codec, &Default::default())?;
        let mut audio = None::<Self>;
        while let Some(packet) = container.next_packet()? {
            if packet.track_id != track_id {
                continue;
            }
            let decoded = decoder.decode(&packet)?;
            let spec = decoded.spec();
            let rate = spec.rate();
            let channels = spec.channels().count();
            if !(8_000..=192_000).contains(&rate) || !(1..=2).contains(&channels) {
                return Err(AlertAudioError::Format);
            }
            let output = audio.get_or_insert_with(|| Self {
                channels: channels as u16,
                sample_rate: rate,
                samples: Vec::new(),
            });
            if usize::from(output.channels) != channels || output.sample_rate != rate {
                return Err(AlertAudioError::Format);
            }
            let old_length = output.samples.len();
            let new_length = old_length.saturating_add(decoded.samples_interleaved());
            if new_length >= MAX_SECONDS * rate as usize * channels {
                return Err(AlertAudioError::Duration);
            }
            output.samples.resize(new_length, 0);
            decoded.copy_to_slice_interleaved(&mut output.samples[old_length..]);
        }
        audio
            .filter(|clip| !clip.samples.is_empty())
            .ok_or(AlertAudioError::Duration)
    }

    pub fn wave_bytes(&self) -> Vec<u8> {
        let size = (self.samples.len() * 2) as u32;
        let byte_frame = self.channels * 2;
        let mut bytes = Vec::with_capacity(44 + size as usize);
        bytes.extend(b"RIFF");
        bytes.extend((36 + size).to_le_bytes());
        bytes.extend(b"WAVEfmt ");
        bytes.extend(16u32.to_le_bytes());
        bytes.extend(1u16.to_le_bytes());
        bytes.extend(self.channels.to_le_bytes());
        bytes.extend(self.sample_rate.to_le_bytes());
        bytes.extend((self.sample_rate * u32::from(byte_frame)).to_le_bytes());
        bytes.extend(byte_frame.to_le_bytes());
        bytes.extend(16u16.to_le_bytes());
        bytes.extend(b"data");
        bytes.extend(size.to_le_bytes());
        for sample in &self.samples {
            bytes.extend(sample.to_le_bytes());
        }
        bytes
    }
}

fn is_alert_container(bytes: &[u8]) -> bool {
    let form = bytes.get(..4);
    let variant = bytes.get(8..12);
    form == Some(b"caff")
        || form == Some(b"RIFF") && variant == Some(b"WAVE")
        || form == Some(b"FORM") && matches!(variant, Some(b"AIFF" | b"AIFC"))
}
