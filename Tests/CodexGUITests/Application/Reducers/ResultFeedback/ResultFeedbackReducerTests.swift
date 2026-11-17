import Foundation
import Testing

@testable import CodexGUI

@MainActor
struct ResultFeedbackReducerTests
{
	@Test func acceptedReportKeepsCapturedRatingAndCannotBeSubmittedTwice() throws
	{
		var model = try model()
		let operation = operation(
			model: model,
			rating: .bad
		)
		let accepted = ResultFeedbackReducer.reduce(
			&model,
			.resultFeedback(.requested(operation))
		)
		try #require(accepted.effects.count == 1)
		guard case .submitResultFeedback(let sent) = accepted.effects[0]
		else
		{
			Issue.record("Expected an upload effect")
			return
		}
		#expect(sent == operation)
		#expect(ResultFeedbackReducer.presentation(model: model).pending == operation.submission
			.target)
		let duplicate = self.operation(
			model: model,
			rating: .good
		)
		#expect(ResultFeedbackReducer.reduce(
			&model,
			.resultFeedback(.requested(duplicate))
		).effects
			.isEmpty)
		_ = ResultFeedbackReducer.reduce(
			&model,
			.resultFeedback(.finished(
				operation,
				.submitted
			))
		)
		#expect(model.resultFeedback.submitted[operation.submission.target] == .bad)
		#expect(!ResultFeedbackReducer.canSubmit(
			operation.submission.target,
			model: model
		))
		#expect(ResultFeedbackReducer.reduce(
			&model,
			.resultFeedback(.requested(duplicate))
		).effects
			.isEmpty)
	}

	@Test func admissionRejectsForeignUnloadedRunningAndNonAnswerTurns() throws
	{
		var original = try model()
		let target = ResultFeedbackTarget(
			threadID: "chat",
			turnID: "turn"
		)
		#expect(ResultFeedbackReducer.canSubmit(
			target,
			model: original
		))
		for invalidCase in 0 ..< 5
		{
			var model = original
			var request = operation(model: model)
			switch invalidCase
			{
			case 0: request = ResultFeedbackOperation(
					context: OperationContext(
						workspace: WorkspaceIdentity(
							sessionID: UUID(),
							canonicalCheckoutPath: "/tmp/foreign"
						),
						generation: model.connection.generation,
						requestID: UUID(),
						threadID: "chat",
						turnID: "turn"
					),
					submission: request.submission
				)
			case 1: model.conversations.content[.thread("chat")]?.loadedTurns = []
			case 2: model.conversations.content[.thread("chat")]?
				.loadedTurns = [try turn(status: "inProgress")]
			case 3: model.conversations.content[.thread("chat")]?
				.loadedTurns = [try turn(type: "userMessage")]
			case 4: model.conversations.selectedConversation = .thread("other")
			default:
				model.identity = WorkspaceIdentity(
					sessionID: model.identity.sessionID,
					canonicalCheckoutPath: nil
				)
				request = self.operation(model: model)
			}
			#expect(ResultFeedbackReducer.reduce(
				&model,
				.resultFeedback(.requested(request))
			)
			.effects.isEmpty)
			#expect(model.resultFeedback.pending == nil)
		}
		original.lifecycle.quitReservation = WorkspaceQuitReservation(
			requestID: UUID(),
			reference: WorkspaceLifecycleReducer.reference(original)
		)
		#expect(!ResultFeedbackReducer.canSubmit(
			target,
			model: original
		))
	}

	@Test func lostTransportReservesOutcomeAndRejectsLateAcknowledgementAndRetry() throws
	{
		var model = try model()
		let operation = operation(model: model)
		_ = ResultFeedbackReducer.reduce(
			&model,
			.resultFeedback(.requested(operation))
		)
		model.connection.isConnected = false
		model.connection.generation += 1
		let cancellation = ResultFeedbackReducer.reduce(
			&model,
			.connection(.disconnected(
				workspace: model.identity,
				generation: operation.context.generation,
				message: "Lost transport"
			))
		)
		#expect(cancellation.effects.count == 1)
		#expect(model.resultFeedback.pending == nil)
		#expect(model.resultFeedback.uncertain.contains(operation.submission.target))
		model.connection.isConnected = true
		_ = ResultFeedbackReducer.reduce(
			&model,
			.resultFeedback(.finished(
				operation,
				.submitted
			))
		)
		#expect(model.resultFeedback.submitted.isEmpty)
		#expect(!ResultFeedbackReducer.canSubmit(
			operation.submission.target,
			model: model
		))
		let retry = self.operation(model: model)
		#expect(ResultFeedbackReducer.reduce(
			&model,
			.resultFeedback(.requested(retry))
		).effects
			.isEmpty)
	}

	@Test func definitiveRejectionCanRetryButUncertainAndDisabledReportsCannot() throws
	{
		for outcome in ["rejected", "uncertain", "disabled"]
		{
			var model = try model()
			let operation = operation(model: model)
			_ = ResultFeedbackReducer.reduce(
				&model,
				.resultFeedback(.requested(operation))
			)
			_ = ResultFeedbackReducer.reduce(
				&model,
				.resultFeedback(.finished(
					operation,
					.failed(
						OperationFailure(
							message: "Rejected",
							outcomeIsUncertain: outcome == "uncertain"
						),
						unavailable: outcome == "disabled"
					)
				))
			)
			#expect(ResultFeedbackReducer
				.canSubmit(
					operation.submission.target,
					model: model
				) == (outcome == "rejected"))
			if outcome == "disabled"
			{
				model.connection.generation += 1
				_ = ResultFeedbackReducer.reduce(
					&model,
					.connection(.connectionFinished(
						OperationContext(
							workspace: model.identity,
							generation: model.connection.generation,
							requestID: UUID()
						),
						.succeeded(())
					))
				)
				#expect(ResultFeedbackReducer.canSubmit(
					operation.submission.target,
					model: model
				))
			}
		}
	}

	@Test func acceptedReportCompletesForOriginalTurnAfterSelectionChanges() throws
	{
		var model = try model()
		let operation = operation(model: model)
		_ = ResultFeedbackReducer.reduce(
			&model,
			.resultFeedback(.requested(operation))
		)
		model.conversations.selectedConversation = .thread("other")
		_ = ResultFeedbackReducer.reduce(
			&model,
			.resultFeedback(.finished(
				operation,
				.submitted
			))
		)
		#expect(model.resultFeedback.submitted == [operation.submission.target: .good])
		#expect(model.resultFeedback.pending == nil)
	}

	@Test func writeCertaintyAndKnownRejectionDetermineWhetherRetryIsSafe()
	{
		for mayHaveBeenSent in [true, false]
		{
			let write = ProtocolWriteFailure(
				cause: AppServerError.disconnected,
				mayHaveBeenSent: mayHaveBeenSent,
				requiresDisconnect: true
			)
			#expect(ResultFeedbackRequestFailure.classify(
				write,
				uploadStarted: true
			).failure
				.outcomeIsUncertain == mayHaveBeenSent)
		}
		let rejected = ResultFeedbackRequestFailure.classify(
			AppServerError.requestRejected("Sending feedback is disabled by configuration."),
			uploadStarted: true
		)
		#expect(rejected.unavailable && !rejected.failure.outcomeIsUncertain)
		#expect(ResultFeedbackRequestFailure.classify(
			AppServerError.requestRejected("Upstream report failed"),
			uploadStarted: true
		).failure.outcomeIsUncertain)
		#expect(!ResultFeedbackRequestFailure.classify(
			CancellationError(),
			uploadStarted: false
		)
		.failure.outcomeIsUncertain)
		#expect(ResultFeedbackRequestFailure.classify(
			AppServerError.requestTimedOut("feedback/upload"),
			uploadStarted: true
		).failure.outcomeIsUncertain)
	}

	private func model() throws -> WorkspaceModel
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/feedback"
		))
		model.connection.isConnected = true
		model.conversations.selectedConversation = .thread("chat")
		var content = ConversationContentModel()
		content.loadedTurns = [try turn()]
		model.conversations.content[.thread("chat")] = content
		return model
	}

	private func turn(
		status: String = "completed",
		type: String = "agentMessage"
	) throws -> CodexTurn
	{
		let item = try #require(CodexItem(json: ["id": "answer", "type": type, "text": "Answer"]))
		return CodexTurn(
			id: "turn",
			status: status,
			items: [item],
			error: nil
		)
	}

	private func operation(
		model: WorkspaceModel,
		rating: ResultFeedbackRating = .good
	) -> ResultFeedbackOperation
	{
		ResultFeedbackOperation(
			context: OperationContext(
				workspace: model.identity,
				generation: model.connection.generation,
				requestID: UUID(),
				threadID: "chat",
				turnID: "turn"
			),
			submission: ResultFeedbackSubmission(
				target: ResultFeedbackTarget(
					threadID: "chat",
					turnID: "turn"
				),
				rating: rating
			)
		)
	}
}
