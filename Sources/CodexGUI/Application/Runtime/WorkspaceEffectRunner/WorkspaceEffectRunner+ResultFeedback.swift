import Foundation

extension WorkspaceEffectRunner
{
	func performResultFeedback(_ operation: ResultFeedbackOperation) async -> WorkspaceAction
	{
		var uploadStarted = false
		do
		{
			try Task.checkCancellation()
			let ownsCurrentTransport = !hasObservedSubscription
				|| (subscription?.workspace == operation.context.workspace
					&& subscription?.generation == operation.context.generation)
			guard ownsCurrentTransport
			else
			{
				return .resultFeedback(.finished(
					operation,
					.failed(
						OperationFailure(
							message: "Feedback transport ownership changed before submission.",
							outcomeIsUncertain: false
						),
						unavailable: false
					)
				))
			}
			let directory = try conversationDirectory(operation.context)
			uploadStarted = true
			try await service.submitResultFeedback(
				operation.submission,
				in: directory
			)
			// Preserve an acknowledgement even when local cancellation raced it.
			return .resultFeedback(.finished(
				operation,
				.submitted
			))
		}
		catch
		{
			let failure = ResultFeedbackRequestFailure.classify(
				error,
				uploadStarted: uploadStarted
			)
			return .resultFeedback(.finished(
				operation,
				.failed(
					failure.failure,
					unavailable: failure.unavailable
				)
			))
		}
	}
}
