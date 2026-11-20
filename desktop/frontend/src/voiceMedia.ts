import { invoke } from '@tauri-apps/api/core';

const mediaDeadline = 15_000;

async function waitForPeer(condition: () => boolean, signal: AbortSignal) {
  const end = performance.now() + mediaDeadline;
  while (!condition()) {
    signal.throwIfAborted();
    if (performance.now() > end) throw new Error('WebRTC negotiation timed out');
    await new Promise<void>((resolve) => setTimeout(resolve, 25));
  }
  signal.throwIfAborted();
}

async function gather(peer: RTCPeerConnection, description: RTCSessionDescriptionInit, signal: AbortSignal) {
  await peer.setLocalDescription(description);
  await waitForPeer(() => peer.iceGatheringState === 'complete', signal);
  const sdp = peer.localDescription?.sdp;
  if (!sdp) throw new Error('WebRTC did not retain its local description');
  return sdp;
}

function testStream(audio: AudioContext, owned: OscillatorNode[]) {
  const generated = audio.createOscillator();
  const destination = audio.createMediaStreamDestination();
  generated.connect(destination);
  generated.start();
  owned.push(generated);
  return destination.stream;
}

export type VoiceMediaEvidence = {
  receiving: boolean;
  sending: boolean;
  microphoneMuted: boolean;
  speakerMuted: boolean;
};

async function receivedAudio(peer: RTCPeerConnection) {
  const reports = await peer.getStats();
  let received = false;
  reports.forEach((report) => {
    if (report.type === 'inbound-rtp' && (report.kind ?? report.mediaType) === 'audio' &&
        (report.packetsReceived ?? 0) > 0) received = true;
  });
  return received;
}

export class VoicePeer {
  private peer = new RTCPeerConnection();
  private partner: RTCPeerConnection | undefined;
  private stream: MediaStream | undefined;
  private playback: GainNode;
  private microphoneMuted = false;
  private generated: OscillatorNode[] = [];
  private lifetime = new AbortController();
  private channel: RTCDataChannel | undefined;
  private remoteChannels = new Set<RTCDataChannel>();

  constructor(private audio: AudioContext, private synthetic: boolean, private failed: () => void) {
    this.peer.onconnectionstatechange = () => {
      if (!this.lifetime.signal.aborted && this.peer.connectionState === 'failed') failed();
    };
    this.playback = audio.createGain();
    this.playback.connect(synthetic ? audio.createMediaStreamDestination() : audio.destination);
    this.peer.ontrack = ({ track }) => {
      if (track.kind !== 'audio' || this.lifetime.signal.aborted) return;
      this.audio.createMediaStreamSource(new MediaStream([track])).connect(this.playback);
    };
  }

  async offer() {
    const signal = this.lifetime.signal;
    const stream = this.synthetic ? testStream(this.audio, this.generated) : await navigator.mediaDevices.getUserMedia({
      audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true },
    });
    if (signal.aborted) {
      for (const track of stream.getTracks()) track.stop();
      signal.throwIfAborted();
    }
    this.stream = stream;
    for (const track of stream.getAudioTracks()) {
      track.enabled = !this.microphoneMuted;
      this.peer.addTrack(track, stream);
    }
    this.channel = this.peer.createDataChannel('oai-events');
    this.channel.onclose = () => { if (!this.lifetime.signal.aborted) this.failed(); };
    const offer = await gather(this.peer, await this.peer.createOffer(), signal);
    if (this.synthetic) {
      const partner = new RTCPeerConnection();
      this.partner = partner;
      partner.ondatachannel = ({ channel }) => {
        this.remoteChannels.add(channel);
        channel.onclose = () => { this.remoteChannels.delete(channel); };
      };
      const response = testStream(this.audio, this.generated);
      for (const track of response.getAudioTracks()) partner.addTrack(track, response);
      await partner.setRemoteDescription({ type: 'offer', sdp: offer });
      const answer = await gather(partner, await partner.createAnswer(), signal);
      await invoke('record_voice_fixture_exchange', { offer, answer });
    }
    return offer;
  }

  async answer(sdp: string) {
    await this.peer.setRemoteDescription({ type: 'answer', sdp });
    await waitForPeer(() => {
      const state = this.peer.connectionState;
      if (state === 'failed' || state === 'closed') throw new Error('The WebRTC media connection closed');
      return state === 'connected';
    }, this.lifetime.signal);
  }

  mute(microphone: boolean, speakers: boolean) {
    this.microphoneMuted = microphone;
    for (const track of this.stream?.getAudioTracks() ?? []) track.enabled = !microphone;
    this.playback.gain.value = speakers ? 0 : 1;
  }

  async fixtureMedia(): Promise<VoiceMediaEvidence> {
    if (!this.synthetic || !this.partner || !this.stream) throw new Error('No synthetic media connection');
    return {
      receiving: await receivedAudio(this.peer), sending: await receivedAudio(this.partner),
      microphoneMuted: this.stream.getAudioTracks().every((track) => !track.enabled),
      speakerMuted: this.playback.gain.value === 0,
    };
  }

  close() {
    if (this.lifetime.signal.aborted) return;
    this.lifetime.abort();
    for (const track of this.stream?.getTracks() ?? []) track.stop();
    this.channel?.close();
    this.peer.close();
    this.partner?.close();
    for (const node of this.generated.splice(0)) {
      node.stop();
      node.disconnect();
    }
    this.playback.disconnect();
  }
}
