import Foundation
import Testing

@testable import CodexGUI

@Suite @MainActor
struct SubagentConversationRuntimeTests
{
	@Test func backCancelsLoadingAndIgnoresLateBackendReply() async throws
	{
		let service = MockCodexService()
		service.suspendNextRead = true
		let runtime = SubagentConversationRuntime(
			service: service,
			projectPath: nil
		)
		runtime.select(agent(service.thread.id))
		#expect(await waitUntil
		{
			service.pendingRead != nil
		})
		runtime.back()
		service.pendingRead?.resume(returning: try detail(
			service,
			text: "stale"
		))
		service.pendingRead = nil
		await Task.yield()
		#expect(runtime.state.agent == nil)
		#expect(runtime.state.entries.isEmpty)
		#expect(!runtime.state.isLoading)
		runtime.invalidate()
		runtime.select(agent(service.thread.id))
		#expect(runtime.state.agent == nil)
		#expect(service.readThreadCount == 1)
	}

	@Test func liveEventsCoalesceAndEventuallyPublishTheLatestSerialRead() async throws
	{
		let service = MockCodexService()
		service.suspendNextRead = true
		service.savedTurns = [try turn(text: "new content")]
		let runtime = SubagentConversationRuntime(
			service: service,
			projectPath: nil
		)
		var displayedBodies: [String] = []
		runtime.onChange =
		{
			state in
			displayedBodies.append(contentsOf: state.entries.map(\.body))
		}
		runtime.select(agent(service.thread.id))
		#expect(await waitUntil
		{
			service.pendingRead != nil
		})
		for _ in 0 ..< 10
		{
			runtime.receive(.agentMessageDelta(
				threadId: service.thread.id,
				turnId: "turn",
				itemId: "message",
				text: "delta"
			))
		}
		service.pendingRead?.resume(returning: try detail(
			service,
			text: "old content"
		))
		service.pendingRead = nil
		#expect(await waitUntil
		{
			!runtime.state.isLoading && runtime.state.entries.first?.body == "new content"
		})
		#expect(displayedBodies.contains("old content"))
		#expect(displayedBodies.last == "new content")
		#expect(service.readThreadCount == 2)
		runtime.receive(.agentMessageDelta(
			threadId: "unrelated-parent",
			turnId: "turn",
			itemId: "message",
			text: "parent output"
		))
		try await Task.sleep(for: .milliseconds(150))
		#expect(service.readThreadCount == 2)
		runtime.invalidate()
	}

	@Test func eventsDuringEveryFetchStillPublishIntermediateContent() async throws
	{
		let service = MockCodexService()
		service.suspendNextRead = true
		service.savedTurns = [try turn(text: "final content")]
		let runtime = SubagentConversationRuntime(
			service: service,
			projectPath: nil
		)
		runtime.select(agent(service.thread.id))
		for index in 0 ..< 3
		{
			#expect(await waitUntil
			{
				service.pendingRead != nil
			})
			runtime.receive(.agentMessageDelta(
				threadId: service.thread.id,
				turnId: "turn",
				itemId: "message",
				text: "delta"
			))
			service.suspendNextRead = index < 2
			service.pendingRead?.resume(returning: try detail(
				service,
				text: "content \(index)"
			))
			service.pendingRead = nil
			#expect(await waitUntil
			{
				runtime.state.entries.first?.body == "content \(index)"
			})
		}
		#expect(await waitUntil
		{
			runtime.state.entries.first?.body == "final content" && !runtime.state.isLoading
		})
		#expect(service.readThreadCount == 4)
		runtime.invalidate()
	}

	@Test func retryLoadsAfterLocalFailureAndPaginationKeepsCurrentContent() async throws
	{
		let service = MockCodexService()
		service.readThreadError = AppServerError.protocolError("Offline")
		let runtime = SubagentConversationRuntime(
			service: service,
			projectPath: nil
		)
		runtime.select(agent(service.thread.id))
		#expect(await waitUntil
		{
			!runtime.state.isLoading
		})
		#expect(runtime.state.error != nil)
		service.readThreadError = nil
		service.savedTurns = [try turn(text: "current")]
		service.readNextCursor = "older"
		let earlierTurn = try #require(CodexTurn(json: [
			"id": "earlier-turn",
			"status": "completed",
			"items": [["id": "message", "type": "agentMessage", "text": "earlier"]],
		]))
		service.earlierPages["older"] = ([earlierTurn], nil)
		runtime.retry()
		#expect(await waitUntil
		{
			!runtime.state.isLoading && runtime.state.error == nil
		})
		#expect(runtime.state.entries.map(\.body) == ["current"])
		runtime.loadEarlierTurns()
		#expect(await waitUntil
		{
			!runtime.state.isLoading && runtime.state.entries.count == 2
		})
		#expect(runtime.state.entries.map(\.body) == ["earlier", "current"])
		#expect(service.earlierReadCursors == ["older"])
		#expect(runtime.state.nextCursor == nil)
		runtime.invalidate()
	}

	@Test func wrongThreadAndCheckoutRepliesFailLocally() async throws
	{
		let service = MockCodexService()
		let runtime = SubagentConversationRuntime(
			service: service,
			projectPath: nil
		)
		runtime.select(agent("unrecognized-child"))
		#expect(await waitUntil
		{
			!runtime.state.isLoading
		})
		#expect(runtime.state.error != nil)
		#expect(runtime.state.entries.isEmpty)
		#expect(runtime.state.selectedThreadID == "unrecognized-child")
		runtime.invalidate()
		let scopedRuntime = SubagentConversationRuntime(
			service: service,
			projectPath: "/fixture/different-checkout"
		)
		scopedRuntime.select(agent(service.thread.id))
		#expect(await waitUntil
		{
			!scopedRuntime.state.isLoading
		})
		#expect(scopedRuntime.state.error != nil)
		#expect(scopedRuntime.state.entries.isEmpty)
		scopedRuntime.invalidate()
	}

	private func agent(_ threadID: String) -> CodexSubagentActivity
	{
		CodexSubagentActivity(json: ["agentThreadId": threadID, "agentPath": "/root/child"])
	}

	private func detail(
		_ service: MockCodexService,
		text: String
	) throws -> ThreadDetail
	{
		ThreadDetail(
			summary: service.thread,
			turns: [try turn(text: text)],
			nextTurnsCursor: nil
		)
	}

	private func turn(text: String) throws -> CodexTurn
	{
		try #require(CodexTurn(json: [
			"id": "turn",
			"status": "completed",
			"items": [["id": "message", "type": "agentMessage", "text": text]],
		]))
	}

	private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async -> Bool
	{
		for _ in 0 ..< 200
		{
			if condition()
			{
				return true
			}
			try? await Task.sleep(for: .milliseconds(5))
		}
		return condition()
	}
}
