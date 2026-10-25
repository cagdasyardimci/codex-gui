import Foundation
import Testing

@testable import CodexGUI

struct WorkspaceModelTests
{
	private let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
	private let requestID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

	private var identity: WorkspaceIdentity
	{
		WorkspaceIdentity(
			sessionID: sessionID,
			canonicalCheckoutPath: "/checkout"
		)
	}

	private var context: OperationContext
	{
		OperationContext(
			workspace: identity,
			generation: 1,
			requestID: requestID
		)
	}

	@Test func scopeRejectsAnotherStoreCheckoutGenerationAndRequest()
	{
		let anotherSession = WorkspaceIdentity(
			sessionID: requestID,
			canonicalCheckoutPath: "/checkout"
		)
		let anotherCheckout = WorkspaceIdentity(
			sessionID: sessionID,
			canonicalCheckoutPath: "/other-checkout"
		)
		#expect(!context.belongsTo(
			workspace: anotherSession,
			generation: 1
		))
		#expect(!context.belongsTo(
			workspace: anotherCheckout,
			generation: 1
		))
		#expect(!context.belongsTo(
			workspace: identity,
			generation: 2
		))
		let anotherRequest = OperationContext(
			workspace: identity,
			generation: 1,
			requestID: sessionID
		)
		#expect(!context.isSameRequest(as: anotherRequest))
	}

	@Test func newSubmissionBindsBackendIDsWithoutLosingRequestIdentity()
	{
		#expect(context.threadID == nil)
		#expect(context.turnID == nil)
		var acknowledged = context
		acknowledged.threadID = "thread"
		acknowledged.turnID = "turn"
		#expect(acknowledged.isSameRequest(as: context))
		#expect(acknowledged != context)
	}

	@Test func terminalAgentAndDisconnectedSessionKeepCommandBarrier()
	{
		var model = WorkspaceModel(identity: identity)
		model.execution.owner = ExecutionOwner(submission: context)
		model.execution.state = .completed
		model.execution.agentOutcome = .completed
		model.execution.commandLifetime = TaskCommandLifetime(pending: [
			TaskCommandOwnership(
				threadID: "thread",
				turnID: "turn",
				itemID: "command"
			),
		])
		#expect(!model.connection.isConnected)
		#expect(model.execution.isTaskActive)
		#expect(model.execution.blocksCleanup)

		model.execution.commandLifetime.observe(
			CodexItem(json: [
				"id": "command",
				"type": "commandExecution",
				"status": "completed",
			])!,
			threadID: "thread",
			turnID: "turn"
		)
		#expect(model.execution.agentOutcome == .completed)
		#expect(!model.execution.blocksCleanup)
		model.execution.hasUncertainRequest = true
		#expect(model.execution.blocksCleanup)
	}

	@Test func copiedConversationAndDraftDoNotMutateOriginalOrCapturedSubmission()
	{
		var original = WorkspaceModel(identity: identity)
		original.composer.drafts[.newChat] = ComposerDraft(
			text: "submitted",
			revision: 1
		)
		original.conversations.content[.newChat] = ConversationContentModel()
		let submission = ComposerSubmission(
			context: context,
			conversation: .newChat,
			draft: original.composer.drafts[.newChat]!,
			inputs: [.text("submitted")],
			skills: [],
			modelID: "model",
			effort: "low",
			preferences: .standard,
			retainedContextRequestID: requestID
		)
		original.composer.pendingSubmissions[requestID] = submission
		var copy = original
		copy.composer.drafts[.newChat]?.text = "later edit"
		copy.composer.drafts[.newChat]?.revision = 2
		copy.preferences.runPreferences = RunPreferences(
			approvalMode: .fullAccess,
			fastMode: true
		)
		copy.conversations.content[.newChat]?.diff = "later diff"
		#expect(original.composer.drafts[.newChat]?.text == "submitted")
		#expect(original.conversations.content[.newChat]?.diff == "")
		#expect(copy.composer.pendingSubmissions[requestID]?.draft.revision == 1)
		#expect(copy.composer.pendingSubmissions[requestID]?.preferences == .standard)
	}

}
