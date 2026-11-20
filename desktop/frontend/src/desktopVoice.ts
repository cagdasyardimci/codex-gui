import { invoke } from '@tauri-apps/api/core';
import { listen, type UnlistenFn } from '@tauri-apps/api/event';
import type { PrepareVoiceCall, VoiceAudioUpdate, VoiceCallUpdate, VoiceCallView } from './generated/workspace';
import { VoicePeer, type VoiceMediaEvidence } from './voiceMedia';
import { VoiceSocket } from './voiceSocket';

export class DesktopVoice {
  private opening = false;
  private launched: string | undefined;
  private audio: AudioContext | undefined;
  private view: VoiceCallView | null = null;
  private web: { id: string; peer: VoicePeer; answering: boolean } | undefined;
  private socket: { id: string; peer: VoiceSocket } | undefined;

  constructor(private present: (update: VoiceCallUpdate) => void, private synthetic: () => boolean) {}

  async observe(signal: AbortSignal) {
    let announced = false;
    const subscriptions: UnlistenFn[] = [];
    const retire = () => {
      for (const stop of subscriptions.splice(0)) stop();
      const owned = this.web?.id ?? this.socket?.id;
      this.closeMedia();
      this.closeAudio();
      if (owned) void this.end(owned).catch(console.error);
    };
    signal.addEventListener('abort', retire, { once: true });
    try {
      subscriptions.push(await listen<VoiceAudioUpdate>('desktop:voice-audio', ({ payload }) => {
        const socket = this.socket;
        if (!signal.aborted && socket?.id === payload.id) socket.peer.play(payload.audio);
      }));
      subscriptions.push(await listen<VoiceCallUpdate>('desktop:voice', ({ payload }) => {
        if (signal.aborted) return;
        announced = true;
        this.receive(payload);
      }));
      const initial = await invoke<VoiceCallUpdate>('read_voice_call');
      if (!announced && !signal.aborted) this.receive(initial);
    } catch (error) {
      retire();
      throw error;
    } finally {
      if (signal.aborted) retire();
    }
  }

  async start(request: PrepareVoiceCall, flush: () => Promise<void> | null) {
    if (!this.canStart()) return;
    this.opening = true;
    try {
      if (typeof AudioContext !== 'undefined') {
        this.audio = new AudioContext();
        void this.audio.resume().catch(console.error);
      }
      await flush();
      const call = await invoke<VoiceCallView>('prepare_voice_call', { request });
      if (!this.view || this.view.id === call.id) this.openMedia(call);
    } catch (error) {
      console.error(error);
      if (!this.view) this.closeAudio();
    } finally {
      this.opening = false;
    }
  }

  mute(id: string, microphone: boolean, muted: boolean) {
    return invoke<void>('set_voice_mute', { request: { id, microphone, muted } });
  }

  end(id: string) {
    if (this.web?.id === id || this.socket?.id === id) this.closeMedia();
    return invoke<void>('end_voice_call', { id });
  }

  async fixtureMedia(call: VoiceCallView): Promise<VoiceMediaEvidence> {
    if (call.media === 'native') return invoke('read_voice_fixture_media', { id: call.id });
    if (this.socket?.id === call.id) return this.socket.peer.fixtureMedia();
    if (this.web?.id === call.id) return this.web.peer.fixtureMedia();
    throw new Error('The fixture no longer owns the call');
  }

  private canStart() {
    return !this.opening && !this.view;
  }

  private receive(update: VoiceCallUpdate) {
    const call = update.call;
    this.view = call;
    this.present(update);
    const local = this.web?.id ?? this.socket?.id;
    if (local && (local !== call?.id || call.phase === 'ending')) this.closeMedia();
    if (!call) {
      this.launched = undefined;
      if (!this.opening) this.closeAudio();
      return;
    }
    if (call.phase === 'ending') return;
    if (call.phase === 'preparing' && this.audio) this.openMedia(call);

    if (this.socket?.id === call.id) {
      this.socket.peer.setActive(call.phase === 'active');
      this.socket.peer.mute(call.microphoneMuted, call.speakerMuted);
      return;
    }
    const web = this.web;
    if (!web || web.id !== call.id) {
      if (!this.opening && call.media !== 'native' && !this.audio) void this.end(call.id).catch(console.error);
      return;
    }
    web.peer.mute(call.microphoneMuted, call.speakerMuted);
    if (call.phase === 'connecting' && update.answer && !web.answering) {
      web.answering = true;
      void web.peer.answer(update.answer).then(() => {
        if (this.web === web) return invoke('voice_media_ready', { id: call.id });
      }).catch((error) => {
        if (this.web === web) this.failed(call.id, error);
      });
    }
  }

  private openMedia(call: VoiceCallView) {
    if (this.launched === call.id) return;
    this.launched = call.id;
    void this.launch(call).catch((error) => {
      if (this.view?.id === call.id && this.view.phase !== 'ending') this.failed(call.id, error);
    });
  }

  private async launch(call: VoiceCallView) {
    let offer: string | null = null;
    if (call.media !== 'native') {
      const audio = this.audio;
      if (!audio) throw new Error('Voice audio is unavailable');
      if (call.media === 'pcm') {
        const peer = new VoiceSocket(audio, call.id, this.synthetic(), (error) => this.failed(call.id, error));
        this.socket = { id: call.id, peer };
        peer.mute(call.microphoneMuted, call.speakerMuted);
        await peer.connect();
      } else {
        const peer = new VoicePeer(audio, this.synthetic(), () => this.failed(call.id, 'WebRTC connection lost'));
        this.web = { id: call.id, peer, answering: false };
        peer.mute(call.microphoneMuted, call.speakerMuted);
        offer = await peer.offer();
      }
    }
    await invoke('start_voice_transport', { request: { id: call.id, offer } });
  }

  private failed(id: string, error: unknown) {
    console.error(error);
    const stopping = error instanceof DOMException && (error.name === 'NotAllowedError' || error.name === 'SecurityError');
    const action = stopping ? this.end(id) : invoke('voice_media_failed', { id });
    void action.catch(console.error);
  }

  private closeMedia() {
    this.web?.peer.close();
    this.socket?.peer.close();
    this.web = undefined;
    this.socket = undefined;
  }

  private closeAudio() {
    const previous = this.audio;
    this.audio = undefined;
    if (previous) void previous.close().catch(console.error);
  }
}
