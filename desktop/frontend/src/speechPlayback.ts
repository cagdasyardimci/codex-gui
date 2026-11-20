import { Channel, invoke } from '@tauri-apps/api/core';
import type { SpeechAudio, SpeechEvent } from './generated/workspace';

type FixtureSpeech = { id: string; frames: number; closed: boolean };
let fixtureSpeech: FixtureSpeech | undefined;

export function speechFixtureEvidence() {
  return fixtureSpeech;
}

export class SpeechPlayback {
  private id = crypto.randomUUID();
  private context = new AudioContext();
  private sink: AudioNode;
  private sources = new Set<AudioBufferSourceNode>();
  private next = 0;
  private draining: number | undefined;
  private closed = false;
  private opening: Promise<void> | undefined;
  private fixture: FixtureSpeech | undefined;

  constructor(synthetic: boolean, private readonly onClose?: () => void) {
    this.sink = this.context.destination;
    void this.context.resume().catch(console.error);
    if (synthetic) {
      const muted = this.context.createGain();
      muted.gain.value = 0;
      muted.connect(this.context.destination);
      this.sink = muted;
      this.fixture = { id: this.id, frames: 0, closed: false };
      fixtureSpeech = this.fixture;
    }
  }

  start(open: (id: string, events: Channel<SpeechEvent>) => Promise<void>) {
    const events = new Channel<SpeechEvent>();
    events.onmessage = (event) => {
      if (this.closed) return;
      try {
        if (event.type === 'audio') this.enqueue(event.audio);
        else if (event.type === 'segmentFinished') {
          this.draining = event.index;
          this.acknowledgeDrain();
        } else this.close();
      } catch (error) {
        console.error(error);
        this.stop();
      }
    };
    this.opening = open(this.id, events);
    void this.opening.catch((error) => {
      if (!this.closed) console.error(error);
      this.close();
    });
  }

  stop() {
    if (this.closed) return;
    this.close();
    void this.opening?.then(() => invoke('stop_speech', { id: this.id })).catch(console.error);
  }

  private enqueue(audio: SpeechAudio) {
    if (this.next - this.context.currentTime > 60) throw new Error('Playback queued too much audio');
    const buffer = pcmBuffer(this.context, audio);
    const source = this.context.createBufferSource();
    source.buffer = buffer;
    source.connect(this.sink);
    this.sources.add(source);
    source.onended = () => {
      this.sources.delete(source);
      source.disconnect();
      this.acknowledgeDrain();
    };
    const at = Math.max(this.next, this.context.currentTime + 0.025);
    source.start(at);
    this.next = at + buffer.duration;
    if (this.fixture) this.fixture.frames += buffer.length;
  }

  private acknowledgeDrain() {
    if (this.closed || this.sources.size || this.draining === undefined) return;
    const index = this.draining;
    this.draining = undefined;
    void invoke('speech_segment_drained', { id: this.id, index }).catch((error) => {
      console.error(error);
      this.stop();
    });
  }

  private close() {
    if (this.closed) return;
    this.closed = true;
    for (const source of this.sources) {
      source.onended = null;
      source.stop();
      source.disconnect();
    }
    this.sources.clear();
    const fixture = this.fixture;
    void this.context.close().then(() => { if (fixture) fixture.closed = true; }).catch(console.error);
    this.onClose?.();
  }
}

export function pcmBuffer(context: AudioContext, audio: SpeechAudio) {
  const bytes = Uint8Array.from(atob(audio.data), (byte) => byte.charCodeAt(0));
  const reader = new DataView(bytes.buffer);
  const frames = bytes.length / (2 * audio.numChannels);
  const buffer = context.createBuffer(audio.numChannels, frames, audio.sampleRate);
  for (let channel = 0; channel < audio.numChannels; channel += 1) {
    const samples = buffer.getChannelData(channel);
    for (let frame = 0; frame < frames; frame += 1) {
      samples[frame] = reader.getInt16(2 * (frame * audio.numChannels + channel), true) / 32768;
    }
  }
  return buffer;
}
