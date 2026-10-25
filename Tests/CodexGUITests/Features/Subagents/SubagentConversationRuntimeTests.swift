import Foundation
import Testing

@testable import CodexGUI

@Suite @MainActor
struct SubagentConversationRuntimeTests
{
	@Test(.timeLimit(.minutes(1)))
	func backCancelsLoadingAndIgnoresLateBackendReply() async throws
	{
		let service = MockCodexService()
		let lateReply = try detail(
			service,
			text: "stale"
		)
		let read = SuspendedSubagentReadFixture(
			service: service,
			reply: lateReply
		)
		let runtime = SubagentConversationRuntime(
			service: service,
			projectPath: nil
		)
		var publishedBodies: [String] = []
		runtime.onChange =
		{
			publishedBodies.append(contentsOf: $0.entries.map(\.body))
		}
		runtime.select(agent(service.thread.id))
		let pending = runtime.operationTasks()
		do
		{
			try #require(pending.count == 1)
			try #require(await service.awaitReadiness
			{
				service.pendingRead != nil
			})
			runtime.back()
			let allCancelled = pending.allSatisfy(\.isCancelled)
			#expect(allCancelled)
			#expect(runtime.operationTasks().isEmpty)
			await read.releaseAndJoin(pending)
			#expect(runtime.state.agent == nil)
			#expect(runtime.state.entries.isEmpty)
			#expect(!runtime.state.isLoading)
			#expect(publishedBodies.isEmpty)
			runtime.invalidate()
			runtime.select(agent(service.thread.id))
			#expect(runtime.state.agent == nil)
			#expect(service.readThreadCount == 1)
		}
		catch
		{
			runtime.invalidate()
			await read.releaseAndJoin(pending)
			throw error
		}
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

@MainActor
private final class SuspendedSubagentReadFixture
{
	private let service: MockCodexService
	private let reply: ThreadDetail
	private var releaseRequested = false
	private var observation: UUID?

	init(
		service: MockCodexService,
		reply: ThreadDetail
	)
	{
		self.service = service
		self.reply = reply
		service.suspendNextRead = true
		observation = service.observeReadiness
		{
			[weak self] in self?.releasePendingRead()
		}
	}

	func releaseAndJoin(_ tasks: [Task<Void, Never>]) async
	{
		releaseRequested = true
		releasePendingRead()
		for task in tasks
		{
			await task.value
		}
		if let observation
		{
			service.removeReadinessObserver(observation)
			self.observation = nil
		}
	}

	private func releasePendingRead()
	{
		guard releaseRequested, let pending = service.pendingRead
		else
		{
			return
		}
		// Cancellation can precede the service call; keep the observation until it returns.
		service.pendingRead = nil
		pending.resume(returning: reply)
	}
}
