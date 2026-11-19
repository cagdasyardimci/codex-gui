import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct VoiceChatRuntimeTests
{
	enum Scenario: String, Sendable
	{
		case fallback
		case stopBeforeClose
		case reconnect
		case disconnectBeforeClose
	}

	@Test(arguments: [Scenario.fallback, .stopBeforeClose, .reconnect, .disconnectBeforeClose])
	func voiceRecoveryWaitsForRequestedCloseAndHonorsTheUserAction(
		_ scenario: Scenario
	) async throws
	{
		let directory = try await AppServerTestExecutable.temporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let executable = try await AppServerTestExecutable.mockExecutable(
			in: directory,
			script: #"""
			#!/usr/bin/env python3
			import json, os, sys
			if '--version' in sys.argv:
			    print('codex-cli 0.169.0')
			    sys.exit(0)

			def emit(message):
			    print(json.dumps(message), flush=True)

			def notify(method, **params):
			    emit({'method': method, 'params': params})

			scenario = 'SCENARIO'
			starts = []
			close_released = False
			for line in sys.stdin:
			    msg = json.loads(line)
			    method = msg['method']
			    params = msg.get('params', {})
			    if method == 'initialized': continue
			    result = {}
			    if method == 'config/read':
			        result = {'config': {
			            'model_provider': 'openai',
			            'realtime': {'voice': 'maple' if starts else 'cove'},
			            'model_providers': {'openai': {'experimental_bearer_token': 'fixture'}}
			        }}
			    elif method == 'account/read':
			        result = {'account': {'type': 'chatgpt'}}
			    elif method == 'thread/realtime/listVoices':
			        result = {'voices': {'v3': ['cove', 'maple'], 'defaultV1': 'cove'}}
			    elif method == 'thread/resume':
			        assert params['threadId'] == 'selected'
			        cwd = os.path.realpath(os.path.dirname(sys.argv[0]))
			        result = {'cwd': cwd, 'thread': {'id': 'selected', 'cwd': cwd}}
			    elif method == 'thread/turns/list':
			        assert params['threadId'] == 'selected'
			        result = {'data': [], 'nextCursor': None}
			    elif method == 'thread/realtime/start':
			        assert params['threadId'] == 'selected'
			        assert params['version'] == 'v3'
			        assert params['voice'] == 'cove'
			        transport = params['transport']['type']
			        if starts:
			            assert close_released, 'fallback began before the requested close'
			            if scenario == 'reconnect':
			                assert transport == 'webrtc'
			                assert params['voiceSessionId'] != starts[0][1]
			            else:
			                assert transport == 'websocket'
			                assert params['voiceSessionId'] == starts[0][1]
			        else:
			            assert transport == 'webrtc'
			        if scenario in ('reconnect', 'disconnectBeforeClose'):
			            notify('thread/realtime/sdp', threadId='selected', sdp='v=answer')
			            notify('thread/realtime/started', threadId='selected')
			        elif not starts:
			            notify('thread/realtime/error', threadId='selected', message='fixture')
			        else:
			            notify('skills/changed')
			        starts.append((transport, params['voiceSessionId']))
			    elif method == 'thread/realtime/stop':
			        assert params['threadId'] == 'selected'
			        if close_released:
			            notify('thread/realtime/closed', threadId='selected', reason='requested')
			        else:
			            notify('thread/realtime/closed',
			                   threadId='selected', reason='transport_closed')
			            notify('account/updated')
			    elif method == 'fixture/releaseClose':
			        close_released = True
			        notify('thread/realtime/closed', threadId='selected', reason='requested')
			    elif method == 'fixture/drop':
			        notify('thread/realtime/error', threadId='selected', message='fixture')
			    elif method == 'fixture/transports':
			        result = {'data': [transport for transport, session in starts]}
			    elif method != 'initialize':
			        raise ValueError(method)
			    emit({'id': msg['id'], 'result': result})
			"""#.replacingOccurrences(
				of: "SCENARIO",
				with: scenario.rawValue
			)
		)
		let server = AppServer(
			executableOverride: executable,
			requestTimeout: .seconds(5)
		)
		try await server.connect()
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: directory.path
		))
		model.connection.isConnected = true
		model.preferences.accountStatus = AccountStatus(
			type: "chatgpt",
			email: nil,
			requiresOpenAIAuth: true
		)
		model.conversations.selectedConversation = .thread("selected")
		let store = WorkspaceStateStore(
			model: model,
			service: server,
			persistence: WorkspacePersistenceScheduler(writeDraft:
				{
					_ in
				}),
			projectContextStore: ProjectContextStore(directory: directory)
		)
		var peers: [TestPeer] = []
		let runtime = VoiceChatRuntime(
			requestMicrophonePermission:
			{
				true
			},
			makePeer:
			{
				_, onReady, _, _ in
				let peer = TestPeer(onReady: onReady)
				peers.append(peer)
				return peer
			}
		)
		let host = NSView()
		runtime.webRTCHost = host
		let available = AsyncStream<Void>.makeStream()
		let live = AsyncStream<Void>.makeStream()
		let waitingForClose = AsyncStream<Void>.makeStream()
		let fallbackStarted = AsyncStream<Void>.makeStream()
		let retired = AsyncStream<Void>.makeStream()
		var didStart = false
		var publishedLivePeerCount = 0
		runtime.onChange =
		{
			if didStart
			{
				if runtime.acceptsText, publishedLivePeerCount != peers.count
				{
					publishedLivePeerCount = peers.count
					live.continuation.yield(())
				}
				if !runtime.hasCall
				{
					retired.continuation.yield(())
				}
			}
			else if runtime.canStart(store: store)
			{
				available.continuation.yield(())
			}
		}
		server.onEvent =
		{
			switch $0
			{
			case .accountUpdated: waitingForClose.continuation.yield(())
			case .skillsChanged: fallbackStarted.continuation.yield(())
			default: break
			}
		}
		let deadline = Task
		{
			try? await Task.sleep(for: .seconds(10))
			available.continuation.finish()
			live.continuation.finish()
			waitingForClose.continuation.finish()
			fallbackStarted.continuation.finish()
			retired.continuation.finish()
		}
		defer
		{
			deadline.cancel()
			runtime.onChange = nil
			server.onEvent = nil
			store.shutdown()
			runtime.stop()
			server.disconnect()
		}

		runtime.refreshAvailability(store: store)
		try #require(await receivedEvent(in: available.stream))
		didStart = true
		runtime.start(store: store)
		var liveEvents = live.stream.makeAsyncIterator()
		if scenario == .reconnect || scenario == .disconnectBeforeClose
		{
			let started: Void? = await liveEvents.next()
			try #require(started != nil)
			runtime.toggleMicrophone()
			runtime.toggleSpeakers()
			_ = try await server.request(
				"fixture/drop",
				params: [:]
			)
		}
		try #require(await receivedEvent(in: waitingForClose.stream))
		#expect(peers.first?.closed == true)
		#expect(runtime.hasCall)
		#expect(!runtime.canReconnect(store: store))
		#expect(runtime.threadID == "selected")
		let beforeClose = try await server.request(
			"fixture/transports",
			params: [:]
		)
		#expect(beforeClose["data"] as? [String] == ["webrtc"])
		if scenario == .disconnectBeforeClose
		{
			server.disconnect()
			#expect(!runtime.hasCall)
			try await server.connect()
			didStart = false
			runtime.refreshAvailability(store: store)
			try #require(await receivedEvent(in: available.stream))
			#expect(runtime.canReconnect(store: store))
			#expect(peers.count == 1)
			return
		}
		if scenario == .stopBeforeClose
		{
			runtime.stop()
		}
		_ = try await server.request(
			"fixture/releaseClose",
			params: [:]
		)
		var expectedTransports = ["webrtc"]
		switch scenario
		{
		case .fallback:
			try #require(await receivedEvent(in: fallbackStarted.stream))
			runtime.stop()
			expectedTransports.append("websocket")
		case .stopBeforeClose, .disconnectBeforeClose:
			break
		case .reconnect:
			try #require(await receivedEvent(in: retired.stream))
			try #require(runtime.canReconnect(store: store))
			let beforeReconnect = try await server.request(
				"fixture/transports",
				params: [:]
			)
			#expect(beforeReconnect["data"] as? [String] == expectedTransports)
			runtime.start(store: store)
			let reconnected: Void? = await liveEvents.next()
			try #require(reconnected != nil)
			#expect(runtime.acceptsText)
			#expect(runtime.threadID == "selected")
			#expect(runtime.microphoneMuted && runtime.speakersMuted)
			#expect(!runtime.canReconnect(store: store))
			runtime.stop()
			expectedTransports.append("webrtc")
		}
		try #require(await receivedEvent(in: retired.stream))
		let afterClose = try await server.request(
			"fixture/transports",
			params: [:]
		)
		#expect(afterClose["data"] as? [String] == expectedTransports)
		_ = host
	}

	private func receivedEvent(in stream: AsyncStream<Void>) async -> Bool
	{
		var iterator = stream.makeAsyncIterator()
		return await iterator.next() != nil
	}

	private final class TestPeer: VoiceChatPeer
	{
		var closed = false
		let onReady: () -> Void

		init(onReady: @escaping () -> Void)
		{
			self.onReady = onReady
		}

		func makeOffer() async throws -> String
		{
			"v=fixture"
		}

		func applyAnswer(_ sdp: String) async throws
		{
			onReady()
		}

		func setMuted(
			microphone: Bool,
			speakers: Bool
		)
		{
		}

		func close()
		{
			closed = true
		}
	}
}
