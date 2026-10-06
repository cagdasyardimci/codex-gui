import Foundation
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ExecutionSubmissionCancellationTests
{
	@Test func localStopSettlesExecutionAndReleasesSubmissionWithoutClearingDraft()
	{
		var (model, context) = fixture()
		let draft = ComposerDraft(text: "Keep this request")
		let submission = ComposerSubmission(
			context: context,
			conversation: .thread("worker"),
			draft: draft,
			inputs: [.text(draft.text)],
			skills: [],
			modelID: nil,
			effort: nil,
			preferences: .standard,
			retainedContextRequestID: UUID()
		)
		model.executions.entries[.thread("worker")]!.submissionRequest = context
		model.executions.entries[.thread("worker")]!.state = .stopping
		model.executions.entries[.thread("worker")]!.stopRequested = true
		model.composer.pendingSubmissions[context.requestID] = submission
		model.composer.submissionConversations[context.requestID] = .thread("worker")
		model.composer.drafts[.thread("worker")] = draft
		let action = WorkspaceAction.execution(.submissionCancelledBeforeSend(context))
		_ = ExecutionReducer.reduce(
			&model,
			action
		)
		let composerResult = ComposerReducer.reduce(
			&model,
			action
		)
		#expect(model.executions.entries[.thread("worker")]!.state == .completed)
		#expect(!model.executions.entries[.thread("worker")]!.hasUncertainRequest)
		#expect(model.composer.drafts[.thread("worker")]?.text == draft.text)
		#expect(composerResult.effects.contains
		{
			if case .releaseSubmission(let operation) = $0
			{
				return operation.submission.context.isSameRequest(as: context)
			}
			return false
		})
	}

	private func fixture() -> (WorkspaceModel, OperationContext)
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/neutral/repository"
		))
		model.connection.isConnected = true
		model.executions.entries[.thread("worker")] = ExecutionModel()
		model.connection.generation = 1
		let context = OperationContext(
			workspace: model.identity,
			generation: 1,
			requestID: UUID(),
			threadID: "worker"
		)
		model.executions.entries[.thread("worker")]!.owner = ExecutionOwner(submission: context)
		model.executions.entries[.thread("worker")]!.activeThreadID = "worker"
		model.executions.entries[.thread("worker")]!.state = .running
		model.conversations.selectedConversation = .thread("other")
		return (model, context)
	}
}
