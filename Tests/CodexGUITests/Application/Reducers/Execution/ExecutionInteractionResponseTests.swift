import Foundation
import Testing

@testable import CodexGUI

@MainActor
struct ExecutionInteractionResponseTests
{
	private func fixture() -> (WorkspaceModel, InteractionResponseOperation)
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/response-delivery"
		))
		model.connection.isConnected = true
		model.connection.generation = 1
		model.execution.activeThreadID = "worker"
		model.execution.activeTurnID = "turn"
		model.execution.state = .awaitingApproval
		model.conversations.selectedConversation = .thread("other")
		model.execution.pendingInteractions = [interaction("approval")]
		let response = operation(model)
		_ = ExecutionReducer.reduce(
			&model,
			.execution(.interactionResponseRequested(response))
		)
		return (model, response)
	}

	private func interaction(_ id: String) -> PendingInteraction
	{
		PendingInteraction(
			id: id,
			threadId: "worker",
			turnId: "turn",
			itemId: "command",
			approvalId: nil,
			kind: .commandApproval,
			reason: nil,
			command: "check",
			cwd: nil,
			grantRoot: nil,
			networkHost: nil,
			networkProtocol: nil,
			questions: [],
			requestedPermissions: nil,
			additionalPermissions: nil,
			availableDecisions: [.accept, .decline]
		)
	}

	private func operation(
		_ model: WorkspaceModel,
		interactionID: String = "approval"
	) -> InteractionResponseOperation
	{
		InteractionResponseOperation(
			context: OperationContext(
				workspace: model.identity,
				generation: model.connection.generation,
				requestID: UUID(),
				threadID: "worker",
				turnID: "turn"
			),
			interactionID: interactionID,
			response: .approval(.accept)
		)
	}

	private func fail(
		_ response: InteractionResponseOperation,
		outcomeIsUncertain: Bool,
		model: inout WorkspaceModel
	)
	{
		_ = ExecutionReducer.reduce(
			&model,
			.execution(.interactionResponseFinished(
				response.context,
				.failed(OperationFailure(
					message: "Synthetic cancellation",
					outcomeIsUncertain: outcomeIsUncertain
				))
			))
		)
	}

	private func observe(
		_ event: AppServerEvent,
		context: OperationContext,
		model: inout WorkspaceModel
	)
	{
		_ = ExecutionReducer.reduce(
			&model,
			.execution(.backendObserved(
				context,
				event
			))
		)
	}

	@Test func possiblySentResponseRejectsRetryWithoutChangingExecutionUncertainty()
	{
		var (model, response) = fixture()
		fail(
			response,
			outcomeIsUncertain: true,
			model: &model
		)
		#expect(model.execution.pendingResponses["approval"]?.context == response.context)
		#expect(model.execution.pendingInteractions.map(\.id) == ["approval"])
		#expect(model.execution.state == .awaitingApproval)
		#expect(model.execution.statusMessage?.contains("delivery is uncertain") == true)
		#expect(!model.execution.hasUncertainRequest)
		#expect(!model.execution.needsReconciliation)
		#expect(model.execution.blocksCleanup)

		let retry = operation(model)
		let rejected = ExecutionReducer.reduce(
			&model,
			.execution(.interactionResponseRequested(retry))
		)
		#expect(rejected.effects.isEmpty)
		#expect(model.execution.pendingResponses["approval"]?.context == response.context)
	}

	@Test func unsentResponseAllowsRetryAndRejectsTheEarlierCompletion()
	{
		var (model, response) = fixture()
		fail(
			response,
			outcomeIsUncertain: false,
			model: &model
		)
		#expect(model.execution.pendingResponses.isEmpty)
		#expect(model.execution.pendingInteractions.map(\.id) == ["approval"])
		let retry = operation(model)
		let accepted = ExecutionReducer.reduce(
			&model,
			.execution(.interactionResponseRequested(retry))
		)
		#expect(accepted.effects.count == 1)
		#expect(model.execution.pendingResponses["approval"]?.context == retry.context)
		fail(
			response,
			outcomeIsUncertain: true,
			model: &model
		)
		#expect(model.execution.pendingResponses["approval"]?.context == retry.context)
	}

	@Test func serverResolutionRetiresOnlyTheMatchingResponseReservation()
	{
		var (model, response) = fixture()
		model.execution.pendingInteractions.append(interaction("other-approval"))
		let otherResponse = operation(
			model,
			interactionID: "other-approval"
		)
		_ = ExecutionReducer.reduce(
			&model,
			.execution(.interactionResponseRequested(otherResponse))
		)
		fail(
			response,
			outcomeIsUncertain: true,
			model: &model
		)
		model.execution.hasUncertainRequest = true
		model.execution.needsReconciliation = true

		observe(
			.interactionResolved(
				threadId: "foreign",
				requestID: "approval"
			),
			context: response.context,
			model: &model
		)
		#expect(model.execution.pendingResponses.count == 2)
		observe(
			.interactionResolved(
				threadId: "worker",
				requestID: "approval"
			),
			context: response.context,
			model: &model
		)
		#expect(model.execution.pendingResponses["approval"] == nil)
		#expect(model.execution.pendingResponses["other-approval"]?.context
			== otherResponse.context)
		#expect(model.execution.pendingInteractions.map(\.id) == ["other-approval"])
		#expect(model.execution.state == .awaitingApproval)
		#expect(model.execution.hasUncertainRequest)
		#expect(model.execution.needsReconciliation)
	}

	@Test func resolvingTheUncertainResponseClearsItsWarning()
	{
		var (model, response) = fixture()
		fail(
			response,
			outcomeIsUncertain: true,
			model: &model
		)
		observe(
			.interactionResolved(
				threadId: "worker",
				requestID: "approval"
			),
			context: response.context,
			model: &model
		)
		#expect(model.execution.pendingResponses.isEmpty)
		#expect(model.execution.pendingInteractions.isEmpty)
		#expect(model.execution.statusMessage == nil)
		#expect(model.execution.state == .running)
	}

	@Test func resolvingAResponsePreservesAnUnrelatedRetryableBackendError()
	{
		var (model, response) = fixture()
		fail(
			response,
			outcomeIsUncertain: true,
			model: &model
		)
		let message = "Codex is retrying the remote operation."
		observe(
			.error(
				threadId: "worker",
				turnId: "turn",
				message: message,
				willRetry: true
			),
			context: response.context,
			model: &model
		)
		observe(
			.interactionResolved(
				threadId: "worker",
				requestID: "approval"
			),
			context: response.context,
			model: &model
		)
		#expect(model.execution.pendingResponses.isEmpty)
		#expect(model.execution.pendingInteractions.isEmpty)
		#expect(model.execution.statusMessage == message)
		#expect(model.execution.state == .running)
	}

	@Test func confirmedDeliveryCanSettleAnEarlierUncertainResponse()
	{
		var (model, response) = fixture()
		fail(
			response,
			outcomeIsUncertain: true,
			model: &model
		)
		_ = ExecutionReducer.reduce(
			&model,
			.execution(.interactionResponseFinished(
				response.context,
				.succeeded(())
			))
		)
		#expect(model.execution.pendingResponses.isEmpty)
		#expect(model.execution.pendingInteractions.isEmpty)
		#expect(model.execution.state == .running)
		#expect(model.execution.statusMessage == nil)
	}

	@Test func terminalTurnClearsResponseReservationsWithoutAddingAnUncertaintyBarrier()
	{
		var (model, response) = fixture()
		fail(
			response,
			outcomeIsUncertain: true,
			model: &model
		)
		observe(
			.turnCompleted(
				threadId: "worker",
				turn: CodexTurn(
					id: "turn",
					status: "completed",
					items: [],
					error: nil
				)
			),
			context: response.context,
			model: &model
		)
		#expect(model.execution.pendingResponses.isEmpty)
		#expect(model.execution.pendingInteractions.isEmpty)
		#expect(model.execution.state == .completed)
		#expect(!model.execution.blocksCleanup)
	}

	@Test func terminalFailureClearsResponsesWithoutRemovingIndependentRecoveryBarriers()
	{
		var (model, response) = fixture()
		fail(
			response,
			outcomeIsUncertain: true,
			model: &model
		)
		model.execution.hasUncertainRequest = true
		model.execution.needsReconciliation = true
		observe(
			.error(
				threadId: "worker",
				turnId: "turn",
				message: "Task failed",
				willRetry: false
			),
			context: response.context,
			model: &model
		)
		#expect(model.execution.pendingResponses.isEmpty)
		#expect(model.execution.pendingInteractions.isEmpty)
		#expect(model.execution.state == .failed)
		#expect(model.execution.hasUncertainRequest)
		#expect(model.execution.needsReconciliation)
		#expect(model.execution.blocksCleanup)
	}

	@Test func disconnectRetiresResponsesAndPreservesItsExistingRecoveryBarrier()
	{
		var (model, response) = fixture()
		fail(
			response,
			outcomeIsUncertain: true,
			model: &model
		)
		_ = ConnectionReducer.reduce(
			&model,
			.connection(.disconnected(
				workspace: model.identity,
				generation: model.connection.generation - 1,
				message: "Stale disconnect"
			))
		)
		#expect(model.execution.pendingResponses.count == 1)
		_ = ConnectionReducer.reduce(
			&model,
			.connection(.disconnected(
				workspace: model.identity,
				generation: model.connection.generation,
				message: "Disconnected"
			))
		)
		#expect(model.execution.pendingResponses.isEmpty)
		#expect(model.execution.pendingInteractions.isEmpty)
		#expect(model.execution.needsReconciliation)
		#expect(model.execution.hasUncertainRequest)
		#expect(model.execution.blocksCleanup)
	}

	@Test func reconnectRetiresResponsesOnlyWhenItsTransitionIsAccepted()
	{
		var (model, response) = fixture()
		let reconnect = OperationContext(
			workspace: model.identity,
			generation: model.connection.generation,
			requestID: UUID()
		)
		let rejected = ConnectionReducer.reduce(
			&model,
			.connection(.connectRequested(reconnect))
		)
		#expect(rejected.effects.isEmpty)
		#expect(model.execution.pendingResponses["approval"]?.context == response.context)
		#expect(model.connection.generation == response.context.generation)

		model.execution.state = .failed
		let accepted = ConnectionReducer.reduce(
			&model,
			.connection(.connectRequested(reconnect))
		)
		#expect(!accepted.effects.isEmpty)
		#expect(model.execution.pendingResponses.isEmpty)
		#expect(model.connection.generation == response.context.generation + 1)
	}
}
