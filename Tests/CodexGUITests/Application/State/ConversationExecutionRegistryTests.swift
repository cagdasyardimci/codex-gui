import Foundation
import Testing

@testable import CodexGUI

@Suite
struct ConversationExecutionRegistryTests
{

	@Test @MainActor func staleRequestReadRejectsWhileDurableScopeRetainsOriginalOwner()
	{
		var model = fixture()
		let captured = context(
			model,
			threadID: "a"
		)
		model.execution.owner = ExecutionOwner(submission: captured)
		model.connection.generation += 1
		model.conversations.selectedConversation = .thread("b")
		#expect(model.execution(for: captured) == nil)
		var invocationCount = 0
		var observedOwner: OperationContext?

		_ = WorkspaceExecutionScope.reduce(
			action: .execution(.draftAcknowledgementFinished(
				captured,
				.failed(OperationFailure(
					message: "Synthetic persistence result",
					outcomeIsUncertain: false
				))
			)),
			model: &model,
			body:
			{
				model in
				invocationCount += 1
				observedOwner = model.execution.owner?.submission
				#expect(model.execution.owner?.submission == captured)
				model.execution.statusMessage = "Durable acknowledgement for A"
				return WorkspaceReduction()
			}
		)
		#expect(invocationCount == 1)
		#expect(observedOwner == captured)
		#expect(model.execution(for: .thread("a")).statusMessage == "Durable acknowledgement for A")
		#expect(model.execution.owner == nil)
		#expect(model.execution.statusMessage == nil)
	}

	private func fixture() -> WorkspaceModel
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/execution-registry"
		))
		model.connection.isConnected = true
		model.connection.generation = 1
		model.conversations.selectedConversation = .thread("a")
		return model
	}

	private func context(
		_ model: WorkspaceModel,
		requestID: UUID = UUID(),
		threadID: String?
	) -> OperationContext
	{
		OperationContext(
			workspace: model.identity,
			generation: model.connection.generation,
			requestID: requestID,
			threadID: threadID
		)
	}
}
