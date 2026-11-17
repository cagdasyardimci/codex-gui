import Foundation

struct ResultFeedbackRequestFailure: Error, LocalizedError
{
	let failure: OperationFailure
	let unavailable: Bool
	var errorDescription: String?
	{
		failure.message
	}

	static func classify(
		_ error: Error,
		uploadStarted: Bool
	) -> ResultFeedbackRequestFailure
	{
		if let failure = error as? ResultFeedbackRequestFailure
		{
			return failure
		}
		let message = BackendDiagnosticsBuffer.displaySafeText(error.localizedDescription)
		let lowercased = message.lowercased()
		let unavailable = lowercased.contains("feedback is disabled")
			|| lowercased.contains("does not support result feedback")
			|| lowercased.contains("method not found")
			|| lowercased.contains("unknown method")
		let uncertain: Bool
		if case AppServerError.requestRejected = error
		{
			// Unknown report-service errors do not establish that its upload was rejected.
			uncertain = uploadStarted && !unavailable
		}
		else if let write = error as? ProtocolWriteFailure
		{
			uncertain = uploadStarted && write.mayHaveBeenSent
		}
		else
		{
			uncertain = uploadStarted
		}
		return ResultFeedbackRequestFailure(
			failure: OperationFailure(
				message: message,
				outcomeIsUncertain: uncertain
			),
			unavailable: unavailable
		)
	}
}
