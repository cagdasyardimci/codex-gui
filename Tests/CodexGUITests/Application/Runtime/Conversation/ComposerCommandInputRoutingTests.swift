import Foundation
import Testing

@testable import CodexGUI

@Suite
@MainActor
struct ComposerCommandInputRoutingTests
{
	@Test(arguments: ["ordinary input", "/unknown", "//copy"])
	func rawInputRoutingPreservesOrdinaryAndEscapedTextAndHandlesLocalErrors(_ text: String) throws
	{
		var (model, request) = try fixture("/status")
		model.composer.drafts[request.conversation]?.text = text
		let before = model.composer.drafts[request.conversation]
		let suite = "ComposerCommandRouting.\(UUID())"
		let defaults = try #require(UserDefaults(suiteName: suite))
		defer
		{
			defaults.removePersistentDomain(forName: suite)
		}
		let storage = LocalStorage(defaults: defaults)
		let service = WorkspaceCodexService(
			directory: URL(fileURLWithPath: "/tmp/commands"),
			threadID: "thread"
		)
		let store = WorkspaceStateStore(
			model: model,
			service: service,
			storage: storage,
			persistence: WorkspacePersistenceScheduler(writeDraft:
				{
					_ in
					Issue.record("Input routing unexpectedly wrote a draft")
				}),
			reducers: [ComposerCommandReducer.reducer]
		)
		defer
		{
			store.shutdown()
		}
		let routed = store.inputs.prepareComposerCommandInput(
			text,
			steering: false
		)
		if text == "/unknown"
		{
			guard case .handled(let handle) = routed
			else
			{
				Issue.record("Unknown command must be handled locally")
				return
			}
			#expect(handle == nil)
			#expect(store.model.composerCommands.error?.contains("Unknown command") == true)
		}
		else
		{
			guard case .message(
				let message,
				let mode
			) = routed
			else
			{
				Issue.record("Expected ordinary message routing")
				return
			}
			#expect(message == (text == "//copy" ? "/copy" : text))
			#expect(mode == nil)
			#expect(store.model.composerCommands.error == nil)
		}
		#expect(store.model.composer.drafts[request.conversation] == before)
		#expect(!store.model.composerCommands.blocksNewWork)
		#expect(service.connectionCount == 0)
		#expect(service.turnRequests.isEmpty)
	}

	private func fixture(_ text: String) throws -> (WorkspaceModel, SlashCommandPresentationRequest)
	{
		let identity = WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/commands"
		)
		var model = WorkspaceModel(identity: identity)
		model.connection.generation = 7
		model.connection.isConnected = true
		model.execution.state = .ready
		model.lifecycle.owner = .source(sessionID: identity.sessionID)
		model.conversations.selectedConversation = .thread("thread")
		model.conversations.threads = [detail(turns: []).summary]
		model.conversations.content[.thread("thread")] = ConversationContentModel(
			loadedTurns: [turn("old-turn")]
		)
		model.preferences.models = [try #require(ModelOption(json: [
			"model": "test-model",
			"isDefault": true,
			"defaultReasoningEffort": "medium",
			"serviceTiers": [["id": "priority", "name": "Fast", "description": "Test fast tier"]],
			"supportedReasoningEfforts": [
				["reasoningEffort": "medium"],
				["reasoningEffort": "high"]
			],
		]))]
		let draft = ComposerDraft(
			text: text,
			context: [ComposerContextItem(
				kind: .textExcerpt,
				title: "Retained context",
				path: "file.swift",
				excerpt: "value"
			)],
			revision: 3,
			lifetime: 2
		)
		model.composer.drafts[.thread("thread")] = draft
		guard case .command(let invocation) = SlashCommandParser.parse(text)
		else
		{
			throw FixtureFailure.invalidCommand
		}
		let request = SlashCommandPresentationRequest(
			context: OperationContext(
				workspace: identity,
				generation: 7,
				requestID: UUID(),
				threadID: "thread"
			),
			invocation: invocation,
			conversation: .thread("thread"),
			draft: draft
		)
		return (model, request)
	}

	private func turn(
		_ id: String,
		status: String = "completed",
		items: [CodexItem] = []
	) -> CodexTurn
	{
		CodexTurn(
			id: id,
			status: status,
			items: items,
			error: nil
		)
	}

	private func detail(
		id: String = "thread",
		turns: [CodexTurn]
	) -> ThreadDetail
	{
		ThreadDetail(
			summary: ThreadSummary(json: ["id": id, "cwd": "/tmp/commands"])!,
			turns: turns,
			nextTurnsCursor: nil
		)
	}

	private enum FixtureFailure: Error
	{
		case invalidCommand
	}
}
