import AppKit

extension MainWindowController
{
	func renderPinnedSummary(
		_ snapshot: ConversationSnapshot,
		target: WorkspaceIntentTarget
	)
	{
		let owner = FeaturePresentationOwner(
			snapshot,
			storeIdentity: target.presentationIdentity
		)
		let firstPresentation = summaryReconciliation.owner == nil
		summaryReconciliation.select(owner)
		let visibilityOwner = FeaturePresentationOwner(
			snapshot,
			storeIdentity: String(describing: ObjectIdentifier(target.store))
		)
		let visible = summaryVisibility.isVisible(for: visibilityOwner)
		if visible, snapshot.projectPath != nil, target.accepts(.loadEarlierTurns),
			!currentStore.isRetired, !currentStore.model.lifecycle.isShutdown
		{
			summaryGitLoader.loadIfNeeded(for: owner)
		}
		if target.accepts(.loadEarlierTurns)
		{
			var sections = ContextSummarySections()
			sections.changes = summaryChangesProvider?(owner)
				?? .unavailable("Open Changes to load a repository comparison")
			sections.sources = .unavailable("Sources integration unavailable")
			// Sources and Subagents remain unavailable until their integration is restored.
			sections.availableDestinations = [.changes]
			summaryReconciliation.accept(ContextSummaryUpdate(
				owner: owner,
				revision: summaryReconciliation.revision + 1,
				sections: sections
			))
		}
		var sections = summaryReconciliation.sections
		sections.changesContext = gitSummary.scopeDescription
		if currentStore.isRetired || currentStore.model.lifecycle.isShutdown
		{
			sections = ContextSummarySections()
			sections.changes = .unavailable("Workspace unavailable")
			sections.sources = .unavailable("Workspace unavailable")
			sections.availableDestinations = []
		}
		inspector.onSummaryDisplayChange =
		{
			[weak self] displayed in
			self?.summaryToggleButton.state = displayed ? .on : .off
			self?.inspector.toolsTabs.setSummaryVisible(displayed)
			self?.summaryToggleButton.setAccessibilityValue(displayed ? "Visible" : "Hidden")
		}
		inspector.renderSummary(
			PinnedSummaryPresentation(
				snapshot,
				ownerIdentity: target.presentationIdentity,
				sections: sections
			),
			visible: visible
		)
		if firstPresentation, visible, snapshot.projectPath != nil
		{
			paneController.setReviewCollapsed(false)
		}
		inspector.summary.onNavigate =
		{
			[weak self] request in
			guard request.owner == owner, target.accepts(.loadEarlierTurns),
					request.destination == .changes
			else
			{
				return
			}
			self?.openGitChanges(
				request,
				inToolTab: true
			)
		}
	}

	/// Future Git integration projects its canonical comparison for the captured owner.
	/// It must reject stale owner/revision/scope before returning totals; nil unregisters it.
	func registerSummaryChangesProvider(
		_ provider: ((FeaturePresentationOwner) -> SummarySection<SummaryChangeTotals>)?
	)
	{
		summaryChangesProvider = provider
		guard let snapshot = latestSnapshot
		else
		{
			return
		}
		let target = WorkspaceIntentTarget(
			store: currentStore,
			snapshot: snapshot,
			coordinator: coordinator
		)
		renderPinnedSummary(
			snapshot,
			target: target
		)
	}

	@objc func togglePinnedSummary()
	{
		guard let snapshot = latestSnapshot
		else
		{
			return
		}
		let owner = FeaturePresentationOwner(
			snapshot,
			storeIdentity: String(describing: ObjectIdentifier(currentStore))
		)
		let visible = summaryVisibility.isVisible(for: owner)
		let expandedConversation = paneController.isShowingExpandedConversation
		let hiddenByContainer = (inspector.isShowingTools && !inspector
			.isSummaryBesideExpandedConversation) || inspector.isShowingDetails
			|| paneController.split.splitViewItems[2].isCollapsed
		if !visible || !hiddenByContainer
		{
			summaryVisibility.toggle(for: owner)
		}
		let target = WorkspaceIntentTarget(
			store: currentStore,
			snapshot: snapshot,
			coordinator: coordinator
		)
		let revealing = !visible || hiddenByContainer
		if revealing, summaryVisibility.isVisible(for: owner),
			snapshot.projectPath != nil, target.accepts(.loadEarlierTurns)
		{
			summaryGitLoader.refresh(for: FeaturePresentationOwner(
				snapshot,
				storeIdentity: target.presentationIdentity
			))
		}
		inspector.animateSummaryVisibilityChange
		{
			if expandedConversation
			{
				inspector.showSummaryBesideExpandedConversation()
			}
			else
			{
				inspector.showSummary()
			}
			renderPinnedSummary(
				snapshot,
				target: target
			)
			// The inspector opens to make the explicit reveal observable at supported widths.
			if !expandedConversation, summaryVisibility.isVisible(for: owner)
			{
				paneController.setReviewCollapsed(false)
			}
		}
	}

	func openCurrentChanges(toggleIfShowing: Bool = false)
	{
		guard let snapshot = latestSnapshot
		else
		{
			return
		}
		let target = WorkspaceIntentTarget(
			store: currentStore,
			snapshot: snapshot,
			coordinator: coordinator
		)
		guard snapshot.projectPath != nil, target.accepts(.loadEarlierTurns)
		else
		{
			return
		}
		let request = ContextPanelRequest(
			owner: FeaturePresentationOwner(
				snapshot,
				storeIdentity: target.presentationIdentity
			),
			destination: .changes
		)
		if toggleIfShowing, inspector.panels.destination == .changes,
			!inspector.panels.view.isHidden, paneController.isGitReviewFocused
		{
			inspector.showSummary()
		}
		else if toggleIfShowing, inspector.panels.destination == .changes,
				!inspector.panels.view.isHidden, !paneController.isReviewCollapsed
		{
			paneController.toggleReview()
			if paneController.isReviewCollapsed
			{
				inspector.gitChanges.close()
			}
		}
		else
		{
			openGitChanges(request)
		}
	}
}
