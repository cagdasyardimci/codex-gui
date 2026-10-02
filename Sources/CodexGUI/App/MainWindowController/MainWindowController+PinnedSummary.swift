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
		if summaryReconciliation.owner != owner
		{
			closeSourcesPanel()
		}
		summaryReconciliation.select(owner)
		_ = inspector.view
		inspector.panels.register(
			sources,
			for: .sources,
			providesHeader: true
		)
		sources.onClose =
		{
			[weak self] in self?.closeSourcesPanel()
		}
		inspector.onCloseDetail =
		{
			[weak self] destination in
			if destination == .sources
			{
				self?.closeSourcesPanel()
			}
		}
		if target.accepts(.loadEarlierTurns)
		{
			let update = ContextSummaryUpdate(
				owner: owner,
				revision: summaryReconciliation.revision + 1,
				sections: ContextSummarySelector.sections(
					model: target.store.model,
					chatID: snapshot.selectedThreadID,
					changes: summaryChangesProvider?(owner) ?? .unavailable("Totals unavailable")
				)
			)
			summaryReconciliation.accept(update)
		}
		var sections = summaryReconciliation.sections
		sections.changesContext = gitSummary.scopeDescription
		sections.availableDestinations.formIntersection(inspector.panels.availableDestinations)
		if let sources = sections.sources.value,
			!inspector.panels.supportsRecordNavigation(.sources)
		{
			// Previews stay readable without implying an unregistered resource action.
			let previews = sources.map
			{
				source in
				var source = source
				source.detailRecordID = nil
				return source
			}
			switch sections.sources
			{
			case .available: sections.sources = .available(previews)
			case .loading: sections.sources = .loading(previous: previews)
			case .failed(
				let reason,
				_
			): sections.sources = .failed(
					reason,
					previous: previews
				)
			case .unavailable: break
			}
		}
		if currentStore.isRetired || currentStore.model.lifecycle.isShutdown
		{
			sections = ContextSummarySections()
			sections.changes = .unavailable("Workspace unavailable")
			sections.sources = .unavailable("Workspace unavailable")
			sections.availableDestinations = []
		}
		let presentation = PinnedSummaryPresentation(
			snapshot,
			ownerIdentity: target.presentationIdentity,
			sections: sections
		)
		// Visibility keys use stable store identity; reconnects do not reset a user's choice.
		let visibilityOwner = FeaturePresentationOwner(
			snapshot,
			storeIdentity: String(describing: ObjectIdentifier(target.store))
		)
		let visible = summaryVisibility.isVisible(for: visibilityOwner)
		inspector.onSummaryDisplayChange =
		{
			[weak self] displayed in
			self?.summaryToggleButton.state = displayed ? .on : .off
			self?.summaryToggleButton.setAccessibilityValue(displayed ? "Visible" : "Hidden")
		}
		inspector.renderSummary(
			presentation,
			visible: visible
		)
		if firstPresentation, visible, snapshot.projectPath != nil
		{
			paneController.setReviewCollapsed(false)
		}
		inspector.summary.onNavigate =
		{
			[weak self] request in
			guard let self, request.owner == owner,
					target.accepts(.loadEarlierTurns)
			else
			{
				return
			}
			switch request.destination
			{
			case .sources: self.openSources(request)
			case .subagents: self.openSubagents(request)
			case .changes: self.openGitChanges(request)
			case .workspaceFiles, .reportedChanges: break
			}
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
		let hiddenByContainer = inspector.isShowingDetails
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
		closeSourcesPanel()
		inspector.showSummary()
		renderPinnedSummary(
			snapshot,
			target: target
		)
		// The inspector opens to make the explicit reveal observable at supported widths.
		if summaryVisibility.isVisible(for: owner)
		{
			paneController.setReviewCollapsed(false)
		}
	}
}
