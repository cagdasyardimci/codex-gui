import Foundation

/// Thread activity remains visible when another conversation owns the selected controls.
struct ThreadExecutionPresentation: Equatable
{
	let state: ExecutionState
	let outcomeUncertain: Bool

	var title: String
	{
		outcomeUncertain ? "Outcome unknown" : state.title
	}

	init(
		state: ExecutionState,
		outcomeUncertain: Bool = false
	)
	{
		self.state = state
		self.outcomeUncertain = outcomeUncertain
	}

	init(_ execution: ExecutionModel)
	{
		state = execution.state
		outcomeUncertain = execution.needsReconciliation || execution.hasUncertainRequest
	}
}
