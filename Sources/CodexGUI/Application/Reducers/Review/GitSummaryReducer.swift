import Foundation

/// The pinned totals always come from their own uncommitted request.
enum GitSummaryReducer
{
	static func reduce(
		state: inout GitSummaryState,
		action: GitSummaryAction
	) -> GitSummaryTransition
	{
		switch action
		{
		case .select(let owner):
			guard state.owner != owner
			else
			{
				return GitSummaryTransition()
			}
			state.generation += 1
			state.revision += 1
			state.owner = owner
			state.pendingRequest = nil
			state.projection = nil
			return GitSummaryTransition(effects: [.cancelRead])
		case .loadIfNeeded(let owner):
			guard state.owner == owner, state.projection == nil,
					state.pendingRequest == nil
			else
			{
				return GitSummaryTransition()
			}
			return beginLoad(
				state: &state,
				owner: owner
			)
		case .refresh(let owner):
			guard state.owner == owner
			else
			{
				return GitSummaryTransition()
			}
			return beginLoad(
				state: &state,
				owner: owner
			)
		case let .received(
			result,
			request
		):
			guard state.owner == request.owner, state.pendingRequest == request,
					state.generation == request.generation,
					let previous = state.projection
			else
			{
				return GitSummaryTransition()
			}
			state.pendingRequest = nil
			state.revision += 1
			let comparisonID: String?
			let snapshotScope: GitComparisonScope?
			let totals: SummarySection<SummaryChangeTotals>
			switch result
			{
			case .snapshot(let snapshot) where snapshot.request == request:
				comparisonID = snapshot.id
				snapshotScope = snapshot.request.scope
				totals = .available(SummaryChangeTotals(
					additions: snapshot.additions,
					deletions: snapshot.deletions
				))
			case .snapshot:
				comparisonID = previous.comparisonID
				snapshotScope = previous.snapshotScope
				totals = .failed(
					GitComparisonFailure.repositoryChanged.message,
					previous: previous.totals.value
				)
			case .unavailable(let failure):
				comparisonID = previous.comparisonID
				snapshotScope = previous.snapshotScope
				totals = .failed(
					failure.message,
					previous: previous.totals.value
				)
			}
			state.projection = GitReviewSummaryProjection(
				owner: request.owner,
				revision: state.revision,
				scope: .uncommitted,
				comparisonID: comparisonID,
				snapshotScope: snapshotScope,
				totals: totals
			)
			return GitSummaryTransition(publishes: true)
		case .cancel:
			state.generation += 1
			state.owner = nil
			state.pendingRequest = nil
			state.projection = nil
			return GitSummaryTransition(effects: [.cancelRead])
		}
	}

	private static func beginLoad(
		state: inout GitSummaryState,
		owner: FeaturePresentationOwner
	) -> GitSummaryTransition
	{
		guard let root = owner.runtimeOwner?.workspace.canonicalCheckoutPath ?? owner.projectPath
		else
		{
			return GitSummaryTransition()
		}
		let previous = state.projection
		state.generation += 1
		state.revision += 1
		let request = GitComparisonRequest(
			owner: owner,
			repositoryRoot: root,
			scope: .uncommitted,
			generation: state.generation
		)
		state.pendingRequest = request
		state.projection = GitReviewSummaryProjection(
			owner: owner,
			revision: state.revision,
			scope: .uncommitted,
			comparisonID: previous?.comparisonID,
			snapshotScope: previous?.snapshotScope,
			totals: .loading(previous: previous?.totals.value)
		)
		return GitSummaryTransition(
			effects: [.cancelRead, .read(request)],
			publishes: true
		)
	}
}
