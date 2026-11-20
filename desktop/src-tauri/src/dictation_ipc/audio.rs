use std::sync::{Arc, Mutex, mpsc::RecvTimeoutError};

use cpal::{
    FromSample, SampleFormat, SizedSample, StreamConfig,
    traits::{DeviceTrait, HostTrait, StreamTrait},
};

use super::*;

pub(super) const RECOGNIZER_RATE: u32 = 16_000;

pub(super) fn record(
    events: &Channel<DictationEvent>,
    controls: &Receiver<Control>,
    sender: SyncSender<Control>,
) -> Result<Vec<f32>> {
    let device = cpal::default_host()
        .default_input_device()
        .ok_or("No microphone")?;
    let supported = device.default_input_config()?;
    let config = supported.config();
    let rate = config.sample_rate;
    if !(4_000..=192_000).contains(&rate) || config.channels == 0 {
        return Err("Unsupported microphone format".into());
    }
    let samples = Arc::new(Mutex::new(Vec::new()));
    let stream = match supported.sample_format() {
        SampleFormat::I16 => microphone::<i16>(&device, config, &samples, sender),
        SampleFormat::U16 => microphone::<u16>(&device, config, &samples, sender),
        SampleFormat::I24 => microphone::<cpal::I24>(&device, config, &samples, sender),
        SampleFormat::I32 => microphone::<i32>(&device, config, &samples, sender),
        SampleFormat::F32 => microphone::<f32>(&device, config, &samples, sender),
        SampleFormat::F64 => microphone::<f64>(&device, config, &samples, sender),
        _ => return Err("Unsupported microphone sample format".into()),
    }?;
    stream.play()?;
    events.send(DictationEvent::Started)?;
    let finish = matches!(
        controls.recv_timeout(MAX_RECORDING),
        Ok(Control::Finish) | Err(RecvTimeoutError::Timeout)
    );
    drop(stream);
    if !finish {
        return Err("Microphone invalidated".into());
    }
    let samples = std::mem::take(&mut *samples.lock().expect("microphone buffer lock poisoned"));
    Ok(resample(samples, rate))
}

fn microphone<T: SizedSample>(
    device: &cpal::Device,
    config: StreamConfig,
    samples: &Arc<Mutex<Vec<f32>>>,
    sender: SyncSender<Control>,
) -> Result<cpal::Stream>
where
    f32: FromSample<T>,
{
    let samples = samples.clone();
    let channels = usize::from(config.channels);
    let limit = config.sample_rate as usize * MAX_RECORDING.as_secs() as usize;
    Ok(device.build_input_stream(
        &config,
        move |input: &[T], _| {
            let mut samples = samples.lock().expect("microphone buffer lock poisoned");
            let remaining = limit.saturating_sub(samples.len());
            samples.extend(input.chunks_exact(channels).take(remaining).map(|frame| {
                let sum: f32 = frame.iter().map(|sample| f32::from_sample_(*sample)).sum();
                (sum / channels as f32).clamp(-1.0, 1.0)
            }));
        },
        move |_| {
            let _ = sender.try_send(Control::Cancel);
        },
        None,
    )?)
}

fn resample(samples: Vec<f32>, source: u32) -> Vec<f32> {
    if source == RECOGNIZER_RATE || samples.is_empty() {
        return samples;
    }
    let stride = f64::from(source) / f64::from(RECOGNIZER_RATE);
    let frames = (samples.len() as f64 / stride).floor() as usize;
    (0..frames)
        .map(|index| {
            let position = index as f64 * stride;
            let start = position.floor() as usize;
            if stride < 1.0 {
                let next = samples[(start + 1).min(samples.len() - 1)];
                return samples[start] + (next - samples[start]) * position.fract() as f32;
            }
            let end = (((index + 1) as f64 * stride).floor() as usize).min(samples.len());
            let span = &samples[start..end];
            span.iter().sum::<f32>() / span.len() as f32
        })
        .collect()
}
