import Foundation

/// Controller-facing store for the canonical uncommitted pinned summary.
@MainActor
final class GitSummaryBackgroundLoader
{
	private var state = GitSummaryState()
	private let effects: GitSummaryEffectRunner
	var projection: GitReviewSummaryProjection?
	{
		state.projection
	}
	var onChange: ((GitReviewSummaryProjection?) -> Void)?
	// Capture before cancellation or replacement to await this read's complete result handling.
	var readTask: Task<Void, Never>?
	{
		effects.readTask
	}

	init(service: any GitComparisonService = LocalGitComparisonService())
	{
		effects = GitSummaryEffectRunner(service: service)
	}

	func select(_ owner: FeaturePresentationOwner)
	{
		dispatch(.select(owner))
	}

	func loadIfNeeded(for owner: FeaturePresentationOwner)
	{
		dispatch(.loadIfNeeded(owner))
	}

	func refresh(for owner: FeaturePresentationOwner)
	{
		dispatch(.refresh(owner))
	}

	func cancel()
	{
		dispatch(.cancel)
	}

	private func dispatch(_ action: GitSummaryAction)
	{
		let transition = GitSummaryReducer.reduce(
			state: &state,
			action: action
		)

		for effect in transition.effects
		{
			effects.run(effect)
			{
				[weak self] result, request in
				self?.dispatch(.received(
					result,
					request: request
				))
			}
		}

		if transition.publishes
		{
			onChange?(state.projection)
		}
	}
}
