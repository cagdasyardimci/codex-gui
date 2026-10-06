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

}
