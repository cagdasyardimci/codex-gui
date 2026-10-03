import Foundation

/// The controller-facing store for review state. Every write passes through the reducer.
@MainActor
final class GitReviewRuntime
{
	private(set) var state = GitReviewState()
	var onChange: ((GitReviewState) -> Void)?
	let automaticRefreshEnabled: Bool
	private let effects: GitReviewEffectRunner

	init(
		service: any GitComparisonService = LocalGitComparisonService(),
		automaticRefreshEnabled: Bool = false
	)
	{
		effects = GitReviewEffectRunner(service: service)
		self.automaticRefreshEnabled = automaticRefreshEnabled
	}

	func activate(
		owner: FeaturePresentationOwner,
		lastTurnID: String? = nil,
		baselineRevision: Int = 0,
		baselineFailure: GitComparisonFailure? = nil
	)
	{
		dispatch(.activate(
			owner: owner,
			lastTurnID: lastTurnID,
			baselineRevision: baselineRevision,
			baselineFailure: baselineFailure
		))
	}

	func updateContext(
		lastTurnID: String?,
		baselineRevision: Int,
		baselineFailure: GitComparisonFailure? = nil
	)
	{
		dispatch(.updateContext(
			lastTurnID: lastTurnID,
			baselineRevision: baselineRevision,
			baselineFailure: baselineFailure
		))
	}

	func refreshIfNeeded()
	{
		guard let owner = state.owner
		else
		{
			return
		}
		dispatch(.poll(owner))
	}

	func close()
	{
		dispatch(.close)
	}

	func reload()
	{
		dispatch(.reload)
	}

	func repositoryChanged()
	{
		dispatch(.repositoryChanged)
	}

	func selectScope(_ scope: GitComparisonScope)
	{
		dispatch(.selectScope(scope))
	}

	func setRevisions(
		base: String,
		target: String
	)
	{
		dispatch(.setRevisions(
			base: base,
			target: target
		))
	}

	func setFilter(_ filter: String)
	{
		dispatch(.setFilter(filter))
	}

	func selectFile(_ id: String)
	{
		dispatch(.selectFile(id))
	}

	func toggleDirectory(_ path: String)
	{
		dispatch(.toggleDirectory(path))
	}

	func expandGap(_ id: String)
	{
		dispatch(.expandGap(id))
	}

	func setOptions(_ options: GitDiffPresentationOptions)
	{
		dispatch(.setOptions(options))
	}

	private func dispatch(_ action: GitReviewAction)
	{
		let transition = GitReviewReducer.reduce(
			state: &state,
			action: action,
			automaticRefreshEnabled: automaticRefreshEnabled
		)

		for effect in transition.effects
		{
			effects.run(
				effect,
				onResult:
				{
					[weak self] result, request in
					self?.dispatch(.received(
						result,
						request: request
					))
				},
				onPoll:
				{
					[weak self] owner in
					self?.dispatch(.poll(owner))
				}
			)
		}

		if transition.publishes
		{
			onChange?(state)
		}
	}
}
