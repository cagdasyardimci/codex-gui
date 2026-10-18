import Foundation

/// Selected-task edit totals; previous-turn counts can bridge missing active-turn reports.
struct ConversationTurnChangeSummary: Equatable, Sendable
{
	let fileCount: Int
	let additions: Int
	let deletions: Int
	let failure: GitComparisonFailure?
	let usesReportedEditFallback: Bool
	var usesPreviousTurn: Bool = false
	let isLoading: Bool
	static let loading = ConversationTurnChangeSummary()

	private init()
	{
		fileCount = 0
		additions = 0
		deletions = 0
		failure = nil
		usesReportedEditFallback = false
		isLoading = true
	}

	init?(comparison: GitComparisonSnapshot)
	{
		guard !comparison.files.isEmpty
		else
		{
			return nil
		}
		fileCount = comparison.files.count
		additions = comparison.additions
		deletions = comparison.deletions
		failure = nil
		usesReportedEditFallback = comparison.usesReportedEditFallback
		isLoading = false
	}

	init(
		unavailable failure: GitComparisonFailure,
		request: GitComparisonRequest? = nil
	)
	{
		let changes = ReportedRepositoryFileChanges.filter(
			request?.reportedChanges ?? [],
			repositoryRoot: request?.repositoryRoot
		)
		fileCount = Set(changes.map
		{
			Data(($0.movePath ?? $0.path).utf8)
		}).count
		var additions = 0
		var deletions = 0
		for change in changes
		{
			let counts = GitDiffParser.lineCounts(
				in: ConversationNetFileChanges.normalizedDiff(change)
			)
			additions += counts.additions
			deletions += counts.deletions
		}
		self.additions = additions
		self.deletions = deletions
		self.failure = failure
		usesReportedEditFallback = !changes.isEmpty
		isLoading = false
	}

	init?(
		result: GitComparisonResult,
		usesPreviousTurn: Bool = false,
		request: GitComparisonRequest? = nil
	)
	{
		switch result
		{
		case .snapshot(let comparison): self.init(comparison: comparison)
		case .unavailable(let failure): self.init(
				unavailable: failure,
				request: request
			)
		}
		self.usesPreviousTurn = usesPreviousTurn
	}

	init?(_ snapshot: ConversationSnapshot)
	{
		guard let request = snapshot
			.runningGitReviewRequest(owner: FeaturePresentationOwner(snapshot))
		else
		{
			return nil
		}
		self.init(
			result: GitReportedTurnComparison.compare(request),
			usesPreviousTurn: request.lastTurnID != snapshot.activeTurnID,
			request: request
		)
	}
}
