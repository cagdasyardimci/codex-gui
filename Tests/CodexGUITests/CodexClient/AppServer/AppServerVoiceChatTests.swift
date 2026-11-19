import Foundation
import Testing

@testable import CodexGUI

@MainActor
struct AppServerVoiceChatTests
{
	@Test func chatGPTVoiceNegotiatesSDPWithoutAProviderKey() async throws
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
			import json, sys
			if '--version' in sys.argv:
			    print('codex-cli 0.169.0')
			    sys.exit(0)
			for line in sys.stdin:
			    msg = json.loads(line)
			    method = msg.get('method')
			    if method == 'initialized': continue
			    result = {}
			    if method == 'config/read':
			        result = {'config': {'model_provider': 'openai'}}
			    elif method == 'thread/realtime/listVoices':
			        result = {'voices': {'v3': ['cove'], 'defaultV1': 'cove'}}
			    elif method == 'thread/realtime/start':
			        params = msg['params']
			        assert params['version'] == 'v3', params
			        assert params['voice'] == 'cove', params
			        assert params['transport'] == {
			            'type': 'webrtc', 'sdp': 'v=offer\r\n'
			        }, params
			        answers = [('different', 'wrong'), (params['threadId'], 'v=answer\r\n')]
			        for owner, sdp in answers:
			            answer = {'method': 'thread/realtime/sdp',
			                      'params': {'threadId': owner, 'sdp': sdp}}
			            print(json.dumps(answer), flush=True)
			    elif method != 'initialize':
			        raise ValueError(method)
			    print(json.dumps({'id': msg['id'], 'result': result}), flush=True)
			"""#
		)
		let server = AppServer(
			executableOverride: executable,
			requestTimeout: .seconds(5)
		)
		defer
		{
			server.disconnect()
		}
		try await server.connect()
		#expect(try await server.chatGPTVoiceAvailable(in: directory))
		var answers: [String] = []
		server.voiceChatObservers["voice-owner"] =
		{
			if case .sdp(let answer) = $0
			{
				answers.append(answer)
			}
		}
		try await server.startVoiceChat(
			threadID: "voice-owner",
			sessionID: UUID(),
			offer: "v=offer\r\n",
			voice: try await server.realtimeVoiceForSession(in: directory)
		)
		#expect(answers == ["v=answer\r\n"])
	}

	@Test func voiceUsesTheSelectedChatWithoutCreatingOrRenamingIt() async throws
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
			for line in sys.stdin:
			    msg = json.loads(line)
			    method = msg.get('method')
			    if method == 'initialized': continue
			    result = {}
			    if method == 'thread/resume':
			        assert msg['params']['threadId'] == 'selected', msg
			        cwd = os.path.realpath(os.path.dirname(sys.argv[0]))
			        result = {'cwd': cwd, 'thread': {
			            'id': 'selected', 'cwd': cwd, 'name': 'Existing task'
			        }}
			    elif method == 'thread/turns/list':
			        assert msg['params']['threadId'] == 'selected', msg
			        result = {'data': [], 'nextCursor': None}
			    elif method == 'config/read':
			        cwd = os.path.realpath(os.path.dirname(sys.argv[0]))
			        assert os.path.realpath(msg['params']['cwd']) == cwd, msg
			        result = {'config': {'realtime': {'voice': 'maple'}}}
			    elif method == 'thread/realtime/listVoices':
			        result = {'voices': {'v3': ['maple', 'cove'], 'defaultV1': 'cove'}}
			    elif method == 'thread/realtime/start':
			        assert msg['params']['threadId'] == 'selected', msg
			        assert msg['params']['voice'] == 'maple', msg
			    elif method != 'initialize':
			        raise ValueError(method)
			    print(json.dumps({'id': msg['id'], 'result': result}), flush=True)
			"""#
		)
		let server = AppServer(
			executableOverride: executable,
			requestTimeout: .seconds(5)
		)
		defer
		{
			server.disconnect()
		}
		try await server.connect()
		let summary = try await server.prepareVoiceChat(
			threadID: "selected",
			projectPath: directory.path,
			model: nil,
			effort: nil,
			preferences: RunPreferences(
				approvalMode: .askForApproval,
				fastMode: true
			)
		)
		try await server.startVoiceChat(
			threadID: summary.id,
			sessionID: UUID(),
			offer: nil,
			voice: try await server.realtimeVoiceForSession(in: directory)
		)
		#expect(summary.name == "Existing task")
	}

	@Test func timelineExtendsToTheVisibleTurnAndRestoresSpeechAcrossThePageBoundary() async throws
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
			import json, sys
			if '--version' in sys.argv:
			    print('codex-cli 0.169.0')
			    sys.exit(0)
			for line in sys.stdin:
			    msg = json.loads(line)
			    method = msg.get('method')
			    if method == 'initialized': continue
			    result = {}
			    if method == 'thread/timeline/list':
			        if 'cursor' not in msg['params']:
			            result = {'activeRealtimeSessionAtPageStart': 'session', 'data': [
			                {'type': 'realtime', 'item': {
			                    'type': 'transcriptSegment', 'id': 'speech',
			                    'role': 'assistant', 'text': 'Spoken reply.'
			                }},
			                {'type': 'item', 'turnId': 'voice-first'},
			                {'type': 'turnStarted', 'turnId': 'voice-second'},
			                {'type': 'realtime', 'item': {'type': 'realtimeSessionClosed'}},
			                {'type': 'turnStarted', 'turnId': 'after'}
			            ], 'nextCursor': 'older'}
			        else:
			            assert msg['params']['cursor'] == 'older'
			            result = {'activeRealtimeSessionAtPageStart': None, 'data': [
			                {'type': 'turnStarted', 'turnId': 'before'},
			                {'type': 'realtime', 'item': {'type': 'realtimeSessionStarted'}},
			                {'type': 'turnStarted', 'turnId': 'voice-first'}
			            ]}
			    elif method != 'initialize':
			        raise ValueError(method)
			    print(json.dumps({'id': msg['id'], 'result': result}), flush=True)
			"""#
		)
		let server = AppServer(
			executableOverride: executable,
			requestTimeout: .seconds(5)
		)
		defer
		{
			server.disconnect()
		}
		try await server.connect()
		let recent = try await server.loadVoiceTimeline(
			threadID: "voice-owner",
			covering: .throughTurn("voice-second")
		)
		#expect(recent.history.voiceTurnIDs == ["voice-first", "voice-second"])
		#expect(recent.history.segments.isEmpty)
		#expect(!recent.covers(.throughTurn("voice-first")))
		let extended = try await server.loadVoiceTimeline(
			threadID: "voice-owner",
			covering: .throughTurn("voice-first"),
			extending: recent
		)
		let history = extended.history
		#expect(history.voiceTurnIDs == ["voice-first", "voice-second"])
		#expect(history.segments.map(\.precedingTurnID) == ["voice-first"])
		#expect(history.orderedTurnIDs == ["before", "voice-first", "voice-second", "after"])
		let laterReply = ConversationEntry(
			id: "after:reply",
			kind: .agent,
			title: "",
			body: "Later."
		)
		let earlierPrompt = ConversationEntry(
			id: "voice-first:prompt",
			kind: .user,
			title: "",
			body: "Earlier."
		)
		let visible = VoiceChatTranscript.present(
			[earlierPrompt, laterReply],
			segments: history.segments,
			historicalTurnOrder: history.orderedTurnIDs
		)
		#expect(visible.map(\.body) == ["Earlier.", "Spoken reply.", "Later."])
	}

	@Test func timelineRepeatsATimedOutReadAtTheSameCursor() async throws
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
			import json, sys
			if '--version' in sys.argv:
			    print('codex-cli 0.169.0')
			    sys.exit(0)
			older_reads = 0
			for line in sys.stdin:
			    msg = json.loads(line)
			    method = msg.get('method')
			    if method == 'initialized': continue
			    result = {}
			    if method == 'thread/timeline/list':
			        cursor = msg['params'].get('cursor')
			        if cursor is None:
			            result = {'data': [], 'nextCursor': 'older'}
			        else:
			            assert cursor == 'older'
			            older_reads += 1
			            if older_reads == 1:
			                continue
			            assert older_reads == 2
			            result = {'data': [
			                {'type': 'realtime', 'item': {
			                    'type': 'transcriptSegment', 'id': 'speech',
			                    'role': 'user', 'text': 'Voice without a coding turn.'
			                }}
			            ]}
			    elif method != 'initialize':
			        raise ValueError(method)
			    print(json.dumps({'id': msg['id'], 'result': result}), flush=True)
			"""#
		)
		let server = AppServer(
			executableOverride: executable,
			requestTimeout: .seconds(1)
		)
		defer
		{
			server.disconnect()
		}
		try await server.connect()
		let window = try await server.loadVoiceTimeline(
			threadID: "voice-owner",
			covering: .entireThread
		)
		#expect(window.history.segments.map(\.text) == ["Voice without a coding turn."])
		#expect(window.history.segments.first?.precedingTurnID == nil)
	}

	@Test func interleavedEventsReachOnlyTheOwningVoiceThread()
	{
		let server = AppServer()
		let threadID = "voice-owner"
		let itemID = "voice-item"
		var transcript: VoiceChatSegment?
		var played: Data?
		var closed = false
		server.voiceChatObservers[threadID] =
		{
			event in
			switch event
			{
			case .segment(let segment): transcript = segment
			case .transcriptDelta(
				let id,
				let text
			):
				#expect(id == transcript?.id)
				transcript?.text += text
			case .audio(let chunk):
				#expect(chunk.sampleRate == 24_000 && chunk.channelCount == 1)
				played = chunk.pcmData
			case .closed: closed = true
			default: Issue.record("Unexpected voice session event")
			}
		}

		func emit(
			_ method: String,
			thread: String = threadID,
			_ params: [String: Any] = [:]
		)
		{
			var params = params
			params["threadId"] = thread
			server.receiveNotification(
				method: "thread/realtime/" + method,
				parameters: params
			)
		}

		let partialItem = ["type": "transcriptSegment", "id": itemID, "role": "user", "text": ""]
		emit(
			"item/started",
			["item": partialItem]
		)
		emit(
			"item/transcript/delta",
			["itemId": itemID, "delta": "Hel"]
		)
		emit(
			"item/transcript/delta",
			thread: "different",
			["itemId": itemID, "delta": "wrong"]
		)
		emit(
			"closed",
			thread: "different"
		)
		#expect(transcript?.text == "Hel" && transcript?.isUser == true)
		#expect(!closed)
		emit(
			"item/completed",
			["item": partialItem.merging(["text": "Hello!"])
			{
				_, new in new
			}]
		)
		#expect(transcript?.text == "Hello!")

		let pcm = Data([0, 0, 255, 127])
		emit(
			"outputAudio/delta",
			[
				"audio": [
					"data": pcm.base64EncodedString(),
					"sampleRate": 24_000,
					"numChannels": 1,
					"samplesPerChannel": 2,
				],
			]
		)
		#expect(played == pcm)
		emit("closed")
		#expect(closed)
	}
}
