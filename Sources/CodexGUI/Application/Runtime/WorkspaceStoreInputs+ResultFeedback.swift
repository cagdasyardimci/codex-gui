import Foundation

extension WorkspaceStoreInputs
{
	func canSubmitResultFeedback(_ target: ResultFeedbackTarget) -> Bool
	{
		ResultFeedbackReducer.canSubmit(
			target,
			model: store.model
		)
	}

	@discardableResult
	func submitResultFeedback(
		_ target: ResultFeedbackTarget,
		rating: ResultFeedbackRating
	) -> WorkspaceOperationHandle?
	{
		guard canSubmitResultFeedback(target)
		else
		{
			return nil
		}
		var context = store.operationContext(threadID: target.threadID)
		context.turnID = target.turnID
		let operation = ResultFeedbackOperation(
			context: context,
			submission: ResultFeedbackSubmission(
				target: target,
				rating: rating
			)
		)
		store.dispatch(.resultFeedback(.requested(operation)))
		return store.operation(for: context)
	}
}
