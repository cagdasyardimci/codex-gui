import { invoke } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';
import type { PrepareVoiceCall, VoiceCallUpdate, VoiceCallView } from './generated/workspace';
import { VoicePeer, type VoiceMediaEvidence } from './voiceMedia';

export class DesktopVoice {
  private opening = false;
  private view: VoiceCallView | null = null;
  private web: { id: string; peer: VoicePeer; answering: boolean } | undefined;

  constructor(private present: (call: VoiceCallView | null) => void) {}

  async observe(signal: AbortSignal) {
    let announced = false;
    const stop = await listen<VoiceCallUpdate>('desktop:voice', ({ payload }) => {
      if (signal.aborted) return;
      announced = true;
      this.receive(payload);
    });
    const retire = () => {
      stop();
      const web = this.web;
      this.closeMedia();
      if (web) void this.end(web.id).catch(console.error);
    };
    if (signal.aborted) {
      retire();
      return;
    }
    signal.addEventListener('abort', retire, { once: true });
    const initial = await invoke<VoiceCallUpdate>('read_voice_call');
    if (!announced && !signal.aborted) this.receive(initial);
  }

  async start(request: PrepareVoiceCall, flush: () => Promise<void> | null, synthetic: boolean) {
    if (!this.canStart()) return;
    this.opening = true;
    let audio: AudioContext | undefined;
    let call: VoiceCallView | undefined;
    try {
      if (typeof AudioContext !== 'undefined' && typeof RTCPeerConnection !== 'undefined') {
        audio = new AudioContext();
        void audio.resume().catch(console.error);
      }
      await flush();
      call = await invoke<VoiceCallView>('prepare_voice_call', { request });
      let offer: string | null = null;
      if (call.media === 'webview') {
        if (!audio) throw new Error('WebRTC audio is unavailable');
        const peer = new VoicePeer(audio, synthetic);
        this.web = { id: call.id, peer, answering: false };
        audio = undefined;
        if (this.view?.id === call.id) peer.mute(this.view.microphoneMuted, this.view.speakerMuted);
        offer = await peer.offer();
      }
      await invoke('start_voice_transport', { request: { id: call.id, offer } });
    } catch (error) {
      console.error(error);
      if (call) {
        try { await this.end(call.id); } catch (endError) { console.error(endError); }
      }
    } finally {
      if (audio) void audio.close().catch(console.error);
      this.opening = false;
    }
  }

  mute(id: string, microphone: boolean, muted: boolean) {
    return invoke<void>('set_voice_mute', { request: { id, microphone, muted } });
  }

  end(id: string) {
    if (this.web?.id === id) this.closeMedia();
    return invoke<void>('end_voice_call', { id });
  }

  async fixtureMedia(call: VoiceCallView): Promise<VoiceMediaEvidence> {
    if (call.media === 'native') return invoke('read_voice_fixture_media', { id: call.id });
    if (this.web?.id !== call.id) throw new Error('The fixture no longer owns the WebRTC call');
    return this.web.peer.fixtureMedia();
  }

  private canStart() {
    return !this.opening && !this.view;
  }

  private receive(update: VoiceCallUpdate) {
    const call = update.call;
    this.view = call;
    this.present(call);
    if (this.web && (this.web.id !== call?.id || call.phase === 'ending')) this.closeMedia();
    if (!call || call.media !== 'webview' || call.phase === 'ending') return;
    const web = this.web;
    if (!web || web.id !== call.id) {
      if (!this.opening) void this.end(call.id).catch(console.error);
      return;
    }
    web.peer.mute(call.microphoneMuted, call.speakerMuted);
    if (call.phase === 'connecting' && update.answer && !web.answering) {
      web.answering = true;
      void web.peer.answer(update.answer).then(() => {
        if (this.web === web) return invoke('voice_media_ready', { id: call.id });
      }).catch((error) => {
        if (this.web !== web) return;
        console.error(error);
        void this.end(call.id).catch(console.error);
      });
    }
  }

  private closeMedia() {
    const web = this.web;
    this.web = undefined;
    web?.peer.close();
  }
}
