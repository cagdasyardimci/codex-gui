import { invoke } from '@tauri-apps/api/core';
import type { SpeechAudio } from './generated/workspace';
import type { VoiceMediaEvidence } from './voiceMedia';
import { pcmBuffer } from './speechPlayback';
import workletUrl from './voiceCapture.worklet.js?url&no-inline';

const loadedModules = new WeakMap<AudioContext, Promise<void>>();

export class VoiceSocket {
  private cancelled = false;
  private active = false;
  private muted = false;
  private submitting = false;
  private errors = 0;
  private sent = false;
  private received = false;
  private stream: MediaStream | undefined;
  private input: MediaStreamAudioSourceNode | undefined;
  private worklet: AudioWorkletNode | undefined;
  private oscillator: OscillatorNode | undefined;
  private speakers: GainNode;
  private sources = new Set<AudioBufferSourceNode>();
  private next = 0;

  constructor(private audio: AudioContext, private id: string, private synthetic: boolean,
    private failed: (error: unknown) => void) {
    this.speakers = audio.createGain();
    if (!synthetic) this.speakers.connect(audio.destination);
  }

  async connect() {
    const loaded = loadedModules.get(this.audio) ?? this.audio.audioWorklet.addModule(workletUrl);
    loadedModules.set(this.audio, loaded);
    await loaded;
    if (this.cancelled) return;

    const stream = this.synthetic ? this.generate() : await navigator.mediaDevices.getUserMedia({
      audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true },
    });
    if (this.cancelled) {
      for (const track of stream.getTracks()) track.stop();
      return;
    }
    this.stream = stream;
    for (const track of stream.getAudioTracks()) {
      track.onended = () => { if (!this.cancelled) this.failed('Voice microphone disconnected'); };
    }
    this.input = this.audio.createMediaStreamSource(stream);
    this.worklet = new AudioWorkletNode(this.audio, 'voice-capture', {
      numberOfInputs: 1, numberOfOutputs: 1, channelCount: 1,
      channelCountMode: 'explicit', outputChannelCount: [1],
    });
    this.worklet.port.onmessage = (event: MessageEvent<ArrayBuffer>) => this.submit(event.data);
    this.input.connect(this.worklet);
    this.worklet.connect(this.audio.destination);
    this.mute(this.muted, this.speakers.gain.value === 0);
  }

  setActive(active: boolean) {
    this.active = active;
  }

  mute(microphone: boolean, speakers: boolean) {
    this.muted = microphone;
    this.speakers.gain.value = speakers ? 0 : 1;
    for (const track of this.stream?.getAudioTracks() ?? []) track.enabled = !microphone;
  }

  play(audio: SpeechAudio) {
    if (this.cancelled || !this.active || this.next - this.audio.currentTime > 3) return;
    const buffer = pcmBuffer(this.audio, audio);
    const source = this.audio.createBufferSource();
    source.buffer = buffer;
    source.connect(this.speakers);
    this.sources.add(source);
    source.onended = () => {
      this.sources.delete(source);
      source.disconnect();
    };
    const at = Math.max(this.audio.currentTime + 0.025, this.next);
    source.start(at);
    this.next = at + buffer.duration;
    this.received = true;
  }

  fixtureMedia(): VoiceMediaEvidence {
    return { receiving: this.received, sending: this.sent, microphoneMuted: this.muted,
      speakerMuted: this.speakers.gain.value === 0 };
  }

  close() {
    this.cancelled = true;
    this.active = false;
    for (const track of this.stream?.getTracks() ?? []) track.stop();
    this.oscillator?.stop();
    this.oscillator?.disconnect();
    this.input?.disconnect();
    this.worklet?.disconnect();
    this.worklet?.port.close();
    for (const source of this.sources) {
      source.onended = null;
      source.stop();
      source.disconnect();
    }
    this.sources.clear();
    this.speakers.disconnect();
  }

  private generate() {
    const output = this.audio.createMediaStreamDestination();
    this.oscillator = this.audio.createOscillator();
    this.oscillator.connect(output);
    this.oscillator.start();
    return output.stream;
  }

  private submit(data: ArrayBuffer) {
    if (!this.active || this.muted || this.submitting || this.cancelled) return;
    const payload = new Uint8Array(data);
    const encoded = btoa(String.fromCharCode(...payload));
    this.submitting = true;
    void invoke('append_voice_audio', { update: { id: this.id, audio: {
      data: encoded, sampleRate: 24_000, numChannels: 1, samplesPerChannel: payload.length / 2,
    } } }).then(() => {
      this.sent = true;
      this.errors = 0;
    }).catch((error) => {
      if (this.active && !this.muted && ++this.errors === 2) this.failed(error);
    }).finally(() => { this.submitting = false; });
  }
}
