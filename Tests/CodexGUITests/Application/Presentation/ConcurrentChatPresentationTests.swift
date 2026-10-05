import Foundation
import Testing

@testable import CodexGUI

@Suite
@MainActor
struct ConcurrentChatPresentationTests
{
	@Test func backgroundSettingsStatusAppearsOnlyInItsOwningChat() throws
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/presentation"
		))
		model.connection.isConnected = true
		model.conversations.selectedConversation = .thread("displayed")
		let draft = ComposerDraft(text: "/plan")
		guard case .command(let invocation) = SlashCommandParser.parse(draft.text)
		else
		{
			throw TestFailure()
		}
		let request = SlashCommandPresentationRequest(
			context: OperationContext(
				workspace: model.identity,
				generation: 0,
				requestID: UUID(),
				threadID: "background"
			),
			invocation: invocation,
			conversation: .thread("background"),
			draft: draft
		)
		var operation = ComposerCommandSettingsOperation(
			request: request,
			mode: CollaborationMode(
				mode: .plan,
				model: "model",
				reasoningEffort: nil
			)
		)
		operation.outcomeUncertain = true
		model.composerCommands.pendingSettings = operation
		model.composerCommands.planModes[.thread("background")] = .plan
		let displayed = WorkspaceSelectors.snapshot(
			model: model,
			now: Date(timeIntervalSince1970: 0)
		)
		#expect(displayed.planModeStatus == nil)
		#expect(!displayed.planMode)
		model.conversations.selectedConversation = .thread("background")
		let background = WorkspaceSelectors.snapshot(
			model: model,
			now: Date(timeIntervalSince1970: 0)
		)
		#expect(background.planModeStatus?.contains("Plan mode unknown") == true)
		#expect(background.planMode)
	}

	@Test func backgroundHistoryFailureDoesNotReplaceSelectedChatStatus()
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/presentation"
		))
		model.connection.isConnected = true
		model.conversations.selectedConversation = .thread("displayed")
		model.conversations.historyErrors["background"] = "Background history failed"
		let displayed = WorkspaceSelectors.snapshot(
			model: model,
			now: Date(timeIntervalSince1970: 0)
		)
		#expect(displayed.statusMessage == nil)
		model.conversations.selectedConversation = .thread("background")
		let background = WorkspaceSelectors.snapshot(
			model: model,
			now: Date(timeIntervalSince1970: 0)
		)
		#expect(background.statusMessage == "Background history failed")
	}

	@Test func selectedExecutionControlsStayLocalWhileSidebarIncludesBothOwners()
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/presentation"
		))
		model.connection.isConnected = true
		model.conversations.selectedConversation = .thread("a")
		model.execution.activeThreadID = "a"
		model.execution.state = .running
		model.execution.activeActivity = "Activity A"
		model.conversations.selectedConversation = .thread("b")
		model.execution.activeThreadID = "b"
		model.execution.state = .awaitingAnswer
		model.execution.activeActivity = "Activity B"
		let b = WorkspaceSelectors.snapshot(
			model: model,
			now: Date(timeIntervalSince1970: 0)
		)
		#expect(b.executionState == .awaitingAnswer)
		#expect(b.activeThreadID == "b")
		#expect(b.activeActivity == "Activity B")
		#expect(b.threadExecutions["a"]?.state == .running)
		#expect(b.threadExecutions["b"]?.state == .awaitingAnswer)
		#expect(b.activeExecutionCount == 2)
		model.conversations.selectedConversation = .thread("a")
		let a = WorkspaceSelectors.snapshot(
			model: model,
			now: Date(timeIntervalSince1970: 0)
		)
		#expect(a.executionState == .running)
		#expect(a.activeThreadID == "a")
		#expect(a.activeActivity == "Activity A")
		#expect(a.threadExecutions == b.threadExecutions)
	}

	@Test func backgroundCommandFailureAppearsOnlyInItsOwningChat()
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/presentation"
		))
		model.connection.isConnected = true
		model.conversations.selectedConversation = .thread("displayed")
		model.composerCommands.conversationErrors[.thread("background")] = "Settings failed"
		let displayed = WorkspaceSelectors.snapshot(
			model: model,
			now: Date(timeIntervalSince1970: 0)
		)
		#expect(displayed.statusMessage == nil)
		model.conversations.selectedConversation = .thread("background")
		let background = WorkspaceSelectors.snapshot(
			model: model,
			now: Date(timeIntervalSince1970: 0)
		)
		#expect(background.statusMessage == "Settings failed")
	}

	private struct TestFailure: Error
	{
	}
}
