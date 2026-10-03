import Foundation

/// All review choices and result acceptance are synchronous value transitions.
enum GitReviewReducer
{
	static func reduce(
		state: inout GitReviewState,
		action: GitReviewAction,
		automaticRefreshEnabled: Bool
	) -> GitReviewTransition
	{
		switch action
		{
		case let .activate(
			owner,
			lastTurnID,
			baselineRevision,
			baselineFailure
		):
			if state.isOpen, state.owner == owner
			{
				return updateContext(
					state: &state,
					lastTurnID: lastTurnID,
					baselineRevision: baselineRevision,
					baselineFailure: baselineFailure,
					automaticRefreshEnabled: automaticRefreshEnabled
				)
			}
			state.activate(
				owner: owner,
				lastTurnID: lastTurnID,
				baselineRevision: baselineRevision,
				baselineFailure: baselineFailure
			)
			var transition = beginRead(state: &state)
			transition.effects.insert(
				.stopPolling,
				at: 0
			)
			if automaticRefreshEnabled
			{
				transition.effects.append(.startPolling(owner))
			}
			return transition
		case let .updateContext(
			lastTurnID,
			baselineRevision,
			baselineFailure
		):
			return updateContext(
				state: &state,
				lastTurnID: lastTurnID,
				baselineRevision: baselineRevision,
				baselineFailure: baselineFailure,
				automaticRefreshEnabled: automaticRefreshEnabled
			)
		case .close:
			state.close()
			return GitReviewTransition(
				effects: [.cancelRead, .stopPolling],
				publishes: true
			)
		case .reload:
			return beginRead(state: &state)
		case .repositoryChanged:
			state.markRepositoryChanged()
			return beginRead(state: &state)
		case .selectScope(let scope):
			state.selectScope(scope)
			return beginRead(state: &state)
		case let .setRevisions(
			base,
			target
		):
			state.setRevisions(
				base: base,
				target: target
			)
			return beginRead(state: &state)
		case .setFilter(let filter):
			state.setFilter(filter)
			return GitReviewTransition(publishes: true)
		case .selectFile(let id):
			return GitReviewTransition(publishes: state.selectFile(id))
		case .toggleDirectory(let path):
			state.toggleDirectory(path)
			return GitReviewTransition(publishes: true)
		case .expandGap(let id):
			state.expandGap(id)
			return GitReviewTransition(publishes: true)
		case .setOptions(let options):
			state.setOptions(options)
			return GitReviewTransition(publishes: true)
		case .poll(let owner):
			guard automaticRefreshEnabled, state.isOpen, state.owner == owner,
					state.snapshot != nil, state.pendingRequest == nil, state.failure == nil
			else
			{
				return GitReviewTransition()
			}
			return beginRead(state: &state)
		case let .received(
			result,
			request
		):
			return GitReviewTransition(publishes: state.accept(
				result,
				request: request
			))
		}
	}

	private static func updateContext(
		state: inout GitReviewState,
		lastTurnID: String?,
		baselineRevision: Int,
		baselineFailure: GitComparisonFailure?,
		automaticRefreshEnabled: Bool
	) -> GitReviewTransition
	{
		guard state.updateTurnContext(
			lastTurnID: lastTurnID,
			baselineRevision: baselineRevision,
			baselineFailure: baselineFailure
		)
		else
		{
			return GitReviewTransition()
		}
		if automaticRefreshEnabled
		{
			return beginRead(state: &state)
		}
		return GitReviewTransition(
			effects: [.cancelRead],
			publishes: true
		)
	}

	private static func beginRead(state: inout GitReviewState) -> GitReviewTransition
	{
		guard let request = state.beginRequest()
		else
		{
			return GitReviewTransition(
				effects: [.cancelRead],
				publishes: true
			)
		}
		if request.scope == .lastTurn, let failure = state.baselineFailure
		{
			_ = state.accept(
				.unavailable(failure),
				request: request
			)
			return GitReviewTransition(
				effects: [.cancelRead],
				publishes: true
			)
		}
		return GitReviewTransition(
			effects: [.cancelRead, .read(request)],
			publishes: true
		)
	}
}
