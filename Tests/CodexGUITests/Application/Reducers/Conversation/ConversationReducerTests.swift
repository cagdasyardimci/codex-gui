import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite
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

	@Test func historyReadsSubscribeForSelectionAndDisplayedRecoveryOnly() throws
	{
		let cases: [(ConversationReadPurpose, String, Bool)] = [
			(.selection, "thread", true),
			(.recovery, "thread", true),
			(.recovery, "background", false),
			(.search, "thread", false),
			(.completion, "thread", false),
		]
		for (purpose, threadID, expected) in cases
		{
			var model = fixture()
			let requested = ConversationReadOperation(
				context: context(
					model,
					threadID: threadID
				),
				commandRevision: 0,
				purpose: purpose
			)
			_ = reduce(
				&model,
				.conversations(.historyRequested(requested))
			)
			let captured = try #require(model.conversations.pendingReads[requested.key])
			#expect(captured.resumesThread == expected)
		}
	}

	@Test(arguments: [false, true])
	func selectingAnActiveChatEnsuresItsSubscription(_ alreadySubscribed: Bool)
	{
		var model = fixture()
		model.execution.activeThreadID = "thread"
		model.execution.state = .running
		if alreadySubscribed
		{
			model.conversations.subscribedThreadIDs.insert("thread")
		}
		_ = reduce(
			&model,
			.conversations(.selectionRequested(context(model)))
		)
		let pending = model.conversations.pendingReads.values.first
		#expect((pending != nil) == !alreadySubscribed)
		#expect(alreadySubscribed || pending?.resumesThread == true)
	}

	@Test(arguments: ["content", "notification", "local-choice"])
	func resumedSettingsRespectIndependentFreshness(_ newer: String) throws
	{
		var model = fixture()
		let requested = ConversationReadOperation(
			context: context(model),
			commandRevision: 0,
			purpose: .recovery
		)
		_ = reduce(
			&model,
			.conversations(.historyRequested(requested))
		)
		let captured = try #require(model.conversations.pendingReads[requested.key])
		var resumed = detail()
		resumed.settings = try #require(ThreadSettings(json: [
			"cwd": "/tmp/conversation",
			"model": "resumed-model",
			"effort": "medium",
		]))
		switch newer
		{
		case "content": model.conversations.contentRevisions["thread", default: 0] += 1
		case "notification":
			let fresh = try #require(ThreadSettings(json: [
				"cwd": "/tmp/conversation",
				"model": "phone-model",
				"effort": "low",
			]))
			var reduction = WorkspaceReduction()
			ComposerCommandReducer.observeThreadState(
				.threadSettingsUpdated(
					threadId: "thread",
					settings: fresh
				),
				model: &model,
				result: &reduction
			)
		default:
			model.preferences.localThreadSelections["thread"] = ComposerSelection(
				modelID: "local-model",
				effort: "high",
				fastMode: false
			)
		}
		_ = reduce(
			&model,
			.conversations(.historyReceived(
				captured,
				.succeeded(resumed)
			))
		)
		#expect(model.conversations.subscribedThreadIDs.contains("thread"))
		let expected = newer == "content" ? "resumed-model"
			: newer == "notification" ? "phone-model" : "local-model"
		#expect(model.composerSelection.modelID == expected)
		if newer == "content"
		{
			#expect(model.conversations.content[.thread("thread")] == nil)
		}
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

	@Test func obsoleteReadScopesAndFailuresCannotReplaceNewerSelection()
	{
		var model = fixture()
		let current = ConversationReadOperation(
			context: context(model),
			commandRevision: 2,
			purpose: .selection,
			contentRevision: 3
		)
		let key = ConversationReadKey(
			purpose: .selection,
			threadID: "thread"
		)
		model.conversations.pendingReads[key] = current
		model.conversations.pendingSelection = current.context
		model.execution.commandEventRevisions["thread"] = 2
		model.conversations.contentRevisions["thread"] = 3
		let scopes = [
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
			OperationContext(
				workspace: model.identity,
				generation: 1,
				requestID: current.context.requestID,
				threadID: "other"
			),
		]
		let staleOperations = [
			ConversationReadOperation(
				context: current.context,
				commandRevision: 1,
				purpose: .selection,
				contentRevision: 3
			),
			ConversationReadOperation(
				context: current.context,
				commandRevision: 2,
				purpose: .selection,
				contentRevision: 2
			),
		] + scopes.map
		{
			scope in
			ConversationReadOperation(
				context: scope,
				commandRevision: 2,
				purpose: .selection,
				contentRevision: 3
			)
		}
		for stale in staleOperations
		{
			for result in [OperationResult<ThreadDetail>.succeeded(detail("obsolete")),
							.failed(OperationFailure(
							message: "obsolete",
							outcomeIsUncertain: false
							))]
			{
				var receivingModel = model
				let rejected = reduce(
					&receivingModel,
					.conversations(.historyReceived(
						stale,
						result
					))
				)
				#expect(receivingModel.conversations.pendingReads[key]?.context == current.context)
				#expect(receivingModel.conversations.pendingReads[key]?.commandRevision == 2)
				#expect(receivingModel.conversations.pendingReads[key]?.contentRevision == 3)
				#expect(receivingModel.conversations.pendingSelection == current.context)
				#expect(receivingModel.conversations.content[.thread("thread")] == nil)
				#expect(receivingModel.conversations.historyErrors["thread"] == nil)
				#expect(receivingModel.conversations.error == nil)
				#expect(rejected.domainEvents.isEmpty)
			}
		}
		_ = reduce(
			&model,
			.conversations(.historyReceived(
				current,
				.succeeded(detail())
			))
		)
		#expect(model.conversations.pendingReads[key] == nil)
		#expect(model.conversations.pendingSelection == nil)
		#expect(model.conversations.content[.thread("thread")]?.loadedTurns
			.map(\.id) == ["current"])
		#expect(model.conversations.lastAppliedHistoryRequestID == current.context.requestID)
	}

	@Test(arguments: ["command", "content"])
	func historyCapturedBeforeANewerRevisionCannotReplaceCurrentContent(_ revision: String)
	{
		var seed = fixture()
		let operation = ConversationReadOperation(
			context: context(seed),
			commandRevision: 2,
			purpose: .selection,
			contentRevision: 3
		)
		seed.conversations.pendingReads[operation.key] = operation
		seed.conversations.pendingSelection = operation.context
		seed.execution.commandEventRevisions["thread"] = revision == "command" ? 3 : 2
		seed.conversations.contentRevisions["thread"] = revision == "content" ? 4 : 3
		seed.conversations.content[.thread("thread")] = ConversationContentModel(
			loadedTurns: [turn("retained")],
			hasLoadedHistory: true
		)
		for observation in [OperationResult<ThreadDetail>.succeeded(detail("obsolete")),
							.failed(OperationFailure(
								message: "obsolete",
								outcomeIsUncertain: false
							))]
		{
			var model = seed
			let result = reduce(
				&model,
				.conversations(.historyReceived(
					operation,
					observation
				))
			)
			#expect(model.conversations.pendingReads[operation.key] == nil)
			#expect(model.conversations.pendingSelection == nil)
			#expect(model.conversations.content[.thread("thread")]?.loadedTurns.map(\.id) == [
				"retained"
			])
			#expect(model.conversations.historyErrors["thread"] == nil)
			#expect(model.conversations.lastAppliedHistoryRequestID == nil)
			#expect(result.domainEvents.count == 1)
			#expect(result.domainEvents.contains
			{
				if case .conversationHistoryFinished(
					.history(let finished),
					.succeeded(false)
				) = $0
				{
					return finished.context == operation.context
				}
				return false
			})
		}
	}

}
