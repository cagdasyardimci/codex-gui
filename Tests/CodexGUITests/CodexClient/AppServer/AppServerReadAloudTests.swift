import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AppServerReadAloudTests
{
	@Test(arguments: [
		"api-key",
		"bearer",
		"no-credentials",
		"disabled",
		"no-voices",
		"missing-config"
	])
	func availabilityRequiresCredentialsAndV3VoicesWithoutStartingSpeech(mode: String) async throws
	{
		let (server, directory) = try await fixture(mode: mode)
		defer
		{
			server.disconnect()
			try? FileManager.default.removeItem(at: directory)
		}
		try await server.connect()
		#expect(try await server.readAloudAvailable(in: directory) == ["api-key", "bearer"]
			.contains(mode))
		let expected: [String]
		switch mode
		{
		case "disabled", "missing-config": expected = ["config/read"]
		case "no-credentials": expected = ["config/read", "account/read"]
		default: expected = ["config/read", "account/read", "thread/realtime/listVoices"]
		}
		#expect(try await methods(in: server) == expected)
	}

	@Test func speechWireAndOwnerEventsRemainScopedAndUnsubscribeAfterStopRejects() async throws
	{
		let (server, directory) = try await fixture(mode: "stop-rejected")
		defer
		{
			server.disconnect()
			try? FileManager.default.removeItem(at: directory)
		}
		let received = AsyncStream<String>.makeStream()
		let barriers = AsyncStream<Void>.makeStream()
		defer
		{
			server.onReadAloudEvent = nil
			server.onEvent = nil
			received.continuation.finish()
			barriers.continuation.finish()
		}
		var tags: [String] = []
		server.onReadAloudEvent =
		{
			threadID, event in
			#expect(threadID == "private-voice")
			let tag: String
			switch event
			{
			case .started(let version): tag = "started:" + version
			case .audio(let chunk):
				#expect(chunk.pcmData == Data([0, 0, 255, 127]))
				#expect(chunk.sampleRate == 24000 && chunk.channelCount == 1)
				#expect(chunk.frameCount == 2)
				tag = "audio"
			case .segmentFinished: tag = "finished"
			case .failed: tag = "failed"
			case .closed: tag = "closed"
			case .playbackDrained:
				Issue.record("A backend notification invented a local playback completion")
				tag = "playback-drained"
			}
			tags.append(tag)
			received.continuation.yield(tag)
		}
		server.onEvent =
		{
			if case .threadQueueChanged = $0
			{
				barriers.continuation.yield(())
			}
		}
		try await server.connect()
		let threadID = try await server.createReadAloudThread(in: directory)
		#expect(threadID == "private-voice")
		try await server.startReadAloudSession(threadID: threadID)
		try await server.appendReadAloudSpeech(
			threadID: threadID,
			text: "Hello 👋\nExact \"quoted\" source."
		)
		_ = try await server.settingsRequest(
			"test/emit",
			params: [:]
		)
		var events = received.stream.makeAsyncIterator()
		while try #require(await events.next()) != "closed"
		{
		}
		var barrier = barriers.stream.makeAsyncIterator()
		try #require(await barrier.next() != nil)
		#expect(tags == ["started:v3", "audio", "finished", "failed", "failed", "failed", "closed"])
		await server.retireReadAloudThread(threadID: threadID)
		await server.retireReadAloudThread(threadID: threadID)
		#expect(server.readAloudThreadGenerations[threadID] == nil)
		#expect(try await methods(in: server) == [
			"thread/start",
			"thread/realtime/start",
			"thread/realtime/appendSpeech",
			"thread/realtime/stop",
			"thread/unsubscribe"
		])
		_ = try await server.settingsRequest(
			"test/emit",
			params: [:]
		)
		try #require(await barrier.next() != nil)
		#expect(tags.count == 7)
	}

	@Test func reconnectRejectsPreviousConnectionThreadsAndTheirEvents() async throws
	{
		let (server, directory) = try await fixture(mode: "api-key")
		defer
		{
			server.disconnect()
			try? FileManager.default.removeItem(at: directory)
		}
		try await server.connect()
		let threadID = try await server.createReadAloudThread(in: directory)
		let oldGeneration = server.connectionGeneration
		#expect(server.readAloudThreadGenerations[threadID] == oldGeneration)
		server.disconnect()
		try await server.connect()
		#expect(server.connectionGeneration != oldGeneration)
		var delivered = false
		server.onReadAloudEvent =
		{
			_, _ in delivered = true
		}
		defer
		{
			server.onReadAloudEvent = nil
		}
		#expect(!server.receiveReadAloudNotification(
			method: "thread/realtime/transcript/done",
			parameters: ["threadId": threadID, "role": "assistant"]
		))
		#expect(!delivered)
		do
		{
			try await server.startReadAloudSession(threadID: threadID)
			Issue.record("Started speech on a previous connection's private thread")
		}
		catch AppServerError.disconnected
		{
		}
		do
		{
			try await server.appendReadAloudSpeech(
				threadID: threadID,
				text: "Stale speech"
			)
			Issue.record("Appended speech to a previous connection's private thread")
		}
		catch AppServerError.disconnected
		{
		}
		await server.retireReadAloudThread(threadID: threadID)
		#expect(try await methods(in: server) == [])
		#expect(try await server.createReadAloudThread(in: directory) == threadID)
		#expect(server.readAloudThreadGenerations[threadID] == server.connectionGeneration)
		await server.retireReadAloudThread(threadID: threadID)
		#expect(try await methods(in: server) == [
			"thread/start",
			"thread/realtime/stop",
			"thread/unsubscribe"
		])
	}

	private func methods(in server: AppServer) async throws -> [String]
	{
		let result = try await server.settingsRequest(
			"test/requests",
			params: [:]
		)
		return try #require(result["methods"] as? [String])
	}

	private func fixture(mode: String) async throws -> (AppServer, URL)
	{
		let directory = try await AppServerTestExecutable.temporaryDirectory()
		do
		{
			let absentKey = "CODEX_GUI_VOICE_TEST_" + UUID().uuidString
			let executable = try await AppServerTestExecutable.mockExecutable(
				in: directory,
				script: #"""
				#!/usr/bin/env python3
				import json, os, sys
				if '--version' in sys.argv:
				    print('codex-cli 0.164.0')
				    sys.exit(0)
				mode = "\#(mode)"
				methods = []
				def send(value): print(json.dumps(value), flush=True)
				def event(method, params): send({'method':method, 'params':params})
				def owned(method, extra=None):
				    event(method, dict({'threadId':'private-voice'}, **(extra or {})))
				for line in sys.stdin:
				    message = json.loads(line)
				    method = message.get('method')
				    params = message.get('params', {})
				    if method in (None, 'initialized'): continue
				    if method not in ('initialize', 'test/requests', 'test/emit'):
				        methods.append(method)
				    result = {}
				    if method == 'initialize': result = {'userAgent':'controlled-voice-mock'}
				    elif method == 'config/read':
				        assert params == {'includeLayers':False,
				                          'cwd':os.path.dirname(__file__)}, params
				        provider = {'env_key':'\#(absentKey)'}
				        if mode == 'bearer': provider['experimental_bearer_token'] = 'fixture-only'
				        config = {'model_provider':'test-voice-provider',
				                  'model_providers':{'test-voice-provider':provider},
				                  'features':{'realtime_conversation':mode != 'disabled'}}
				        result = {'config':None if mode == 'missing-config' else config}
				    elif method == 'account/read':
				        assert params == {'refreshToken':False}, params
				        kind = 'apiKey' if mode in ('api-key', 'no-voices') else 'chatgpt'
				        result = {'account':{'type':kind}, 'requiresOpenaiAuth':True}
				    elif method == 'thread/realtime/listVoices':
				        assert params == {}, params
				        result = {'voices':{'v1':['cove'],
				                             'v3':[] if mode == 'no-voices' else ['cove']}}
				    elif method == 'thread/start':
				        assert params == {'cwd':os.path.dirname(__file__), 'ephemeral':True,
				                          'approvalPolicy':'never', 'sandbox':'read-only'}, params
				        result = {'thread':{'id':'private-voice'}}
				    elif method == 'thread/realtime/start':
				        assert params == {'threadId':'private-voice', 'version':'v3',
				                          'outputModality':'audio', 'includeStartupContext':False,
				                          'clientManagedHandoffs':True,
				                          'flushTranscriptTailOnSessionEnd':False,
				                          'backendReasoningStatus':False,
				                          'transport':{'type':'websocket'}}, params
				    elif method == 'thread/realtime/appendSpeech':
				        assert params == {'threadId':'private-voice',
				                          'text':'Hello 👋\nExact "quoted" source.'}, params
				    elif method in ('thread/realtime/stop', 'thread/unsubscribe'):
				        assert params == {'threadId':'private-voice'}, params
				        if method.endswith('/stop') and mode == 'stop-rejected':
				            send({'id':message['id'], 'error':{'code':-32600,
				                  'message':'Controlled stop rejection'}})
				            continue
				    elif method == 'test/requests': result = {'methods':methods}
				    elif method == 'test/emit':
				        audio = {'data':'AAD/fw==', 'sampleRate':24000,
				                 'numChannels':1, 'samplesPerChannel':2}
				        event('thread/realtime/outputAudio/delta',
				              {'threadId':'chat', 'audio':audio})
				        owned('thread/realtime/started', {'version':'v3'})
				        owned('thread/realtime/outputAudio/delta',
				              {'audio':dict(audio, data='', samplesPerChannel=0)})
				        owned('thread/realtime/outputAudio/delta', {'audio':audio})
				        owned('thread/realtime/transcript/done', {'role':'user'})
				        owned('thread/realtime/transcript/done', {'role':'assistant'})
				        broken = dict(audio, data='not base64')
				        owned('thread/realtime/outputAudio/delta', {'audio':broken})
				        owned('thread/realtime/outputAudio/delta',
				              {'audio':{'data':'AAD/fw=='}})
				        owned('thread/realtime/itemAdded', {'item':{'type':'handoff_request'}})
				        owned('thread/realtime/closed')
				        event('thread/queue/changed', {'threadId':'delivery-barrier'})
				    else:
				        send({'id':message['id'], 'error':{'code':-32601,
				              'message':'Unexpected method '+str(method)}})
				        continue
				    send({'id':message['id'], 'result':result})
				"""#
			)
			return (
				AppServer(
					executableOverride: executable,
					requestTimeout: .seconds(3)
				),
				directory
			)
		}
		catch
		{
			try? FileManager.default.removeItem(at: directory)
			throw error
		}
	}
}
