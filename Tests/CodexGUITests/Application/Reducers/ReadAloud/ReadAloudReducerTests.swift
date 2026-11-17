import Foundation
import Testing

@testable import CodexGUI

@MainActor
struct ReadAloudReducerTests
{
	@Test func admissionRequiresAnExistingTerminalAgentItemAndConnectedOwner() throws
	{
		var model = try fixture()
		for id in ["turn:missing", "missing:answer", "turn:", "turn:user"]
		{
			let reduction = ReadAloudReducer.reduce(
				&model,
				.readAloud(.requested(request(
					model,
					entryID: id
				)))
			)
			#expect(reduction.effects.isEmpty && model.readAloud.active == nil)
		}
		let request = request(model)
		let reduction = ReadAloudReducer.reduce(
			&model,
			.readAloud(.requested(request))
		)
		#expect(model.readAloud.active == request)
		#expect(model.readAloud.phase == .starting && reduction.effects.count == 1)
		model.connection.isConnected = false
		let disconnected = ReadAloudReducer.reduce(
			&model,
			.connection(.disconnected(
				workspace: model.identity,
				generation: model.connection.generation,
				message: "Disconnected"
			))
		)
		#expect(model.readAloud.active == nil && model.readAloud.phase == .idle)
		#expect(disconnected.effects
			.contains
			{
				if case .cancel(let context) = $0
				{
					return context == request.context
				}; return false
			})
		_ = ReadAloudReducer.reduce(
			&model,
			.readAloud(.speaking(request))
		)
		#expect(model.readAloud.phase == .idle)
	}

	@Test func stoppedAndReplacedOwnersRejectLateSpeechPublications() throws
	{
		var model = try fixture()
		let first = request(model)
		_ = ReadAloudReducer.reduce(
			&model,
			.readAloud(.requested(first))
		)
		_ = ReadAloudReducer.reduce(
			&model,
			.readAloud(.stopRequested)
		)
		let next = request(model)
		_ = ReadAloudReducer.reduce(
			&model,
			.readAloud(.requested(next))
		)
		_ = ReadAloudReducer.reduce(
			&model,
			.readAloud(.finished(
				first,
				nil
			))
		)
		#expect(model.readAloud.active == next)
		model.conversations.selectedConversation = .thread("other")
		let result = ReadAloudReducer.reduce(
			&model,
			.readAloud(.speaking(next))
		)
		#expect(model.readAloud.active == nil && !result.effects.isEmpty)
	}

	@Test func segmentationPreservesLongUnicodeAndPrefersWordBoundaries() throws
	{
		let text = String(
			repeating: "A spoken sentence with café and 🧩.\n",
			count: 120
		)
		let parts = try ReadAloudTextSegments.make(text)
		#expect(parts.count > 1 && parts.joined() == text)
		#expect(parts.allSatisfy
		{
			!$0.isEmpty && $0.utf8.count <= 400
		})
		#expect(parts.dropLast().allSatisfy
		{
			$0.last?.isWhitespace == true
		})
		let giant = String(
			repeating: "語",
			count: 1000
		)
		let split = try ReadAloudTextSegments.make(giant)
		#expect(split.joined() == giant && split.allSatisfy
		{
			$0.utf8.count <= 400
		})
		#expect(throws: ReadAloudError.self)
		{
			try ReadAloudTextSegments.make(" \n\t")
		}
		#expect(throws: ReadAloudError.self)
		{
			try ReadAloudTextSegments.make(String(
				repeating: "x",
				count: 256 * 1024 + 1
			))
		}
	}

	@Test func composedSelectionAndLifecycleTransitionsRetirePlaybackBeforePublication() throws
	{
		for transition in ["selection", "quit", "cleanup", "shutdown"]
		{
			var model = try fixture()
			let active = request(model)
			_ = ReadAloudReducer.reduce(
				&model,
				.readAloud(.requested(active))
			)
			let action: WorkspaceAction
			switch transition
			{
			case "selection":
				action = .conversations(.selectionRequested(OperationContext(
					workspace: model.identity,
					generation: model.connection.generation,
					requestID: UUID(),
					threadID: "other"
				)))
			case "quit":
				action = .workspaceLifecycle(.quitFrozen(
					WorkspaceQuitRequest(requestID: UUID()),
					WorkspaceLifecycleReducer.reference(model)
				))
			case "cleanup":
				let managed = TaskWorkspace(
					id: UUID(),
					taskID: "read-aloud",
					threadID: "chat",
					sourceProjectPath: "/source",
					repositoryGitDirectory: "/source/.git",
					branch: "codex/read-aloud",
					checkoutPath: "/tmp/read-aloud",
					baseCommit: "base",
					sourceWasDirty: false,
					createdAt: .distantPast,
					phase: .active
				)
				model.lifecycle.owner = .managed(
					workspaceID: managed.id,
					sessionID: model.identity.sessionID
				)
				model.lifecycle.managedWorkspace = managed
				action = .workspaceLifecycle(.cleanupReserved(WorkspaceCleanupRequest(
					requestID: UUID(),
					owner: WorkspaceLifecycleReducer.reference(model),
					expected: managed
				)))
			default: action = .workspaceLifecycle(.shutdownRequested)
			}
			var result = WorkspaceReduction()
			for reducer in WorkspaceStoreFactory.reducers
			{
				result.merge(reducer.reduce(
					&model,
					action
				))
			}
			#expect(model.readAloud.active == nil && model.readAloud.phase == .idle)
			#expect(result.effects
				.contains
				{
					if case .cancel(let context) = $0
					{
						return context == active.context
					}; return false
				})
		}
		var nested = try fixture()
		let active = request(nested)
		_ = ReadAloudReducer.reduce(
			&nested,
			.readAloud(.requested(active))
		)
		let context = OperationContext(
			workspace: nested.identity,
			generation: nested.connection.generation,
			requestID: UUID(),
			threadID: "other"
		)
		let result = WorkspaceLifecycleComposition.reduceConnectionTransition(
			&nested,
			.conversations(.selectionRequested(context))
		)
		#expect(nested.readAloud.active == nil && nested.conversations
			.selectedConversation == .thread("other"))
		#expect(result.effects
			.contains
			{
				if case .cancel(let context) = $0
				{
					return context == active.context
				}; return false
			})
	}

	private func fixture() throws -> WorkspaceModel
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/read-aloud"
		))
		model.connection.isConnected = true
		model.readAloud.available = true
		model.conversations.selectedConversation = .thread("chat")
		let answer = try #require(CodexItem(json: [
			"id": "answer",
			"type": "agentMessage",
			"text": "Answer"
		]))
		let user = try #require(CodexItem(json: [
			"id": "user",
			"type": "userMessage",
			"text": "Question"
		]))
		var content = ConversationContentModel()
		content.loadedTurns = [CodexTurn(
			id: "turn",
			status: "completed",
			items: [answer, user],
			error: nil
		)]
		model.conversations.content[.thread("chat")] = content
		return model
	}

	private func request(
		_ model: WorkspaceModel,
		entryID: String = "turn:answer"
	) -> ReadAloudRequest
	{
		ReadAloudRequest(
			context: OperationContext(
				workspace: model.identity,
				generation: model.connection.generation,
				requestID: UUID(),
				threadID: "chat"
			),
			entryID: entryID,
			text: "Answer"
		)
	}
}
