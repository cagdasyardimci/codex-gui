import Foundation
import Testing

@testable import CodexGUI

@Suite @MainActor
struct MessageSearchRuntimeTests
{
	@Test func backgroundSearchPublishesMatchingContentsAndScope() async throws
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/message-search"
		))
		model.conversations.threads = [try #require(ThreadSummary(json: [
			"id": "thread",
			"cwd": "/tmp/message-search"
		]))]
		let items = try [
			["id": "text", "type": "agentMessage", "text": "Café decision"],
			["id": "command", "type": "commandExecution", "command": "echo cafe"],
			["id": "output", "type": "commandExecution", "aggregatedOutput": "CAFÉ output"],
			[
				"id": "file",
				"type": "fileChange",
				"changes": [["path": "cafe.swift", "kind": "update"]]
			],
		].map
		{
			try #require(CodexItem(json: $0))
		}
		model.conversations.content[.thread("thread")] = ConversationContentModel(
			loadedTurns: [CodexTurn(
				id: "turn",
				status: "completed",
				items: items,
				error: nil
			)],
			hasLoadedHistory: true,
			nextTurnsCursor: "earlier"
		)
		let store = WorkspaceStateStore(
			model: model,
			service: MockCodexService(),
			persistence: WorkspacePersistenceScheduler
			{
				_ in
			},
			reducers: [ContextNavigationReducer.reducer]
		)
		defer
		{
			store.shutdown()
		}
		let context = store.operationContext()
		store.dispatch(.contextNavigation(.searchRequested(
			context,
			query: " cafe "
		)))
		let operation = try #require(store.operation(for: context))
		#expect(store.model.contextNavigation.pendingMessageSearch != nil)
		#expect(await operation.wait() == .finished)
		let results = try #require(store.model.contextNavigation.messageSearch)
		#expect(results.query == "cafe")
		#expect(results.hits.map(\.itemID) == ["text", "command", "output", "file"])
		#expect(results.scope.loadedThreadCount == 1)
		#expect(results.scope.threadsWithEarlierTurns == 1)
		#expect(store.model.contextNavigation.pendingMessageSearch == nil)
	}

	@Test func cancellingSearchPreservesPersistenceSharingItsRequest() async throws
	{
		let workspace = WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/search-cancel"
		)
		let context = OperationContext(
			workspace: workspace,
			generation: 1,
			requestID: UUID()
		)
		let search = MessageSearchOperation(
			context: context,
			query: "needle",
			historyRevision: 1
		)
		var written: [String] = []
		var outcomes: [WorkspaceAction] = []
		let scheduler = WorkspacePersistenceScheduler(writeDraft:
			{
				written.append($0.draft.text)
			})
		let runner = WorkspaceEffectRunner(
			service: MockCodexService(),
			persistence: scheduler,
			mapEvent:
			{
				_, _ in []
			},
			deliver:
			{
				action, complete in
				outcomes.append(action)
				complete()
			}
		)
		defer
		{
			runner.shutdown()
		}
		runner.accept(
			[
				.persistDraft(WorkspaceDraftWrite(
					context: context,
					conversation: .newChat,
					draft: ComposerDraft(text: "keep")
				)),
				.searchMessages(
					search,
					threads: [],
					totalThreadCount: 0
				),
			],
			workspace: workspace
		)
		let handle = try #require(runner.handles[WorkspaceEffectRunner.RequestKey(context)])
		#expect(runner.tasks.count == 2)
		runner.accept(
			[.cancelMessageSearch(search)],
			workspace: workspace
		)
		#expect(runner.tasks.count == 1)
		#expect(runner.tasks.values
			.contains
			{
				if case .persistDraft = $0.effect
				{
					return true
				}
				return false
			})
		try await scheduler.drain()
		_ = await handle.wait()
		#expect(written == ["keep"])
		#expect(outcomes.contains
		{
			if case .contextNavigation(.messageSearchFinished(
				search,
				.failed
			)) = $0
			{
				return true
			}
			return false
		})
	}

	@Test func historyRefreshesBoundBookkeepingAndRejectOlderReplay() async throws
	{
		let workspace = WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/search-refresh"
		)
		let context = OperationContext(
			workspace: workspace,
			generation: 1,
			requestID: UUID()
		)
		var delivered = 0
		let runner = WorkspaceEffectRunner(
			service: MockCodexService(),
			persistence: WorkspacePersistenceScheduler(
				writeDraft:
				{
					_ in
				},
				waitForDraftEdits:
				{
				}
			),
			completedRequestLimit: 4,
			mapEvent:
			{
				_, _ in []
			},
			deliver:
			{
				_, complete in
				delivered += 1
				complete()
			}
		)
		defer
		{
			runner.shutdown()
		}
		runner.accept(
			[.persistDraft(WorkspaceDraftWrite(
				context: context,
				conversation: .newChat,
				draft: ComposerDraft(text: "keep")
			))],
			workspace: workspace
		)
		let persistence = try #require(runner.operation(for: context))
		#expect(await persistence.wait() == .finished)
		for revision in 1 ... 64
		{
			let search = MessageSearchOperation(
				context: context,
				query: "needle",
				historyRevision: revision
			)
			runner.accept(
				[.searchMessages(
					search,
					threads: [],
					totalThreadCount: 0
				)],
				workspace: workspace
			)
			let handle = try #require(runner.operation(for: context))
			#expect(await handle.wait() == .finished)
			#expect(runner.accepted.count == 2)
			#expect(runner.retainedOperationCount == 1)
		}
		#expect(delivered == 65)
		for revision in [1, 64]
		{
			let replay = MessageSearchOperation(
				context: context,
				query: "needle",
				historyRevision: revision
			)
			runner.accept(
				[.searchMessages(
					replay,
					threads: [],
					totalThreadCount: 0
				)],
				workspace: workspace
			)
		}
		#expect(runner.runningOperationCount == 0)
		#expect(runner.accepted.count == 2)
		#expect(delivered == 65)
	}

	@Test func supersededSearchStopsAtAnItemBoundary() throws
	{
		let item = try #require(CodexItem(json: [
			"id": "item",
			"type": "agentMessage",
			"text": "needle"
		]))
		let thread = SearchableThread(
			threadID: "thread",
			title: "Thread",
			turns: [CodexTurn(
				id: "turn",
				status: "completed",
				items: Array(
					repeating: item,
					count: 100
				),
				error: nil
			)],
			hasEarlierTurns: false
		)
		var checkedItems = 0
		let results = MessageSearch.search(
			query: "needle",
			threads: [thread],
			totalThreadCount: 1
		)
		#expect(results.hits.count == 100)
		let cancelled = MessageSearch.search(
			query: "needle",
			threads: [thread],
			totalThreadCount: 1,
			isCancelled:
			{
				checkedItems += 1
				return checkedItems > 3
			}
		)
		#expect(checkedItems == 4)
		#expect(cancelled.hits.count == 3)
	}
}
