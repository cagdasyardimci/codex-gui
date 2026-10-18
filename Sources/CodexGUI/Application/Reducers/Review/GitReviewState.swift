import Foundation

/// Canonical comparison and presentation choices are separate. Jobs never live in this value.
struct GitReviewState
{
	private(set) var owner: FeaturePresentationOwner?
	private(set) var isOpen = false
	private(set) var lastTurnID: String?
	private(set) var reportedChanges: [FileChange]?
	private(set) var baselineRevision = 0
	private(set) var baselineFailure: GitComparisonFailure?
	var scope: GitComparisonScope = .uncommitted
	var baseRevision = "HEAD^"
	var targetRevision = "HEAD"
	private(set) var generation = 0
	private(set) var summaryRevision = 0
	private(set) var snapshot: GitComparisonSnapshot?
	private(set) var pendingRequest: GitComparisonRequest?
	private(set) var failure: GitComparisonFailure?
	private(set) var isStale = false
	var filter = ""
	var selectedFileID: String?
	var expandedDirectories: Set<Data> = []
	var options = GitDiffPresentationOptions()
	private(set) var selectionMessage: String?

	mutating func selectScope(_ value: GitComparisonScope)
	{
		scope = value
	}

	@discardableResult
	mutating func setReportedChanges(_ changes: [FileChange]?) -> Bool
	{
		let sameReports: Bool
		switch (reportedChanges, changes)
		{
		case (nil, nil): sameReports = true
		case (let previous?, let next?):
			sameReports = FileChange.haveSameExactContent(
				previous,
				next
			)
		default: sameReports = false
		}
		guard !sameReports
		else
		{
			return false
		}
		reportedChanges = changes
		if changes == nil, scope == .lastTurn
		{
			discardLastTurnSnapshot()
		}
		return true
	}

	mutating func setRevisions(
		base: String,
		target: String
	)
	{
		baseRevision = base
		targetRevision = target
	}

	mutating func setFilter(_ value: String)
	{
		filter = value
	}

	@discardableResult
	mutating func selectFile(_ id: String) -> Bool
	{
		guard snapshot?.files.contains(where:
			{
				$0.id.utf8.elementsEqual(id.utf8)
			}) == true
		else
		{
			return false
		}
		selectedFileID = id
		return true
	}

	mutating func toggleDirectory(_ path: String)
	{
		let identity = Data(path.utf8)
		if !expandedDirectories.insert(identity).inserted
		{
			expandedDirectories.remove(identity)
		}
	}

	mutating func expandGap(_ id: String)
	{
		options.expandedGapIDs.insert(Data(id.utf8))
	}

	mutating func setOptions(_ value: GitDiffPresentationOptions)
	{
		options = value
	}

	mutating func activate(
		owner: FeaturePresentationOwner,
		lastTurnID: String? = nil,
		baselineRevision: Int = 0,
		baselineFailure: GitComparisonFailure? = nil
	)
	{
		guard !isOpen || self.owner != owner
		else
		{
			return
		}
		let nextGeneration = generation + 1
		let nextRevision = summaryRevision + 1
		self = GitReviewState()
		generation = nextGeneration
		summaryRevision = nextRevision
		self.owner = owner
		self.lastTurnID = lastTurnID
		self.baselineRevision = baselineRevision
		self.baselineFailure = baselineFailure
		isOpen = true
	}

	/// Returns whether a Last Turn request must be replaced. Other scopes retain their result.
	@discardableResult
	mutating func updateTurnContext(
		lastTurnID: String?,
		baselineRevision: Int,
		baselineFailure: GitComparisonFailure? = nil
	) -> Bool
	{
		let hasTurnContextChanged = self.lastTurnID != lastTurnID
			|| self.baselineRevision != baselineRevision
			|| self.baselineFailure != baselineFailure
		guard hasTurnContextChanged
		else
		{
			return false
		}
		if self.lastTurnID != lastTurnID
		{
			reportedChanges = nil
			if scope == .lastTurn
			{
				discardLastTurnSnapshot()
			}
		}
		self.lastTurnID = lastTurnID
		self.baselineRevision = baselineRevision
		self.baselineFailure = baselineFailure
		guard isOpen, scope == .lastTurn
		else
		{
			return false
		}
		markRepositoryChanged()
		return true
	}

	mutating func close()
	{
		let nextGeneration = generation + 1
		let nextRevision = summaryRevision + 1
		self = GitReviewState()
		generation = nextGeneration
		summaryRevision = nextRevision
	}

	mutating func beginRequest() -> GitComparisonRequest?
	{
		guard isOpen, let owner,
				let root = owner.runtimeOwner?.workspace.canonicalCheckoutPath ?? owner.projectPath
		else
		{
			return nil
		}
		generation += 1
		summaryRevision += 1
		let request = GitComparisonRequest(
			owner: owner,
			repositoryRoot: root,
			scope: scope,
			generation: generation,
			baseRevision: baseRevision,
			targetRevision: targetRevision,
			lastTurnID: scope == .lastTurn ? lastTurnID : nil,
			reportedChanges: scope == .lastTurn ? reportedChanges : nil
		)
		pendingRequest = request
		failure = nil
		isStale = snapshot != nil
		return request
	}

	@discardableResult
	mutating func accept(
		_ result: GitComparisonResult,
		request: GitComparisonRequest
	) -> Bool
	{
		guard isOpen, owner == request.owner, pendingRequest == request,
				scope == request.scope, generation == request.generation
		else
		{
			return false
		}
		switch result
		{
		case .snapshot(let value):
			guard value.request == request
			else
			{
				return false
			}
			pendingRequest = nil
			let sameComparison = snapshot.map
			{
				$0.patch == value.patch
					&& $0.request.scope == value.request.scope
					&& $0.request.lastTurnID == value.request.lastTurnID
					&& $0.resolvedBase == value.resolvedBase
					&& $0.resolvedTarget == value.resolvedTarget
			} == true
			let previousFile = selectedFileID
			var acceptedValue = value
			if sameComparison, let previousSnapshot = snapshot
			{
				acceptedValue.id = previousSnapshot.id
			}
			snapshot = acceptedValue
			isStale = false
			failure = nil
			if !sameComparison
			{
				options.expandedGapIDs.removeAll()
			}
			if let previousFile, !value.files.contains(where:
				{
					$0.id.utf8.elementsEqual(previousFile.utf8)
				})
			{
				selectionMessage = "The selected file is absent from the new comparison."
				selectedFileID = nil
			}
			if selectedFileID == nil
			{
				selectedFileID = value.files.first?.id
			}
			for file in value.files where !sameComparison
			{
				let parts = file.path.split(separator: "/")
				for count in 1 ..< max(
					1,
					parts.count
				)
				{
					expandedDirectories
						.insert(Data(parts.prefix(count).joined(separator: "/").utf8))
				}
			}
		case .unavailable(let reason):
			pendingRequest = nil
			failure = reason
			if scope == .lastTurn
			{
				discardLastTurnSnapshot()
			}
			isStale = snapshot != nil
		}
		summaryRevision += 1
		return true
	}

	/// Another turn's totals, or totals from withdrawn reports, cannot stand in for this turn.
	private mutating func discardLastTurnSnapshot()
	{
		snapshot = nil
		isStale = false
		selectedFileID = nil
		selectionMessage = nil
		expandedDirectories.removeAll()
		options.expandedGapIDs.removeAll()
	}

	mutating func markRepositoryChanged()
	{
		isStale = snapshot != nil
		// Invalidate all outstanding reads before a replacement request is issued.
		generation += 1
		summaryRevision += 1
		pendingRequest = nil
	}

	/// Totals are derived from exactly the chosen complete snapshot, never filtered rows.
	var summary: SummarySection<SummaryChangeTotals>
	{
		let previous = snapshot.map
		{
			SummaryChangeTotals(
				additions: $0.additions,
				deletions: $0.deletions
			)
		}
		if pendingRequest != nil
		{
			return .loading(previous: previous)
		}
		if let failure
		{
			return .failed(
				failure.message,
				previous: previous
			)
		}
		if isStale
		{
			return .unavailable("Comparison is stale; refresh required")
		}
		if let previous
		{
			return .available(previous)
		}
		return .unavailable("No repository comparison is available")
	}

	var copyCommand: String?
	{
		guard !isStale, pendingRequest == nil, failure == nil
		else
		{
			return nil
		}
		return snapshot?.copyCommand
	}
}

extension GitReviewState
{
	var summaryProjection: GitReviewSummaryProjection?
	{
		guard let owner
		else
		{
			return nil
		}
		return GitReviewSummaryProjection(
			owner: owner,
			revision: summaryRevision,
			scope: scope,
			comparisonID: snapshot?.id,
			snapshotScope: snapshot?.request.scope,
			totals: summary
		)
	}
}
