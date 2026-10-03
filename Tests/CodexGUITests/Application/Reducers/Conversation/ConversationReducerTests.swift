import Foundation
import Testing

@testable import CodexGUI

@MainActor
struct ConversationReducerTests
{
	private func fixture() -> WorkspaceModel
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/conversation"
		))
		model.connection.isConnected = true
		model.connection.generation = 1
		model.execution.state = .ready
		model.conversations.selectedConversation = .thread("thread")
		return model
	}

	private func context(
		_ model: WorkspaceModel,
		threadID: String? = "thread"
	) -> OperationContext
	{
		OperationContext(
			workspace: model.identity,
			generation: model.connection.generation,
			requestID: UUID(),
			threadID: threadID
		)
	}

	private func detail(_ turnID: String = "current") -> ThreadDetail
	{
		ThreadDetail(
			summary: ThreadSummary(json: ["id": "thread", "cwd": "/tmp/conversation"])!,
			turns: [turn(turnID)],
			nextTurnsCursor: "older"
		)
	}

	private func turn(_ id: String) -> CodexTurn
	{
		CodexTurn(
			id: id,
			status: "completed",
			items: [CodexItem(json: [
				"id": "answer-\(id)",
				"type": "agentMessage",
				"text": id,
			])!],
			error: nil
		)
	}

	@discardableResult
	private func reduce(
		_ model: inout WorkspaceModel,
		_ action: WorkspaceAction
	) -> WorkspaceReduction
	{
		let result = WorkspaceFeatureComposition.reduce(
			&model,
			action
		)
		for change in result.domainEvents
		{
			_ = ConversationReviewComposition.reduceDomainEvent(
				&model,
				change
			)
		}
		return result
	}

	@Test func directConversationReducerKeepsListRequestsFeatureLocal()
	{
		var model = fixture()
		let operation = ConversationListOperation(
			context: context(model),
			archived: false,
			boundThreadID: nil
		)
		let result = ConversationReducer.reduce(
			&model,
			.conversations(.threadListRequested(operation))
		)
		#expect(model.conversations.pendingList?.context == operation.context)
		#expect(result.effects.contains
		{
			if case .readConversationList = $0
			{
				return true
			}
			return false
		})
	}

	@Test func sidebarManagementTargetsUnselectedTaskAndPreservesViewedConversation()
	{
		for permanentlyDelete in [false, true]
		{
			var model = fixture()
			model.conversations.threads = [ThreadSummary(json: [
				"id": "other",
				"cwd": "/tmp/conversation"
			])!]
			model.conversations
				.content[.thread("other")] = ConversationContentModel(hasLoadedHistory: true)
			let captured = context(
				model,
				threadID: "other"
			)
			let operation: ThreadManagementOperation = permanentlyDelete ? .delete(captured) :
				.archive(captured)
			let started = reduce(
				&model,
				.conversations(.managementRequested(operation))
			)
			#expect(started.effects.count == 1)
			#expect(model.conversations.pendingManagement?.context == captured)
			let finished = reduce(
				&model,
				.conversations(.managementFinished(
					captured,
					.succeeded(())
				))
			)
			#expect(model.conversations.selectedConversation == .thread("thread"))
			#expect(model.conversations.pendingManagement == nil)
			#expect(!finished.effects.isEmpty)
			if permanentlyDelete
			{
				#expect(model.conversations.content[.thread("other")] == nil)
				#expect(model.conversations.threads.isEmpty)
			}
		}
	}

	@Test func deleteRejectsUnknownTaskAndRetainsHistoryOnBackendFailure()
	{
		var model = fixture()
		let unknown = context(
			model,
			threadID: "unknown"
		)
		#expect(reduce(
			&model,
			.conversations(.managementRequested(.delete(unknown)))
		).effects.isEmpty)
		let captured = context(model)
		model.conversations
			.content[.thread("thread")] = ConversationContentModel(hasLoadedHistory: true)
		_ = reduce(
			&model,
			.conversations(.managementRequested(.delete(captured)))
		)
		_ = reduce(
			&model,
			.conversations(.managementFinished(
				captured,
				.failed(OperationFailure(
					message: "Rejected",
					outcomeIsUncertain: false
				))
			))
		)
		#expect(model.conversations.selectedConversation == .thread("thread"))
		#expect(model.conversations.content[.thread("thread")]?.hasLoadedHistory == true)
		#expect(model.conversations.error?.contains("Rejected") == true)
	}

	@Test func rejectedConnectionAndProjectIntentsCannotDiscardCurrentConversationWork()
	{
		var model = fixture()
		model.execution.state = .running
		let read = ConversationReadOperation(
			context: context(model),
			commandRevision: 0,
			purpose: .selection
		)
		model.conversations.pendingReads[read.key] = read
		model.conversations.content[.thread("thread")] = ConversationContentModel(
			loadedTurns: [turn("retained")],
			hasLoadedHistory: true
		)
		let actions: [WorkspaceAction] = [
			.connection(.connectRequested(context(
				model,
				threadID: nil
			))),
			.connection(.disconnected(
				workspace: model.identity,
				generation: 0,
				message: "obsolete"
			)),
			.connection(.projectOpened(
				model.identity,
				selectedThreadID: "other"
			)),
		]
		for action in actions
		{
			_ = ConnectionReducer.reduce(
				&model,
				action
			)
			_ = reduce(
				&model,
				action
			)
			#expect(model.conversations.pendingReads[read.key]?.context == read.context)
			#expect(model.conversations.content[.thread("thread")]?.loadedTurns
				.map(\.id) == ["retained"])
		}
	}

	@Test func obsoleteListSuccessAndFailureLeaveNewerListRequestUntouched()
	{
		var model = fixture()
		let old = ConversationListOperation(
			context: context(
				model,
				threadID: nil
			),
			archived: false
		)
		let current = ConversationListOperation(
			context: context(
				model,
				threadID: nil
			),
			archived: true
		)
		model.conversations.pendingList = current
		model.conversations.showingArchived = true
		let retained = detail().summary
		model.conversations.threads = [retained]
		let results: [OperationResult<[ThreadSummary]>] = [
			.succeeded([]),
			.failed(OperationFailure(
				message: "obsolete",
				outcomeIsUncertain: false
			)),
		]
		for result in results
		{
			_ = reduce(
				&model,
				.conversations(.threadListReceived(
					old,
					result
				))
			)
			#expect(model.conversations.pendingList?.context == current.context)
			#expect(model.conversations.threads == [retained])
			#expect(model.conversations.error == nil)
		}
	}

	@Test func obsoleteReadScopesAndFailuresCannotReplaceNewerSelection()
	{
		var model = fixture()
		let current = ConversationReadOperation(
			context: context(model),
			commandRevision: 2,
			purpose: .selection
		)
		let key = ConversationReadKey(
			purpose: .selection,
			threadID: "thread"
		)
		model.conversations.pendingReads[key] = current
		model.conversations.pendingSelection = current.context
		model.execution.commandEventRevisions["thread"] = 2
		let scopes = [
			current.context,
			context(model),
			OperationContext(
				workspace: model.identity,
				generation: 0,
				requestID: current.context.requestID,
				threadID: "thread"
			),
			OperationContext(
				workspace: WorkspaceIdentity(
					sessionID: UUID(),
					canonicalCheckoutPath: "/tmp/conversation"
				),
				generation: 1,
				requestID: current.context.requestID,
				threadID: "thread"
			),
			OperationContext(
				workspace: WorkspaceIdentity(
					sessionID: model.identity.sessionID,
					canonicalCheckoutPath: "/tmp/other"
				),
				generation: 1,
				requestID: current.context.requestID,
				threadID: "thread"
			),
		]
		for scope in scopes
		{
			let stale = ConversationReadOperation(
				context: scope,
				commandRevision: 1,
				purpose: .selection
			)
			for result in [OperationResult<ThreadDetail>.succeeded(detail("obsolete")),
							.failed(OperationFailure(
							message: "obsolete",
							outcomeIsUncertain: false
							))]
			{
				_ = reduce(
					&model,
					.conversations(.historyReceived(
						stale,
						result
					))
				)
				#expect(model.conversations.pendingReads[key]?.context == current.context)
				#expect(model.conversations.pendingSelection == current.context)
				#expect(model.conversations.content[.thread("thread")] == nil)
				#expect(model.conversations.error == nil)
			}
		}
	}

	@Test func obsoletePageSuccessAndFailureCannotRetireNewerSharedPage()
	{
		var model = fixture()
		let scope = HistoryPageScope(
			projectPath: "/tmp/conversation",
			generation: 1,
			cursor: "older"
		)
		let old = HistoryLoadOperation(
			context: context(model),
			pageScope: scope,
			commandRevision: 0
		)
		let current = HistoryLoadOperation(
			context: context(model),
			pageScope: scope,
			commandRevision: 1
		)
		model.conversations.historyLoads["thread"] = current
		model.execution.commandEventRevisions["thread"] = 1
		model.conversations.content[.thread("thread")] = ConversationContentModel(
			loadedTurns: [turn("latest")],
			hasLoadedHistory: true,
			nextTurnsCursor: "older"
		)
		let wrongGeneration = HistoryLoadOperation(
			context: OperationContext(
				workspace: model.identity,
				generation: 0,
				requestID: current.context.requestID,
				threadID: "thread"
			),
			pageScope: HistoryPageScope(
				projectPath: "/tmp/conversation",
				generation: 0,
				cursor: "older"
			),
			commandRevision: 1
		)
		let wrongCheckout = HistoryLoadOperation(
			context: OperationContext(
				workspace: WorkspaceIdentity(
					sessionID: model.identity.sessionID,
					canonicalCheckoutPath: "/tmp/other"
				),
				generation: 1,
				requestID: current.context.requestID,
				threadID: "thread"
			),
			pageScope: scope,
			commandRevision: 1
		)
		let wrongCursor = HistoryLoadOperation(
			context: current.context,
			pageScope: HistoryPageScope(
				projectPath: "/tmp/conversation",
				generation: 1,
				cursor: "obsolete"
			),
			commandRevision: 1
		)
		for operation in [old, wrongGeneration, wrongCheckout, wrongCursor]
		{
			for result in [OperationResult<HistoryPage>.succeeded(HistoryPage(
				turns: [turn("obsolete")],
				nextCursor: nil
			)), .failed(
				OperationFailure(
					message: "obsolete",
					outcomeIsUncertain: false
				)
			)]
			{
				_ = reduce(
					&model,
					.conversations(.earlierTurnsReceived(
						operation,
						result
					))
				)
				#expect(model.conversations.historyLoads["thread"]?.context == current.context)
				#expect(model.conversations.content[.thread("thread")]?.loadedTurns
					.map(\.id) == ["latest"])
				#expect(model.conversations.content[.thread("thread")]?.nextTurnsCursor == "older")
				#expect(model.conversations.error == nil)
			}
		}
	}

	@Test func overlappingPageTurnsMergeOnceAndPreserveExistingReviewSelection()
	{
		var model = fixture()
		let latest = turn("latest")
		let earlier = turn("earlier")
		let history = ConversationReadOperation(
			context: context(model),
			commandRevision: 0,
			purpose: .selection
		)
		model.conversations.pendingReads[ConversationReadKey(
			purpose: .selection,
			threadID: "thread"
		)] = history
		model.conversations.pendingSelection = history.context
		_ = reduce(
			&model,
			.conversations(.historyReceived(
				history,
				.succeeded(ThreadDetail(
					summary: detail().summary,
					turns: [latest],
					nextTurnsCursor: "older"
				))
			))
		)
		model.review.conversations[.thread("thread")]?.selectedTurnID = "latest"
		let page = HistoryLoadOperation(
			context: context(model),
			pageScope: HistoryPageScope(
				projectPath: "/tmp/conversation",
				generation: 1,
				cursor: "older"
			),
			commandRevision: 0
		)
		model.conversations.historyLoads["thread"] = page
		_ = reduce(
			&model,
			.conversations(.earlierTurnsReceived(
				page,
				.succeeded(HistoryPage(
					turns: [earlier,
							earlier,
							latest],
					nextCursor: nil
				))
			))
		)
		#expect(model.conversations.content[.thread("thread")]?.loadedTurns.map(\.id) == [
			"earlier",
			"latest"
		])
		#expect(model.review.conversations[.thread("thread")]?.turns.map(\.turnID) == [
			"earlier",
			"latest"
		])
		#expect(model.review.conversations[.thread("thread")]?.selectedTurnID == "latest")
		#expect(model.review.conversations[.thread("thread")]?.turns.allSatisfy
		{
			$0.threadID == "thread"
		} == true)
		#expect(model.conversations.historyLoads["thread"] == nil)
	}
}
