interface MediaEvidence {
  secureContext: boolean;
  captureApi: boolean;
  playbackApi: boolean;
  peerApi: boolean;
  negotiatedSessions: number;
  failure: string | null;
}

export async function probeMedia(): Promise<MediaEvidence> {
  const evidence: MediaEvidence = {
    secureContext: window.isSecureContext,
    captureApi: typeof navigator.mediaDevices?.getUserMedia === 'function',
    playbackApi: typeof AudioContext === 'function',
    peerApi: typeof RTCPeerConnection === 'function',
    negotiatedSessions: 0,
    failure: null,
  };
  if (!evidence.peerApi) return evidence;
  try {
    for (let session = 0; session < 2; session += 1) {
      await negotiateVoiceOffer();
      evidence.negotiatedSessions += 1;
    }
  } catch (error) {
    evidence.failure = error instanceof Error ? error.message : String(error);
  }
  return evidence;
}

async function negotiateVoiceOffer() {
  const sender = new RTCPeerConnection();
  const receiver = new RTCPeerConnection();
  let timer = 0;
  try {
    const negotiation = async () => {
      sender.addTransceiver('audio', { direction: 'sendrecv' });
      sender.createDataChannel('oai-events');
      const offer = await sender.createOffer();
      await sender.setLocalDescription(offer);
      await receiver.setRemoteDescription(offer);
      const answer = await receiver.createAnswer();
      await receiver.setLocalDescription(answer);
      await sender.setRemoteDescription(answer);
      if (![offer.sdp, answer.sdp].every((sdp) =>
        sdp && /^m=audio [1-9]\d* /m.test(sdp) &&
          /^a=rtpmap:\d+ opus\/48000/im.test(sdp) &&
          /^m=application [1-9]\d* /m.test(sdp)
      )) {
        throw new Error('Media negotiation did not retain Opus audio and the data channel');
      }
    };
    const timeout = new Promise<never>((_, reject) => {
      timer = window.setTimeout(() => reject(new Error('Media negotiation timed out')), 10_000);
    });
    await Promise.race([negotiation(), timeout]);
  } finally {
    window.clearTimeout(timer);
    sender.close();
    receiver.close();
  }
}
