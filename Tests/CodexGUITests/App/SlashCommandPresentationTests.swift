import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite(
	"Captured slash command presentation",
	.serialized
)
struct SlashCommandPresentationTests
{
	@Test func pickerRequestExpiresOnDraftEditAttachmentChangeGenerationAndOwner()
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/project"
		))
		let draft = ComposerDraft(
			text: "/model",
			revision: 4,
			lifetime: 2
		)
		model.composer.drafts[.newChat] = draft
		let request = SlashCommandPresentationRequest(
			context: OperationContext(
				workspace: model.identity,
				generation: 0,
				requestID: UUID()
			),
			invocation: SlashCommandInvocation(
				descriptor: SlashCommandRegistry.descriptor(for: .model),
				arguments: ""
			),
			conversation: .newChat,
			draft: draft
		)
		#expect(MainWindowController.slashRequestIsCurrent(
			request,
			model: model
		))
		model.composer.drafts[.newChat]?.revision += 1
		#expect(!MainWindowController.slashRequestIsCurrent(
			request,
			model: model
		))
		model.composer.drafts[.newChat] = draft
		model.composer.drafts[.newChat]?.context.append(ComposerContextItem(
			kind: .fileReference,
			title: "File",
			path: "File.swift"
		))
		#expect(!MainWindowController.slashRequestIsCurrent(
			request,
			model: model
		))
		model.composer.drafts[.newChat] = draft
		model.connection.generation = 1
		#expect(!MainWindowController.slashRequestIsCurrent(
			request,
			model: model
		))
		model.connection.generation = 0
		model.identity = WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/project"
		)
		#expect(!MainWindowController.slashRequestIsCurrent(
			request,
			model: model
		))
	}

	@Test func forkRecoveryListRequiresSameCheckoutAndOffersExplicitOriginalContinuation() throws
	{
		let threads = try [
			["id": "original", "cwd": "/tmp/project", "name": "Original"],
			["id": "candidate", "cwd": "/tmp/project", "name": "Possible result"],
			["id": "other", "cwd": "/tmp/other", "name": "Other checkout"],
		].map
		{
			try #require(ThreadSummary(json: $0))
		}
		// The helper receives the freshly published list; its cwd filter independently excludes
		// unrelated checkouts and its original action names the uncertainty explicitly.
		let recoverySnapshot = ConversationSnapshot(
			projectPath: "/tmp/project",
			threads: threads,
			selectedThreadID: "original",
			entries: [],
			canLoadEarlierTurns: false,
			changedFiles: [],
			diff: "",
			draft: "/fork",
			canSend: false,
			accountDescription: "Test",
			backendDescription: "Test",
			executionState: .ready,
			statusMessage: nil,
			models: [],
			selectedModelID: nil,
			selectedEffort: nil,
			pendingInteractions: [],
			recentProjects: []
		)
		let commands = MainWindowController.forkRecoveryCommands(
			in: recoverySnapshot,
			originalThreadID: "original"
		)
		#expect(commands.map(\.destination) == [
			.conversation("candidate"),
			.action("continue-original")
		])
		#expect(commands.last?.title == "Continue Original Chat")
		#expect(commands.last?.detail.contains("may remain saved") == true)
		let missingOriginal = MainWindowController.forkRecoveryCommands(
			in: recoverySnapshot,
			originalThreadID: "absent"
		)
		#expect(missingOriginal.last?.isEnabled == false)
		#expect(missingOriginal.last?.detail.contains("absent from the refreshed") == true)
	}

	@Test func forkRecoveryRejectsCapturedThreadMismatchWithoutConsumingDraft()
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/project"
		))
		model.conversations.selectedConversation = .thread("original")
		let draft = ComposerDraft(
			text: "/fork",
			revision: 3,
			lifetime: 4
		)
		model.composer.drafts[.thread("original")] = draft
		let request = SlashCommandPresentationRequest(
			context: OperationContext(
				workspace: model.identity,
				generation: 0,
				requestID: UUID(),
				threadID: "other"
			),
			invocation: SlashCommandInvocation(
				descriptor: SlashCommandRegistry.descriptor(for: .fork),
				arguments: ""
			),
			conversation: .thread("original"),
			draft: draft
		)
		#expect(!MainWindowController.slashRequestIsCurrent(
			request,
			model: model
		))
		#expect(model.composer.drafts[.thread("original")] == draft)
	}

	@Test func copyUsesLatestAgentBodyInSelectedSnapshotOnly()
	{
		let entries = [
			ConversationEntry(
				id: "a",
				kind: .agent,
				title: "Codex",
				body: "First reply"
			),
			ConversationEntry(
				id: "b",
				kind: .user,
				title: "You",
				body: "User message"
			),
			ConversationEntry(
				id: "c",
				kind: .agent,
				title: "Codex",
				body: "Latest reply 🧭"
			),
			ConversationEntry(
				id: "d",
				kind: .command,
				title: "Command",
				body: "Tool output"
			),
		]
		#expect(MainWindowController.latestAgentResponse(in: snapshot(entries)) == "Latest reply 🧭")
		#expect(MainWindowController.latestAgentResponse(in: snapshot([])) == nil)
		#expect(MainWindowController
			.latestAgentResponse(in: snapshot([entries[1], entries[3]])) == nil)
	}

	@Test func statusDisplaysLastInputAndCumulativeUsageSeparatelyWithoutInferringOccupancy() throws
	{
		_ = NSApplication.shared
		var current = snapshot([])
		let last: [String: Any] = ["inputTokens": 120,
									"cachedInputTokens": 60,
									"outputTokens": 10,
									"reasoningOutputTokens": 4,
									"totalTokens": 130]
		let total: [String: Any] = ["inputTokens": 7000,
									"cachedInputTokens": 3000,
									"outputTokens": 2000,
									"reasoningOutputTokens": 500,
									"totalTokens": 9000]
		current.threadTokenUsage = try #require(ThreadTokenUsage(json: [
			"last": last,
			"total": total,
			"modelContextWindow": 1000,
		]))
		current.threadStatus = try #require(ThreadStatus(json: [
			"type": "active",
			"activeFlags": ["waitingOnApproval"]
		]))
		let view = StatusPopoverView(frame: .zero)
		view.render(current)
		let label = try #require(statusContextLabel(in: view))
		#expect(label.stringValue.contains("Last request input: 120 tokens (60 cached)"))
		#expect(label.stringValue.contains("Model context window: 1000 tokens"))
		#expect(label.stringValue.contains("Conversation total usage: 9000 tokens"))
		#expect(label.stringValue.contains("Active (waiting for approval)"))
		#expect(label.stringValue.contains("Current context occupancy: not reported"))
		#expect(!label.stringValue.contains("%"))
		view.render(snapshot([]))
		#expect(label.stringValue.contains("Last request input: unavailable"))
		#expect(label.stringValue.contains("Conversation total usage: unavailable"))
		#expect(!label.stringValue.contains("9000"))
	}

	private func statusContextLabel(in view: NSView) -> NSTextField?
	{
		if let label = view as? NSTextField,
			label
			.accessibilityLabel() == "Selected conversation status and token usage"
		{
			return label
		}
		return view.subviews.lazy.compactMap
		{
			statusContextLabel(in: $0)
		}.first
	}

	private func snapshot(_ entries: [ConversationEntry]) -> ConversationSnapshot
	{
		ConversationSnapshot(
			projectPath: nil,
			threads: [],
			selectedThreadID: nil,
			entries: entries,
			canLoadEarlierTurns: false,
			changedFiles: [],
			diff: "",
			draft: "",
			canSend: false,
			accountDescription: "Test",
			backendDescription: "Test",
			executionState: .ready,
			statusMessage: nil,
			models: [],
			selectedModelID: nil,
			selectedEffort: nil,
			pendingInteractions: [],
			recentProjects: []
		)
	}
}
