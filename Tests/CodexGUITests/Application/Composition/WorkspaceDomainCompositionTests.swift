import Foundation
import Testing
@testable import CodexGUI

@MainActor
struct WorkspaceDomainCompositionTests
{
	@Test("Accepted domain events finish in FIFO order before reentrant publication")
	func domainQueueIsAtomic()
	{
		var reduced: [String] = []
		let detail = ThreadDetail(
			summary: ThreadSummary(json: ["id": "thread", "cwd": "/tmp"])!,
			turns: [],
			nextTurnsCursor: nil
		)
		let reducer = WorkspaceReducer
		{
			_, action in
			if case .preferences(.accountRefreshRequested) = action
			{
				return WorkspaceReduction(domainEvents: [.connectionBegan, .connectionDisconnected])
			}
			return WorkspaceReduction()
		}
		let store = makeStore(
			reducers: [reducer],
			reduceDomainEvent:
			{
				model, event in
				switch event
				{
				case .connectionBegan:
					reduced.append("began")
					return WorkspaceReduction(domainEvents: [.historyAccepted(
						detail,
						threadID: "thread"
					)])
				case .connectionDisconnected: reduced.append("disconnected")
				case .historyAccepted:
					reduced.append("history")
					model.preferences.selectedModelID = "composed"
				default: break
				}
				return WorkspaceReduction()
			}
		)
		var publications = 0
		var initial = true
		store.observePublications
		{
			publication in
			if initial
			{
				initial = false
				#expect(reduced.isEmpty)
				#expect(publication.model.preferences.selectedModelID == nil)
				return
			}
			publications += 1
			#expect(reduced == ["began", "disconnected", "history"])
			#expect(publication.model.preferences.selectedModelID == "composed")
			if publications == 1
			{
				store.dispatch(.preferences(.modelSelected(
					store.operationContext(),
					"later"
				)))
			}
		}
		store.dispatch(.preferences(.accountRefreshRequested(store.operationContext())))
		#expect(publications == 2)
		#expect(reduced == ["began", "disconnected", "history"])
		store.shutdown()
	}

	@Test("Accepted sign-in publishes a presentation command without a domain event")
	func signInCommandIsSeparate()
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: nil
		))
		let context = OperationContext(
			workspace: model.identity,
			generation: 0,
			requestID: UUID()
		)
		model.preferences.pendingSignIn = context
		let url = URL(string: "https://example.com/sign-in")!
		let store = makeStore(
			model: model,
			reducers: [PreferenceReducer.reducer]
		)
		var acceptedCommands = 0
		var initial = true
		store.observePublications
		{
			publication in
			if initial
			{
				initial = false
				#expect(publication.model.preferences.pendingSignIn == context)
				#expect(publication.commands.isEmpty)
				return
			}
			#expect(!publication.coalescible)
			#expect(publication.model.preferences.pendingSignIn == nil)
			#expect(publication.model.preferences
				.statusMessage == "Continue signing in through your browser.")
			for command in publication.commands
			{
				if case .openSignIn(let captured) = command
				{
					#expect(captured == url)
					acceptedCommands += 1
				}
			}
		}
		store.dispatch(.preferences(.signInURLReceived(
			context,
			.succeeded(url)
		)))
		#expect(acceptedCommands == 1)
		store.shutdown()
	}

	@Test("Stream events coalesce while terminal presentation commands publish immediately")
	func commandsPreserveTerminalPublication()
	{
		let reducer = WorkspaceReducer
		{
			_, action in
			guard case .execution(.backendObserved(
				_,
				let event,
				_
			)) = action
			else
			{
				return WorkspaceReduction()
			}
			if case .skillsChanged = event
			{
				return WorkspaceReduction(
					domainEvents: [.backendObserved(.agentMessageDelta(
						threadId: "thread",
						turnId: "turn",
						itemId: "item",
						text: "done"
					))],
					presentationCommands: [.taskFinished]
				)
			}
			return WorkspaceReduction(domainEvents: [.backendObserved(event)])
		}
		let store = makeStore(reducers: [reducer])
		var coalescible: [Bool] = []
		var terminalCommands = 0
		store.observePublications
		{
			publication in
			coalescible.append(publication.coalescible)
			for command in publication.commands
			{
				if case .taskFinished = command
				{
					terminalCommands += 1
				}
			}
		}
		let context = store.operationContext(threadID: "thread")
		store.dispatch(.execution(.backendObserved(
			context,
			.agentMessageDelta(
				threadId: "thread",
				turnId: "turn",
				itemId: "item",
				text: "text"
			)
		)))
		store.dispatch(.execution(.backendObserved(
			context,
			.skillsChanged
		)))
		#expect(coalescible == [false, true, false])
		#expect(terminalCommands == 1)
		store.shutdown()
	}

	@Test("Execution borrows canonical selection while its active owner survives navigation")
	func executionReadsCanonicalSelection()
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp"
		))
		model.connection.isConnected = true
		model.execution.state = .ready
		model.conversations.selectedConversation = .thread("selected")
		let context = OperationContext(
			workspace: model.identity,
			generation: 0,
			requestID: UUID()
		)
		let running = CodexTurn(json: ["id": "turn", "status": "inProgress", "items": []])!
		_ = ExecutionReducer.reduce(
			&model,
			.execution(.backendObserved(
				context,
				.turnStarted(
					threadId: "foreign",
					turn: running
				)
			))
		)
		#expect(model.execution.activeThreadID == nil)
		_ = ExecutionReducer.reduce(
			&model,
			.execution(.backendObserved(
				context,
				.turnStarted(
					threadId: "selected",
					turn: running
				)
			))
		)
		#expect(model.execution.activeThreadID == "selected")
		#expect(model.execution.state == .running)
		model.conversations.selectedConversation = .thread("browsed")
		let completed = CodexTurn(json: ["id": "turn", "status": "completed", "items": []])!
		_ = ExecutionReducer.reduce(
			&model,
			.execution(.backendObserved(
				context,
				.turnCompleted(
					threadId: "selected",
					turn: completed
				)
			))
		)
		#expect(model.execution.activeThreadID == "selected")
		#expect(model.execution.state == .completed)
		#expect(model.conversations.selectedConversation == .thread("browsed"))
	}

	private func makeStore(
		model: WorkspaceModel = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: nil
		)),
		reducers: [WorkspaceReducer],
		reduceDomainEvent: @escaping @MainActor (
			inout WorkspaceModel,
			WorkspaceDomainEvent
		)
			-> WorkspaceReduction =
			{
				_, _ in WorkspaceReduction()
			}
	) -> WorkspaceStateStore
	{
		WorkspaceStateStore(
			model: model,
			service: AppServer(),
			persistence: WorkspacePersistenceScheduler
			{
				_ in
			},
			reducers: reducers,
			reduceDomainEvent: reduceDomainEvent
		)
	}
}
