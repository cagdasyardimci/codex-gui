import AppKit

extension MainWindowController
{
	func configureGitSummary(
		target: WorkspaceIntentTarget,
		snapshot: ConversationSnapshot
	)
	{
		let owner = FeaturePresentationOwner(
			snapshot,
			storeIdentity: target.presentationIdentity
		)
		gitSummary.select(owner)
		summaryGitLoader.onChange =
		{
			[weak self] projection in self?.acceptGitSummary(projection)
		}
		summaryGitLoader.select(owner)
		if inspector.gitChanges.runtime.state.isOpen,
			inspector.gitChanges.runtime.state.owner != owner
		{
			inspector.gitChanges.close()
		}
		inspector.gitChanges.updateOwner(
			owner,
			lastTurnID: snapshot.lastReportedGitTurn?.id ?? snapshot.lastGitTurnID,
			baselineRevision: snapshot.gitTurnBaselineRevision,
			baselineFailure: snapshot.gitTurnBaselineFailure
		)
		inspector.gitChanges.runtime.setReportedChanges(snapshot.reportedGitChanges)
		summaryChangesProvider =
		{
			[weak self] owner in
			self?.gitSummary.section(for: owner) ?? .unavailable("Comparison unavailable")
		}
		gitSummary.accept(
			summaryGitLoader.projection,
			canonical: summaryGitLoader.projection
		)
	}

	private func acceptGitSummary(_ projection: GitReviewSummaryProjection?)
	{
		guard gitSummary.accept(
			projection,
			canonical: summaryGitLoader.projection
		), let snapshot = latestSnapshot
		else
		{
			return
		}
		let target = WorkspaceIntentTarget(
			store: currentStore,
			snapshot: snapshot,
			coordinator: coordinator
		)
		guard target.accepts(.loadEarlierTurns)
		else
		{
			return
		}
		renderPinnedSummary(
			snapshot,
			target: target
		)
	}

	func openGitChanges(
		_ request: ContextPanelRequest,
		inToolTab: Bool = false
	)
	{
		guard let snapshot = latestSnapshot, request.destination == .changes
		else
		{
			return
		}
		let target = WorkspaceIntentTarget(
			store: currentStore,
			snapshot: snapshot,
			coordinator: coordinator
		)
		guard target.accepts(.loadEarlierTurns), request.owner == FeaturePresentationOwner(
			snapshot,
			storeIdentity: target.presentationIdentity
		)
		else
		{
			return
		}
		if inToolTab
		{
			openChangesToolTab()
			return
		}
		guard inspector.open(request)
		else
		{
			return
		}
		inspector.gitChanges.activate(
			owner: request.owner,
			lastTurnID: snapshot.lastReportedGitTurn?.id ?? snapshot.lastGitTurnID,
			baselineRevision: snapshot.gitTurnBaselineRevision,
			baselineFailure: snapshot.gitTurnBaselineFailure
		)
		inspector.gitChanges.runtime.setReportedChanges(snapshot.reportedGitChanges)
		paneController.setReviewCollapsed(false)
	}

	func openCurrentChangesInToolTab(scope: GitComparisonScope? = nil)
	{
		guard let snapshot = latestSnapshot, snapshot.projectPath != nil,
				inspector.isShowingTools
		else
		{
			return
		}
		let target = WorkspaceIntentTarget(
			store: currentStore,
			snapshot: snapshot,
			coordinator: coordinator
		)
		guard target.accepts(.loadEarlierTurns)
		else
		{
			return
		}
		inspector.showGitChangesInSelectedToolTab(
			owner: FeaturePresentationOwner(
				snapshot,
				storeIdentity: target.presentationIdentity
			),
			lastTurnID: snapshot.lastReportedGitTurn?.id ?? snapshot.lastGitTurnID,
			baselineRevision: snapshot.gitTurnBaselineRevision,
			baselineFailure: snapshot.gitTurnBaselineFailure
		)
		inspector.gitChanges.runtime.setReportedChanges(snapshot.reportedGitChanges)
		if let scope
		{
			inspector.gitChanges.runtime.selectScope(scope)
		}
	}
}
