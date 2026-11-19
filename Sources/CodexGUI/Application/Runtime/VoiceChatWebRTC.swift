import AppKit
import WebKit

@MainActor
protocol VoiceChatPeer: AnyObject
{
	func makeOffer() async throws -> String
	func applyAnswer(_ sdp: String) async throws
	func setMuted(
		microphone: Bool,
		speakers: Bool
	)
	func close()
}

/// Owns the audio tracks and peer connection for one voice call. App-server owns signaling.
@MainActor
final class VoiceChatWebRTC: NSObject, VoiceChatPeer, WKNavigationDelegate, WKUIDelegate
{
	@MainActor
	private final class MessageRelay: NSObject, WKScriptMessageHandler
	{
		weak var peer: VoiceChatWebRTC?

		func userContentController(
			_ userContentController: WKUserContentController,
			didReceive message: WKScriptMessage
		)
		{
			peer?.receive(message)
		}
	}

	private static let origin = URL(string: "https://codex-voice.invalid/")!
	private let webView: WKWebView
	private var navigation: CheckedContinuation<Void, Error>?
	private var closed = false
	private var onReady: (() -> Void)?
	private var onFailure: (() -> Void)?
	private var onPlaybackLevel: ((Double) -> Void)?

	init(
		host: NSView,
		onReady: @escaping () -> Void,
		onFailure: @escaping () -> Void,
		onPlaybackLevel: @escaping (Double) -> Void
	)
	{
		let configuration = WKWebViewConfiguration()
		configuration.websiteDataStore = .nonPersistent()
		configuration.mediaTypesRequiringUserActionForPlayback = []
		webView = WKWebView(
			frame: NSRect(
				x: 0,
				y: 0,
				width: 1,
				height: 1
			),
			configuration: configuration
		)
		self.onReady = onReady
		self.onFailure = onFailure
		self.onPlaybackLevel = onPlaybackLevel
		super.init()
		webView.setAccessibilityHidden(true)
		webView.navigationDelegate = self
		webView.uiDelegate = self
		let relay = MessageRelay()
		relay.peer = self
		configuration.userContentController.add(
			relay,
			name: "voicePeer"
		)
		host.addSubview(
			webView,
			positioned: .below,
			relativeTo: nil
		)
	}

	func makeOffer() async throws -> String
	{
		guard !closed
		else
		{
			throw CancellationError()
		}
		try await withCheckedThrowingContinuation
		{
			navigation = $0
			// WebKit assigns a secure origin to this app-owned document without a network load.
			webView.loadSimulatedRequest(
				URLRequest(url: Self.origin),
				responseHTML: Self.document
			)
		}
		guard !closed, let offer = try await webView.callAsyncJavaScript(
			"return await voice.offer()",
			arguments: [:],
			in: nil,
			contentWorld: .page
		) as? String, !offer.isEmpty
		else
		{
			throw ReadAloudError.invalidResponse
		}
		return offer
	}

	func applyAnswer(_ sdp: String) async throws
	{
		guard !closed
		else
		{
			throw CancellationError()
		}
		_ = try await webView.callAsyncJavaScript(
			"await voice.answer(sdp)",
			arguments: ["sdp": sdp],
			in: nil,
			contentWorld: .page
		)
	}

	func setMuted(
		microphone: Bool,
		speakers: Bool
	)
	{
		guard !closed
		else
		{
			return
		}
		webView.callAsyncJavaScript(
			"voice.mute(microphone, speakers)",
			arguments: ["microphone": microphone, "speakers": speakers],
			in: nil,
			in: .page
		)
		{
			[weak self] result in
			if case .failure = result
			{
				self?.onFailure?()
			}
		}
	}

	func close()
	{
		guard !closed
		else
		{
			return
		}
		closed = true
		onReady = nil
		onFailure = nil
		onPlaybackLevel = nil
		finishNavigation(.failure(CancellationError()))
		webView.configuration.userContentController.removeScriptMessageHandler(forName: "voicePeer")
		webView.stopLoading()
		webView.setMicrophoneCaptureState(.none)
		webView.evaluateJavaScript("voice.close()")
		webView.removeFromSuperview()
	}

	func webView(
		_ webView: WKWebView,
		didFinish navigation: WKNavigation!
	)
	{
		finishNavigation(.success(()))
	}

	func webView(
		_ webView: WKWebView,
		didFailProvisionalNavigation navigation: WKNavigation!,
		withError error: Error
	)
	{
		finishNavigation(.failure(error))
	}

	func webView(
		_ webView: WKWebView,
		didFail navigation: WKNavigation!,
		withError error: Error
	)
	{
		finishNavigation(.failure(error))
	}

	func webViewWebContentProcessDidTerminate(_ webView: WKWebView)
	{
		onFailure?()
	}

	func webView(
		_ webView: WKWebView,
		decidePolicyFor navigationAction: WKNavigationAction
	) async -> WKNavigationActionPolicy
	{
		!closed && navigationAction.targetFrame?.isMainFrame == true
			&& navigationAction.request.url == Self.origin ? .allow : .cancel
	}

	func webView(
		_ webView: WKWebView,
		decideMediaCapturePermissionsFor origin: WKSecurityOrigin,
		initiatedBy frame: WKFrameInfo,
		type: WKMediaCaptureType
	) async -> WKPermissionDecision
	{
		!closed && frame.isMainFrame && type == .microphone && trusted(origin) ? .grant : .deny
	}

	private func receive(_ message: WKScriptMessage)
	{
		guard !closed, message.frameInfo.isMainFrame, trusted(message.frameInfo.securityOrigin)
		else
		{
			return
		}
		switch message.body as? String
		{
		case "ready": onReady?()
		case "failed": onFailure?()
		default: break
		}
		if let level = message.body as? Double, (0 ... 1).contains(level)
		{
			onPlaybackLevel?(level)
		}
	}

	private func trusted(_ origin: WKSecurityOrigin) -> Bool
	{
		origin.protocol == "https" && origin.host == Self.origin.host
	}

	private func finishNavigation(_ result: Result<Void, Error>)
	{
		let pending = navigation
		navigation = nil
		pending?.resume(with: result)
	}

	private static let document = """
	<!doctype html>
	<meta http-equiv="Content-Security-Policy"
	      content="default-src 'none'; script-src 'unsafe-inline'; media-src blob:">
	<audio></audio>
	<script>
	const voice = (() => {
	  const peer = new RTCPeerConnection({iceServers: []});
	  const channel = peer.createDataChannel('oai-events');
	  const audio = document.querySelector('audio');
	  audio.muted = true;
	  let microphone, closed = false, meterTimer;
	  const signal = event => {
	    if (!closed) window.webkit.messageHandlers.voicePeer.postMessage(event);
	  };
	  channel.onopen = () => signal('ready');
	  channel.onclose = () => signal('failed');
	  peer.onconnectionstatechange = () => {
	    if (peer.connectionState === 'failed') signal('failed');
	  };
	  const meter = receiver => {
	    let previous;
	    const sample = async () => {
	      let level = 0;
	      if (!audio.muted) {
	        try {
	          const reports = await receiver.getStats();
	          const inbound = [...reports.values()].find(report => report.type === 'inbound-rtp');
	          if (inbound) {
	            const {totalAudioEnergy: energy, totalSamplesDuration: duration, id} = inbound;
	            if (Number.isFinite(energy) && Number.isFinite(duration)) {
	              if (previous?.id === id && duration > previous.duration) {
	                level = Math.sqrt(Math.max(0, (energy - previous.energy) /
	                                             (duration - previous.duration)));
	              }
	              previous = {energy, duration, id};
	            } else {
	              level = inbound.audioLevel ?? 0;
	            }
	          }
	        } catch {
	          // Metering is independent of playback.
	        }
	      } else {
	        previous = undefined;
	      }
	      if (!closed && receiver.track === audio.srcObject?.getAudioTracks()[0]) {
	        signal(audio.muted ? 0 : Math.min(1, level));
	        meterTimer = setTimeout(sample, 80);
	      }
	    };
	    clearTimeout(meterTimer);
	    sample();
	  };
	  peer.ontrack = ({track, receiver}) => {
	    audio.srcObject = new MediaStream([track]);
	    audio.play().catch(() => signal('failed'));
	    meter(receiver);
	  };
	  return {
	    async offer() {
	      const stream = await navigator.mediaDevices.getUserMedia({audio: true});
	      if (closed) {
	        stream.getTracks().forEach(track => track.stop());
	        throw new Error('Closed');
	      }
	      microphone = stream.getAudioTracks()[0];
	      microphone.enabled = false;
	      peer.addTrack(microphone, stream);
	      await peer.setLocalDescription(await peer.createOffer());
	      if (peer.iceGatheringState !== 'complete') {
	        await new Promise(resolve => {
	          const done = () => {
	            peer.removeEventListener('icegatheringstatechange', check);
	            clearTimeout(deadline);
	            resolve();
	          };
	          const check = () => {
	            if (peer.iceGatheringState === 'complete') done();
	          };
	          const deadline = setTimeout(done, 2000);
	          peer.addEventListener('icegatheringstatechange', check);
	          check();
	        });
	      }
	      return peer.localDescription.sdp;
	    },
	    async answer(sdp) { await peer.setRemoteDescription({type: 'answer', sdp}); },
	    mute(mic, speakers) {
	      if (microphone && channel.readyState === 'open') microphone.enabled = !mic;
	      audio.muted = speakers;
	    },
	    close() {
	      closed = true;
	      clearTimeout(meterTimer);
	      microphone?.stop();
	      peer.close();
	      audio.srcObject = null;
	    },
	  };
	})();
	</script>
	"""
}
