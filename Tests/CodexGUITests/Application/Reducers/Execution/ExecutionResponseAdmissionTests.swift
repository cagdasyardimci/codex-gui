import Foundation
import Testing

@testable import CodexGUI

@Suite(
	.serialized
) @MainActor
struct ExecutionResponseAdmissionTests
{

	@Test func responseAdmissionKeepsTheFirstTicketAndAllowsRetryOnlyAfterSettlement() async throws
	{
		let storeFixture = try await CapturedIntentStoreFixture.makeStore()
		defer
		{
			storeFixture.cleanup()
		}
		let store = storeFixture.store
		let service = storeFixture.service
		await store.inputs.connect()
		// Context IO can outlast connection bootstrap; await this fixture's eligibility.
		await awaitWorkspaceSnapshot(store)
		{
			$0.canSend
		}
		try #require(store.currentSnapshot.canSend)
		store.inputs.updateDraft("Run")
		let submission = try #require(store.inputs.send())
		#expect(await submission.wait() == .finished)
		let approval = service.approval(id: "one-ticket")
		service.emit(.interaction(approval))
		var model = store.model
		func proposal() -> InteractionResponseOperation
		{
			var context = store.operationContext(threadID: approval.threadId)
			context.turnID = approval.turnId
			return InteractionResponseOperation(
				context: context,
				interactionID: approval.id,
				response: .approval(.accept)
			)
		}
		let first = proposal()
		let accepted = ExecutionReducer.reduce(
			&model,
			.execution(.interactionResponseRequested(first))
		)
		#expect(accepted.effects.count == 1)
		if case .respond(let effect) = accepted.effects.first
		{
			#expect(effect.context == first.context)
		}
		else
		{
			Issue.record("First response did not emit its captured effect")
		}
		let duplicate = proposal()
		#expect(duplicate.context.requestID != first.context.requestID)
		let rejected = ExecutionReducer.reduce(
			&model,
			.execution(.interactionResponseRequested(duplicate))
		)
		#expect(rejected.effects.isEmpty)
		#expect(model.execution.pendingResponses[approval.id]?.context == first.context)
		#expect(model.execution.pendingInteractions.map(\.id) == [approval.id])

		_ = ExecutionReducer.reduce(
			&model,
			.execution(.interactionResponseFinished(
				first.context,
				.failed(OperationFailure(
					message: "Synthetic response failure",
					outcomeIsUncertain: false
				))
			))
		)
		#expect(model.execution.pendingResponses[approval.id] == nil)
		#expect(model.execution.pendingInteractions.map(\.id) == [approval.id])
		let retry = proposal()
		let retried = ExecutionReducer.reduce(
			&model,
			.execution(.interactionResponseRequested(retry))
		)
		#expect(retried.effects.count == 1)
		#expect(model.execution.pendingResponses[approval.id]?.context == retry.context)
		_ = ExecutionReducer.reduce(
			&model,
			.execution(.interactionResponseFinished(
				first.context,
				.succeeded(())
			))
		)
		#expect(model.execution.pendingResponses[approval.id]?.context == retry.context)
		_ = ExecutionReducer.reduce(
			&model,
			.execution(.interactionResponseFinished(
				retry.context,
				.succeeded(())
			))
		)
		#expect(model.execution.pendingInteractions.isEmpty)
		#expect(ExecutionReducer.reduce(
			&model,
			.execution(.interactionResponseRequested(proposal()))
		).effects.isEmpty)
	}

}
