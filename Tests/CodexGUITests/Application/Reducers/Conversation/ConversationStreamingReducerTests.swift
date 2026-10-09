import Foundation
import Testing

@testable import CodexGUI

@MainActor
struct ConversationStreamingReducerTests
{
	private let projectPath = "/tmp/streaming"
	private let conversation = ConversationKey.thread("worker")

	private func fixture() -> WorkspaceModel
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: projectPath
		))
		model.connection.generation = 2
		model.connection.isConnected = true
		model.conversations.selectedConversation = .thread("viewed")
		var execution = ExecutionModel()
		execution.activeThreadID = "worker"
		execution.activeTurnID = "current"
		model.executions.entries[.thread("worker")] = execution
		return model
	}

	private func message(
		_ id: String,
		text: String
	) -> CodexItem
	{
		CodexItem(json: ["id": id, "type": "agentMessage", "text": text])!
	}

	private func command(
		status: String,
		output: String? = nil,
		name: String = "printf"
	) -> CodexItem
	{
		var json: [String: Any] = [
			"id": "command",
			"type": "commandExecution",
			"command": name,
			"status": status
		]
		json["aggregatedOutput"] = output
		return CodexItem(json: json)!
	}

	private func turn(
		_ id: String,
		items: [CodexItem],
		status: String = "completed"
	) -> CodexTurn
	{
		CodexTurn(
			id: id,
			status: status,
			items: items,
			error: nil
		)
	}

	private func merge(
		_ turns: [CodexTurn],
		model: inout WorkspaceModel
	)
	{
		ConversationContentReducer.merge(
			ThreadDetail(
				summary: ThreadSummary(json: ["id": "worker", "cwd": projectPath])!,
				turns: turns,
				nextTurnsCursor: "older"
			),
			model: &model
		)
	}

	private func delta(
		_ text: String,
		itemID: String = "answer",
		model: inout WorkspaceModel
	)
	{
		ConversationContentReducer.observe(
			.agentMessageDelta(
				threadId: "worker",
				turnId: "current",
				itemId: itemID,
				text: text
			),
			model: &model
		)
	}

	private func commandDelta(
		_ text: String,
		model: inout WorkspaceModel
	)
	{
		ConversationContentReducer.observe(
			.commandOutputDelta(
				threadId: "worker",
				turnId: "current",
				itemId: "command",
				text: text
			),
			model: &model
		)
	}

	private func reduce(
		_ action: WorkspaceAction,
		model: inout WorkspaceModel
	)
	{
		let reduction = WorkspaceFeatureComposition.reduce(
			&model,
			action
		)
		for event in reduction.domainEvents
		{
			_ = ConversationReviewComposition.reduceDomainEvent(
				&model,
				event
			)
		}
	}

	@Test(arguments: [false, true])
	func serverUserMessageReplacesLocalRowBeforeAnyHistoryRefresh(_ newChat: Bool) throws
	{
		var model = fixture()
		let inputs: [TurnInput] = [.text("Same request"), .localImage(path: "/tmp/image.png")]
		let submission = ComposerSubmission(
			context: OperationContext(
				workspace: model.identity,
				generation: model.connection.generation,
				requestID: UUID(),
				threadID: newChat ? nil : "worker"
			),
			conversation: newChat ? .newChat : conversation,
			draft: ComposerDraft(text: "Same request"),
			inputs: inputs,
			skills: [],
			modelID: nil,
			effort: nil,
			preferences: .standard,
			retainedContextRequestID: UUID()
		)
		let user = try #require(CodexItem(json: [
			"id": "user",
			"type": "userMessage",
			"content": [
				["type": "text", "text": "Same request"],
				["type": "localImage", "path": "/tmp/image.png"]
			]
		]))
		let earlier = ConversationContentReducer.entry(
			for: user,
			id: "earlier:user"
		)
		if !newChat
		{
			model.conversations.content[conversation] = ConversationContentModel(entries: [earlier])
		}
		_ = ConversationReducer.reduceDomainEvent(
			&model,
			.submissionAccepted(submission)
		)
		if newChat
		{
			_ = ConversationReducer.reduceDomainEvent(
				&model,
				.submissionPrepared(PreparedSubmission(
					submission: submission,
					thread: ThreadDetail(
						summary: ThreadSummary(json: ["id": "worker", "cwd": projectPath])!,
						turns: [],
						nextTurnsCursor: nil
					)
				))
			)
		}
		ConversationContentReducer.observe(
			.turnStarted(
				threadId: "worker",
				turn: turn(
					"current",
					items: [],
					status: "inProgress"
				)
			),
			model: &model
		)
		// A delayed event from an older turn must not consume the current local row.
		if !newChat
		{
			ConversationContentReducer.observe(
				.itemCompleted(
					threadId: "worker",
					turnId: "earlier",
					item: user
				),
				model: &model
			)
			#expect(model.conversations.content[conversation]?.entries.count == 2)
		}
		for event in [
			AppServerEvent.itemStarted(
				threadId: "worker",
				turnId: "current",
				item: user
			),
			.itemCompleted(
				threadId: "worker",
				turnId: "current",
				item: user
			)
		]
		{
			ConversationContentReducer.observe(
				event,
				model: &model
			)
			let entries = try #require(model.conversations.content[conversation]?.entries)
			#expect(entries.map(\.id) == (newChat ? [] : [earlier.id]) + ["current:user"])
			#expect(entries.last?.imageAttachments.map(\.path) == ["/tmp/image.png"])
			#expect(entries.last?.body == "Same request")
			#expect(model.conversations.content[conversation]?.localUserMessageTurnIDs
				.isEmpty == true)
		}
		// A second identical server item is a separate message, even within the same turn.
		let second = try #require(CodexItem(json: [
			"id": "second-user",
			"type": "userMessage",
			"content": [["type": "text", "text": "Same request"],
						["type": "localImage", "path": "/tmp/image.png"]]
		]))
		ConversationContentReducer.observe(
			.itemStarted(
				threadId: "worker",
				turnId: "current",
				item: second
			),
			model: &model
		)
		#expect(model.conversations.content[conversation]?.entries.count == (newChat ? 2 : 3))
	}

	@Test(arguments: ["a", "e\u{301}", "👩🏽‍💻"])
	func expansionThresholdCountsGraphemesAcrossFragmentBoundaries(_ grapheme: String)
	{
		var model = fixture()
		let initial = String(
			repeating: grapheme,
			count: 2_000
		)
		delta(
			initial,
			model: &model
		)
		delta(
			"",
			model: &model
		)
		#expect(model.conversations.content[conversation]?.entries[0].isExpandable == false)
		delta(
			"\u{301}",
			model: &model
		)
		#expect(model.conversations.content[conversation]?.entries[0].isExpandable == false)
		delta(
			"x",
			model: &model
		)
		#expect(model.conversations.content[conversation]?.entries[0].isExpandable == true)
		delta(
			"\n完成",
			model: &model
		)
		let entry = model.conversations.content[conversation]!.entries[0]
		#expect(entry.isExpandable)
		#expect(Array(entry.body.utf8) == Array((initial + "\u{301}x\n完成").utf8))

		ConversationContentReducer.observe(
			.itemCompleted(
				threadId: "worker",
				turnId: "current",
				item: message(
					"answer",
					text: "short"
				)
			),
			model: &model
		)
		delta(
			"!",
			model: &model
		)
		#expect(model.conversations.content[conversation]?.entries[0].body == "short!")
		#expect(model.conversations.content[conversation]?.entries[0].isExpandable == false)
	}

	@Test func aShortenedMessageDoesNotRetainItsPreviousExpansionFlag()
	{
		var model = fixture()
		delta(
			String(
				repeating: "x",
				count: 2_001
			),
			model: &model
		)
		delta(
			"",
			model: &model
		)
		#expect(model.conversations.content[conversation]?.entries[0].isExpandable == true)
		model.conversations.content[conversation]?.entries[0].body = "short"
		let retained = model
		delta(
			"!",
			model: &model
		)
		#expect(model.conversations.content[conversation]?.entries[0].body == "short!")
		#expect(model.conversations.content[conversation]?.entries[0].isExpandable == false)
		#expect(retained.conversations.content[conversation]?.entries[0].isExpandable == true)
	}

	@Test func memberwiseEntriesAndExternalMutationsRetainFirstDuplicateMatch()
	{
		var model = fixture()
		let first = ConversationContentReducer.entry(
			for: message(
				"answer",
				text: "first"
			),
			id: "current:answer"
		)
		let duplicate = ConversationContentReducer.entry(
			for: message(
				"answer",
				text: "duplicate"
			),
			id: "current:answer"
		)
		model.conversations.content[conversation] = ConversationContentModel(
			entries: [first, duplicate]
		)
		let retained = model
		delta(
			"+",
			model: &model
		)
		#expect(model.conversations.content[conversation]?.entries.map(\.body) == [
			"first+",
			"duplicate"
		])
		#expect(retained.conversations.content[conversation]?.entries.map(\.body) == [
			"first",
			"duplicate"
		])

		let other = ConversationContentReducer.entry(
			for: message(
				"other",
				text: "other"
			),
			id: "current:other"
		)
		model.conversations.content[conversation]!.entries = [other, duplicate, first]
		delta(
			"!",
			model: &model
		)
		model.conversations.content[conversation]!.entries.append(other)
		delta(
			"?",
			itemID: "other",
			model: &model
		)
		#expect(model.conversations.content[conversation]?.entries.map(\.body) == [
			"other?",
			"duplicate!",
			"first",
			"other"
		])
	}

	@Test func historyReplacementReindexesDuplicatesAndKeepsReferenceRevisionStableDuringStreaming()
	{
		var model = fixture()
		let reference = CodexItem(json: [
			"id": "user",
			"type": "userMessage",
			"content": [[
				"type": "localImage",
				"path": "/tmp/retained-reference.png"
			]]
		])!
		merge(
			[turn(
				"current",
				items: [message(
					"answer",
					text: "old"
				)]
			)],
			model: &model
		)
		delta(
			" stale",
			model: &model
		)
		merge(
			[
				turn(
					"earlier",
					items: [reference]
				),
				turn(
					"current",
					items: [
						message(
							"answer",
							text: "canonical"
						),
						message(
							"answer",
							text: "second duplicate"
						),
					]
				),
			],
			model: &model
		)
		let retained = model.conversations.content[conversation]!
		delta(
			" fresh",
			model: &model
		)
		let streamed = model.conversations.content[conversation]!
		#expect(streamed.entries.map(\.body) == [
			retained.entries[0].body,
			"canonical fresh",
			"second duplicate"
		])
		#expect(streamed.loadedHistoryRevision == retained.loadedHistoryRevision)
		#expect(streamed.loadedUserReferences?.map(\.path) == ["/tmp/retained-reference.png"])
		#expect(retained.entries[1].body == "canonical")

		merge(
			[],
			model: &model
		)
		delta(
			"new",
			model: &model
		)
		#expect(model.conversations.content[conversation]?.entries.map(\.body) == ["new"])
		#expect(model.conversations.content[conversation]?.loadedUserReferences?.isEmpty == true)
	}

	@Test func prependedHistoryKeepsStreamingAgentAndCommandEntriesAtTheirNewIndices()
	{
		var model = fixture()
		merge(
			[turn(
				"current",
				items: [message(
					"answer",
					text: "base"
				), command(status: "running")],
				status: "inProgress"
			)],
			model: &model
		)
		delta(
			" one",
			model: &model
		)
		commandDelta(
			"one",
			model: &model
		)
		let operation = HistoryLoadOperation(
			context: OperationContext(
				workspace: model.identity,
				generation: model.connection.generation,
				requestID: UUID(),
				threadID: "worker"
			),
			pageScope: HistoryPageScope(
				projectPath: projectPath,
				generation: model.connection.generation,
				cursor: "older"
			),
			commandRevision: 0
		)
		model.conversations.historyLoads["worker"] = operation
		reduce(
			.conversations(.earlierTurnsReceived(
				operation,
				.succeeded(HistoryPage(
					turns: [turn(
						"earlier",
						items: [message(
							"answer",
							text: "earlier"
						)]
					)],
					nextCursor: nil
				))
			)),
			model: &model
		)
		delta(
			" two",
			model: &model
		)
		commandDelta(
			"two",
			model: &model
		)
		#expect(model.conversations.content[conversation]?.entries.map(\.id) == [
			"earlier:answer",
			"current:answer",
			"current:command"
		])
		#expect(model.conversations.content[conversation]?.entries.map(\.body) == [
			"earlier",
			"base one two",
			"$ printf\nonetwo"
		])
	}

	@Test(arguments: ["running", "inProgress"])
	func commandBodyKeepsEmptyFragmentNewlineAndCompletionSemantics(_ status: String)
	{
		var model = fixture()
		ConversationContentReducer.observe(
			.itemStarted(
				threadId: "worker",
				turnId: "current",
				item: command(status: status)
			),
			model: &model
		)
		commandDelta(
			"",
			model: &model
		)
		#expect(model.conversations.content[conversation]?.entries[0].body == "$ printf")
		let fragments = ["e", "\u{301}", "", "\n", "👩🏽‍💻", "\u{2028}"]
		for fragment in fragments
		{
			commandDelta(
				fragment,
				model: &model
			)
		}
		let output = fragments.joined()
		#expect(Array(model.conversations.content[conversation]!.entries[0].body.utf8) ==
			Array(("$ printf\n" + output).utf8))
		ConversationContentReducer.observe(
			.itemStarted(
				threadId: "worker",
				turnId: "current",
				item: command(
					status: status,
					name: "renamed"
				)
			),
			model: &model
		)
		commandDelta(
			" tail",
			model: &model
		)
		#expect(model.conversations.content[conversation]?.entries[0].body ==
			"$ renamed\n" + output + " tail")

		let completed = command(
			status: "completed",
			output: "authoritative"
		)
		ConversationContentReducer.observe(
			.itemCompleted(
				threadId: "worker",
				turnId: "current",
				item: completed
			),
			model: &model
		)
		commandDelta(
			"ignored",
			model: &model
		)
		#expect(model.conversations.content[conversation]?.entries == [
			ConversationContentReducer.entry(
				for: completed,
				id: "current:command"
			)
		])
	}

	@Test func commandOutputBeforeStartCanonicalizesOnceAndRetainsEveryFragment()
	{
		var model = fixture()
		commandDelta(
			"",
			model: &model
		)
		#expect(model.conversations.content[conversation]?.entries[0].body == "")
		commandDelta(
			"",
			model: &model
		)
		#expect(model.conversations.content[conversation]?.entries[0].body == "$ ")
		commandDelta(
			"one",
			model: &model
		)
		commandDelta(
			"two",
			model: &model
		)
		#expect(model.conversations.content[conversation]?.entries[0].body == "$ \nonetwo")
		ConversationContentReducer.observe(
			.itemStarted(
				threadId: "worker",
				turnId: "current",
				item: command(status: "running")
			),
			model: &model
		)
		commandDelta(
			"three",
			model: &model
		)
		#expect(model.conversations.content[conversation]?.entries[0]
			.body == "$ printf\nonetwothree")
	}

	@Test func admittedFragmentsRetainExecutionOwnerAndRejectStaleOrForeignContexts()
	{
		var model = fixture()
		let current = OperationContext(
			workspace: model.identity,
			generation: model.connection.generation,
			requestID: UUID(),
			threadID: "worker",
			turnID: "current"
		)
		model.executions.entries[.thread("worker")]?.owner = ExecutionOwner(submission: current)
		let event = AppServerEvent.agentMessageDelta(
			threadId: "worker",
			turnId: "current",
			itemId: "answer",
			text: "accepted"
		)
		for context in [
			OperationContext(
				workspace: current.workspace,
				generation: current.generation - 1,
				requestID: current.requestID,
				threadID: "worker"
			),
			OperationContext(
				workspace: WorkspaceIdentity(
					sessionID: current.workspace.sessionID,
					canonicalCheckoutPath: "/tmp/foreign"
				),
				generation: current.generation,
				requestID: current.requestID,
				threadID: "worker"
			),
		]
		{
			reduce(
				.execution(.backendObserved(
					context,
					event
				)),
				model: &model
			)
			#expect(model.conversations.content.isEmpty)
		}
		reduce(
			.execution(.backendObserved(
				current,
				event
			)),
			model: &model
		)
		#expect(model.conversations.content[conversation]?.entries.map(\.body) == ["accepted"])
		#expect(model.conversations.content[.thread("viewed")] == nil)
		#expect(model.conversations.selectedConversation == .thread("viewed"))
		#expect(model.execution(for: conversation).owner?.submission == current)
		#expect(model.execution.owner == nil)
		#expect(model.execution.activeThreadID == nil)
		#expect(model.execution.activeTurnID == nil)
	}
}
